import '../engine/usi_protocol.dart';
import '../shogi/shogi.dart';
import 'taunts.dart';

/// 図星判定に必要な局面情報（プレイヤーの手番、AI が指した直後）。
class TauntContext {
  const TauntContext({
    required this.position,
    required this.playerCandidates,
    this.lastAiMoveLossCp,
  });

  /// プレイヤーが指す番の局面。
  final Position position;

  /// この局面のエンジン候補（プレイヤー視点、最善が先頭）。
  final List<Candidate> playerCandidates;

  /// 直前の AI の手の評価損（cp）。
  final int? lastAiMoveLossCp;
}

/// 図星係数 truth ∈ {0, 0.3, 0.5, 1.0}（設計書 §4.3）。
double judgeTruth(TauntKind kind, TauntContext ctx) {
  switch (kind) {
    case TauntKind.blunderCall:
      final loss = ctx.lastAiMoveLossCp;
      if (loss == null) return 0;
      if (loss >= 150) return 1.0;
      if (loss >= 50) return 0.5;
      return 0;
    case TauntKind.hangingPiece:
      final best = ctx.playerCandidates.isEmpty ? null : ctx.playerCandidates.first;
      if (best == null) return 0;
      final Move move;
      try {
        move = Move.fromUsi(best.usi);
      } on FormatException {
        return 0;
      }
      if (move.isDrop || ctx.position.board[move.to] == null) return 0;
      // 駒を取るのが最善で、しかもプレイヤーが明確に得をするなら「浮いている」。
      return best.sortScore >= 150 ? 1.0 : 0.5;
    case TauntKind.threat:
      // プレイヤー側に詰みがある＝AI玉が詰めろ以上。
      final best = ctx.playerCandidates.isEmpty ? null : ctx.playerCandidates.first;
      if (best?.mateIn != null && best!.mateIn! > 0) return 1.0;
      if (best != null && best.sortScore >= 1500) return 0.5;
      return 0;
    case TauntKind.mock:
      return TauntTable.mockTruth;
    case TauntKind.praise:
      return 1.0;
  }
}
