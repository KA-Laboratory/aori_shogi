import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/llm/model_catalog.dart';
import 'package:aori_shogi/core/llm/model_download.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本物の HTTP サーバーを立てて試す。検証したいのは「途中で切れたものを弾くか」
/// なので、ここを偽物にすると意味が無い。
Future<HttpServer> _serve(List<int> body, {int status = 200, int? truncateTo}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response.statusCode = status;
    if (status == 200) {
      if (truncateTo == null) {
        req.response.contentLength = body.length;
        req.response.add(body);
      } else {
        // 通信が途中で切れた状態。contentLength は名乗らない（名乗ると Dart の
        // HttpServer 側が「足りない」と怒って close できない）。受け取る側から見ると
        // 総量が分からないまま短いデータで終わる、という本番と同じ形になる。
        req.response.add(body.sublist(0, truncateTo));
      }
    }
    await req.response.close();
  });
  return server;
}

LlmModelSpec _spec(HttpServer s, {required int bytes, String? sha}) => LlmModelSpec(
  id: 'test.litertlm',
  label: 'test',
  family: LlmFamily.qwen3,
  url: 'http://${s.address.host}:${s.port}/model.litertlm',
  bytes: bytes,
  sha256: sha,
  note: '',
);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('model_dl'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final body = utf8.encode('これはモデルのつもりのバイト列' * 50);
  final sha = sha256.convert(body).toString();

  test('正しく落ちてくれば、そのファイルを返す', () async {
    final server = await _serve(body);
    addTearDown(() => server.close(force: true));
    final d = ModelDownloader(dir: tmp);
    final f = await d.fetch(_spec(server, bytes: body.length, sha: sha));
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), body.length);
    expect(f.path.endsWith('test.litertlm'), isTrue);
  });

  test('途中で切れたら弾く（1.9GB でこれが起きても気づけるように）', () async {
    final server = await _serve(body, truncateTo: body.length ~/ 2);
    addTearDown(() => server.close(force: true));
    final d = ModelDownloader(dir: tmp);
    await expectLater(
      d.fetch(_spec(server, bytes: body.length, sha: sha)),
      throwsA(isA<ModelDownloadException>().having((e) => e.message, 'message', contains('大きさが合いません'))),
    );
  });

  test('サイズは合うが中身が違えば弾く', () async {
    final other = utf8.encode('ち' * body.length).sublist(0, body.length);
    final server = await _serve(other);
    addTearDown(() => server.close(force: true));
    final d = ModelDownloader(dir: tmp);
    await expectLater(
      d.fetch(_spec(server, bytes: body.length, sha: sha)),
      throwsA(isA<ModelDownloadException>().having((e) => e.message, 'message', contains('壊れています'))),
    );
  });

  test('失敗したら .part を残さない（次の取得が混乱しないように）', () async {
    final server = await _serve(body, truncateTo: 10);
    addTearDown(() => server.close(force: true));
    final d = ModelDownloader(dir: tmp);
    await expectLater(d.fetch(_spec(server, bytes: body.length, sha: sha)), throwsA(isA<Exception>()));
    expect(tmp.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    expect(tmp.listSync().where((e) => e.path.endsWith('test.litertlm')), isEmpty);
  });

  test('サーバーが 404 を返したら弾く', () async {
    final server = await _serve(body, status: 404);
    addTearDown(() => server.close(force: true));
    final d = ModelDownloader(dir: tmp);
    await expectLater(
      d.fetch(_spec(server, bytes: body.length, sha: sha)),
      throwsA(isA<ModelDownloadException>().having((e) => e.message, 'message', contains('404'))),
    );
  });

  test('ハッシュが分からないモデルはサイズだけ見る', () async {
    final server = await _serve(body);
    addTearDown(() => server.close(force: true));
    final d = ModelDownloader(dir: tmp);
    final f = await d.fetch(_spec(server, bytes: body.length)); // sha256 なし
    expect(f.lengthSync(), body.length);
  });

  test('すでに正しいものがあれば落とし直さない', () async {
    final server = await _serve(body);
    addTearDown(() => server.close(force: true));
    final spec = _spec(server, bytes: body.length, sha: sha);
    final d = ModelDownloader(dir: tmp);
    d.fileFor(spec).writeAsBytesSync(body);
    await server.close(force: true); // サーバーを止めても取れるなら、落としていない
    final f = await d.fetch(spec);
    expect(f.lengthSync(), body.length);
  });

  test('進捗が最後まで流れる', () async {
    final server = await _serve(body);
    addTearDown(() => server.close(force: true));
    final seen = <int>[];
    await ModelDownloader(dir: tmp).fetch(
      _spec(server, bytes: body.length, sha: sha),
      onProgress: (p) => seen.add(p.percent),
    );
    expect(seen, isNotEmpty);
    expect(seen.last, 100);
  });
}
