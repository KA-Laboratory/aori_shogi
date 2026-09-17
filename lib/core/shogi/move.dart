import 'piece.dart';
import 'square.dart';

/// 指し手。盤上の移動（from あり）または駒打ち（drop あり）。
class Move {
  const Move.board(int this.from, this.to, {this.promote = false}) : drop = null;
  const Move.drop(PieceType this.drop, this.to) : from = null, promote = false;

  final int? from;
  final int to;
  final bool promote;
  final PieceType? drop;

  bool get isDrop => drop != null;

  String toUsi() =>
      isDrop ? '${drop!.sfen}*${usiSquare(to)}' : '${usiSquare(from!)}${usiSquare(to)}${promote ? '+' : ''}';

  static Move fromUsi(String s) {
    if (s.length >= 4 && s[1] == '*') {
      final type = PieceType.fromSfenLetter(s[0].toUpperCase());
      if (type == null || !handOrder.contains(type)) {
        throw FormatException('bad drop: $s');
      }
      return Move.drop(type, parseUsiSquare(s.substring(2, 4)));
    }
    if (s.length < 4 || s.length > 5) throw FormatException('bad move: $s');
    final promote = s.length == 5;
    if (promote && s[4] != '+') throw FormatException('bad move: $s');
    return Move.board(parseUsiSquare(s.substring(0, 2)), parseUsiSquare(s.substring(2, 4)), promote: promote);
  }

  @override
  bool operator ==(Object other) =>
      other is Move && other.from == from && other.to == to && other.promote == promote && other.drop == drop;

  @override
  int get hashCode => Object.hash(from, to, promote, drop);

  @override
  String toString() => toUsi();
}
