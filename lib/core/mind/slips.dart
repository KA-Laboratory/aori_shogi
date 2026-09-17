import 'dart:math' as math;

import '../engine/usi_protocol.dart';
import '../shogi/shogi.dart';
import 'mind_state.dart';

/// ボロ（口が滑る）: 軍師がうっかり読みや弱点を漏らす。本当のことも嘘（ブラフ）もある。
/// Python: aori_lab/slips.py の移植。コードが「漏らすか・何を・真偽」を決め、言い方はセリフ側。
enum SlipKind { plan, fear, confess, eval }

class Slip {
  const Slip({required this.kind, required this.truthful, required this.fact, this.moveUsi, this.ply = 0});

  final SlipKind kind;
  final bool truthful;

  /// 漏らす内容（例: 「▲４五桂と指されるのが一番こわい」）。
  final String fact;

  /// plan: 軍師が指すつもりの手 / fear: 相手に指されたら困る手。
  final String? moveUsi;
  final int ply;
}

double slipChance(MindState m, {double questionBonus = 0}) {
  final p = 0.02 +
      0.55 * m.looseLips +
      0.15 * math.max(0.0, m.panic - 0.5) +
      0.1 * math.max(0.0, m.hubris - 0.6) +
      questionBonus;
  return p.clamp(0.0, 0.8);
}

double truthfulChance(MindState m) => (0.9 - 0.75 * m.suspicion).clamp(0.15, 0.9);

String _kif(Position before, String usi, String? prevUsi) {
  final prev = prevUsi == null ? null : Move.fromUsi(prevUsi);
  final side = before.turn == Side.black ? '▲' : '△';
  return side + kifMoveText(before, Move.fromUsi(usi), previous: prev).replaceAll(RegExp(r'\(\d+\)'), '');
}

/// プレイヤーの手番の局面で呼ぶ。[playerCandidates] はプレイヤー視点（pv 付き、最善が先頭）。
Slip? decideSlip({
  required MindState mind,
  required Position position,
  required List<Candidate> playerCandidates,
  required int? aiLossCp,
  required String? prevUsi,
  required math.Random rng,
  double questionBonus = 0,
  int ply = 0,
}) {
  if (playerCandidates.isEmpty || rng.nextDouble() >= slipChance(mind, questionBonus: questionBonus)) {
    return null;
  }
  var truthful = rng.nextDouble() < truthfulChance(mind);
  final weights = <SlipKind, double>{
    SlipKind.plan: 1.0 + 2.0 * mind.hubris,
    SlipKind.fear: 0.5 + 2.5 * mind.panic,
    SlipKind.confess: ((aiLossCp ?? 0) >= 150 ? 2.5 : 0.3) * (0.5 + mind.panic),
    SlipKind.eval: 0.6 + (mind.stance != Stance.even ? 1.0 : 0.0),
  };
  final total = weights.values.reduce((a, b) => a + b);
  var r = rng.nextDouble() * total;
  var kind = SlipKind.eval;
  for (final e in weights.entries) {
    r -= e.value;
    if (r <= 0) {
      kind = e.key;
      break;
    }
  }
  final best = playerCandidates.first;
  final worst = playerCandidates.length > 1 ? playerCandidates.last : null;

  try {
    switch (kind) {
      case SlipKind.fear:
        if (!truthful && worst == null) truthful = true;
        final c = truthful ? best : worst!;
        return Slip(
            kind: kind, truthful: truthful, fact: '${_kif(position, c.usi, prevUsi)}と指されるのが一番こわい', moveUsi: c.usi, ply: ply);
      case SlipKind.plan:
        final src = truthful ? best : (worst ?? best);
        if (src.pv.length < 2) return null;
        if (!truthful && identical(src, best)) truthful = true;
        final after = position.play(Move.fromUsi(src.pv[0]));
        return Slip(
            kind: kind,
            truthful: truthful,
            fact: '次は${_kif(after, src.pv[1], src.pv[0])}で決めるつもり',
            moveUsi: src.pv[1],
            ply: ply);
      case SlipKind.confess:
        final loss = aiLossCp ?? 0;
        if (truthful && loss >= 150) {
          return Slip(kind: kind, truthful: true, fact: 'さっきの手は実は悪手だった', ply: ply);
        }
        if (!truthful && loss < 50) {
          return Slip(kind: kind, truthful: false, fact: 'さっきの手は実は悪手だった', ply: ply);
        }
        break;
      case SlipKind.eval:
        break;
    }
  } on FormatException {
    return null;
  }
  const real = {Stance.dominant: '実はもう勝ちが見えている', Stance.even: '実はまだ決め手がない', Stance.losing: '実はかなり苦しい'};
  const fake = {Stance.dominant: '実はかなり苦しい', Stance.even: '実はもう勝ちが見えている', Stance.losing: '実はもう勝ちが見えている'};
  return Slip(kind: SlipKind.eval, truthful: truthful, fact: (truthful ? real : fake)[mind.stance]!, ply: ply);
}
