import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogue/intent.dart';
import '../../core/dialogue/lexicon.dart';
import '../../core/dialogue/player_memory.dart';
import '../../core/dialogue/tone.dart';
import '../../core/dialogue/line_library.dart';
import '../../core/engine/shogi_engine.dart';
import '../../core/mind/gunshi_brain.dart';
import '../../core/mind/mind_state.dart';
import '../../core/mind/move_policy.dart';
import '../../core/mind/negotiation.dart';
import '../../core/mind/slips.dart';
import '../../core/mind/taunts.dart';
import '../../core/shogi/shogi.dart';
import 'engine_controller.dart';

/// 選択中のもの: 盤上のマス、または持ち駒の種類。
sealed class Selection {
  const Selection();
}

class SquareSelection extends Selection {
  const SquareSelection(this.square);
  final int square;
}

class HandSelection extends Selection {
  const HandSelection(this.type);
  final PieceType type;
}

/// 対局相手の構成。
enum OpponentMode {
  human,
  aiWhite,
  aiBlack,
  aiBoth; // 動作確認用

  bool isAi(Side side) => switch (this) {
    OpponentMode.human => false,
    OpponentMode.aiWhite => side == Side.white,
    OpponentMode.aiBlack => side == Side.black,
    OpponentMode.aiBoth => true,
  };

  /// 感情表示の対象になる軍師の手番（1人のときだけ）。
  Side? get gunshiSide => switch (this) {
    OpponentMode.aiWhite => Side.white,
    OpponentMode.aiBlack => Side.black,
    _ => null,
  };
}

/// 感想戦の1手分。
class ReviewEntry {
  ReviewEntry({
    required this.ply,
    required this.side,
    required this.kif,
    required this.byGunshi,
    this.bestKif,
    this.lossCp,
  });

  /// 0 始まりの手数。
  final int ply;
  final Side side;
  final String kif;
  final bool byGunshi;

  /// エンジンの最善手（同じなら null）。
  final String? bestKif;

  /// 最善との差（cp）。分からないときは null。
  int? lossCp;

  bool get isBlunder => (lossCp ?? 0) >= 150;
}

enum ChatRole { gunshi, player, system }

class ChatEntry {
  const ChatEntry(this.role, this.text, {this.slip = false});
  final ChatRole role;
  final String text;

  /// 口が滑った発言（本当か嘘かは表示しない）。
  final bool slip;
}

class GameViewState {
  const GameViewState({
    required this.game,
    required this.revision,
    this.selection,
    this.legalTargets = const {},
    this.mode = OpponentMode.human,
    this.level = SkillLevel.normal,
    this.clock,
    this.declaration,
    this.review = const [],
    this.thinking = false,
    this.observing = false,
    this.lastSearch,
    this.engineError,
    this.mind,
    this.speech,
    this.lastTaunt,
    this.tauntAvailable = false,
    this.chat = const [],
    this.pendingOffer,
    this.dealTurns = 0,
  });

  final ShogiGame game;

  /// ShogiGame は可変なので、変更のたびに増やして再描画させる。
  final int revision;
  final Selection? selection;
  final Set<int> legalTargets;
  final OpponentMode mode;

  /// 軍師の棋力レベル。
  final SkillLevel level;

  /// 両者の残り時間（持ち時間なしのときも入る）。
  final GameClock? clock;

  /// 手番側の入玉宣言の可否（宣言ボタンの出し分けに使う）。
  final Declaration? declaration;

  /// 感想戦の材料（対局中も溜まる）。
  final List<ReviewEntry> review;
  final bool thinking;

  /// AI の手の直後に局面を解析中（煽りの図星判定の準備中）。
  final bool observing;
  final SearchResult? lastSearch;
  final String? engineError;

  /// 軍師の感情（1人の AI 対局時）。
  final MindState? mind;
  final String? speech;
  final TauntOutcome? lastTaunt;

  /// いま煽り・話しかけで感情を動かせるか（プレイヤーの手番につき最大3回）。
  final bool tauntAvailable;
  final List<ChatEntry> chat;

  /// 軍師からの持ちかけ（受ける/断るを待っている）。
  final OfferKind? pendingOffer;

