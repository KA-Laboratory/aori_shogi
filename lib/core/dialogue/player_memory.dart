/// たわいのない雑談と、相手について覚えておく記憶。
///
/// - 将棋と関係ない話には、人として共感し、まだ知らないことを1つ聞き返す（セリフは line_library の smalltalk）。
/// - 相手が話した事実（犬種・名前など）を端末内に保存し、次の対局以降の会話で使う。
/// - 何を覚えるかは提案（M3では端末内LLM）でよいが、保存してよいかはこのコードが決める。
/// - 保存形式は Python 版 aori_lab/smalltalk.py と共通の JSON（version 1）。
library;

import 'dart:convert';
import 'dart:math' as math;

/// 記憶の話題。Python 版の TOPICS と同じ並び。
const memoryTopics = <String>['pet', 'family', 'work', 'school', 'hobby', 'food', 'place', 'event', 'other'];

/// 覚えてはいけない話題（住所・連絡先・お金・思想信条・性的な話）。含む事実は保存しない。
/// 健康・恋愛の話は覚えてよい（2026-09-17 オーナー判断）。端末内のみ保存し、一覧から消せる。
final sensitivePattern = RegExp(
  '住所|番地|丁目|マンション名|電話|メール|@|パスワード|暗証|口座|カード番号|'
  '年収|給料|借金|ローン|貯金|資産|'
  '宗教|信仰|政党|支持政党|選挙で|性的|'
  r'\d{3,}-\d{2,}|\d{7,}',
);

/// 将棋の話かどうか（雑談扱いにしない）。
final _shogiWords = RegExp(
  '将棋|指す|指し|駒|王手|詰み|詰ん|詰め|悪手|好手|定跡|戦法|囲い|飛車|桂馬|香車|投了|待った|軍師|'
  '手番|盤|対局|先手|後手|タダ|ただ取り|浮いて|浮き駒|取られる|成り|成る',
);

/// 1文字の駒名は「散歩」「金曜」「角度」「玉ねぎ」を除くため、前が漢字でなく後ろが助詞などの時だけ。
final _piece1 = RegExp(r'(?<![一-鿿々])[角金銀桂香歩玉飛馬龍竜](?=[がをにはでものとだじ、。!！?？]|$)');

final _aiQuestion = RegExp(r'(AI|ＡＩ|ai|エーアイ|人工知能|ロボット|機械|プログラム|bot|ボット|中の人|人間).{0,8}(\?|？|なの|でしょ|だろ|ですか|か$)');

final _pet = RegExp('(犬|猫|うさぎ|ハムスター|インコ|金魚)');
final _keep = RegExp('飼|うちの|散歩');
final _name = RegExp(r'名前は[「『]?([ぁ-んァ-ヶー一-龠A-Za-z]{1,10}?)[」』]?(?:[。、！!？?\s]|です|だよ|って|$)');

/// 将棋と関係ない話か。
bool isSmalltalk(String text) => !_shogiWords.hasMatch(text) && !_piece1.hasMatch(text);

/// 「AIなの？」と聞かれたか。
bool asksIfAi(String text) => _aiQuestion.hasMatch(text);

String _now() {
  final d = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

final _rng = math.Random();
String _newId() => List.generate(10, (_) => '0123456789abcdef'[_rng.nextInt(16)]).join();

/// 相手について覚えた1件。
class MemoryFact {
  MemoryFact({
    required this.key,
    required this.value,
    this.topic = 'other',
    this.text = '',
    String? id,
    String? firstSeen,
    String? lastSeen,
    this.mentions = 1,
    this.quote = '',
  }) : id = id ?? _newId(),
       firstSeen = firstSeen ?? _now(),
       lastSeen = lastSeen ?? firstSeen ?? _now();

  factory MemoryFact.fromJson(Map<String, dynamic> j) => MemoryFact(
    key: j['key'] as String? ?? '',
    value: j['value'] as String? ?? '',
    topic: memoryTopics.contains(j['topic']) ? j['topic'] as String : 'other',
    text: j['text'] as String? ?? '',
    id: j['id'] as String?,
    firstSeen: j['first_seen'] as String?,
    lastSeen: j['last_seen'] as String?,
    mentions: (j['mentions'] as num?)?.toInt() ?? 1,
    quote: j['quote'] as String? ?? '',
  );

  /// 何についてか（例: 犬の名前）。
  String key;

  /// 値（例: ポチ）。
  String value;
  String topic;

  /// 自然文（例: 犬を飼っている。名前はポチ）。
  String text;
  final String id;
  final String firstSeen;
  String lastSeen;
  int mentions;

  /// 根拠になった相手の発言。
  String quote;

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'topic': topic,
    'text': text,
    'id': id,
    'first_seen': firstSeen,
    'last_seen': lastSeen,
    'mentions': mentions,
    'quote': quote,
  };

  String get sentence => text.isNotEmpty ? text : '$key: $value';
}

