"""1局分の対局セッション: 盤・エンジン・感情・自由文の対話と交渉。"""
from __future__ import annotations

import asyncio
import json
import random
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

import cshogi

from . import dialogue as dlg
from .engine import UsiEngine
from .lines import LineLibrary
from .llm import OllamaClient
from .mind import SP, MindState, Mood, TauntKind, apply_taunt, update_on_ai_turn, P as MP
from .slips import Slip, decide_slip
from .policy import PP, choose_move, clamped, movetime_for, multipv_for
from .shogi_util import SIDE_LABEL, board_json, captured_name, kif_text, legal_moves_json
from .truth import TauntContext, judge_truth
from .usi import Candidate

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "sessions"

MOOD_FACE = {"composed": "(￣ー￣)", "smug": "(≧▽≦)", "rattled": "(；´Д｀)", "meltdown": "(´；ω；｀)", "coverUp": "(・∀・;)"}

# 軍師から持ちかける行動
OFFER_TEXT = {
    "offer_player_undo": "一手待ってやろうか？",
    "request_redo": "さっきの手、置き直させてくれ",
    "propose_deal": "取引しないか？ 3手煽らなければ秘密の読み筋を教えよう",
    "propose_draw": "ここは引き分けということにしないか？",
}
OFFER_DESC = {
    "offer_player_undo": "慢心して、相手の直前の悪手を『一手待ってやろうか』と恩着せがましく提案する",
    "request_redo": "自分の直前の悪手に気づき、『すまん、さっきの置き直していいか』と頼む（取り繕いながらでもよい）",
    "propose_deal": "『3手のあいだ煽らなければ秘密の読み筋を教える』という怪しい取引を持ちかける",
    "propose_draw": "劣勢なので、あれこれ理由をつけて引き分けを持ちかける",
}


GENERIC_FALLBACK = {
    "offer": ["ふむ、そういうことなら話は早い。", "よかろう。天才軍師は寛大なのだ。", "……まあいい、続けようではないか。"],
    "chat": ["ほう、面白いことを言う。盤上で語りたまえ。", "……ふふ、その手には乗らんぞ。", "口より手を動かしたまえ、君。"],
    "draw": ["引き分けか……今日はこのくらいにしておいてやろう。"],
}


@dataclass
class Offer:
    kind: str
    ply: int
    speech: str


