import 'move.dart';
import 'piece.dart';
import 'square.dart';

typedef _Dir = (int, int);

const List<_Dir> _orth = [(0, -1), (0, 1), (-1, 0), (1, 0)];
const List<_Dir> _diag = [(-1, -1), (1, -1), (-1, 1), (1, 1)];
const List<_Dir> _goldSteps = [(0, -1), (-1, -1), (1, -1), (-1, 0), (1, 0), (0, 1)];
const List<_Dir> _silverSteps = [(0, -1), (-1, -1), (1, -1), (-1, 1), (1, 1)];

/// 先手視点（前方 = dy -1）の1マス移動。
List<_Dir> _steps(PieceType t) => switch (t) {
      PieceType.pawn => const [(0, -1)],
      PieceType.knight => const [(-1, -2), (1, -2)],
      PieceType.silver => _silverSteps,
      PieceType.gold ||
      PieceType.proPawn ||
      PieceType.proLance ||
      PieceType.proKnight ||
      PieceType.proSilver =>
        _goldSteps,
      PieceType.king => const [..._orth, ..._diag],
      PieceType.horse => _orth,
      PieceType.dragon => _diag,
      _ => const [],
    };

/// 先手視点の走り駒の方向。
List<_Dir> _slides(PieceType t) => switch (t) {
      PieceType.lance => const [(0, -1)],
      PieceType.bishop || PieceType.horse => _diag,
      PieceType.rook || PieceType.dragon => _orth,
      _ => const [],
    };

/// 局面（不変）。盤・持ち駒・手番・手数。
class Position {
  Position._(this.board, this.hands, this.turn, this.ply);

  static const startSfen =
      'lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1';

  factory Position.initial() => Position.fromSfen(startSfen);

  /// 81マス。
  final List<Piece?> board;

  /// hands[side.index][PieceType.index]（歩〜飛の7種）。
  final List<List<int>> hands;
  final Side turn;
  final int ply;

  int handCount(Side side, PieceType type) => hands[side.index][type.index];

  // ---------------------------------------------------------------- SFEN