  /// 取引中: あと何手煽らない約束か。
  final int dealTurns;

  Position get position => game.position;
  Move? get lastMove => game.moves.isEmpty ? null : game.moves.last;
}

/// 軍師のセリフ集。main() で読み込んで override する（未設定ならセリフなし）。
final lineLibraryProvider = Provider<LineLibrary?>((ref) => null);

/// 自由文分類の辞書。main() で読み込んで override する（未設定ならキーワード版）。
final intentLexiconProvider = Provider<IntentLexicon?>((ref) => null);

/// 相手について覚えていること。端末では main.dart が PlayerMemoryFile で読み込んだものを差し替える。
final playerMemoryProvider = Provider<PlayerMemory>((ref) => PlayerMemory());

/// 口調プロファイル（assets/lines/gunshi_tone.json）。気分に合わせてセリフを整える。
final toneProfileProvider = Provider<ToneProfile?>((ref) => null);

Future<ToneProfile> loadToneProfile() async =>
    ToneProfile.fromJsonString(await rootBundle.loadString(ToneProfile.assetPath));

Future<IntentLexicon> loadIntentLexicon() async => IntentLexicon.fromJson(
  await rootBundle.loadString(IntentLexicon.termsAsset),
  await rootBundle.loadString(IntentLexicon.sentimentAsset),
  await rootBundle.loadString(IntentLexicon.emotionAsset),
);

Future<LineLibrary> loadLineLibrary() async =>
    LineLibrary.fromJsonString(await rootBundle.loadString(LineLibrary.assetPath));

final gameControllerProvider = NotifierProvider<GameController, GameViewState>(GameController.new);

class GameController extends Notifier<GameViewState> {
  static const effectsPerTurn = 3;

  List<Move> _legal = const [];
  OpponentMode _mode = OpponentMode.human;
  SkillLevel _level = SkillLevel.normal;
  TimeControl _timeControl = TimeControl.none;
  GameClock _clock = GameClock(TimeControl.none);
  Timer? _ticker;
  DateTime? _turnStartedAt;
  Side? _clockSide;
  bool _thinking = false;
  bool _observing = false;
  SearchResult? _lastSearch;
  String? _engineError;
  int _gameId = 0;
  final Map<Side, GunshiBrain> _brains = {};
  String? _speech;
  TauntOutcome? _lastTaunt;
  int _effectsLeft = effectsPerTurn;
  final _rng = math.Random();
  final List<ChatEntry> _chat = [];
  final List<ReviewEntry> _review = [];
  String? _playerBestUsi;
  OfferKind? _pending;
  final Map<OfferKind, int> _offerCounts = {};
  int _lastOfferPly = -99;
  int _dealTurns = 0;
  int _undoCount = 0;
  Slip? _slipThisTurn;
  LineTrigger? _exploitReaction;

  @override
  GameViewState build() {
    ref.onDispose(() => _ticker?.cancel());
    final game = ShogiGame();
    _legal = game.position.legalMoves();
    return GameViewState(game: game, revision: 0);
  }

  ShogiGame get _game => state.game;
  GunshiBrain? get _gunshi => _mode.gunshiSide == null ? null : _brains[_mode.gunshiSide];

  void _refresh({Selection? selection}) {
    Set<int> targets = const {};
    if (_pending == null) {
      if (selection is SquareSelection) {
        targets = {
          for (final m in _legal)
            if (m.from == selection.square) m.to,
        };
      } else if (selection is HandSelection) {
        targets = {
          for (final m in _legal)
            if (m.drop == selection.type) m.to,
        };
      }
    }
    final g = _gunshi;
    state = GameViewState(
      game: _game,
      revision: state.revision + 1,
      selection: _pending == null ? selection : null,
      legalTargets: targets,
      mode: _mode,
      level: _level,
      clock: _clock,
      declaration: _game.isOver ? null : checkDeclaration(_game.position),
      review: List.unmodifiable(_review),
      thinking: _thinking,
      observing: _observing,
      lastSearch: _lastSearch,
      engineError: _engineError,
      mind: g?.mind,
      speech: _speech,
      lastTaunt: _lastTaunt,
      tauntAvailable:
          g != null &&
          _effectsLeft > 0 &&
          !_thinking &&
          !_game.isOver &&
          _game.position.turn != g.side &&
          g.canReceiveTaunt,
      chat: List.unmodifiable(_chat),
      pendingOffer: _pending,
      dealTurns: _dealTurns,
    );
  }

