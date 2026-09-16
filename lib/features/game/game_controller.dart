import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shogi/shogi.dart';

/// 選択中のもの: 盤上のマス、または持ち駒の種類。
sealed class Selection {
  const Selection();
}

class SquareSelection extends Selection {
  const SquareSelection(this.square);
  final int square;
}

class HandSelection extends Selection {
  const HandSelection(this.type);
  final PieceType type;
}

class GameViewState {
  const GameViewState({
    required this.game,
    required this.revision,
    this.selection,
    this.legalTargets = const {},
  });

  final ShogiGame game;

  /// ShogiGame は可変なので、変更のたびに増やして再描画させる。
  final int revision;
  final Selection? selection;
  final Set<int> legalTargets;

  Position get position => game.position;
  Move? get lastMove => game.moves.isEmpty ? null : game.moves.last;
}

final gameControllerProvider =
    NotifierProvider<GameController, GameViewState>(GameController.new);

class GameController extends Notifier<GameViewState> {
  List<Move> _legal = const [];

  @override
  GameViewState build() {
    final game = ShogiGame();
    _legal = game.position.legalMoves();
    return GameViewState(game: game, revision: 0);
  }

  ShogiGame get _game => state.game;

  void _refresh({Selection? selection}) {
    Set<int> targets = const {};
    if (selection is SquareSelection) {
      targets = {
        for (final m in _legal)
          if (m.from == selection.square) m.to,
      };
    } else if (selection is HandSelection) {
      targets = {
        for (final m in _legal)
          if (m.drop == selection.type) m.to,
      };
    }
    state = GameViewState(
      game: _game,
      revision: state.revision + 1,
      selection: selection,
      legalTargets: targets,
    );
  }

  /// マスをタップ。移動先として確定できる候補手を返す（成/不成の2択なら2件）。
  List<Move> tapSquare(int sq) {
    if (_game.isOver) return const [];
    final sel = state.selection;
    if (sel != null && state.legalTargets.contains(sq)) {
      return [
        for (final m in _legal)
          if (m.to == sq &&
              switch (sel) {
                SquareSelection(:final square) => m.from == square,
                HandSelection(:final type) => m.drop == type,
              })
            m,
      ];
    }
    final piece = state.position.board[sq];
    if (piece != null && piece.side == state.position.turn) {
      final same = sel is SquareSelection && sel.square == sq;
      _refresh(selection: same ? null : SquareSelection(sq));
    } else {
      _refresh();
    }
    return const [];
  }

  void tapHand(Side side, PieceType type) {
    if (_game.isOver || side != state.position.turn) return;
    if (state.position.handCount(side, type) == 0) return;
    final sel = state.selection;
    final same = sel is HandSelection && sel.type == type;
    _refresh(selection: same ? null : HandSelection(type));
  }

  void play(Move move) {
    _game.play(move);
    _legal = _game.isOver ? const [] : _game.position.legalMoves();
    _refresh();
  }

  void undo() {
    if (_game.undo()) {
      _legal = _game.position.legalMoves();
      _refresh();
    }
  }

  void resign() {
    _game.resign();
    _legal = const [];
    _refresh();
  }

  void newGame() {
    ref.invalidateSelf();
  }
}