  factory Position.fromSfen(String sfen) {
    var s = sfen.trim();
    if (s.startsWith('sfen ')) s = s.substring(5);
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length < 3) throw FormatException('bad sfen: $sfen');
    final rows = parts[0].split('/');
    if (rows.length != 9) throw FormatException('bad sfen rows: $sfen');
    final board = List<Piece?>.filled(81, null);
    for (var y = 0; y < 9; y++) {
      var x = 0;
      var promoted = false;
      for (final ch in rows[y].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          x += n;
          continue;
        }
        if (ch == '+') {
          promoted = true;
          continue;
        }
        var type = PieceType.fromSfenLetter(ch.toUpperCase());
        if (type == null || x > 8) throw FormatException('bad sfen: $sfen');
        if (promoted) {
          type = type.promoted ?? (throw FormatException('bad sfen: $sfen'));
          promoted = false;
        }
        final side = ch == ch.toUpperCase() ? Side.black : Side.white;
        board[y * 9 + x] = Piece(type, side);
        x++;
      }
      if (x != 9) throw FormatException('bad sfen row $y: $sfen');
    }
    final turn = switch (parts[1]) {
      'b' => Side.black,
      'w' => Side.white,
      _ => throw FormatException('bad turn: $sfen'),
    };
    final hands = [List<int>.filled(7, 0), List<int>.filled(7, 0)];
    if (parts[2] != '-') {
      var count = 0;
      for (final ch in parts[2].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          count = count * 10 + n;
          continue;
        }
        final type = PieceType.fromSfenLetter(ch.toUpperCase());
        if (type == null || !handOrder.contains(type)) {
          throw FormatException('bad hand: $sfen');
        }
        final side = ch == ch.toUpperCase() ? Side.black : Side.white;
        hands[side.index][type.index] += count == 0 ? 1 : count;
        count = 0;
      }
    }
    final ply = parts.length > 3 ? int.tryParse(parts[3]) ?? 1 : 1;
    return Position._(board, hands, turn, ply);
  }

  String toSfen({bool withPly = true}) {
    final sb = StringBuffer();
    for (var y = 0; y < 9; y++) {
      var empty = 0;
      for (var x = 0; x < 9; x++) {
        final p = board[y * 9 + x];
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) sb.write(empty);
          empty = 0;
          sb.write(p.sfen);
        }
      }
      if (empty > 0) sb.write(empty);
      if (y < 8) sb.write('/');
    }
    sb.write(turn == Side.black ? ' b ' : ' w ');
    final hand = StringBuffer();
    for (final side in Side.values) {
      for (final t in handOrder) {
        final c = hands[side.index][t.index];
        if (c == 0) continue;
        if (c > 1) hand.write(c);
        hand.write(side == Side.black ? t.sfen : t.sfen.toLowerCase());
      }
    }
    sb.write(hand.isEmpty ? '-' : hand);
    if (withPly) sb.write(' $ply');
    return sb.toString();
  }

  /// 千日手判定用のキー（手数を除く）。
  String get repetitionKey => toSfen(withPly: false);

  // ------------------------------------------------------------ 利き

  /// from にある駒 p の利き先。
  Iterable<int> attacksFrom(int from, Piece p) sync* {
    final s = p.side == Side.black ? 1 : -1;
    final x = from % 9, y = from ~/ 9;
    for (final (dx, dy) in _steps(p.type)) {
      final nx = x + dx * s, ny = y + dy * s;
      if (nx >= 0 && nx < 9 && ny >= 0 && ny < 9) yield ny * 9 + nx;
    }
    for (final (dx, dy) in _slides(p.type)) {
      var nx = x + dx * s, ny = y + dy * s;
      while (nx >= 0 && nx < 9 && ny >= 0 && ny < 9) {
        final t = ny * 9 + nx;
        yield t;
        if (board[t] != null) break;
        nx += dx * s;
        ny += dy * s;
      }
    }
  }

  bool isAttacked(int sq, Side by) {
    for (var i = 0; i < 81; i++) {
      final p = board[i];
      if (p != null && p.side == by && attacksFrom(i, p).contains(sq)) {
        return true;
      }
    }
    return false;
  }

  int? kingSquare(Side side) {
    for (var i = 0; i < 81; i++) {
      final p = board[i];
      if (p != null && p.side == side && p.type == PieceType.king) return i;
    }
    return null;
  }

  bool inCheck(Side side) {
    final k = kingSquare(side);
    return k != null && isAttacked(k, side.opponent);
  }

  // ---------------------------------------------------------- 合法手

  static bool inPromotionZone(int sq, Side side) =>
      side == Side.black ? sq ~/ 9 <= 2 : sq ~/ 9 >= 6;

  /// その駒がそのマスに不成で居られない（行き所のない駒）か。
  static bool isDeadSquare(PieceType type, Side side, int sq) {
    final rankFromFront = side == Side.black ? sq ~/ 9 : 8 - sq ~/ 9;
    return switch (type) {
      PieceType.pawn || PieceType.lance => rankFromFront == 0,
      PieceType.knight => rankFromFront <= 1,
      _ => false,
    };
  }

  List<Move> pseudoLegalMoves() {
    final moves = <Move>[];
    for (var from = 0; from < 81; from++) {
      final p = board[from];
      if (p == null || p.side != turn) continue;
      for (final to in attacksFrom(from, p)) {
        final target = board[to];
        if (target != null && target.side == turn) continue;
        final canPromo = p.type.canPromote &&
            (inPromotionZone(from, turn) || inPromotionZone(to, turn));
        if (!isDeadSquare(p.type, turn, to)) {
          moves.add(Move.board(from, to));
        }
        if (canPromo) moves.add(Move.board(from, to, promote: true));
      }
    }
    for (final type in handOrder) {
      if (handCount(turn, type) == 0) continue;
      for (var to = 0; to < 81; to++) {
        if (board[to] != null || isDeadSquare(type, turn, to)) continue;
        if (type == PieceType.pawn && _hasUnpromotedPawnOnFile(turn, to % 9)) {
          continue; // 二歩
        }
        moves.add(Move.drop(type, to));
      }
    }
    return moves;
  }

  bool _hasUnpromotedPawnOnFile(Side side, int x) {
    for (var y = 0; y < 9; y++) {
      final p = board[y * 9 + x];
      if (p != null && p.side == side && p.type == PieceType.pawn) return true;
    }
    return false;
  }

  /// 合法手。[checkUchifuzume] が false のときは打ち歩詰め判定を省く（内部用）。
  List<Move> legalMoves({bool checkUchifuzume = true}) {
    final result = <Move>[];
    for (final m in pseudoLegalMoves()) {
      final next = play(m);
      if (next.inCheck(turn)) continue;
      if (checkUchifuzume &&
          m.drop == PieceType.pawn &&
          next.inCheck(next.turn) &&
          !next.hasAnyLegalMove(checkUchifuzume: false)) {
        continue; // 打ち歩詰め
      }
      result.add(m);
    }
    return result;
  }

  bool hasAnyLegalMove({bool checkUchifuzume = true}) {
    for (final m in pseudoLegalMoves()) {
      final next = play(m);
      if (next.inCheck(turn)) continue;
      if (checkUchifuzume &&
          m.drop == PieceType.pawn &&
          next.inCheck(next.turn) &&
          !next.hasAnyLegalMove(checkUchifuzume: false)) {
        continue;
      }
      return true;
    }
    return false;
  }

  bool isLegal(Move m) => legalMoves().contains(m);

  bool get isCheckmate => inCheck(turn) && !hasAnyLegalMove();

  /// 指し手を適用した新しい局面を返す（合法性は検査しない）。
  Position play(Move m) {
    final b = List<Piece?>.of(board);
    final h = [List<int>.of(hands[0]), List<int>.of(hands[1])];
    if (m.isDrop) {
      h[turn.index][m.drop!.index]--;
      b[m.to] = Piece(m.drop!, turn);
    } else {
      final p = b[m.from!]!;
      final captured = b[m.to];
      if (captured != null && captured.type != PieceType.king) {
        h[turn.index][captured.type.base.index]++;
      }
      b[m.from!] = null;
      b[m.to] = Piece(m.promote ? p.type.promoted! : p.type, turn);
    }
    return Position._(b, h, turn.opponent, ply + 1);
  }

  int perft(int depth) {
    if (depth == 0) return 1;
    final moves = legalMoves();
    if (depth == 1) return moves.length;
    var n = 0;
    for (final m in moves) {
      n += play(m).perft(depth - 1);
    }
    return n;
  }

  Piece? at(int file, int rank) => board[squareOf(file, rank)];
}