  // ------------------------------------------------------------ 持ち時間
  /// 持ち時間の設定。対局中に変えると時計を入れ替えて次の手から数え直す。
  void setTimeControl(TimeControl control) {
    _timeControl = control;
    _clock = GameClock(control);
    _startClockForTurn();
    _refresh();
  }

  TimeControl get timeControl => _timeControl;

  void _startClockForTurn() {
    _stopClock();
    if (_timeControl.unlimited || _game.isOver) return;
    final side = _game.position.turn;
    _clockSide = side;
    _clock.startTurn(side);
    _turnStartedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
  }

  void _stopClock() {
    _ticker?.cancel();
    _ticker = null;
    _chargeElapsed();
    _clockSide = null;
  }

  /// 前回の計測時から経った分を手番側から引く。
  void _chargeElapsed() {
    final side = _clockSide;
    final since = _turnStartedAt;
    if (side == null || since == null) return;
    final now = DateTime.now();
    _clock.tick(side, now.difference(since).inMilliseconds);
    _turnStartedAt = now;
  }

  void _onTick() {
    final side = _clockSide;
    if (side == null) return;
    _chargeElapsed();
    if (_clock.of(side).flagged) {
      _stopClock();
      _game.timeUp(side);
      _legal = const [];
      _pending = null;
      _onGameOverIfNeeded();
    }
    _refresh();
  }

  // ------------------------------------------------------------ 入玉宣言
  /// 入玉宣言。条件を満たしていれば終局し true。
  bool declareWin() {
    if (_game.isOver || !_humanToMove) return false;
    final ok = _game.declareWin(side: _game.position.turn);
    if (!ok) return false;
    _stopClock();
    _legal = const [];
    _pending = null;
    _onGameOverIfNeeded();
    _refresh();
    return true;
  }

  // ------------------------------------------------------------ セリフ
  String _line(LineTrigger trigger, {Map<String, String> vars = const {}}) {
    final lib = ref.read(lineLibraryProvider);
    final g = _gunshi;
    if (lib == null || g == null) return '';
    final line = lib.pick(g.mind.mood, trigger, _rng, vars: vars);
    // 気分に合わせて整える（動揺・大混乱では、平静から借りた丁寧なセリフを常体に戻す）
    return ref.read(toneProfileProvider)?.rewrite(line, mood: g.mind.mood.name) ?? line;
  }

  void _gunshiSays(String text, {bool slip = false}) {
    if (text.isEmpty) return;
    _speech = text;
    _chat.add(ChatEntry(ChatRole.gunshi, text, slip: slip));
    if (_chat.length > 80) _chat.removeRange(0, _chat.length - 80);
  }

  void _system(String text) => _chat.add(ChatEntry(ChatRole.system, text));

  void _say(LineTrigger trigger, {Map<String, String> vars = const {}}) => _gunshiSays(_line(trigger, vars: vars));

  String _kifOf(int moveIndex) {
    final positions = _game.positions;
    final moves = _game.moves;
    return kifMoveText(
      positions[moveIndex],
      moves[moveIndex],
      previous: moveIndex > 0 ? moves[moveIndex - 1] : null,
    ).replaceAll(RegExp(r'\(\d+\)'), '');
  }

  String _kifOfUsi(String usi) {
    final prev = _game.moves.isEmpty ? null : _game.moves.last;
    return kifMoveText(_game.position, Move.fromUsi(usi), previous: prev).replaceAll(RegExp(r'\(\d+\)'), '');
  }

