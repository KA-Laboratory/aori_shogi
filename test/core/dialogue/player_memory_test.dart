import 'dart:io';

import 'package:aori_shogi/core/dialogue/player_memory.dart';
import 'package:aori_shogi/core/dialogue/player_memory_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('将棋の話は雑談にしない', () {
    expect(isSmalltalk('今日は犬の散歩で疲れたよ'), isTrue);
    expect(isSmalltalk('その飛車、タダじゃない？'), isFalse);
    expect(isSmalltalk('今の手は悪手でしょ'), isFalse);
    // 1文字の駒名に見える日常語は雑談のまま
    expect(isSmalltalk('金曜は玉ねぎを買った'), isTrue);
    expect(isSmalltalk('角が浮いてるよ'), isFalse);
  });

  test('AIか聞かれたのが分かる', () {
    expect(asksIfAi('もしかしてAIなの？'), isTrue);
    expect(asksIfAi('君って本当に人間？'), isTrue);
    expect(asksIfAi('AIの話は面白いな'), isFalse);
  });

  test('規則でペットと名前を拾う', () {
    final facts = keywordFacts('うちの犬の散歩に行ってきた');
    expect(facts.map((f) => f.key), ['ペット']);
    expect(facts.first.value, '犬');
    final named = keywordFacts('名前はポチだよ', recent: ['うちの犬の散歩に行ってきた']);
    expect(named.map((f) => f.key), ['犬の名前']);
    expect(named.first.value, 'ポチ');
  });

  test('機微情報と裏づけのない事実は保存しない', () {
    expect(keywordFacts('うちの犬の散歩、住所は中区だよ'), isEmpty);
    final fact = MemoryFact(key: '犬の名前', value: 'ポチ');
    expect(acceptFact(fact, '名前はポチだよ'), isTrue);
    expect(acceptFact(fact, '犬を飼ってるよ'), isFalse, reason: '相手が言っていない値は保存しない');
    expect(acceptFact(MemoryFact(key: '口座', value: '1234567'), '口座は1234567'), isFalse);
  });

  test('同じ見出しは上書きして回数を数える', () {
    final m = PlayerMemory();
    m.upsert(MemoryFact(key: 'ペット', value: '犬', topic: 'pet', text: '犬を飼っている'));
    m.upsert(MemoryFact(key: 'ペット', value: '猫', topic: 'pet', text: '猫を飼っている'));
    expect(m.facts.length, 1);
    expect(m.facts.first.value, '猫');
    expect(m.facts.first.mentions, 2);
    expect(m.delete(m.facts.first.id), isTrue);
    expect(m.facts, isEmpty);
  });

  test('今の話に関係する記憶を先に出す', () {
    final m = PlayerMemory();
    m.upsert(MemoryFact(key: '仕事', value: '設計', topic: 'work', text: '設計の仕事をしている'));
    m.upsert(MemoryFact(key: '犬の名前', value: 'ポチ', topic: 'pet', text: '犬の名前はポチ'));
    expect(m.relevant('犬は元気？').first.key, '犬の名前');
    expect(m.promptBlock('犬は元気？'), contains('犬の名前はポチ'));
    expect(PlayerMemory().promptBlock('やあ'), contains('まだ何も知らない'));
  });

  test('保存して読み直しても同じ（Python 版と共通の JSON）', () {
    final dir = Directory.systemTemp.createTempSync('aori_memory');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = PlayerMemoryFile(File('${dir.path}/memory/player_memory.json'));
    final m = store.load();
    m.upsert(MemoryFact(key: '犬の名前', value: 'ポチ', topic: 'pet', text: '犬の名前はポチ', quote: '名前はポチだよ'));
    final again = store.load();
    expect(again.facts.length, 1);
    expect(again.facts.first.toJson(), m.facts.first.toJson());
    expect(again.toJsonString(), contains('"first_seen"'));
  });
}