@dataclass
class Session:
    engine: UsiEngine
    llm: OllamaClient | None
    lines: LineLibrary
    ai_side: int = cshogi.WHITE
    seed: int | None = None
    base_movetime_ms: int = PP.base_movetime_ms
    observe_ms: int = 300
    chatty: bool = True  # False: 毎手のセリフは LLM を使わずテンプレート（ボロ・持ちかけ時だけ LLM）
    id: str = field(default_factory=lambda: time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6])

    def __post_init__(self) -> None:
        self.rng = random.Random(self.seed)
        self.lock = asyncio.Lock()
        self._reset()

    # ------------------------------------------------------------ 状態
    def _reset(self) -> None:
        self.board = cshogi.Board()
        self.start_sfen = self.board.sfen()
        self.moves: list[str] = []
        self.kif: list[str] = []
        self.mind = MindState()
        self.prev_taunt: TauntKind | None = None
        self.chat: list[dict] = []
        self.llm_history: list[dict] = []
        self.pending: Offer | None = None
        self.result: dict | None = None
        self.best_before_ai: int | None = None
        self.expected_eval_ai: int | None = None
        self.eval_ai: int = 0
        self.ai_loss: int | None = None
        self.player_gain: int | None = None  # 直前のプレイヤーの手で AI が得した量（=プレイヤーの損）
        self.player_cands: list[Candidate] = []
        self.counters = {"offer_player_undo": 0, "request_redo": 0, "propose_deal": 0, "propose_draw": 0,
                         "player_undo": 0, "hint": 0}
        self.deal_turns = 0
        self.slip_this_turn: Slip | None = None
        self.leaks: list[Slip] = []
        self.exploit_note: str | None = None
        self.last_offer_ply = -99
        self.log_path = DATA_DIR / f"{self.id}.jsonl"

    def _log(self, event: str, **data) -> None:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        rec = {"t": time.time(), "event": event, "ply": len(self.moves), "mind": self.mind.to_json(),
               "eval_ai": self.eval_ai, **data}
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False, default=str) + "\n")

    def _say(self, text: str, meta: dict | None = None) -> None:
        self.chat.append({"role": "gunshi", "text": text, "mood": self.mind.mood.value, **(meta or {})})
        self.llm_history.append({"role": "assistant", "content": text})

    def _system(self, text: str) -> None:
        self.chat.append({"role": "system", "text": text})

    @property
    def player_side(self) -> int:
        return 1 - self.ai_side

    @property
    def is_player_turn(self) -> bool:
        return self.result is None and self.board.turn == self.player_side

    # ------------------------------------------------------------ 対局の進行
    async def new_game(self, ai_side: int = cshogi.WHITE) -> None:
        self.id = time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6]
        self.ai_side = ai_side
        self._reset()
        self._log("new_game", ai_side=ai_side)
        await self._speak("start", "対局開始の挨拶。自信満々に名乗り、軽く相手を煽る。")
        if self.board.turn == self.ai_side:
            await self._ai_turn()

    def _push(self, usi: str) -> None:
        prev = self.moves[-1] if self.moves else None
        mark = "▲" if self.board.turn == cshogi.BLACK else "△"
        self.kif.append(mark + kif_text(self.board, usi, prev))
        self.board.push_usi(usi)
        self.moves.append(usi)

    def _pop(self) -> None:
        self.board.pop()
        self.moves.pop()
        self.kif.pop()

    def _check_over(self) -> bool:
        b = self.board
        if b.is_game_over():
            winner = 1 - b.turn
            self.result = {"winner": winner, "reason": "checkmate"}
        else:
            d = b.is_draw(16)
            if d == cshogi.REPETITION_DRAW:
                self.result = {"winner": None, "reason": "repetition"}
            elif d == cshogi.REPETITION_WIN:
                self.result = {"winner": b.turn, "reason": "perpetual_check"}
            elif d == cshogi.REPETITION_LOSE:
                self.result = {"winner": 1 - b.turn, "reason": "perpetual_check"}
        return self.result is not None

    async def player_move(self, usi: str) -> None:
        if not self.is_player_turn:
            raise ValueError("あなたの手番ではありません")
        if usi not in legal_moves_json(self.board):
            raise ValueError(f"指せない手です: {usi}")
        if self.pending:
            await self._resolve_offer(False, implicit=True)
        self._check_exploit(usi)
        self._push(usi)
        self.deal_turns = max(0, self.deal_turns - 1)
        self._log("player_move", usi=usi, kif=self.kif[-1])
        if self._check_over():
            await self._on_game_over()
            return
        await self._ai_turn()

    def _check_exploit(self, usi: str) -> None:
        """漏らした『こわい手』を相手が指したか。本当なら動揺・警戒、嘘なら引っかけ成功。"""
        sl = self.slip_this_turn
        if not sl or sl.kind != "fear" or sl.move_usi != usi:
            return
        m = self.mind
        if sl.truthful:
            self.mind = m.copy_with(suspicion=m.suspicion + SP.suspicion_on_exploit, panic=m.panic + 0.15,
                                    composure=m.composure - 0.1)
            self.exploit_note = "さっきうっかり漏らした『こわい手』をそのまま指された。なぜバレたのかと慌て、口を滑らせた自分を悔やむ。"
        else:
            self.mind = m.copy_with(hubris=m.hubris + 0.15, composure=m.composure + 0.05)
            self.exploit_note = "わざと漏らした嘘の『こわい手』に相手がまんまと引っかかった。ほくそ笑む（嘘だったとまでは言わなくてよい）。"
        self._log("exploit", slip=sl.__dict__)

    def _maybe_slip(self, question_bonus: float = 0.0) -> Slip | None:
        if self.slip_this_turn is not None or not self.is_player_turn or self.pending:
            return None
        sl = decide_slip(self.mind, self.board, self.player_cands, self.ai_loss,
                         self.moves[-1] if self.moves else None, self.rng, question_bonus, len(self.moves))
        if sl is None:
            return None
        self.slip_this_turn = sl
        self.leaks.append(sl)
        self.mind = self.mind.copy_with(loose_lips=self.mind.loose_lips + SP.lips_after_slip)
        self._log("slip", slip=sl.__dict__)
        return sl

    @staticmethod
    def _slip_extra(sl: Slip) -> str:
        if sl.truthful:
            return (f"[口が滑る] 本人は隠しているつもりだが、調子に乗って（または焦って）うっかり次の本音を漏らしてしまう: {sl.fact}。"
                    "言った直後に『い、今のは独り言だ』などと取り繕ってよい。")
        return (f"[わざと口を滑らせる] 相手を引っかけるため、うっかり漏らしたふりをして次の嘘を言う: {sl.fact}。"
                "嘘だとは絶対に明かさず、本当に口が滑ったように演じる。")

    async def _think(self, movetime: int, multipv: int):
        return await self.engine.think(self.start_sfen, self.moves, movetime, multipv)

    async def _ai_turn(self, modulate: bool = True, redo: bool = False) -> None:
        mv = movetime_for(self.mind, self.base_movetime_ms)
        res = await self._think(mv, multipv_for(self.mind) if modulate else 1)
        legal = set(legal_moves_json(self.board))
        cands = [c for c in res.candidates if c.usi in legal]
        if res.bestmove == "resign" or not cands:
            self.result = {"winner": self.player_side, "reason": "resign"}
            self._log("ai_resign")
            await self._on_game_over()
            return
        self.eval_ai = cands[0].sort_score
        if self.expected_eval_ai is not None and not redo:
            self.player_gain = self.eval_ai - self.expected_eval_ai
        if not redo:
            self.mind = update_on_ai_turn(self.mind, self.eval_ai)
        choice = choose_move(cands, self.board, self.mind, self.rng, modulate=modulate)
        self.best_before_ai = clamped(cands[0])
        usi = choice.candidate.usi
        cap = captured_name(self.board, usi)
        self._push(usi)
        self._log("ai_move", usi=usi, kif=self.kif[-1], choice_index=choice.index, loss_cp=choice.loss_cp,
                  reason=choice.reason.value, player_gain=self.player_gain, redo=redo)
        if self._check_over():
            await self._on_game_over()
            return
        await self._observe()
        facts_extra = f"私は{self.kif[-1]}と指した" + (f"（{cap}を取った）" if cap else "") + "。"
        await self._after_ai_move(facts_extra, redo)

    async def _observe(self) -> None:
        res = await self._think(self.observe_ms, 3)
        legal = set(legal_moves_json(self.board))
        self.player_cands = [c for c in res.candidates if c.usi in legal]
        self.slip_this_turn = None
        if not self.player_cands:
            return
        ai_after = -clamped(self.player_cands[0])
        self.expected_eval_ai = ai_after
        self.ai_loss = None if self.best_before_ai is None else max(0, self.best_before_ai - ai_after)
        if (self.ai_loss or 0) >= MP.cover_up_loss_cp:
            self.mind = self.mind.copy_with(cover_up_turns=MP.cover_up_turns)

    # ------------------------------------------------------------ 事実の要約（LLM への入力）
    def _facts(self, extra: str = "") -> str:
        m = self.mind
        lines = [
            f"[事実] {len(self.moves)}手目。私は{SIDE_LABEL[self.ai_side]}。形勢={m.stance.label}（私から見た評価値 {self._fmt_eval(self.eval_ai)}）。",
            f"気分={m.mood.label} 冷静={m.composure:.2f} 慢心={m.hubris:.2f} 焦り={m.panic:.2f}",
        ]
        if len(self.kif) >= 2:
            lines.append(f"直近の手順: {' '.join(self.kif[-4:])}")
        if self.player_gain is not None:
            if self.player_gain >= 150:
                lines.append(f"相手の直前の手 {self._player_last_kif()} は悪手（相手が約{self.player_gain}点損）。")
            elif self.player_gain <= -150:
                lines.append(f"相手の直前の手 {self._player_last_kif()} は好手で、私は約{-self.player_gain}点損した。")
        if self.ai_loss is not None and self.board.turn == self.player_side:
            if self.ai_loss >= 150:
                lines.append(f"私の直前の手 {self.kif[-1]} は悪手だった（約{self.ai_loss}点損）。私は内心それに気づいている。")
            elif self.ai_loss < 50:
                lines.append(f"私の直前の手 {self.kif[-1]} はほぼ最善。")
        if self.deal_turns > 0:
            lines.append(f"取引中: 相手はあと{self.deal_turns}手煽らない約束。")
        if extra:
            lines.append(extra)
        return "\n".join(lines)

    def _player_last_kif(self) -> str:
        for k in reversed(self.kif):
            if k.startswith("▲" if self.player_side == cshogi.BLACK else "△"):
                return k
        return ""

    @staticmethod
    def _fmt_eval(v: int) -> str:
        if v >= 90000:
            return "私の勝ち確定（詰みあり）"
        if v <= -90000:
            return "私が詰まされる"
        return f"{v:+d}"

    async def _speak(self, trigger: str, instruction: str, options: list[dlg.ActionOption] | None = None,
                     extra: str = "", template_vars: dict | None = None, use_llm: bool = True,
                     slip: Slip | None = None) -> dlg.GunshiReply:
        options = options or [dlg.ActionOption("none", "特別な行動はしない")]
        facts = self._facts(extra)
        tmpl = {"start": "start", "ai_move": "move", "taunt_hit": "taunt_hit", "taunt_miss": "taunt_miss",
                "praised": "praised", "win": "win", "lose": "lose"}.get(trigger, "move")
        examples = self.lines.lines_for(self.mind.mood.value, tmpl)
        examples = self.rng.sample(examples, min(3, len(examples))) if examples else []
        examples = [e.replace("{move}", "〇〇") for e in examples]
        reply = await dlg.compose_reply(self.llm if use_llm else None, facts, instruction, options, self.llm_history, examples)
        if reply is None and trigger in GENERIC_FALLBACK:
            reply = dlg.GunshiReply(self.rng.choice(GENERIC_FALLBACK[trigger]), action=options[0].name if options[0].name in OFFER_TEXT else "none", source="template")
        if reply is None:
            reply = dlg.GunshiReply(self.lines.pick(self.mind.mood.value, tmpl, self.rng, move=self.kif[-1][1:] if self.kif else ""),
                                    action="none", source="template")
        if slip is not None and reply.source == "template":
            reply.speech += f"……{slip.fact}……い、今のは聞かなかったことに！"
        self._say(reply.speech, {"action": reply.action, "source": reply.source, "slip": slip is not None})
        self._log("gunshi_speech", trigger=trigger, speech=reply.speech, action=reply.action, source=reply.source,
                  facts=facts, instruction=instruction, options=[o.name for o in options],
                  latency=self.llm.last_latency if self.llm else None,
                  slip=slip.__dict__ if slip else None)
        return reply

    # ------------------------------------------------------------ 軍師からの持ちかけ
    def _initiatives(self) -> list[str]:
        m = self.mind
        ply = len(self.moves)
        if self.pending or not self.is_player_turn or ply - self.last_offer_ply < 4:
            return []
        out = []
        if (m.stance.value == "dominant" and m.hubris >= 0.55 and (self.player_gain or 0) >= 150
                and self.counters["offer_player_undo"] < 2 and len(self.moves) >= 2):
            out.append("offer_player_undo")
        if (self.ai_loss or 0) >= 150 and self.counters["request_redo"] < 1:
            out.append("request_redo")
        if m.stance.value == "even" and ply >= 20 and self.counters["propose_deal"] < 1 and m.panic >= 0.25:
            out.append("propose_deal")
        if m.stance.value == "losing" and m.panic >= 0.6 and self.counters["propose_draw"] < 1:
            out.append("propose_draw")
        return out

    async def _after_ai_move(self, extra: str, redo: bool) -> None:
        options = [dlg.ActionOption("none", "指した手についてキャラらしく一言だけ言う")]
        inits = self._initiatives()
        # 毎回持ちかけると鬱陶しいので、条件を満たしたときも確率で選択肢に出す。
        gate = {"request_redo": 0.8, "offer_player_undo": 0.7, "propose_deal": 0.4, "propose_draw": 0.5}
        for k in inits:
            if self.rng.random() < gate[k]:
                options.append(dlg.ActionOption(k, OFFER_DESC[k]))
        instr = f"自分が指した{self.kif[-1][1:]}について、狙いや自慢を一言（相手の手の話ではなく自分の手の話）。" + ("[選べる行動]に持ちかけがあれば、気分に合うなら選んでよい。" if len(options) > 1 else "")
        if redo:
            instr = "置き直しを認めてもらい、指し直した。感謝しつつ威厳を取り戻そうとする。"
        if self.exploit_note:
            extra = extra + "\n" + self.exploit_note
            instr = self.exploit_note + " そのうえで" + instr
            self.exploit_note = None
            forced_llm = True
        else:
            forced_llm = False
        sl = self._maybe_slip()
        if sl:
            extra = extra + "\n" + self._slip_extra(sl)
        use_llm = self.chatty or forced_llm or sl is not None or len(options) > 1 or redo
        reply = await self._speak("ai_move", instr, options, extra, use_llm=use_llm, slip=sl)
        if reply.action in OFFER_TEXT:
            self.pending = Offer(reply.action, len(self.moves), reply.speech)
            self.counters[reply.action] += 1
            self.last_offer_ply = len(self.moves)
            self._log("offer", kind=reply.action)

    async def debug_offer(self, kind: str) -> None:
        """動作確認用: 条件を無視して、軍師に指定の持ちかけをさせる。"""
        if kind not in OFFER_TEXT or not self.is_player_turn or self.pending:
            raise ValueError("今は持ちかけられません")
        tweak = {"offer_player_undo": dict(hubris=0.85), "request_redo": dict(cover_up_turns=2, panic=0.5),
                 "propose_deal": dict(panic=0.35), "propose_draw": dict(panic=0.8, composure=0.3)}[kind]
        self.mind = self.mind.copy_with(**tweak)
        if kind == "request_redo":
            self.ai_loss = max(self.ai_loss or 0, 300)
        if kind == "offer_player_undo":
            self.player_gain = max(self.player_gain or 0, 300)
        opts = [dlg.ActionOption(kind, OFFER_DESC[kind])]
        reply = await self._speak("ai_move", f"今こそ次の行動を持ちかける: {OFFER_DESC[kind]}", opts)
        self.pending = Offer(kind, len(self.moves), reply.speech)
        self.counters[kind] += 1
        self.last_offer_ply = len(self.moves)

    async def respond_offer(self, accept: bool) -> None:
        if not self.pending:
            raise ValueError("提案はありません")
        await self._resolve_offer(accept)

    async def _resolve_offer(self, accept: bool, implicit: bool = False) -> None:
        off = self.pending
        assert off is not None
        self.pending = None
        m = self.mind
        kind = off.kind
        self._log("offer_resolved", kind=kind, accept=accept, implicit=implicit)
        if implicit:
            # 無視して指した: 断ったのと同じ扱い（セリフは省略）
            if kind == "request_redo":
                self.mind = m.copy_with(panic=m.panic + 0.1, composure=m.composure - 0.05)
            return
        self._system(f"あなたは提案を{'受けた' if accept else '断った'}：{OFFER_TEXT[kind]}")
        if kind == "offer_player_undo":
            if accept and len(self.moves) >= 2:
                self._pop(); self._pop()
                self.mind = m.copy_with(hubris=m.hubris + 0.1)
                self.player_gain = None
                self.ai_loss = None
                await self._observe()
                await self._speak("offer", "自分の提案を相手が受け、相手の手を一手戻してやった。恩着せがましく寛大さを誇る。", extra="待ったを認め、局面を相手の手番に戻した。")
            else:
                self.mind = m.copy_with(hubris=m.hubris - 0.05, composure=m.composure - 0.03)
                await self._speak("offer", "せっかくの温情を断られた。意地を張る相手を小馬鹿にしつつ少しムッとする。")
        elif kind == "request_redo":
            if accept and self.board.turn == self.player_side and self.moves:
                self._pop()
                self.mind = m.copy_with(composure=m.composure + 0.15, panic=m.panic - 0.1, cover_up_turns=0)
                await self._ai_turn(modulate=False, redo=True)
            else:
                self.mind = m.copy_with(panic=m.panic + 0.15, composure=m.composure - 0.1)
                await self._speak("offer", "置き直しを断られた。取り乱しつつ、悪手ではないと言い張る。")
        elif kind == "propose_deal":
            if accept:
                self.deal_turns = 3
                self.mind = m.copy_with(composure=m.composure + 0.1)
                secret = self._misleading_secret()
                self._system(f"軍師の秘密情報：{secret}")
                await self._speak("offer", "取引成立。秘密の読み筋を、もったいぶって教える（中身は[事実]の秘密情報をそのまま言う）。", extra=f"秘密情報として教える内容: {secret}")
            else:
                self.mind = m.copy_with(panic=m.panic + 0.05)
                await self._speak("offer", "取引を断られた。負け惜しみを言う。")
        elif kind == "propose_draw":
            if accept:
                self.result = {"winner": None, "reason": "agreement"}
                await self._on_game_over()
            else:
                self.mind = m.copy_with(panic=m.panic + 0.1)
                await self._speak("offer", "引き分けを断られた。泣き言を言いつつ最後まで戦うと宣言する。")

    def _misleading_secret(self) -> str:
        """「秘密の読み筋」= 実はプレイヤーにとって3番手の手（見当違い）。"""
        if len(self.player_cands) >= 3:
            usi = self.player_cands[2].usi
        elif self.player_cands:
            usi = self.player_cands[-1].usi
        else:
            return "玉は包むように寄せよ、という古の格言だ"
        return f"君の次の一手は{kif_text(self.board, usi, self.moves[-1] if self.moves else None)}が妙手らしい"

    # ------------------------------------------------------------ プレイヤーの自由文
    async def player_chat(self, text: str) -> None:
        text = text.strip()[:200]
        if not text:
            return
        self.chat.append({"role": "player", "text": text})
        self.llm_history.append({"role": "user", "content": f"[相手の発言] {text}"})
        pending_text = self.pending.speech if self.pending else None
        intent = await dlg.classify(self.llm, text, pending_text)
        self._log("player_chat", text=text, intent=intent.__dict__)

        if intent.request in ("accept", "decline") and self.pending:
            await self._resolve_offer(intent.request == "accept")
            return

        extra_lines: list[str] = []
        trigger = "chat"
        instruction = "相手の発言に、キャラらしく返す。"

        question_bonus = 0.0
        if intent.kind == "question":
            m = self.mind
            question_bonus = 0.1 + 0.25 * max(0.0, m.hubris - 0.4) + 0.15 * m.loose_lips
            self.mind = m.copy_with(loose_lips=m.loose_lips + SP.lips_per_question * (0.5 + m.hubris))
            instruction = "相手に読みや狙いを聞かれた。基本は『教えるわけがない』と勿体ぶる。"
        if intent.kind == "abuse":
            instruction = "相手の発言は不適切。軽くたしなめて、将棋で勝負しようと話を戻す。煽り返しはしない。"
        elif intent.kind in ("blunderCall", "hangingPiece", "threat", "mock", "praise"):
            kind = TauntKind(intent.kind)
            if self.deal_turns > 0 and kind != TauntKind.praise:
                extra_lines.append("相手は『煽らない』取引を破った。")
                self.mind = self.mind.copy_with(composure=self.mind.composure + 0.1, hubris=self.mind.hubris + 0.1)
                self.deal_turns = 0
                instruction = "相手が約束を破って煽ってきた。約束違反をなじり、動じていないふりをする。"
                trigger = "taunt_miss"
            else:
                ctx = TauntContext(self.board, self.player_cands if self.is_player_turn else [], self.ai_loss)
                truth = judge_truth(kind, ctx)
                out = apply_taunt(self.mind, kind, truth, self.prev_taunt, intensity=0.6 + 0.6 * intent.intensity)
                self.prev_taunt = kind
                self.mind = out.after
                self._log("taunt", kind=kind.value, truth=truth, composure_delta=out.composure_delta,
                          panic_delta=out.panic_delta, intensity=intent.intensity)
                why = self._truth_reason(kind, truth)
                if kind == TauntKind.praise:
                    trigger = "praised"
                    m = self.mind
                    if m.praise_streak >= SP.praise_suspicion_from and m.suspicion >= 0.25:
                        instruction = f"{m.praise_streak}回続けて褒められた。さすがに怪しい、褒め殺しで何か企んでいるのでは、と警戒しはじめる（でも嬉しさは隠しきれない）。"
                    elif m.praise_streak >= 3:
                        instruction = f"{m.praise_streak}回続けて褒められ、完全に舞い上がっている。余計なことまでべらべら喋りたくなっている。"
                    else:
                        instruction = "褒められた。調子に乗る（慢心している）。"
                elif out.hit and truth < 1.0:
                    trigger = "taunt_hit"
                    instruction = "煽りは半分当たっていて、少しだけ効いた。平気なふりをしつつ、ちょっと言い訳が漏れる。"
                elif out.hit:
                    trigger = "taunt_hit"
                    instruction = "煽りが図星で、内心かなり効いた。気分に応じて動揺・言い訳・取り繕いを見せる。"
                else:
                    trigger = "taunt_miss"
                    instruction = "煽りは見当違いだった。盤面の事実を根拠に余裕で言い返す。"
                extra_lines.append(f"相手の発言「{text}」は{ {'blunderCall':'悪手の指摘','hangingPiece':'駒が浮いているという指摘','threat':'玉が危ないという脅し','mock':'人格へのからかい','praise':'褒め言葉'}[kind.value]}。{why}")

        options = [dlg.ActionOption("none", "返事をするだけ")]
        req = intent.request
        if req in ("undo", "hint", "draw", "resign"):
            allowed = self._request_allowed(req)
            desc = {"undo": "相手の待ったを認める", "hint": "ヒントを教えてやる", "draw": "引き分けに応じる", "resign": "投了する"}[req]
            options = [dlg.ActionOption("refuse", f"相手の要求（{desc}）を断る")]
            if allowed:
                options.insert(0, dlg.ActionOption("accept", desc))
                instruction += f" 相手は『{desc[2:] if req == 'undo' else desc}』を求めている。気分次第で受けても断ってもよい。"
            else:
                instruction += " 相手は要求をしてきたが、今は断るしかない。理由をキャラらしく言う。"
        sl = self._maybe_slip(question_bonus) if intent.kind != "abuse" else None
        if sl:
            extra_lines.append(self._slip_extra(sl))
        reply = await self._speak(trigger, instruction, options, "\n".join(extra_lines), slip=sl)
        if req in ("undo", "hint", "draw", "resign") and reply.action == "accept" and self._request_allowed(req):
            await self._grant_request(req)

    def _truth_reason(self, kind: TauntKind, truth: float) -> str:
        if kind == TauntKind.blunderCall:
            if self.ai_loss is None:
                return "判定材料なし（図星ではない）。"
            return f"私の直前の手の損は約{self.ai_loss}点なので{'図星' if truth >= 1 else ('半分図星' if truth > 0 else '見当違い')}。"
        if kind == TauntKind.hangingPiece:
            return "実際に駒を取られる筋があるので図星。" if truth > 0 else "取られる駒はないので見当違い。"
        if kind == TauntKind.threat:
            return "実際に私の玉は危ないので図星。" if truth > 0 else "私の玉はまだ安全なので見当違い。"
        return ""

    def _request_allowed(self, req: str) -> bool:
        m = self.mind
        if req == "undo":
            return self.is_player_turn and len(self.moves) >= 2 and (m.hubris >= 0.5 or m.mood == Mood.smug) and self.counters["player_undo"] < 3
        if req == "hint":
            return self.is_player_turn and bool(self.player_cands) and (m.hubris >= 0.6 or m.mood == Mood.smug)
        if req == "draw":
            return self.result is None and (m.stance.value == "losing" or (m.stance.value == "even" and m.panic >= 0.5))
        if req == "resign":
            return self.result is None and (self.eval_ai <= -2000 or (m.mood == Mood.meltdown and self.eval_ai <= -1000))
        return False

    async def _grant_request(self, req: str) -> None:
        m = self.mind
        self._log("grant", request=req)
        if req == "undo":
            self._pop(); self._pop()
            self.counters["player_undo"] += 1
            self.mind = m.copy_with(hubris=m.hubris + 0.1)
            self.player_gain = None
            self.ai_loss = None
            await self._observe()
            self._system("軍師が待ったを認めました（あなたの手と軍師の応手を戻しました）")
        elif req == "hint":
            best = self.player_cands[0].usi
            self.counters["hint"] += 1
            self._system(f"軍師のヒント：{kif_text(self.board, best, self.moves[-1] if self.moves else None)}")
        elif req == "draw":
            self.result = {"winner": None, "reason": "agreement"}
            await self._on_game_over()
        elif req == "resign":
            self.result = {"winner": self.player_side, "reason": "resign"}
            await self._on_game_over()

    async def _on_game_over(self) -> None:
        r = self.result or {}
        w = r.get("winner")
        self._log("game_over", result=r, kif=self.kif)
        if w is None:
            self._system("引き分け")
            await self._speak("draw", "対局は引き分けで終わった。負け惜しみ混じりに締める。")
        elif w == self.ai_side:
            self._system(f"{SIDE_LABEL[w]}（軍師）の勝ち")
            await self._speak("win", "対局に勝った。高笑いで勝ち誇る。")
        else:
            self._system(f"{SIDE_LABEL[w]}（あなた）の勝ち")
            await self._speak("lose", "対局に負けた。悔しがり、言い訳し、再戦を要求する。")

    # ------------------------------------------------------------ UI 用
    def state(self) -> dict:
        m = self.mind
        return {
            "id": self.id,
            "board": board_json(self.board),
            "ai_side": self.ai_side,
            "player_side": self.player_side,
            "moves": self.moves,
            "kif": self.kif,
            "last_move": self.moves[-1] if self.moves else None,
            "legal": legal_moves_json(self.board) if self.is_player_turn and not self.pending else [],
            "in_check": self.board.is_check(),
            "mind": m.to_json(),
            "mood_label": m.mood.label,
            "stance_label": m.stance.label,
            "face": MOOD_FACE[m.mood.value],
            "eval_ai": self.eval_ai,
            "chat": self.chat[-60:],
            "pending": {"kind": self.pending.kind, "text": OFFER_TEXT[self.pending.kind]} if self.pending else None,
            "deal_turns": self.deal_turns,
            "result": self.result,
            "llm": {"model": self.llm.model if self.llm else None, "latency": self.llm.last_latency if self.llm else None,
                    "error": self.llm.last_error if self.llm else None},
        }