  /// [moveIndex] の局面で指したことにして棋譜表記にする（感想戦の「最善手」用）。
  String _kifOfUsiAt(int moveIndex, String usi) {
    final positions = _game.positions;
    if (moveIndex < 0 || moveIndex >= positions.length) return '';
    return kifMoveText(
      positions[moveIndex],
      Move.fromUsi(usi),
      previous: moveIndex > 0 ? _game.moves[moveIndex - 1] : null,
    ).replaceAll(RegExp(r'\(\d+\)'), '');
  }

  /// 感想戦で添える軍師のひとこと。
  String reviewComment(ReviewEntry e) {
    if (!e.isBlunder) return '';
    return _line(e.byGunshi ? LineTrigger.blunderSelf : LineTrigger.blunderPlayer, vars: {'move': e.kif});
  }

  bool get _humanToMove => !_thinking && !_mode.isAi(state.position.turn);

  // ------------------------------------------------------------ 盤の操作
  /// マスをタップ。移動先として確定できる候補手を返す（成/不成の2択なら2件）。
  List<Move> tapSquare(int sq) {
    if (_game.isOver || !_humanToMove || _pending != null) return const [];
    final sel = state.selection;
    if (sel != null && state.legalTargets.contains(sq)) {
      return [
        for (final m in _legal)
          if (m.to == sq &&
              switch (sel) {
                SquareSelection(:final square) => m.from == square,
                HandSelection(:final type) => m.drop == type,
              })
            m,
      ];
    }
    final piece = state.position.board[sq];
    if (piece != null && piece.side == state.position.turn) {
      final same = sel is SquareSelection && sel.square == sq;
      _refresh(selection: same ? null : SquareSelection(sq));
    } else {
      _refresh();
    }
    return const [];
  }

  void tapHand(Side side, PieceType type) {
    if (_game.isOver || side != state.position.turn || !_humanToMove || _pending != null) return;
    if (state.position.handCount(side, type) == 0) return;
    final sel = state.selection;
    final same = sel is HandSelection && sel.type == type;
    _refresh(selection: same ? null : HandSelection(type));
  }

  /// 人間の着手。
  void play(Move move) {
    _checkExploit(move);
    final best = _playerBestUsi;
    _playerBestUsi = null;
    final side = _game.position.turn;
    _applyMove(move);
    _review.add(
      ReviewEntry(
        ply: _game.moves.length - 1,
        side: side,
        kif: _kifOf(_game.moves.length - 1),
        byGunshi: false,
        bestKif: best == null || best == move.toUsi() ? null : _kifOfUsiAt(_game.moves.length - 1, best),
      ),
    );
    if (_dealTurns > 0) _dealTurns--;
    _startNewPlayerTurnState();
    _refresh();
    _maybeAiMove();
  }

  void _startNewPlayerTurnState() {
    _effectsLeft = effectsPerTurn;
    _slipThisTurn = null;
    _gunshi?.tauntContext = null;
  }

  void _applyMove(Move move) {
    _game.play(move);
    _legal = _game.isOver ? const [] : _game.position.legalMoves();
    if (_game.isOver) {
      _stopClock();
    } else {
      _startClockForTurn();
    }
    _onGameOverIfNeeded();
  }

  void _onGameOverIfNeeded() {
    if (_game.isOver) _stopClock();
    final r = _game.result;
    final g = _gunshi;
    if (r == null || g == null) return;
    if (r.winner == null) {
      _gunshiSays('……引き分けか。きょうはこのくらいにしておいてやろう。');
    } else {
      _say(r.winner == g.side ? LineTrigger.win : LineTrigger.lose);
    }
  }

  /// 漏らした『こわい手』を相手が指したか。
  void _checkExploit(Move move) {
    final g = _gunshi;
    final sl = _slipThisTurn;
    if (g == null || sl == null || sl.kind != SlipKind.fear || sl.moveUsi != move.toUsi()) return;
    final m = g.mind;
    if (sl.truthful) {
      g.mind = m.copyWith(
        suspicion: m.suspicion + SlipParams.suspicionOnExploit,
        panic: m.panic + 0.15,
        composure: m.composure - 0.1,
      );
      _exploitReaction = LineTrigger.exploitedTrue;
    } else {
      g.mind = m.copyWith(hubris: m.hubris + 0.15, composure: m.composure + 0.05);
      _exploitReaction = LineTrigger.exploitedFalse;
    }
  }

