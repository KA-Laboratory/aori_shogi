import 'dart:math' as math;

import '../engine/usi_protocol.dart';
import '../shogi/shogi.dart';
import 'mind_state.dart';

/// 感情でエンジンの着手を変調する（設計書 §4.4）。
abstract final class PolicyParams {
  static const baseMovetimeMs = 1500;
  static const tempBase = 30.0;
  static const tempComposure = 400.0;
  static const tempPanic = 300.0;
  static const hubrisThreshold = 0.6;
  static const hubrisAttackBonusCp = 60;
  static const blunderPanicThreshold = 0.7;
  static const blunderRate = 0.15;
  static const blunderMinLossCp = 300;
  static const blunderMaxLossCp = 600;
  static const mateMissPanic = 0.9;
  static const mateMissRate = 0.3;
  static const normalMultiPv = 5;
  static const panicMultiPv = 8;

  /// 評価差を数値化するときの詰みの上限（sortScore が ±100000 近くになるため）。
  static const scoreClampCp = 5000;
}

int movetimeFor(MindState s, {int baseMs = PolicyParams.baseMovetimeMs}) =>
    (baseMs * (0.4 + 0.6 * s.composure)).round();

int multiPvFor(MindState s) =>
    s.panic > PolicyParams.blunderPanicThreshold ? PolicyParams.panicMultiPv : PolicyParams.normalMultiPv;

double temperatureFor(MindState s) =>
    PolicyParams.tempBase + PolicyParams.tempComposure * (1 - s.composure) + PolicyParams.tempPanic * s.panic;

enum PolicyReason { best, softmax, hubrisAttack, blunder, mate, mateMissed }

class PolicyChoice {
  const PolicyChoice({required this.index, required this.candidate, required this.lossCp, required this.reason});
  final int index;
  final Candidate candidate;

  /// 最善との評価差（cp、詰みはクランプ）。
  final int lossCp;
  final PolicyReason reason;
}

int _clamped(Candidate c) => c.sortScore.clamp(-PolicyParams.scoreClampCp, PolicyParams.scoreClampCp);

/// 攻めの手（駒取り・成り・王手）か。
bool isAttackingMove(Position pos, Move m) {
  if (m.promote) return true;
  if (!m.isDrop && pos.board[m.to] != null) return true;
  return pos.play(m).inCheck(pos.turn.opponent);
}

/// [candidates] は手番側視点・最善が先頭。[pos] は候補を指す局面。
PolicyChoice chooseMove({
  required List<Candidate> candidates,
  required Position pos,
  required MindState mind,
  required math.Random rng,
  bool modulate = true,
}) {
  if (candidates.isEmpty) throw ArgumentError('no candidates');
  final best = candidates.first;
  final bestScore = _clamped(best);
  PolicyChoice pick(int i, PolicyReason r) => PolicyChoice(
    index: i,
    candidate: candidates[i],
    lossCp: math.max(0, bestScore - _clamped(candidates[i])),
    reason: r,
  );

  if (!modulate || candidates.length == 1) return pick(0, PolicyReason.best);

  // 詰みは逃さない（ただし大混乱なら時々逃す）。
  if (best.mateIn != null && best.mateIn! > 0) {
    final miss = mind.panic > PolicyParams.mateMissPanic && rng.nextDouble() < PolicyParams.mateMissRate;
    if (!miss) return pick(0, PolicyReason.mate);
    final others = [
      for (var i = 1; i < candidates.length; i++)
        if (candidates[i].mateIn == null) i,
    ];
    if (others.isNotEmpty) return pick(others[rng.nextInt(others.length)], PolicyReason.mateMissed);
    return pick(0, PolicyReason.mate);
  }

  // 大悪手の混入。
  if (mind.panic > PolicyParams.blunderPanicThreshold && rng.nextDouble() < PolicyParams.blunderRate * mind.panic) {
    final pool = <int>[];
    for (var i = 1; i < candidates.length; i++) {
      final d = bestScore - _clamped(candidates[i]);
      if (d >= PolicyParams.blunderMinLossCp && d <= PolicyParams.blunderMaxLossCp) pool.add(i);
    }
    if (pool.isEmpty) {
      for (var i = candidates.length - 1; i >= 1; i--) {
        if (bestScore - _clamped(candidates[i]) >= PolicyParams.blunderMinLossCp) {
          pool.add(i);
          break;
        }
      }
    }
    if (pool.isNotEmpty) return pick(pool[rng.nextInt(pool.length)], PolicyReason.blunder);
  }

  // softmax（慢心なら攻め手に見かけのボーナス）。
  final hubrisOn = mind.hubris > PolicyParams.hubrisThreshold;
  final t = temperatureFor(mind);
  final scores = <double>[];
  final bonus = <bool>[];
  for (final c in candidates) {
    var s = _clamped(c).toDouble();
    var b = false;
    if (hubrisOn) {
      try {
        final m = Move.fromUsi(c.usi);
        if (isAttackingMove(pos, m)) {
          s += PolicyParams.hubrisAttackBonusCp;
          b = true;
        }
      } on FormatException {
        // ignore
      }
    }
    scores.add(s);
    bonus.add(b);
  }
  final top = scores.reduce(math.max);
  final weights = [for (final s in scores) math.exp(-(top - s) / t)];
  final sum = weights.reduce((a, b) => a + b);
  var r = rng.nextDouble() * sum;
  var chosen = weights.length - 1;
  for (var i = 0; i < weights.length; i++) {
    r -= weights[i];
    if (r <= 0) {
      chosen = i;
      break;
    }
  }
  final reason = chosen == 0 ? PolicyReason.best : (bonus[chosen] ? PolicyReason.hubrisAttack : PolicyReason.softmax);
  return pick(chosen, reason);
}