/// 端末内に残る記憶。[onChanged] で保存する（保存先は player_memory_file.dart）。
class PlayerMemory {
  PlayerMemory({List<MemoryFact>? facts, this.onChanged}) : facts = facts ?? [];

  factory PlayerMemory.fromJsonString(String s, {void Function(PlayerMemory)? onChanged}) {
    final d = jsonDecode(s) as Map<String, dynamic>;
    return PlayerMemory(
      facts: [for (final f in (d['facts'] as List? ?? const [])) MemoryFact.fromJson((f as Map).cast())],
      onChanged: onChanged,
    );
  }

  static const version = 1;
  final List<MemoryFact> facts;
  void Function(PlayerMemory)? onChanged;

  String toJsonString() => jsonEncode({
    'version': version,
    'facts': [for (final f in facts) f.toJson()],
  });

  void _changed() => onChanged?.call(this);

  /// 同じ見出しがあれば上書きし、無ければ足す。
  MemoryFact upsert(MemoryFact fact) {
    for (final f in facts) {
      if (f.key == fact.key) {
        f.value = fact.value;
        if (fact.text.isNotEmpty) f.text = fact.text;
        f.topic = fact.topic;
        f.lastSeen = fact.lastSeen;
        f.mentions += 1;
        if (fact.quote.isNotEmpty) f.quote = fact.quote;
        _changed();
        return f;
      }
    }
    facts.add(fact);
    _changed();
    return fact;
  }

  bool delete(String id) {
    final n = facts.length;
    facts.removeWhere((f) => f.id == id);
    if (facts.length == n) return false;
    _changed();
    return true;
  }

  void clear() {
    facts.clear();
    _changed();
  }

  /// 今の発言に関係しそうな記憶を先に、残りは最近のものから。
  List<MemoryFact> relevant(String text, {int limit = 6}) {
    final sorted = [...facts];
    bool hit(MemoryFact f) => [f.key, f.value, ..._topicWords(f.topic)].any((w) => w.isNotEmpty && text.contains(w));
    sorted.sort((a, b) {
      final h = (hit(b) ? 1 : 0) - (hit(a) ? 1 : 0);
      return h != 0 ? h : b.lastSeen.compareTo(a.lastSeen);
    });
    return sorted.take(limit).toList();
  }

  /// 端末内LLMに渡す記憶の塊（Python 版 prompt_block と同じ文面）。
  String promptBlock(String text) {
    final fs = relevant(text);
    if (fs.isEmpty) return '[相手について覚えていること] まだ何も知らない。';
    return '[相手について覚えていること（本人から聞いた事実だけ）]\n'
        '${fs.map((f) => '- ${f.sentence}（${f.firstSeen.substring(0, 10)}に聞いた）').join('\n')}';
  }
}

List<String> _topicWords(String topic) => switch (topic) {
  'pet' => const ['犬', '猫', '散歩', 'ペット'],
  'family' => const ['家族', '子ども', '妻', '夫', '母', '父'],
  'work' => const ['仕事', '会社', '残業'],
  'school' => const ['学校', '授業', 'テスト'],
  'hobby' => const ['趣味'],
  'food' => const ['ごはん', 'ご飯', '食べ', '飲み'],
  'place' => const ['旅行', '行った'],
  'event' => const ['今日', '週末'],
  _ => const [],
};

/// 保存してよいか: 値が相手の発言に実際に出てくる／機微情報でない／長すぎない。
bool acceptFact(MemoryFact f, String playerText) {
  if (f.key.isEmpty || f.value.isEmpty || f.value.length > 30) return false;
  if (sensitivePattern.hasMatch('${f.key}${f.value}${f.text}${f.quote}')) return false;
  final ws = RegExp(r'\s');
  return playerText.replaceAll(ws, '').contains(f.value.replaceAll(ws, ''));
}

/// 規則での最低限: ペットを飼っていること、ペットの名前。
List<MemoryFact> keywordFacts(String text, {List<String> recent = const []}) {
  if (sensitivePattern.hasMatch(text)) return const [];
  final out = <MemoryFact>[];
  final quote = text.length > 60 ? text.substring(0, 60) : text;
  final ctx = [...recent.length > 3 ? recent.sublist(recent.length - 3) : recent, text].join(' ');
  final m = _pet.firstMatch(text);
  if (m != null && _keep.hasMatch(text)) {
    final pet = m.group(1)!;
    out.add(MemoryFact(key: 'ペット', value: pet, topic: 'pet', text: '$petを飼っている', quote: quote));
  }
  final petCtx = _pet.firstMatch(ctx);
  final n = _name.firstMatch(text);
  if (n != null && petCtx != null) {
    final pet = petCtx.group(1)!;
    final name = n.group(1)!;
    out.add(MemoryFact(key: '$petの名前', value: name, topic: 'pet', text: '$petの名前は$name', quote: quote));
  }
  return out;
}
