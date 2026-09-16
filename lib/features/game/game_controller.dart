import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogue/line_library.dart';
import '../../core/engine/shogi_engine.dart';
import '../../core/mind/gunshi_brain.dart';
import '../../core/mind/mind_state.dart';
import '../../core/mind/taunts.dart';
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
  aiBoth; // 動作確認用

  bool isAi(Side side) => switch (this) {
        OpponentMode.human => false,
        OpponentMode.aiWhite => side == Side.white,
        OpponentMode.aiBlack => side == Side.black,
        OpponentMode.aiBoth => true,
      };

  /// 感情表示の対象になる軍師の手番（1人のときだけ）。
  Side? get gunshiSide => switch (this) {
        OpponentMode.aiWhite => Side.white,
        OpponentMode.aiBlack => Side.black,
        _ => null,
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
    this.observing = false,
    this.lastSearch,
    this.engineError,
    this.mind,
    this.speech,
    this.lastTaunt,
    this.tauntAvailable = false,
  });

  final ShogiGame game;

  /// ShogiGame は可変なので、変更のたびに増やして再描画させる。
  final int revision;
  final Selection? selection;
  final Set<int> legalTargets;
  final OpponentMode mode;
  final bool thinking;

  /// AI の手の直後に局面を解析中（煽りの図星判定の準備中）。
  final bool observing;
  final SearchResult? lastSearch;
  final String? engineError;

  /// 軍師の感情（1人の AI 対局時）。
  final MindState? mind;
  final String? speech;
  final TauntOutcome? lastTaunt;

  /// いま煽りを送れるか（プレイヤーの手番につき1回）。
  final bool tauntAvailable;

  Position get position => game.position;
  Move? get lastMove => game.moves.isEmpty ? null : game.moves.last;
}

/// 軍師のセリフ集。main() で読み込んで override する（未設定ならセリフなし）。
final lineLibraryProvider = Provider<LineLibrary?>((ref) => null);

Future<LineLibrary> loadLineLibrary() async =>
    LineLibrary.fromJsonString(await rootBundle.loadString(LineLibrary.assetPath));

final gameControllerProvider = NotifierProvider<GameController, GameViewState>(GameController.new);

class GameController extends Notifier<GameViewState> {
  List<Move> _legal = const [];
  OpponentMode _mode = OpponentMode.human;
  bool _thinking = false;
  bool _observing = false;
  SearchResult? _lastSearch;
  String? _engineError;
  int _gameId = 0;
  final Map<Side, GunshiBrain> _brains = {};
  String? _speech;
  TauntOutcome? _lastTaunt;
  bool _tauntUsed = false;
  final _lineRng = math.Random();

  @override
  GameViewState build() {
    final game = ShogiGame();
    _legal = game.position.legalMoves();
    return GameViewState(game: game, revision: 0);
  }

  ShogiGame get _game => state.game;
  GunshiBrain? get _gunshi => _mode.gunshiSide == null ? null : _brains[_mode.gunshiSide];

  void _refresh({Selection? selection}) {
    Set<int> targets = const {};
    if (selection is SquareSelection) {
      targets = {for (final m in _legal) if (m.from == selection.square) m.to};
    } else if (selection is HandSelection) {
      targets = {for (final m in _legal) if (m.drop == selection.type) m.to};
    }
    final g = _gunshi;
    state = GameViewState(
      game: _game,
      revision: state.revision + 1,
      selection: selection,
      legalTargets: targets,
      mode: _mode,
      thinking: _thinking,
      observing: _observing,
      lastSearch: _lastSearch,
      engineError: _engineError,
      mind: g?.mind,
      speech: _speech,
      lastTaunt: _lastTaunt,
      tauntAvailable: g != null &&
          !_tauntUsed &&
          !_thinking &&
          !_game.isOver &&
          _game.position.turn != g.side &&
          g.canReceiveTaunt,
    );
  }

  String _say(LineTrigger trigger, {Map<String, String> vars = const {}}) {
    final lib = ref.read(lineLibraryProvider);
    final g = _gunshi;
    if (lib == null || g == null) return '';
    return lib.pick(g.mind.mood, trigger, _lineRng, vars: vars);
  }

  bool get _humanToMove => !_thinking && !_mode.isAi(state.position.turn);

  /// マスをタップ。移動先として確定できる候補手を返す（成/不成の2択なら2件）。
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

  /// 人間の着手。
  void play(Move move) {
    _applyMove(move);
    _tauntUsed = false;
    _gunshi?.tauntContext = null;
    _refresh();
    _maybeAiMove();
  }

  void _applyMove(Move move) {
    _game.play(move);
    _legal = _game.isOver ? const [] : _game.position.legalMoves();
    final r = _game.result;
    final g = _gunshi;
    if (r != null && g != null) {
      _speech = r.winner == null
          ? '……千日手か。きょうはこのくらいにしておいてやろう。'
          : _say(r.winner == g.side ? LineTrigger.win : LineTrigger.lose);
    }
  }