  void undo() {
    if (_thinking) return;
    if (_pending != null) _pending = null;
    if (!_game.undo()) return;
    // AI 対局では人間の手番まで戻す。
    while (_mode != OpponentMode.aiBoth && _mode.isAi(_game.position.turn) && _game.moves.isNotEmpty) {
      _game.undo();
    }
    _legal = _game.position.legalMoves();
    _startNewPlayerTurnState();
    _refresh();
    _observeIfNeeded();
    _maybeAiMove();
  }

  /// 棋力レベルの切り替え。対局中でも次の手から効く。
  void setLevel(SkillLevel level) {
    _level = level;
    for (final b in _brains.values) {
      b.level = level;
    }
    _refresh();
  }

  /// 対局相手の切り替え。新しい軍師を用意する。
  void setMode(OpponentMode mode) {
    _mode = mode;
    _engineError = null;
    _resetBrains();
    _refresh();
    _maybeAiMove();
    _observeIfNeeded();
  }

  void _resetBrains() {
    _brains.clear();
    _speech = null;
    _lastTaunt = null;
    _chat.clear();
    _review.clear();
    _playerBestUsi = null;
    _pending = null;
    _offerCounts.clear();
    _lastOfferPly = -99;
    _dealTurns = 0;
    _undoCount = 0;
    _exploitReaction = null;
    _startNewPlayerTurnState();
    final status = ref.read(engineControllerProvider);
    if (status is! EngineReady) return;
    for (final side in Side.values) {
      if (_mode.isAi(side)) {
        _brains[side] = GunshiBrain(
          engine: status.engine,
          side: side,
          seed: DateTime.now().microsecondsSinceEpoch,
          level: _level,
        );
      }
    }
    if (_gunshi != null) _say(LineTrigger.start);
  }

  // ------------------------------------------------------------ 煽り・自由会話
  /// 定型スタンプ。
  void sendTaunt(TauntStamp stamp) => sendChat(stamp.text, forcedKind: stamp.kind);

  /// 自由文で話しかける。
  void sendChat(String raw, {TauntKind? forcedKind}) {
    final text = raw.trim();
    final g = _gunshi;
    if (text.isEmpty || g == null || _game.isOver) return;
    _chat.add(ChatEntry(ChatRole.player, text));
    if (_thinking || _game.position.turn == g.side) {
      _gunshiSays('今は考え中だ、話しかけるな。');
      _refresh();
      return;
    }
    final intent = forcedKind != null
        ? PlayerIntent(kind: IntentKind.values.byName(forcedKind.name), intensity: 1.0)
        : (ref.read(intentLexiconProvider)?.analyze(text, hasPendingOffer: _pending != null).intent ??
              classifyKeywords(text, hasPendingOffer: _pending != null));

    if (_pending != null && (intent.request == IntentRequest.accept || intent.request == IntentRequest.decline)) {
      respondOffer(intent.request == IntentRequest.accept);
      return;
    }

    var questionBonus = 0.0;
    if (intent.kind == IntentKind.abuse) {
      _say(LineTrigger.abuse);
    } else if (intent.isTaunt) {
      _handleTaunt(TauntKind.values.byName(intent.kind.name), intent.intensity, forced: forcedKind != null);
    } else if (intent.kind == IntentKind.question) {
      final m = g.mind;
      questionBonus = 0.1 + 0.25 * math.max(0.0, m.hubris - 0.4) + 0.15 * m.looseLips;
      g.mind = m.copyWith(looseLips: m.looseLips + SlipParams.lipsPerQuestion * (0.5 + m.hubris));
      _say(LineTrigger.questionDodge);
    } else if (asksIfAi(text)) {
      _say(LineTrigger.questionDodge);
    } else if (intent.request == IntentRequest.none) {
      _say(isSmalltalk(text) ? _remember(text) : LineTrigger.chat);
    }

    if (intent.request != IntentRequest.none &&
        intent.request != IntentRequest.accept &&
        intent.request != IntentRequest.decline) {
      _handleRequest(PlayerRequest.values.byName(intent.request.name));
    }
    if (intent.kind != IntentKind.abuse && !_game.isOver) _maybeSlip(questionBonus: questionBonus);
    _refresh();
  }

