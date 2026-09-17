import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('持ち時間', () {
    test('持ち時間を使い切ると秒読みに入り、秒読みも切れると時間切れ', () {
      const c = TimeControl(mainMs: 1000, byoyomiMs: 500);
      final clock = SideClock(c);
      clock.startTurn();
      clock.consume(600);
      expect(clock.text, '0:01');
      expect(clock.flagged, isFalse);
      clock.consume(600);
      expect(clock.flagged, isFalse, reason: '秒読みが残っている');
      clock.consume(600);
      expect(clock.flagged, isTrue);
    });

    test('手番が始まると秒読みは戻る', () {
      final clock = SideClock(const TimeControl(mainMs: 0, byoyomiMs: 1000));
      clock.consume(700);
      clock.startTurn();
      expect(clock.byoyomiLeftMs, 1000);
      expect(clock.flagged, isFalse);
    });

    test('時間無制限は切れない', () {
      final clock = SideClock(TimeControl.none);
      clock.consume(10 * 60 * 1000);
      expect(clock.flagged, isFalse);
      expect(clock.text, '--:--');
    });

    test('時間切れは相手の勝ち', () {
      final game = ShogiGame();
      game.timeUp(Side.black);
      expect(game.result!.reason, GameEndReason.timeUp);
      expect(game.result!.winner, Side.white);
      expect(game.result!.label, contains('後手の勝ち'));
    });
  });

  group('入玉宣言', () {
    test('初期局面では宣言できない（理由も出る）', () {
      final d = checkDeclaration(Position.initial());
      expect(d.canDeclare, isFalse);
      expect(d.missing, contains('玉が敵陣に入っていない'));
      expect(ShogiGame().declareWin(), isFalse);
    });

    test('条件を満たす局面では宣言勝ちになる', () {
      // 先手玉が3段目、先手の駒が敵陣に10枚以上、持ち駒に大駒。後手玉は自陣。
      final pos = Position.fromSfen('GGGGSSKSS/RBRBGGGGG/PPPPPPPPP/9/9/9/9/9/4k4 b RBGSNLP 1');
      final d = checkDeclaration(pos);
      expect(d.inEnemyCamp, isTrue);
      expect(d.piecesInCamp, greaterThanOrEqualTo(10));
      expect(d.points, greaterThanOrEqualTo(28));
      expect(d.canDeclare, isTrue, reason: d.missing.join('/'));
      final game = ShogiGame(pos);
      expect(game.declareWin(), isTrue);
      expect(game.result!.reason, GameEndReason.declaration);
      expect(game.result!.winner, Side.black);
    });

    test('後手は27点で宣言できる', () {
      expect(checkDeclaration(Position.initial(), side: Side.white).requiredPoints, 27);
      expect(checkDeclaration(Position.initial(), side: Side.black).requiredPoints, 28);
    });
  });
}
