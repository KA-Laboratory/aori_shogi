import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/shogi_engine.dart';
import '../../core/shogi/shogi.dart';
import 'engine_controller.dart';

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

/// 対局相手の構成。
enum OpponentMode {
  human,
  aiWhite,
  aiBlack,
  aiBoth; // 動作確認・自己対局用

  bool isAi(Side side) => switch (this) {
        OpponentMode.human => false,
        OpponentMode.aiWhite => side == Side.white,
        OpponentMode.aiBlack => side == Side.black,
        OpponentMode.aiBoth => true,
      };
}

class GameViewState {
  const GameViewState({
    required this.game,
    required this.revision,
    this.selection,
    this.legalTargets = const {},
    this.mode = OpponentMode.human,
    this.thinking = false,
    this.lastSearch,
    this.engineError,
  });

  final ShogiGame game;

  /// ShogiGame は可変なので、変更のたびに増やして再描画させる。
  final int revision;
  final Selection? selection;
  final Set<int> legalTargets;

  final OpponentMode mode;
  final bool thinking;
  final SearchResult? lastSearch;
  final String? engineError;

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

  OpponentMode _mode = OpponentMode.human;
  bool _thinking = false;
  SearchResult? _lastSearch;
  String? _engineError;
  int _gameId = 0;

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
      mode: _mode,
      thinking: _thinking,
      lastSearch: _lastSearch,
      engineError: _engineError,
    );
  }

  /// マスをタップ。移動先として確定できる候補手を返す（成/不成の2択なら2件）。
  bool get _humanToMove => !_thinking && !_mode.isAi(state.position.turn);

  List<Move> tapSquare(int sq) {
    if (_game.isOver || !_humanToMove) return const [];
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
    if (_game.isOver || side != state.position.turn || !_humanToMove) return;
    if (state.position.handCount(side, type) == 0) return;
    final sel = state.selection;
    final same = sel is HandSelection && sel.type == type;
    _refresh(selection: same ? null : HandSelection(type));
  }

  void play(Move move) {
    _game.play(move);
    _legal = _game.isOver ? const [] : _game.position.legalMoves();
    _refresh();
    _maybeAiMove();
  }

  void undo() {
    if (_thinking) return;
    if (!_game.undo()) return;
    // AI 対局では人間の手番まで戻す。
    while (_mode != OpponentMode.aiBoth &&
        _mode.isAi(_game.position.turn) &&
        _game.moves.isNotEmpty) {
      _game.undo();
    }
    _legal = _game.position.legalMoves();
    _refresh();
    _maybeAiMove();
  }

  /// AI 対局の開始/解除。解除すると人間同士に戻る。
  void setMode(OpponentMode mode) {
    _mode = mode;
    _engineError = null;
    _refresh();
    _maybeAiMove();
  }

  Future<void> _maybeAiMove() async {
    if (_thinking || _game.isOver || !_mode.isAi(_game.position.turn)) {
      return;
    }
    final status = ref.read(engineControllerProvider);
    if (status is! EngineReady) {
      _engineError = 'エンジンが準備できていません';
      _refresh();
      return;
    }
    final gameId = _gameId;
    _thinking = true;
    _refresh();
    try {
      final engine = status.engine;
      await engine.setPosition(
          _game.startPosition.toSfen(), [for (final m in _game.moves) m.toUsi()]);
      final result = await engine.think(movetimeMs: 1000, multiPv: 1);
      if (gameId != _gameId) return; // 途中で新規対局になった
      _lastSearch = result;
      _thinking = false;
      final best = result.bestMove;
      if (best.isResign) {
        _game.resign();
        _legal = const [];
        _refresh();
        return;
      }
      final move = Move.fromUsi(best.move);
      if (!_game.position.isLegal(move)) {
        _engineError = 'エンジンが非合法手を返しました: ${best.move}';
        _refresh();
        return;
      }
      // 次の手も AI なら、UI 更新の機会を与えてから続ける。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (gameId != _gameId) return;
      play(move);
    } catch (e) {
      if (gameId != _gameId) return;
      _thinking = false;
      _engineError = '$e';
      _refresh();
    }
  }

  void resign() {
    if (_thinking) return;
    _game.resign();
    _legal = const [];
    _refresh();
  }

  void newGame() {
    _gameId++;
    _thinking = false;
    _lastSearch = null;
    _engineError = null;
    final game = ShogiGame();
    _legal = game.position.legalMoves();
    state = GameViewState(game: game, revision: state.revision + 1, mode: _mode);
    _maybeAiMove();
  }
}
