import 'mind_state.dart';

/// 軍師から持ちかける交渉（Python: session.py の OFFER_* と _initiatives）。
enum OfferKind {
  offerPlayerUndo('一手待ってやろうか？'),
  requestRedo('すまん、さっきの置き直していいか？'),
  proposeDeal('取引しないか？ 3手煽らなければ秘密の読み筋を教えよう'),
  proposeDraw('ここは引き分けということにしないか？');

  const OfferKind(this.text);
  final String text;
}

class NegotiationContext {
  const NegotiationContext({
    required this.mind,
    required this.ply,
    required this.playerGainCp,
    required this.aiLossCp,
    required this.lastOfferPly,
    required this.counts,
  });
  final MindState mind;
  final int ply;

  /// 直前のプレイヤーの手の損（AI が得した量）。
  final int? playerGainCp;

  /// 直前の AI の手の損。
  final int? aiLossCp;
  final int lastOfferPly;
  final Map<OfferKind, int> counts;
}

/// 条件を満たす持ちかけ（実際に出すかは呼び出し側が確率で決める）。
List<OfferKind> availableOffers(NegotiationContext c) {
  final m = c.mind;
  if (c.ply - c.lastOfferPly < 4) return const [];
  final out = <OfferKind>[];
  if (m.stance == Stance.dominant &&
      m.hubris >= 0.55 &&
      (c.playerGainCp ?? 0) >= 150 &&
      (c.counts[OfferKind.offerPlayerUndo] ?? 0) < 2 &&
      c.ply >= 2) {
    out.add(OfferKind.offerPlayerUndo);
  }
  if ((c.aiLossCp ?? 0) >= 150 && (c.counts[OfferKind.requestRedo] ?? 0) < 1) {
    out.add(OfferKind.requestRedo);
  }
  if (m.stance == Stance.even && c.ply >= 20 && (c.counts[OfferKind.proposeDeal] ?? 0) < 1 && m.panic >= 0.25) {
    out.add(OfferKind.proposeDeal);
  }
  if (m.stance == Stance.losing && m.panic >= 0.6 && (c.counts[OfferKind.proposeDraw] ?? 0) < 1) {
    out.add(OfferKind.proposeDraw);
  }
  return out;
}

const offerGate = {
  OfferKind.requestRedo: 0.8,
  OfferKind.offerPlayerUndo: 0.7,
  OfferKind.proposeDeal: 0.4,
  OfferKind.proposeDraw: 0.5,
};

enum PlayerRequest { undo, hint, draw, resign }

/// プレイヤーの要求を軍師が認められる状況か。
bool requestAllowed(
  PlayerRequest r,
  MindState m, {
  required int evalAi,
  required int undoCount,
  required bool hasCandidates,
}) {
  switch (r) {
    case PlayerRequest.undo:
      return (m.hubris >= 0.5 || m.mood == Mood.smug) && undoCount < 3;
    case PlayerRequest.hint:
      return hasCandidates && (m.hubris >= 0.6 || m.mood == Mood.smug);
    case PlayerRequest.draw:
      return m.stance == Stance.losing || (m.stance == Stance.even && m.panic >= 0.5);
    case PlayerRequest.resign:
      return evalAi <= -2000 || (m.mood == Mood.meltdown && evalAi <= -1000);
  }
}
