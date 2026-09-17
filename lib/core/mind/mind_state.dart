/// 軍師の感情状態（設計書 §4.1）。すべて決定的に更新する。
library;

enum Stance {
  dominant, // 優勢
  even, // 互角
  losing; // 劣勢

  String get label => switch (this) {
        Stance.dominant => '優勢',
        Stance.even => '互角',
        Stance.losing => '劣勢',
      };

  /// AI視点の評価値（詰みは sortScore で ±100000 近く）から形勢を決める。
  static Stance fromEval(int evalAi) {
    if (evalAi >= MindParams.stanceThreshold) return Stance.dominant;
    if (evalAi <= -MindParams.stanceThreshold) return Stance.losing;
    return Stance.even;
  }
}

enum Mood {
  composed, // 平静
  smug, // 慢心
  rattled, // 動揺
  meltdown, // 崩壊
  coverUp; // 取り繕い

  String get label => switch (this) {
        Mood.composed => '平静',
        Mood.smug => 'ドヤ顔',
        Mood.rattled => '動揺',
        Mood.meltdown => '大混乱',
        Mood.coverUp => '取り繕い',
      };
}

/// 数値パラメータ（Python 版と共有する定数。変更時は両方を合わせる）。
abstract final class MindParams {
  static const stanceThreshold = 300;
  static const initialComposure = 0.8;
  static const initialHubris = 0.3;
  static const initialPanic = 0.1;
  static const recoveryPerMove = 0.03;
  static const hubrisGainDominant = 0.05;
  static const panicGainLosing = 0.06;
  static const resistanceSameKind = 0.15;
  static const resistanceOtherKind = -0.05;
  static const coverUpLossCp = 200;
  static const coverUpTurns = 2;
}

/// 口の軽さ・警戒心（自由会話とボロ）。Python: aori_lab/mind.py の SP と同値。
abstract final class SlipParams {
  static const initialLooseLips = 0.1;
  static const lipsDecayPerMove = 0.04;
  static const suspicionDecayPerMove = 0.02;
  static const lipsPerPraise = 0.10;
  static const lipsPerPraiseStreak = 0.05;
  static const praiseSuspicionFrom = 4;
  static const praiseSuspicionStep = 0.08;
  static const lipsPerHit = 0.05;
  static const lipsPerQuestion = 0.06;
  static const lipsAfterSlip = -0.20;
  static const suspicionOnExploit = 0.25;
}

class MindState {
  const MindState({
    this.composure = MindParams.initialComposure,
    this.hubris = MindParams.initialHubris,
    this.panic = MindParams.initialPanic,
    this.resistance = 0,
    this.stance = Stance.even,
    this.coverUpTurns = 0,
    this.looseLips = SlipParams.initialLooseLips,
    this.suspicion = 0,
    this.praiseStreak = 0,
  });

  final double composure;
  final double hubris;
  final double panic;
  final double resistance;
  final Stance stance;

  /// 取り繕いモードの残り手数。
  final int coverUpTurns;

  /// 口の軽さ 0..1: 褒め倒し・慢心・焦りで上がり、ボロが出やすくなる。
  final double looseLips;

  /// 警戒心 0..1: 褒めすぎ・漏らした手を突かれると上がり、嘘のボロが増える。
  final double suspicion;

  /// 連続で褒められた回数。
  final int praiseStreak;

  Mood get mood => moodFor(this);

  MindState copyWith({
    double? composure,
    double? hubris,
    double? panic,
    double? resistance,
    Stance? stance,
    int? coverUpTurns,
    double? looseLips,
    double? suspicion,
    int? praiseStreak,
  }) =>
      MindState(
        composure: _clip(composure ?? this.composure),
        hubris: _clip(hubris ?? this.hubris),
        panic: _clip(panic ?? this.panic),
        resistance: _clip(resistance ?? this.resistance),
        stance: stance ?? this.stance,
        coverUpTurns: coverUpTurns ?? this.coverUpTurns,
        looseLips: _clip(looseLips ?? this.looseLips),
        suspicion: _clip(suspicion ?? this.suspicion),
        praiseStreak: praiseStreak ?? this.praiseStreak,
      );

  Map<String, Object> toJson() => {
        'composure': composure,
        'hubris': hubris,
        'panic': panic,
        'resistance': resistance,
        'stance': stance.name,
        'coverUpTurns': coverUpTurns,
        'looseLips': looseLips,
        'suspicion': suspicion,
        'praiseStreak': praiseStreak,
        'mood': mood.name,
      };

  @override
  String toString() =>
      'Mind(${stance.name} ${mood.name} c=${composure.toStringAsFixed(2)} '
      'h=${hubris.toStringAsFixed(2)} p=${panic.toStringAsFixed(2)} r=${resistance.toStringAsFixed(2)})';
}

double _clip(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// 気分の決定表（上から順に評価）。
Mood moodFor(MindState s) {
  if (s.coverUpTurns > 0) return Mood.coverUp;
  if (s.panic >= 0.75 || (s.stance == Stance.losing && s.composure < 0.3)) {
    return Mood.meltdown;
  }
  if (s.panic >= 0.45 || s.composure < 0.45) return Mood.rattled;
  if (s.stance == Stance.dominant && s.hubris >= 0.5) return Mood.smug;
  return Mood.composed;
}

/// AI の手番が来るたびの更新（自然回復・形勢連動・取り繕いの減衰）。
MindState updateOnAiTurn(MindState s, {required int evalAi, int? lastAiMoveLossCp}) {
  final stance = Stance.fromEval(evalAi);
  var c = s.composure + MindParams.recoveryPerMove;
  var p = s.panic - MindParams.recoveryPerMove;
  var h = s.hubris;
  if (stance == Stance.dominant) h += MindParams.hubrisGainDominant;
  if (stance == Stance.losing) p += MindParams.panicGainLosing;
  if (stance != Stance.dominant) h -= MindParams.recoveryPerMove; // 優勢でなければ慢心は冷める
  var cover = s.coverUpTurns > 0 ? s.coverUpTurns - 1 : 0;
  if (lastAiMoveLossCp != null && lastAiMoveLossCp >= MindParams.coverUpLossCp) {
    cover = MindParams.coverUpTurns;
  }
  return s.copyWith(
    composure: c,
    hubris: h,
    panic: p,
    stance: stance,
    coverUpTurns: cover,
    looseLips: s.looseLips - SlipParams.lipsDecayPerMove,
    suspicion: s.suspicion - SlipParams.suspicionDecayPerMove,
  );
}
