import 'mind_state.dart';

/// 煽りの種類（設計書 §4.3）。
enum TauntKind { blunderCall, hangingPiece, threat, mock, praise }

/// 定型スタンプ。
class TauntStamp {
  const TauntStamp(this.id, this.kind, this.text);
  final String id;
  final TauntKind kind;
  final String text;
}

const tauntStamps = <TauntStamp>[
  TauntStamp('blunder', TauntKind.blunderCall, 'いまの手、悪手でしょ'),
  TauntStamp('hanging', TauntKind.hangingPiece, '駒、浮いてない？'),
  TauntStamp('threat', TauntKind.threat, '玉、危なくない？'),
  TauntStamp('mock', TauntKind.mock, '天才軍師（笑）'),
  TauntStamp('praise', TauntKind.praise, 'さすが天才軍師さま！'),
];

/// 煽り1回あたりの効果（truth=1, resistance=0 のとき）。
class TauntEffect {
  const TauntEffect({this.composure = 0, this.hubris = 0, this.panic = 0});
  final double composure, hubris, panic;
}

abstract final class TauntTable {
  static const hit = <TauntKind, TauntEffect>{
    TauntKind.blunderCall: TauntEffect(composure: -0.25, panic: 0.20),
    TauntKind.hangingPiece: TauntEffect(composure: -0.20, panic: 0.15),
    TauntKind.threat: TauntEffect(composure: -0.10, panic: 0.30),
    TauntKind.mock: TauntEffect(composure: -0.15, panic: 0.05),
    TauntKind.praise: TauntEffect(composure: 0.10, hubris: 0.10),
  };

  /// 外れ（truth=0）のとき: 余裕を見せて回復。
  static const miss = TauntEffect(composure: 0.05, hubris: 0.05);

  /// 盤面と無関係な揶揄は常にこの図星係数。
  static const mockTruth = 0.3;

  /// 慢心がこれを超えると揶揄は逆効果（冷静さが戻る）。
  static const mockBackfireHubris = 0.6;
}

class TauntOutcome {
  const TauntOutcome({required this.before, required this.after, required this.truth, required this.kind});
  final MindState before, after;
  final double truth;
  final TauntKind kind;

  bool get hit => truth > 0 && kind != TauntKind.praise;
  double get composureDelta => after.composure - before.composure;
  double get panicDelta => after.panic - before.panic;
}

/// 煽りを感情に反映する。[previousKind] は直前に受けた煽りの種類（耐性計算用）。
/// [intensity] は自由文の強さ（定型スタンプは 1.0）。
TauntOutcome applyTaunt(MindState s, TauntKind kind, double truth,
    {TauntKind? previousKind, double intensity = 1.0}) {
  final resistanceFactor = (1 - s.resistance) * intensity;
  var next = s;
  if (kind == TauntKind.praise) {
    final e = TauntTable.hit[kind]!;
    next = s.copyWith(
      composure: s.composure + e.composure * resistanceFactor,
      hubris: s.hubris + e.hubris * resistanceFactor,
    );
  } else if (kind == TauntKind.mock && s.hubris > TauntTable.mockBackfireHubris) {
    next = s.copyWith(composure: s.composure + TauntTable.miss.composure);
  } else if (truth <= 0) {
    next = s.copyWith(
      composure: s.composure + TauntTable.miss.composure,
      hubris: s.hubris + TauntTable.miss.hubris,
    );
  } else {
    final e = TauntTable.hit[kind]!;
    final k = truth * resistanceFactor;
    next = s.copyWith(
      composure: s.composure + e.composure * k,
      hubris: s.hubris + e.hubris * k,
      panic: s.panic + e.panic * k,
    );
  }
  final dr = previousKind == kind
      ? MindParams.resistanceSameKind
      : MindParams.resistanceOtherKind;
  next = next.copyWith(resistance: next.resistance + dr);
  if (kind == TauntKind.praise) {
    final streak = s.praiseStreak + 1;
    final lips = SlipParams.lipsPerPraise + SlipParams.lipsPerPraiseStreak * (streak < 4 ? streak : 4);
    final sus = streak >= SlipParams.praiseSuspicionFrom
        ? SlipParams.praiseSuspicionStep * (streak - SlipParams.praiseSuspicionFrom + 1)
        : 0.0;
    next = next.copyWith(
      praiseStreak: streak,
      looseLips: next.looseLips + lips * intensity,
      suspicion: next.suspicion + sus,
    );
  } else {
    next = next.copyWith(
      praiseStreak: 0,
      looseLips: next.looseLips + (truth > 0 ? SlipParams.lipsPerHit * truth * intensity : 0),
    );
  }
  return TauntOutcome(before: s, after: next, truth: truth, kind: kind);
}
