import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SFEN / USI', () {
    test('初期局面の往復', () {
      expect(Position.initial().toSfen(), Position.startSfen);
    });

    test('持ち駒と成駒の往復', () {
      const sfen = 'lnsgk2nl/1r4gs1/p1pppp1pp/6p2/1p7/2P6/PP1PPPPPP/1SG4R1/LN2KGSNL b B2Pb 13';
      expect(Position.fromSfen(sfen).toSfen(), sfen);
      const promoted = '4k4/9/4+P4/9/9/9/9/9/4K4 w 2p 20';
      expect(Position.fromSfen(promoted).toSfen(), promoted);
    });

    test('USI 指し手の往復', () {
      for (final s in ['7g7f', '8h2b+', 'P*5e', 'R*1a']) {
        expect(Move.fromUsi(s).toUsi(), s);
      }
      expect(() => Move.fromUsi('K*5e'), throwsFormatException);
    });
  });

  group('perft', () {
    final start = Position.initial();
    test('depth 1', () => expect(start.perft(1), 30));
    test('depth 2', () => expect(start.perft(2), 900));
    test('depth 3', () => expect(start.perft(3), 25470));
  });

  group('特殊ルール', () {
    test('二歩は打てない', () {
      final pos = Position.fromSfen('4k4/9/9/9/9/9/4P4/9/4K4 b P 1');
      final drops = pos.legalMoves().where((m) => m.isDrop).map((m) => m.toUsi());
      expect(drops, isNot(contains('P*5e')));
      expect(drops, contains('P*4e'));
    });

    test('行き所のない駒は打てない・不成にできない', () {
      final pos = Position.fromSfen('4k4/P8/9/9/9/9/9/9/4K4 b NL 1');
      final usi = pos.legalMoves().map((m) => m.toUsi()).toSet();
      expect(usi, isNot(contains('L*1a')));
      expect(usi, isNot(contains('N*1b')));
      expect(usi, contains('N*1c'));
      final pawn = Position.fromSfen('3k5/9/9/4P4/9/9/9/9/4K4 b - 1');
      final pawnPlayed = pawn.play(Move.fromUsi('5d5c'));
      expect(pawnPlayed.board[squareOf(5, 3)]!.type, PieceType.pawn);
      final atLast = Position.fromSfen('3k5/4P4/9/9/9/9/9/9/4K4 b - 1');
      final lm = atLast.legalMoves().map((m) => m.toUsi()).toSet();
      expect(lm, contains('5b5a+'));
      expect(lm, isNot(contains('5b5a')));
    });

    test('打ち歩詰めは反則、香打ちの詰みは合法', () {
      final pos = Position.fromSfen('8k/9/6NG1/9/9/9/9/9/4K4 b PL 1');
      final usi = pos.legalMoves().map((m) => m.toUsi()).toSet();
      expect(usi, isNot(contains('P*1b')));
      expect(usi, contains('L*1b'));
      expect(pos.play(Move.fromUsi('L*1b')).isCheckmate, isTrue);
    });

    test('王手放置になる手は指せない', () {
      // 後手の飛車が5筋に利いていて、先手玉の前の金は動けない（ピン）。
      final pos = Position.fromSfen('4r4/9/9/9/9/9/9/4G4/4K4 b - 1');
      final usi = pos.legalMoves().map((m) => m.toUsi()).toSet();
      expect(usi, contains('5h5g'));
      expect(usi, isNot(contains('5h4h')));
    });
  });

  group('対局進行', () {
    test('千日手（同一局面4回）で引き分け', () {
      final game = ShogiGame();
      for (var i = 0; i < 3; i++) {
        for (final m in ['5i4h', '5a4b', '4h5i', '4b5a']) {
          game.playUsi(m);
        }
      }
      expect(game.result?.reason, GameEndReason.repetition);
    });

    test('詰みで終局', () {
      final game = ShogiGame(Position.fromSfen('8k/9/6NG1/9/9/9/9/9/4K4 b L 1'));
      game.playUsi('L*1b');
      expect(game.result?.reason, GameEndReason.checkmate);
      expect(game.result?.winner, Side.black);
    });

    test('非合法手は例外、待ったで戻る', () {
      final game = ShogiGame();
      expect(() => game.playUsi('7g7e'), throwsA(isA<IllegalMoveException>()));
      game.playUsi('7g7f');
      expect(game.undo(), isTrue);
      expect(game.position.toSfen(), Position.startSfen);
    });

    test('KIF 出力', () {
      final game = ShogiGame();
      for (final m in ['7g7f', '3c3d', '8h2b+', '3a2b']) {
        game.playUsi(m);
      }
      game.resign();
      final kif = toKif(game);
      expect(kif, contains('手合割：平手'));
      expect(kif, contains('   1 ７六歩(77)'));
      expect(kif, contains('   3 ２二角成(88)'));
      expect(kif, contains('   4 同　銀(31)'));
      expect(kif, contains('   5 投了'));
      expect(kif, contains('まで4手で後手の勝ち'));
    });
  });
}
