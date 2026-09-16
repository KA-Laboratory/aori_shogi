import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'usi_protocol.dart';
import 'package:yaneuraou_ffi/yaneuraou_ffi.dart';

export 'usi_protocol.dart';

abstract class ShogiEngine {
  Future<void> setPosition(String sfen, List<String> usiMoves);

  /// 現在の局面を探索し、最善手と MultiPV 候補を返す。
  Future<SearchResult> think({required int movetimeMs, int multiPv = 1});

  /// 候補手解析（感情ロジック・図星判定用の共通入口）。
  Future<List<Candidate>> analyze(String sfen,
      {List<String> moves = const [], int movetimeMs = 300, int multiPv = 5});

  Future<void> stop();

  /// 生のUSI出力（デバッグ表示用）。
  Stream<String> get lines;
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => 'EngineException: $message';
}

/// やねうら王（FFI・同一プロセス）実装。アプリ内で1インスタンスのみ。
class YaneuraOuEngine implements ShogiEngine {
  YaneuraOuEngine._(this._native);

  static YaneuraOuEngine? _instance;
  static Future<YaneuraOuEngine>? _starting;

  final YaneuraOuNative _native;
  final _lineCtrl = StreamController<String>.broadcast();

  Future<void> _lock = Future.value();
  int _multiPv = 1;

  @override
  Stream<String> get lines => _lineCtrl.stream;

  /// 起動して isready まで済ませる。[evalDir] に nn.bin があること。
  static Future<YaneuraOuEngine> start({
    required String evalDir,
    int hashMb = 64,
    int? threads,
  }) {
    if (_instance != null) return Future.value(_instance!);
    return _starting ??= _start(evalDir, hashMb, threads).then((e) {
      _instance = e;
      return e;
    }).whenComplete(() => _starting = null);
  }

  static Future<YaneuraOuEngine> _start(
      String evalDir, int hashMb, int? threads) async {
    final e = YaneuraOuEngine._(YaneuraOuNative.open());
    e._native.init();
    Timer.periodic(const Duration(milliseconds: 10), (_) => e._drain());
    final th = threads ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 4);
    await e._request(() async {
      e._send('usi');
      await e._waitLine((l) => l == 'usiok', const Duration(seconds: 10));
      for (final opt in [
        'EvalDir value $evalDir',
        'FV_SCALE value 20', // Háo の推奨値
        'Threads value $th',
        'USI_Hash value $hashMb',
        'BookFile value no_book',
        'NetworkDelay value 0',
        'NetworkDelay2 value 0',
        'MinimumThinkingTime value 100',
        'MultiPV value 1',
      ]) {
        e._send('setoption name $opt');
      }
      e._send('isready');
      await e._waitLine((l) => l == 'readyok', const Duration(seconds: 60));
      e._send('usinewgame');
    });
    return e;
  }

  void _send(String line) {
    if (kDebugMode) debugPrint('USI> $line');
    _native.send(line);
  }

  void _drain() {
    for (var i = 0; i < 500; i++) {
      final l = _native.poll();
      if (l == null) break;
      if (kDebugMode && !l.startsWith('info depth')) debugPrint('USI< $l');
      _lineCtrl.add(l);
    }
  }

  Future<String> _waitLine(bool Function(String) test, Duration timeout) {
    return lines.firstWhere(test).timeout(timeout,
        onTimeout: () => throw EngineException('timeout waiting engine'));
  }

  /// コマンドを直列化する。
  Future<T> _request<T>(Future<T> Function() body) {
    final prev = _lock;
    final done = Completer<void>();
    _lock = done.future;
    return prev.then((_) => body()).whenComplete(done.complete);
  }

  String? _positionCmd;

  @override
  Future<void> setPosition(String sfen, List<String> usiMoves) async {
    final base = sfen == 'startpos' ? 'position startpos' : 'position sfen $sfen';
    _positionCmd = usiMoves.isEmpty ? base : '$base moves ${usiMoves.join(' ')}';
  }

  @override
  Future<SearchResult> think({required int movetimeMs, int multiPv = 1}) {
    final pos = _positionCmd;
    if (pos == null) throw EngineException('position not set');
    return _request(() async {
      if (multiPv != _multiPv) {
        _send('setoption name MultiPV value $multiPv');
        _multiPv = multiPv;
      }
      final collector = CandidateCollector();
      final sub = lines.listen((l) {
        final info = EngineInfo.parse(l);
        if (info != null) collector.add(info);
      });
      try {
        final bestLine = _waitLine((l) => l.startsWith('bestmove'),
            Duration(milliseconds: movetimeMs + 10000));
        _send(pos);
        _send('go movetime $movetimeMs');
        final best = BestMove.parse(await bestLine)!;
        // bestmove 直前の info を取りこぼさないよう1フレーム待つ。
        await Future<void>.delayed(Duration.zero);
        return SearchResult(
          bestMove: best,
          candidates: collector.candidates,
          depth: collector.depth,
        );
      } finally {
        await sub.cancel();
      }
    });
  }

  @override
  Future<List<Candidate>> analyze(String sfen,
      {List<String> moves = const [], int movetimeMs = 300, int multiPv = 5}) async {
    await setPosition(sfen, moves);
    final r = await think(movetimeMs: movetimeMs, multiPv: math.max(1, multiPv));
    return r.candidates;
  }

  @override
  Future<void> stop() async => _send('stop');
}