  /// 雑談として受ける。相手が話した事実を覚えて、smalltalk のセリフで返す。
  /// 覚える中身は規則で拾えるものだけ（M3で端末内LLMの提案を足し、保存の可否はここで判断する）。
  LineTrigger _remember(String text) {
    final memory = ref.read(playerMemoryProvider);
    final recent = [
      for (final e in _chat)
        if (e.role == ChatRole.player) e.text,
    ];
    final source = [...recent.length > 3 ? recent.sublist(recent.length - 3) : recent].join(' ');
    for (final f in keywordFacts(text, recent: recent)) {
      if (acceptFact(f, '$source $text')) memory.upsert(f);
    }
    return LineTrigger.smalltalk;
  }

  void _handleTaunt(TauntKind kind, double intensity, {required bool forced}) {
    final g = _gunshi!;
    if (_dealTurns > 0 && kind != TauntKind.praise) {
      g.mind = g.mind.copyWith(composure: g.mind.composure + 0.1, hubris: g.mind.hubris + 0.1);
      _dealTurns = 0;
      _say(LineTrigger.dealBroken);
      return;
    }
    if (_effectsLeft <= 0 || !g.canReceiveTaunt) {
      _gunshiSays(g.canReceiveTaunt ? 'しつこいぞ。同じ手番にそう何度も言われても動じん。' : '……ちょっと待て、盤面を確認中だ。');
      return;
    }
    _effectsLeft--;
    final out = g.receiveTaunt(kind, intensity: forced ? 1.0 : 0.6 + 0.6 * intensity);
    _lastTaunt = out;
    final m = g.mind;
    if (kind == TauntKind.praise) {
      if (m.praiseStreak >= SlipParams.praiseSuspicionFrom && m.suspicion >= 0.25) {
        _say(LineTrigger.praiseSuspicious);
      } else if (m.praiseStreak >= 3) {
        _say(LineTrigger.praiseFlood);
      } else {
        _say(LineTrigger.praised);
      }
    } else {
      _say(out.hit ? LineTrigger.tauntHit : LineTrigger.tauntMiss);
    }
  }

  void _handleRequest(PlayerRequest req) {
    final g = _gunshi!;
    final ctx = g.tauntContext;
    final allowed = requestAllowed(
      req,
      g.mind,
      evalAi: g.lastEvalAi,
      undoCount: _undoCount,
      hasCandidates: ctx != null && ctx.playerCandidates.isNotEmpty,
    );
    final undoPossible = _game.moves.length >= 2;
    if (!allowed || (req == PlayerRequest.undo && !undoPossible)) {
      _say(LineTrigger.requestRefuse);
      return;
    }
    _say(LineTrigger.requestAccept);
    switch (req) {
      case PlayerRequest.undo:
        _game.undo();
        _game.undo();
        _undoCount++;
        g.mind = g.mind.copyWith(hubris: g.mind.hubris + 0.1);
        _legal = _game.position.legalMoves();
        _system('軍師が待ったを認めました（あなたの手と軍師の応手を戻しました）');
        _startNewPlayerTurnState();
        _observeIfNeeded();
      case PlayerRequest.hint:
        _system('軍師のヒント：${_kifOfUsi(ctx!.playerCandidates.first.usi)}');
      case PlayerRequest.draw:
        _game.agreeDraw();
        _legal = const [];
      case PlayerRequest.resign:
        _game.resign(side: g.side);
        _legal = const [];
        _say(LineTrigger.lose);
    }
  }

  void _maybeSlip({double questionBonus = 0}) {
    final g = _gunshi;
    final ctx = g?.tauntContext;
    if (g == null || ctx == null || _slipThisTurn != null || _pending != null) return;
    final sl = decideSlip(
      mind: g.mind,
      position: _game.position,
      playerCandidates: ctx.playerCandidates,
      aiLossCp: g.lastAiMoveLossCp,
      prevUsi: _game.moves.isEmpty ? null : _game.moves.last.toUsi(),
      rng: _rng,
      questionBonus: questionBonus,
      ply: _game.moves.length,
    );
    if (sl == null) return;
    _slipThisTurn = sl;
    g.mind = g.mind.copyWith(looseLips: g.mind.looseLips + SlipParams.lipsAfterSlip);
    _gunshiSays(_line(LineTrigger.slip, vars: {'fact': sl.fact}), slip: true);
  }

