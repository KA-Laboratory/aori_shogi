import 'dart:io';

import 'package:aori_shogi/core/dialogue/line_library.dart';
import 'package:aori_shogi/core/dialogue/player_memory.dart';
import 'package:aori_shogi/core/dialogue/speaker.dart';
import 'package:aori_shogi/core/dialogue/tone.dart';
import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LlmClient {
  _FakeLlm(this.replies, {this.ready = true});

  final List<String?> replies;
  int calls = 0;
  @override
  final bool ready;

  @override
  Future<String?> generate({required String system, required String user}) async {
    lastUser = user;
    return calls < replies.length ? replies[calls++] : null;
  }

  String lastUser = '';
}

void main() {
  final tone = ToneProfile.fromJsonString(File('assets/lines/gunshi_tone.json').readAsStringSync());
  final lines = LineLibrary.fromJsonString(File('assets/lines/gunshi_lines.json').readAsStringSync());
  const req = SpeechRequest(
    trigger: LineTrigger.tauntHit,
    mood: Mood.rattled,
    facts: '私の直前の手 5五銀 は悪手（約400点損）。',
    playerText: '今の銀、ミスでしょ',
    instruction: '煽りが図星で効いた。',
  );

  test('テンプレートは必ず何か返す', () async {
    expect(await TemplateSpeaker(lines).speak(req), isNotEmpty);
  });

  test('崩れは書き換えて通す', () async {
    final llm = _FakeLlm(['な、なにを言いますか。計算どおりですよ']);
    final line = await LlmSpeaker(client: llm, tone: tone, lines: lines).speak(req);
    expect(line, isNotNull);
    expect(tone.violations(line!, mood: 'rattled'), isEmpty);
    expect(llm.calls, 1);
  });

  test('直らない崩れは作り直し、駄目ならテンプレートに任せる（null）', () async {
    final llm = _FakeLlm(['そやな、ちげえか', 'お前が悪いんだぜ']);
    final speaker = LlmSpeaker(client: llm, tone: tone, lines: lines);
    expect(await speaker.speak(req), isNull);
    expect(llm.calls, 2);
  });

  test('長すぎるセリフは通さない', () async {
    final llm = _FakeLlm(['${'長' * 91}だ', '……いや、計算どおりだ']);
    expect(await LlmSpeaker(client: llm, tone: tone, lines: lines).speak(req), '……いや、計算どおりだ');
  });

  test('モデルが無いときは null（テンプレートで遊べる）', () async {
    final llm = _FakeLlm(['使われない'], ready: false);
    expect(await LlmSpeaker(client: llm, tone: tone, lines: lines).speak(req), isNull);
    expect(llm.calls, 0);
  });

  test('プロンプトに事実・相手・記憶・口調の念押しが入る', () async {
    final memory = PlayerMemory()..upsert(MemoryFact(key: '犬の名前', value: 'ポチ', topic: 'pet', text: '犬の名前はポチ'));
    final llm = _FakeLlm(['……いや、計算どおりだ']);
    await LlmSpeaker(client: llm, tone: tone, lines: lines).speak(
      SpeechRequest(
        trigger: req.trigger,
        mood: req.mood,
        facts: req.facts,
        playerText: req.playerText,
        instruction: req.instruction,
        memory: memory,
        recentLines: const ['さっきのセリフ'],
      ),
    );
    expect(llm.lastUser, contains('5五銀'));
    expect(llm.lastUser, contains('今の銀、ミスでしょ'));
    expect(llm.lastUser, contains('犬の名前はポチ'));
    expect(llm.lastUser, contains('さっきのセリフ'));
    expect(llm.lastUser.trimRight().endsWith(tone.reminder('rattled')), isTrue, reason: '口調は最後に念押し');
  });
}
