import 'move.dart';
import 'piece.dart';
import 'position.dart';

enum GameEndReason { checkmate, resign, repetition, perpetualCheck, agreement }

class GameResult {
  const GameResult(this.reason, {this.winner});

  /// null は引き分け。
  final Side? winner;
  final GameEndReason reason;

  String get label => switch (reason) {
        GameEndReason.checkmate => '詰み（${winner!.label}の勝ち）',
        GameEndReason.resign => '投了（${winner!.label}の勝ち）',
        GameEndReason.repetition => '千日手（引き分け）',
        GameEndReason.perpetualCheck => '連続王手の千日手（${winner!.label}の勝ち）',
        GameEndReason.agreement => '合意により引き分け',
      };
}

class IllegalMoveException implements Exception {
  IllegalMoveException(this.move);
  final Move move;
  @override
  String toString() => 'IllegalMoveException: $move';
}

/// 1局分の進行（手順・局面履歴・終局判定）。
class ShogiGame {
  ShogiGame([Position? start])
      : _positions = [start ?? Position.initial()];

  final List<Position> _positions;
  final List<Move> _moves = [];
  GameResult? _result;

  Position get position => _positions.last;
  Position get startPosition => _positions.first;
  List<Position> get positions => List.unmodifiable(_positions);
  List<Move> get moves => List.unmodifiable(_moves);
  GameResult? get result => _result;
  bool get isOver => _result != null;

  void play(Move move) {
    if (isOver) throw StateError('game is over');
    if (!position.isLegal(move)) throw IllegalMoveException(move);
    _moves.add(move);
    _positions.add(position.play(move));
    _result = _judge();
  }

  void playUsi(String usi) => play(Move.fromUsi(usi));

  /// 投了。[side] 省略時は手番側が投了する。
  void resign({Side? side}) {
    if (isOver) return;
    _result = GameResult(GameEndReason.resign, winner: (side ?? position.turn).opponent);
  }

  /// 合意による引き分け。
  void agreeDraw() {
    if (isOver) return;
    _result = const GameResult(GameEndReason.agreement);
  }

  /// 待った。投了は取り消し、それ以外は1手戻す。
  bool undo() {
    if (_result?.reason == GameEndReason.resign || _result?.reason == GameEndReason.agreement) {
      _result = null;
      return true;
    }
    if (_moves.isEmpty) return false;
    _moves.removeLast();
    _positions.removeLast();
    _result = null;
    return true;
  }

  GameResult? _judge() {
    final pos = position;
    if (!pos.hasAnyLegalMove()) {
      // 将棋では手が無い＝詰み（ステイルメイトも負け扱い）。
      return GameResult(GameEndReason.checkmate, winner: pos.turn.opponent);
    }
    final key = pos.repetitionKey;
    final occurrences = <int>[];
    for (var i = 0; i < _positions.length; i++) {
      if (_positions[i].repetitionKey == key) occurrences.add(i);
    }
    if (occurrences.length < 4) return null;
    // 連続王手の判定: 1回目の出現から今までの手で、一方の手が全て王手か。
    final first = occurrences.first;
    final allCheckBy = {Side.black: true, Side.white: true};
    for (var j = first + 1; j < _positions.length; j++) {
      final mover = _positions[j - 1].turn;
      final gaveCheck = _positions[j].inCheck(_positions[j].turn);
      if (!gaveCheck) allCheckBy[mover] = false;
    }
    for (final side in Side.values) {
      if (allCheckBy[side]!) {
        return GameResult(GameEndReason.perpetualCheck, winner: side.opponent);
      }
    }
    return const GameResult(GameEndReason.repetition);
  }
}