  // ------------------------------------------------------------ 軍師からの持ちかけ
  void _maybeOffer() {
    final g = _gunshi;
    if (g == null || _pending != null || _game.isOver || _game.position.turn == g.side) return;
    final offers = availableOffers(
      NegotiationContext(
        mind: g.mind,
        ply: _game.moves.length,
        playerGainCp: g.lastPlayerGainCp,
        aiLossCp: g.lastAiMoveLossCp,
        lastOfferPly: _lastOfferPly,
        counts: _offerCounts,
      ),
    );
    for (final o in offers) {
      if (_rng.nextDouble() < offerGate[o]!) {
        _pending = o;
        _offerCounts[o] = (_offerCounts[o] ?? 0) + 1;
        _lastOfferPly = _game.moves.length;
        _say(switch (o) {
          OfferKind.offerPlayerUndo => LineTrigger.offerPlayerUndo,
          OfferKind.requestRedo => LineTrigger.requestRedo,
          OfferKind.proposeDeal => LineTrigger.proposeDeal,
          OfferKind.proposeDraw => LineTrigger.proposeDraw,
        });
        return;
      }
    }
  }

  void respondOffer(bool accept) {
    final g = _gunshi;
    final o = _pending;
    if (g == null || o == null) return;
    _pending = null;
    _system('あなたは提案を${accept ? '受けた' : '断った'}：${o.text}');
    final m = g.mind;
    switch (o) {
      case OfferKind.offerPlayerUndo:
        if (accept && _game.moves.length >= 2) {
          _game.undo();
          _game.undo();
          g.mind = m.copyWith(hubris: m.hubris + 0.1);
          _legal = _game.position.legalMoves();
          _say(LineTrigger.offerAccepted);
          _startNewPlayerTurnState();
          _refresh();
          _observeIfNeeded();
          return;
        }
        g.mind = m.copyWith(hubris: m.hubris - 0.05, composure: m.composure - 0.03);
        _say(LineTrigger.offerDeclined);
      case OfferKind.requestRedo:
        if (accept && _game.moves.isNotEmpty) {
          _game.undo();
          _legal = _game.position.legalMoves();
          g.mind = m.copyWith(composure: m.composure + 0.15, panic: m.panic - 0.1, coverUpTurns: 0);
          _refresh();
          _maybeAiMove(forceBest: true);
          return;
        }
        g.mind = m.copyWith(panic: m.panic + 0.15, composure: m.composure - 0.1);
        _say(LineTrigger.offerDeclined);
      case OfferKind.proposeDeal:
        if (accept) {
          _dealTurns = 3;
          g.mind = m.copyWith(composure: m.composure + 0.1);
          final cands = g.tauntContext?.playerCandidates ?? const [];
          final secret = cands.isEmpty ? '玉は包むように寄せよ' : '${_kifOfUsi(cands.last.usi)}が妙手らしい';
          _say(LineTrigger.dealSecret, vars: {'fact': secret});
          _system('軍師の秘密情報：$secret');
        } else {
          g.mind = m.copyWith(panic: m.panic + 0.05);
          _say(LineTrigger.offerDeclined);
        }
      case OfferKind.proposeDraw:
        if (accept) {
          _game.agreeDraw();
          _legal = const [];
          _onGameOverIfNeeded();
        } else {
          g.mind = m.copyWith(panic: m.panic + 0.1);
          _say(LineTrigger.offerDeclined);
        }
    }
    _refresh();
  }

