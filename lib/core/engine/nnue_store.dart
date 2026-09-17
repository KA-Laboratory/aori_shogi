import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// NNUE 評価関数ファイル（Háo, tanuki-, GPLv3）の保存と初回ダウンロード。
class NnueStore {
  NnueStore({Directory? baseDir, HttpClient Function()? httpClient})
    : _baseDir = baseDir, // ignore: prefer_initializing_formals
      _httpClient = httpClient ?? HttpClient.new;

  static const fileName = 'nn.bin';
  static const expectedSize = 64217066;
  static const expectedSha256 = '1141d275bceec911156801f27303dc9ff5beb24f4f59144cc069306c59e80782';

  /// KA-Laboratory/aori_shogi の nnue-assets ブランチ（main と独立）に置いた gzip 圧縮版。
  /// ⚠ リポジトリが非公開の間は取得できない。開発中は adb で files/eval/nn.bin に配置する
  /// （docs/dev/nnue.md）。
  static const downloadUrl = 'https://raw.githubusercontent.com/KA-Laboratory/aori_shogi/nnue-assets/nn.bin.gz';

  final Directory? _baseDir;
  final HttpClient Function() _httpClient;

  Future<Directory> evalDir() async {
    final base = _baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/eval');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _file() async => File('${(await evalDir()).path}/$fileName');

  /// サイズで簡易確認（毎回のハッシュ計算は重いので、検証はダウンロード時のみ）。
  Future<bool> isInstalled() async {
    final f = await _file();
    return f.existsSync() && f.lengthSync() == expectedSize;
  }

  /// ダウンロードして展開・検証する。進捗 0..1 を流す。
  Stream<double> download() async* {
    final target = await _file();
    final tmp = File('${target.path}.part');
    final client = _httpClient();
    try {
      final req = await client.getUrl(Uri.parse(downloadUrl));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(downloadUrl));
      }
      final total = res.contentLength;
      var received = 0;
      final progress = StreamController<double>();
      final sink = tmp.openWrite();
      final done = res
          .map((chunk) {
            received += chunk.length;
            if (total > 0) progress.add(received / total);
            return chunk;
          })
          .transform(gzip.decoder)
          .pipe(sink)
          .whenComplete(progress.close);
      unawaited(done.catchError((Object _) {})); // 下の await で改めて受ける
      yield* progress.stream;
      await done;

      if (tmp.lengthSync() != expectedSize) {
        throw const FileSystemException('評価関数ファイルのサイズが一致しません');
      }
      final digest = await sha256.bind(tmp.openRead()).first;
      if (digest.toString() != expectedSha256) {
        throw const FileSystemException('評価関数ファイルのハッシュが一致しません');
      }
      if (target.existsSync()) target.deleteSync();
      tmp.renameSync(target.path);
      yield 1.0;
    } finally {
      client.close(force: true);
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
    }
  }
}
