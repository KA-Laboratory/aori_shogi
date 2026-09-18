import 'package:aori_shogi/core/llm/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('モデル一覧は取り違えのない形になっている', () {
    expect(gunshiModels, isNotEmpty);
    expect(gunshiModels.map((m) => m.id).toSet().length, gunshiModels.length, reason: 'ファイル名が重複している');
    for (final m in gunshiModels) {
      expect(m.url, startsWith('https://'));
      expect(m.url, endsWith('.litertlm'), reason: '形式は .litertlm に揃える');
      expect(m.id, endsWith('.litertlm'));
      expect(m.bytes, greaterThan(100 * 1024 * 1024));
      expect(m.note, isNotEmpty);
    }
    expect(defaultGunshiModel, inInclusiveRange(0, gunshiModels.length - 1));
  });

  test('容量の表示は人が読める単位になる', () {
    expect(gunshiModels[0].sizeText, endsWith('MB'));
    expect(gunshiModels.last.sizeText, endsWith('GB'));
  });
}
