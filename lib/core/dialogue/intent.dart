/// 自由文の分類。通常は lexicon.dart の IntentLexicon（辞書版）を使い、辞書が読めない時だけこのキーワード版。
library;

enum IntentKind { blunderCall, hangingPiece, threat, mock, praise, question, chat, abuse }

enum IntentRequest { none, undo, hint, draw, resign, accept, decline }

class PlayerIntent {
  const PlayerIntent({this.kind = IntentKind.chat, this.request = IntentRequest.none, this.intensity = 0.5});
  final IntentKind kind;
  final IntentRequest request;
  final double intensity;

  bool get isTaunt => const {
    IntentKind.blunderCall,
    IntentKind.hangingPiece,
    IntentKind.threat,
    IntentKind.mock,
    IntentKind.praise,
  }.contains(kind);
}

final _kinds = <(IntentKind, RegExp)>[
  (IntentKind.abuse, RegExp(r'死ね|殺す|クズ|ブス|きもい|キモい')),
  (IntentKind.hangingPiece, RegExp(r'浮いて|タダ|ただ取り|取られる|ただで')),
  (IntentKind.threat, RegExp(r'詰み|詰ん|詰め|玉.*(危|やば)|王手|受けなし')),
  (IntentKind.blunderCall, RegExp(r'悪手|ミス|やらかし|最悪の手|ひどい手|緩手|疑問手|ポカ|筋悪')),
  (IntentKind.praise, RegExp(r'さすが|すごい|強い|天才だ|うまい|上手|最強|神')),
  (IntentKind.question, RegExp(r'次.*(何|どこ|どう)|狙い|読み筋|作戦|本当は|本音|どう指す|何を考え')),
  (IntentKind.mock, RegExp(r'笑|ｗ|w{2,}|ポンコツ|へぼ|ヘボ|雑魚|ざこ|自称')),
];

final _requests = <(IntentRequest, RegExp)>[
  (IntentRequest.undo, RegExp(r'待った|待って|今のなし|戻して|やり直')),
  (IntentRequest.hint, RegExp(r'ヒント|教えて|次の手')),
  (IntentRequest.draw, RegExp(r'引き分け|ドロー')),
  (IntentRequest.resign, RegExp(r'投了|負けを認め')),
];

PlayerIntent classifyKeywords(String text, {required bool hasPendingOffer}) {
  var kind = IntentKind.chat;
  for (final (k, re) in _kinds) {
    if (re.hasMatch(text)) {
      kind = k;
      break;
    }
  }
  var req = IntentRequest.none;
  if (hasPendingOffer) {
    if (RegExp(r'^(いい|OK|ok|オーケー|どうぞ|はい|うん|許す|了解)').hasMatch(text.trim())) {
      req = IntentRequest.accept;
    } else if (RegExp(r'だめ|ダメ|断|嫌|いや|ことわ|無理|許さ').hasMatch(text)) {
      req = IntentRequest.decline;
    }
  }
  if (req == IntentRequest.none) {
    for (final (r, re) in _requests) {
      if (re.hasMatch(text)) {
        req = r;
        break;
      }
    }
  }
  // 「次の手教えて」はヒント要求であって軍師への質問ではない
  if (req == IntentRequest.hint && kind == IntentKind.question) kind = IntentKind.chat;
  final bangs = '！'.allMatches(text).length + '!'.allMatches(text).length;
  final intensity = (0.4 + 0.15 * bangs + (kind == IntentKind.mock || kind == IntentKind.abuse ? 0.2 : 0)).clamp(
    0.0,
    1.0,
  );
  return PlayerIntent(kind: kind, request: req, intensity: intensity.toDouble());
}