  void undo() {
    if (_thinking) return;
    if (!_game.undo()) return;
    // AI 対局では人間の手番まで戻す。
    while (_mode != OpponentMode.aiBoth && _mode.isAi(_game.position.turn) && _game.moves.isNotEmpty) {
      _game.undo();
    }
    _legal = _game.position.legalMoves();
    _gunshi?.tauntContext = null;
    _tauntUsed = false;
    _refresh();
    _observeIfNeeded();
    _maybeAiMove();
  }

  /// 対局相手の切り替え。新しい軍師を用意する。
  void setMode(OpponentMode mode) {
    _mode = mode;
    _engineError = null;
    _resetBrains();
    _refresh();
    _maybeAiMove();
    _observeIfNeeded();
  }

  void _resetBrains() {
    _brains.clear();
    _speech = null;
    _lastTaunt = null;
    _tauntUsed = false;
    final status = ref.read(engineControllerProvider);
    if (status is! EngineReady) return;
    for (final side in Side.values) {
      if (_mode.isAi(side)) {
        _brains[side] = GunshiBrain(
          engine: status.engine,
          side: side,
          seed: DateTime.now().microsecondsSinceEpoch,
        );
      }
    }
    if (_gunshi != null) _speech = _say(LineTrigger.start);
  }

  /// 煽りスタンプを送る。
  void sendTaunt(TauntStamp stamp) {
    final g = _gunshi;
    if (g == null || !state.tauntAvailable) return;
    final out = g.receiveTaunt(stamp.kind);
    _lastTaunt = out;
    _tauntUsed = true;
    _speech = _say(stamp.kind == TauntKind.praise
        ? LineTrigger.praised
        : (out.hit ? LineTrigger.tauntHit : LineTrigger.tauntMiss));
    _refresh();
  }

  String _kifOf(int moveIndex) {
    final positions = _game.positions;
    final moves = _game.moves;
    return kifMoveText(positions[moveIndex], moves[moveIndex],
            previous: moveIndex > 0 ? moves[moveIndex - 1] : null)
        .replaceAll(RegExp(r'\(\d+\)'), '');
  }

  Future<void> _maybeAiMove() async {
    if (_thinking || _game.isOver || !_mode.isAi(_game.position.turn)) return;
    final brain = _brains[_game.position.turn];
    if (brain == null) {
      _engineError = 'エンジンが準備できていません';
      _refresh();
      return;
    }
    final gameId = _gameId;
    final ply = _game.moves.length;
    _thinking = true;
    _refresh();
    try {
      final turn = await brain.takeTurn(_game);
      if (gameId != _gameId || ply != _game.moves.length) return;
      _thinking = false;
      if (turn.resign) {
        _game.resign();
        _legal = const [];
        if (brain == _gunshi) _speech = _say(LineTrigger.lose);
        _refresh();
        return;
      }
      _lastSearch = SearchResult(
        bestMove: BestMove(turn.move!.toUsi()),
        candidates: [turn.choice!.candidate],
      );
      final playerMoveText = ply > 0 ? _kifOf(ply - 1) : '';
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (gameId != _gameId) return;
      _applyMove(turn.move!);
      if (brain == _gunshi && !_game.isOver) {
        final aiText = _kifOf(_game.moves.length - 1);
        if (turn.playerBlundered) {
          _speech = _say(LineTrigger.blunderPlayer, vars: {'move': playerMoveText});
        } else if (turn.choice!.lossCp >= 150) {
          _speech = _say(LineTrigger.blunderSelf, vars: {'move': aiText});
        } else {
          _speech = _say(LineTrigger.move, vars: {'move': aiText});
        }
      }
      _refresh();
      if (_mode.isAi(_game.position.turn)) {
        _maybeAiMove();
      } else {
        _observeIfNeeded();
      }
    } catch (e) {
      if (gameId != _gameId) return;
      _thinking = false;
      _engineError = '$e';
      _refresh();
    }
  }

  /// プレイヤーの手番になったら、軍師が局面を解析して図星判定の準備をする。
  Future<void> _observeIfNeeded() async {
    final g = _gunshi;
    if (g == null || _game.isOver || _game.position.turn == g.side || g.canReceiveTaunt || _observing) return;
    final gameId = _gameId;
    final ply = _game.moves.length;
    _observing = true;
    _refresh();
    try {
      await g.observePlayerTurn(_game);
    } catch (e) {
      _engineError = '$e';
    } finally {
      _observing = false;
      if (gameId == _gameId && ply == _game.moves.length) {
        _refresh();
      } else {
        g.tauntContext = null;
      }
    }
  }

  void resign() {
    if (_thinking) return;
    _game.resign();
    _legal = const [];
    final g = _gunshi;
    if (g != null) _speech = _say(LineTrigger.win);
    _refresh();
  }

  void newGame() {
    _gameId++;
    _thinking = false;
    _observing = false;
    _lastSearch = null;
    _engineError = null;
    final game = ShogiGame();
    _legal = game.position.legalMoves();
    state = GameViewState(game: game, revision: state.revision + 1, mode: _mode);
    _resetBrains();
    _refresh();
    _maybeAiMove();
    _observeIfNeeded();
  }
}
