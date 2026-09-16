import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// native/bridge/engine_bridge.h の Dart バインディング。
class YaneuraOuNative {
  YaneuraOuNative._(DynamicLibrary lib)
      : _init = lib.lookupFunction<Int32 Function(), int Function()>('engine_init'),
        _send = lib.lookupFunction<Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)>('engine_send'),
        _poll = lib.lookupFunction<Int32 Function(Pointer<Uint8>, Int32),
            int Function(Pointer<Uint8>, int)>('engine_poll'),
        _isRunning =
            lib.lookupFunction<Int32 Function(), int Function()>('engine_is_running');

  static bool get isSupportedPlatform => Platform.isAndroid;

  static YaneuraOuNative open() {
    if (Platform.isAndroid) {
      return YaneuraOuNative._(DynamicLibrary.open('libyaneuraou.so'));
    }
    if (Platform.isIOS) {
      return YaneuraOuNative._(DynamicLibrary.process());
    }
    throw UnsupportedError('YaneuraOu is not available on ${Platform.operatingSystem}');
  }

  final int Function() _init;
  final void Function(Pointer<Utf8>) _send;
  final int Function(Pointer<Uint8>, int) _poll;
  final int Function() _isRunning;

  static const _bufSize = 1 << 16;
  final Pointer<Uint8> _buf = malloc<Uint8>(_bufSize);

  void init() => _init();

  bool get isRunning => _isRunning() != 0;

  void send(String line) {
    final p = line.toNativeUtf8();
    try {
      _send(p);
    } finally {
      malloc.free(p);
    }
  }

  /// 出力行を1行取り出す。なければ null。
  String? poll() {
    final n = _poll(_buf, _bufSize);
    if (n < 0) return null;
    return _buf.cast<Utf8>().toDartString(length: n);
  }
}
