import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/nnue_store.dart';
import '../../core/engine/shogi_engine.dart';
import 'package:yaneuraou_ffi/yaneuraou_ffi.dart';

sealed class EngineStatus {
  const EngineStatus();
}

class EngineChecking extends EngineStatus {
  const EngineChecking();
}

class EngineUnsupported extends EngineStatus {
  const EngineUnsupported();
}

class EngineNeedsDownload extends EngineStatus {
  const EngineNeedsDownload({this.error});
  final String? error;
}

class EngineDownloading extends EngineStatus {
  const EngineDownloading(this.progress);
  final double progress;
}

class EngineStarting extends EngineStatus {
  const EngineStarting();
}

class EngineReady extends EngineStatus {
  const EngineReady(this.engine);
  final ShogiEngine engine;
}

class EngineFailed extends EngineStatus {
  const EngineFailed(this.message);
  final String message;
}

final nnueStoreProvider = Provider<NnueStore>((ref) => NnueStore());

final engineControllerProvider = NotifierProvider<EngineController, EngineStatus>(EngineController.new);

class EngineController extends Notifier<EngineStatus> {
  @override
  EngineStatus build() {
    if (!YaneuraOuNative.isSupportedPlatform) return const EngineUnsupported();
    Future(_check);
    return const EngineChecking();
  }

  NnueStore get _store => ref.read(nnueStoreProvider);

  Future<void> _check() async {
    if (await _store.isInstalled()) {
      await _start();
    } else {
      state = const EngineNeedsDownload();
    }
  }

  Future<void> download() async {
    if (state is EngineDownloading || state is EngineStarting) return;
    state = const EngineDownloading(0);
    try {
      await for (final p in _store.download()) {
        state = EngineDownloading(p);
      }
      await _start();
    } catch (e) {
      state = EngineNeedsDownload(error: '$e');
    }
  }

  /// 開発用: 既に置かれたファイルを再確認する（adb で配置した場合など）。
  Future<void> recheck() => _check();

  Future<void> _start() async {
    state = const EngineStarting();
    try {
      final dir = await _store.evalDir();
      final engine = await YaneuraOuEngine.start(evalDir: dir.path);
      state = EngineReady(engine);
    } catch (e) {
      state = EngineFailed('$e');
    }
  }
}