  // ------------------------------------------------------------ AI の手番
  Future<void> _maybeAiMove({bool forceBest = false}) async {
    if (_thinking || _game.isOver || !_mode.isAi(_game.position.turn)) return;
    final brain = _brains[_game.position.turn];
    if (brain == null) {
      _engineError = 'エンジンが準備できていません';
      _refresh();
      return;
    }
    final gameId = _gameId;
    final ply = _game.moves.length;
    _thinking = true;
    _refresh();
    try {
      final turn = await brain.takeTurn(_game, forceBest: forceBest);
      if (gameId != _gameId || ply != _game.moves.length) return;
      _thinking = false;
      if (turn.resign) {
        _game.resign();
        _legal = const [];
        if (brain == _gunshi) _say(LineTrigger.lose);
        _refresh();
        return;
      }
      _lastSearch = SearchResult(bestMove: BestMove(turn.move!.toUsi()), candidates: [turn.choice!.candidate]);
      final playerMoveText = ply > 0 ? _kifOf(ply - 1) : '';
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (gameId != _gameId) return;
      _applyMove(turn.move!);
      final aiIndex = _game.moves.length - 1;
      final aiBest = turn.bestUsi;
      _review.add(
        ReviewEntry(
          ply: aiIndex,
          side: brain.side,
          kif: _kifOf(aiIndex),
          byGunshi: brain == _gunshi,
          bestKif: aiBest == null || aiBest == turn.move!.toUsi() ? null : _kifOfUsiAt(aiIndex, aiBest),
          lossCp: turn.choice!.lossCp,
        ),
      );
      // 直前のプレイヤーの手の損（＝軍師の得）が分かるのはこの時点
      final gain = brain.lastPlayerGainCp;
      if (gain != null) {
        for (final e in _review.reversed) {
          if (!e.byGunshi && e.lossCp == null) {
            e.lossCp = math.max(0, gain);
            break;
          }
        }
      }
      if (brain == _gunshi && !_game.isOver) {
        final aiText = _kifOf(aiIndex);
        final reaction = _exploitReaction;
        _exploitReaction = null;
        if (reaction != null) _say(reaction);
        if (forceBest) {
          _say(LineTrigger.redoDone);
        } else if (turn.playerBlundered) {
          _say(LineTrigger.blunderPlayer, vars: {'move': playerMoveText});
        } else if (turn.choice!.lossCp >= 150) {
          _say(LineTrigger.blunderSelf, vars: {'move': aiText});
        } else {
          _say(LineTrigger.move, vars: {'move': aiText});
        }
      }
      _refresh();
      if (_mode.isAi(_game.position.turn)) {
        _maybeAiMove();
      } else {
        _observeIfNeeded();
      }
    } catch (e) {
      if (gameId != _gameId) return;
      _thinking = false;
      _engineError = '$e';
      _refresh();
    }
  }

  /// プレイヤーの手番になったら、軍師が局面を解析して図星判定・ボロ・持ちかけの準備をする。
  Future<void> _observeIfNeeded() async {
    final g = _gunshi;
    if (g == null || _game.isOver || _game.position.turn == g.side || g.canReceiveTaunt || _observing) return;
    final gameId = _gameId;
    final ply = _game.moves.length;
    _observing = true;
    _refresh();
    try {
      await g.observePlayerTurn(_game);
      _playerBestUsi = g.tauntContext?.playerCandidates.firstOrNull?.usi;
    } catch (e) {
      _engineError = '$e';
    } finally {
      _observing = false;
      if (gameId == _gameId && ply == _game.moves.length) {
        _maybeOffer();
        if (_pending == null) _maybeSlip();
        _refresh();
      } else {
        g.tauntContext = null;
      }
    }
  }

  void resign() {
    if (_thinking) return;
    _pending = null;
    _game.resign();
    _legal = const [];
    if (_gunshi != null) _say(LineTrigger.win);
    _refresh();
  }

  void newGame() {
    _gameId++;
    _clock = GameClock(_timeControl);
    _thinking = false;
    _observing = false;
    _lastSearch = null;
    _engineError = null;
    final game = ShogiGame();
    _legal = game.position.legalMoves();
    state = GameViewState(game: game, revision: state.revision + 1, mode: _mode, level: _level, clock: _clock);
    _resetBrains();
    _startClockForTurn();
    _refresh();
    _maybeAiMove();
    _observeIfNeeded();
  }
}
