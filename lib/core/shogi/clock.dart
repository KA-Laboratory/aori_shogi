/// 持ち時間（持ち時間＋秒読み）。画面と同じ数字をコードでも持つ。
library;

import 'piece.dart';

class TimeControl {
  const TimeControl({this.mainMs = 10 * 60 * 1000, this.byoyomiMs = 30 * 1000});

  /// 持ち時間なし（時間切れにならない）。
  static const none = TimeControl(mainMs: 0, byoyomiMs: 0);
  static const tenMinutes = TimeControl();
  static const threeMinutes = TimeControl(mainMs: 3 * 60 * 1000, byoyomiMs: 10 * 1000);

  final int mainMs;
  final int byoyomiMs;

  bool get unlimited => mainMs <= 0 && byoyomiMs <= 0;

  String get label => unlimited
      ? '時間無制限'
      : '${(mainMs / 60000).round()}分'
            '${byoyomiMs > 0 ? '＋秒読み${(byoyomiMs / 1000).round()}秒' : ''}';
}

/// 片側の残り時間。
class SideClock {
  SideClock(this.control) : mainLeftMs = control.mainMs, byoyomiLeftMs = control.byoyomiMs;

  final TimeControl control;
  int mainLeftMs;
  int byoyomiLeftMs;

  bool get flagged => !control.unlimited && mainLeftMs <= 0 && byoyomiLeftMs <= 0;

  /// 手番が始まるときに秒読みを戻す。
  void startTurn() => byoyomiLeftMs = control.byoyomiMs;

  /// [ms] 経過させる。持ち時間を先に使い、尽きたら秒読みを削る。
  void consume(int ms) {
    if (control.unlimited || ms <= 0) return;
    final fromMain = mainLeftMs >= ms ? ms : mainLeftMs;
    mainLeftMs -= fromMain;
    final rest = ms - fromMain;
    if (rest > 0) byoyomiLeftMs = (byoyomiLeftMs - rest).clamp(-1, control.byoyomiMs);
  }

  /// 画面に出す文字（例 9:58 / 秒読み 12）。
  String get text {
    if (control.unlimited) return '--:--';
    if (mainLeftMs > 0) {
      final s = (mainLeftMs / 1000).ceil();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    return byoyomiLeftMs > 0 ? '秒読み ${(byoyomiLeftMs / 1000).ceil()}' : '0:00';
  }
}

/// 両者の時計。
class GameClock {
  GameClock(this.control) : _clocks = {for (final s in Side.values) s: SideClock(control)};

  final TimeControl control;
  final Map<Side, SideClock> _clocks;

  SideClock of(Side side) => _clocks[side]!;

  /// 手番が変わったときに呼ぶ。
  void startTurn(Side side) => of(side).startTurn();

  /// 手番側の時間を進める。時間切れになった手番を返す（切れていなければ null）。
  Side? tick(Side side, int ms) {
    of(side).consume(ms);
    return of(side).flagged ? side : null;
  }

  void reset() {
    for (final c in _clocks.values) {
      c
        ..mainLeftMs = control.mainMs
        ..byoyomiLeftMs = control.byoyomiMs;
    }
  }
}
