import 'dart:math' as math;

import '../engine/shogi_engine.dart';
import '../shogi/shogi.dart';
import 'mind_state.dart';
import 'move_policy.dart';
import 'taunts.dart';
import 'truth_judge.dart';

/// AI の1手分の決定。
class AiTurn {
  const AiTurn({
    required this.move,
    required this.choice,
    required this.evalAi,
    this.bestUsi,
    required this.mindBefore,
    required this.mindAfter,
    this.playerBlundered = false,
    this.resign = false,
  });

  final Move? move;
  final PolicyChoice? choice;

  /// 着手前の AI 視点評価値（sortScore）。
  final int evalAi;

  /// エンジンの最善手（感想戦で「本当はこう指すべきだった」に使う）。
  final String? bestUsi;
  final MindState mindBefore, mindAfter;

  /// 直前のプレイヤーの手が悪手だった（AI 視点で 150cp 以上得した）。
  final bool playerBlundered;
  final bool resign;
}

/// 感情を持つ軍師 AI（エンジン＋感情状態＋着手変調）。
class GunshiBrain {
  GunshiBrain({
    required this.engine,
    required this.side,
    int seed = 0,
    this.modulate = true,
    MindState? fixedMind,
    this.baseMovetimeMs = PolicyParams.baseMovetimeMs,
    this.level = SkillLevel.normal,
    this.fixedMovetimeMs,
    this.observeMs = 300,
  }) : _rng = math.Random(seed),
       _fixed = fixedMind != null,
       mind = fixedMind ?? const MindState();

  final ShogiEngine engine;
  final Side side;
  final bool modulate;
  final int baseMovetimeMs;

  /// 棋力レベル（人間が選ぶ強さ）。
  SkillLevel level;

  /// 指定すると感情に関係なく思考時間を固定（自己対局用）。
  final int? fixedMovetimeMs;
  final int observeMs;
  final math.Random _rng;
  final bool _fixed;

  MindState mind;
  final List<MindState> log = [];

  int? _bestScoreBeforeAiMove;
  int? _expectedEvalAi;
  int? lastAiMoveLossCp;

  /// 直前のプレイヤーの手で AI が得した量（プレイヤーの損）。
  int? lastPlayerGainCp;

  /// 直近の AI 視点評価値。
  int lastEvalAi = 0;
  TauntContext? tauntContext;
  TauntKind? _previousTaunt;

  math.Random get rng => _rng;

  List<String> _usiMoves(ShogiGame g) => [for (final m in g.moves) m.toUsi()];

  /// [forceBest] は置き直し（最善で指し直す）用。
  Future<AiTurn> takeTurn(ShogiGame game, {bool forceBest = false}) async {
    final pos = game.position;
    if (pos.turn != side) throw StateError('not AI turn');
    final before = mind;
    final multiPv = modulate && !forceBest ? multiPvFor(mind, level: level) : 1;
    final movetime = fixedMovetimeMs ?? movetimeFor(mind, baseMs: baseMovetimeMs, level: level);
    await engine.setPosition(game.startPosition.toSfen(), _usiMoves(game));
    final result = await engine.think(movetimeMs: movetime, multiPv: multiPv);
    final cands = result.candidates.where((c) {
      try {
        return pos.isLegal(Move.fromUsi(c.usi));
      } on FormatException {
        return false;
      }
    }).toList();
    if (result.bestMove.isResign || cands.isEmpty) {
      return AiTurn(move: null, choice: null, evalAi: -100000, mindBefore: before, mindAfter: mind, resign: true);
    }
    final evalAi = cands.first.sortScore;
    final expected = _expectedEvalAi;
    final playerBlundered = expected != null && evalAi - expected >= 150;
    if (!forceBest) lastPlayerGainCp = expected == null ? null : evalAi - expected;
    lastEvalAi = evalAi;
    if (!_fixed && !forceBest) {
      mind = updateOnAiTurn(mind, evalAi: evalAi);
    }
    log.add(mind);
    final choice = chooseMove(
      candidates: cands,
      pos: pos,
      mind: mind,
      rng: _rng,
      modulate: modulate && !forceBest,
      level: level,
    );
    _bestScoreBeforeAiMove = cands.first.sortScore.clamp(-PolicyParams.scoreClampCp, PolicyParams.scoreClampCp);
    tauntContext = null;
    return AiTurn(
      move: Move.fromUsi(choice.candidate.usi),
      choice: choice,
      evalAi: evalAi,
      bestUsi: cands.first.usi,
      mindBefore: before,
      mindAfter: mind,
      playerBlundered: playerBlundered,
    );
  }

  /// AI が指した直後（プレイヤーの手番）に呼ぶ。評価損と図星判定の材料を集める。
  Future<void> observePlayerTurn(ShogiGame game) async {
    final pos = game.position;
    if (pos.turn == side || game.isOver) return;
    final cands = await engine.analyze(
      game.startPosition.toSfen(),
      moves: _usiMoves(game),
      movetimeMs: observeMs,
      multiPv: 3,
    );
    if (cands.isEmpty) return;
    final aiAfter = -cands.first.sortScore.clamp(-PolicyParams.scoreClampCp, PolicyParams.scoreClampCp);
    _expectedEvalAi = aiAfter;
    final before = _bestScoreBeforeAiMove;
    lastAiMoveLossCp = before == null ? null : math.max(0, before - aiAfter);
    if (!_fixed && (lastAiMoveLossCp ?? 0) >= MindParams.coverUpLossCp) {
      mind = mind.copyWith(coverUpTurns: MindParams.coverUpTurns);
    }
    tauntContext = TauntContext(position: pos, playerCandidates: cands, lastAiMoveLossCp: lastAiMoveLossCp);
  }

  bool get canReceiveTaunt => tauntContext != null;

  TauntOutcome receiveTaunt(TauntKind kind, {double intensity = 1.0}) {
    final ctx = tauntContext;
    final truth = ctx == null ? 0.0 : judgeTruth(kind, ctx);
    final out = applyTaunt(mind, kind, truth, previousKind: _previousTaunt, intensity: intensity);
    _previousTaunt = kind;
    if (!_fixed) mind = out.after;
    return out;
  }
}
