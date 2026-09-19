/// モデルを自分でダウンロードして、サイズと sha256 を確かめてから入れる。
///
/// なぜ自分で落とすか: `flutter_gemma` の `fromNetwork()` に任せると、**落ちてきた
/// 1.9GB が正しいかを誰も見ていない**。途中で切れてもモデルは読み込めてしまい、
/// 壊れた日本語を喋る（int4 を試したときに、まさにその壊れ方を見た）。
/// そうなると「モデルが悪い」と誤診して、原因を延々と探すことになる。
///
/// 型は `NnueStore.download()` と同じ: `.part` に落とす → サイズ照合 → sha256 照合 →
/// 正式な名前に rename。通ったものだけ `GunshiModelStore.installFromFile()` に渡す。
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'model_catalog.dart';

/// ダウンロードの途中経過。
class ModelDownloadProgress {
  const ModelDownloadProgress(this.received, this.total, {this.verifying = false});

  final int received;
  final int total;

  /// 受信し終えて、サイズと sha256 を確かめている最中。
  final bool verifying;

  /// 0..1。総量が分からないときは null。
  double? get fraction => total > 0 ? received / total : null;

  int get percent => total > 0 ? (received * 100 ~/ total) : 0;
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `.litertlm` を取ってきて検証する。入れるのは呼び出し側（[GunshiModelStore]）。
class ModelDownloader {
  ModelDownloader({required this.dir, HttpClient Function()? httpClient})
    : _httpClient = httpClient ?? HttpClient.new;

  /// 落とす先。端末では getApplicationSupportDirectory()/models を渡す。
  final Directory dir;
  final HttpClient Function() _httpClient;

  File fileFor(LlmModelSpec spec) => File('${dir.path}/${spec.id}');

  /// 取ってきて確かめる。通ったファイルを返す。進捗を [onProgress] に流す。
  ///
  /// 既に正しいものが置いてあれば、落とし直さずにそれを返す。
  Future<File> fetch(LlmModelSpec spec, {void Function(ModelDownloadProgress)? onProgress}) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = fileFor(spec);
    if (target.existsSync() && spec.bytes > 0 && target.lengthSync() == spec.bytes) {
      // サイズが合っていれば、毎回 1.9GB を読み直してまでは確かめない。
      return target;
    }

    final tmp = File('${target.path}.part');
    if (tmp.existsSync()) tmp.deleteSync();
    final client = _httpClient();
    try {
      final uri = Uri.parse(spec.url);
      final res = await (await client.getUrl(uri)).close();
      if (res.statusCode != 200) {
        throw ModelDownloadException('サーバーが ${res.statusCode} を返しました');
      }
      final total = res.contentLength > 0 ? res.contentLength : spec.bytes;
      var received = 0;
      final sink = tmp.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(ModelDownloadProgress(received, total));
        }
      } finally {
        await sink.close();
      }

      onProgress?.call(ModelDownloadProgress(received, total, verifying: true));
      await _verify(tmp, spec);
      if (target.existsSync()) target.deleteSync();
      tmp.renameSync(target.path);
      return target;
    } finally {
      client.close(force: true);
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> _verify(File f, LlmModelSpec spec) async {
    if (spec.bytes > 0 && f.lengthSync() != spec.bytes) {
      throw ModelDownloadException('大きさが合いません（${f.lengthSync()} / ${spec.bytes} バイト）。'
          '通信が途中で切れた可能性があります');
    }
    final want = spec.sha256;
    if (want == null || want.isEmpty) return; // 配布元のハッシュが分からないものは素通し
    final digest = await sha256.bind(f.openRead()).first;
    if (digest.toString() != want) {
      throw ModelDownloadException('ファイルが壊れています（ハッシュ不一致）');
    }
  }
}
