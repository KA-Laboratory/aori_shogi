import 'dart:convert';

import 'intent.dart';

/// 日本語の簡易正規化（tool/build_lexicon.py の norm と同じ規則）。
/// 全角英数→半角、半角カナ→全角相当は扱わない（NFKC の一部のみ）、カタカナ→ひらがな、小文字化、空白除去。
String normalizeJa(String s, {bool foldKana = true}) {
  final sb = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角ASCII→半角
    if (c == 0x3000) continue; // 全角空白
    if (foldKana && c >= 0x30A1 && c <= 0x30F6) c -= 0x60; // カタカナ→ひらがな
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) continue;
    sb.writeCharCode(c);
  }
  return sb.toString().toLowerCase();
}

class _Term {
  const _Term(this.text, this.kind, this.weight, this.keepOnNegation, this.raw);
  final String text;
  final IntentKind kind;
  final double weight;
  final bool keepOnNegation;

  /// カナを畳まない表記で照合する（不適切語）。
  final bool raw;
}

/// 分類の内訳（デバッグ・テスト用）。
class IntentAnalysis {
  IntentAnalysis(this.intent, this.scores, this.matched, this.sentiment, {this.emotions = const {}});
  final PlayerIntent intent;
  final Map<IntentKind, double> scores;
  final List<String> matched;

  /// 評価極性辞書による +/− の合計。
  final double sentiment;

  /// ML-Ask の感情カテゴリごとの出現数（yorokobi, iya, ikari …）。
  final Map<String, int> emotions;
}

/// 将棋用語辞書（assets/lexicon/shogi_terms.json）＋日本語評価極性辞書（assets/lexicon/sentiment_ja.json）による分類器。
class IntentLexicon {
  IntentLexicon._(
    this._terms,
    this._requests,
    this._accept,
    this._decline,
    this._pieces,
    this._sentiment,
    this._maxSentimentLen,
    this._emotions,
    this._intensifiers,
    this._shogiContext,
  );

  static const termsAsset = 'assets/lexicon/shogi_terms.json';
  static const sentimentAsset = 'assets/lexicon/sentiment_ja.json';
  static const emotionAsset = 'assets/lexicon/emotion_ja.json';

  factory IntentLexicon.fromJson(String termsJson, String sentimentJson, [String? emotionJson]) {
    final t = jsonDecode(termsJson) as Map<String, dynamic>;
    final terms = <_Term>[
      for (final e in (t['terms'] as List).cast<Map<String, dynamic>>())
        _Term(
          e['t'] as String,
          IntentKind.values.byName(e['k'] as String),
          (e['w'] as num).toDouble(),
          e['neg'] == true,
          e['raw'] == true,
        ),
    ]..sort((a, b) => b.text.length.compareTo(a.text.length));
    final req = <IntentRequest, List<String>>{
      for (final e in (t['request'] as Map<String, dynamic>).entries)
        IntentRequest.values.byName(e.key): (e.value as List).cast<String>(),
    };
    final sentiment = (jsonDecode(sentimentJson) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );
    var maxLen = 0;
    for (final k in sentiment.keys) {
      if (k.length > maxLen) maxLen = k.length;
    }
    final emo = emotionJson == null ? const <String, dynamic>{} : jsonDecode(emotionJson) as Map<String, dynamic>;
    final emotions = ((emo['words'] as Map<String, dynamic>?) ?? const {}).cast<String, String>();
    for (final k in emotions.keys) {
      if (k.length > maxLen) maxLen = k.length;
    }
    return IntentLexicon._(
      terms,
      req,
      (t['accept'] as List).cast<String>(),
      (t['decline'] as List).cast<String>(),
      (t['pieces'] as List).cast<String>(),
      sentiment,
      maxLen.clamp(1, 12),
      emotions,
      ((emo['intensifiers'] as List?) ?? const []).cast<String>(),
      ((t['shogiContext'] as List?) ?? const []).cast<String>(),
    );
  }

  final List<_Term> _terms;
  final Map<IntentRequest, List<String>> _requests;
  final List<String> _accept;
  final List<String> _decline;
  final List<String> _pieces;
  final Map<String, int> _sentiment;
  final int _maxSentimentLen;
  final Map<String, String> _emotions;
  final List<String> _intensifiers;
  final List<String> _shogiContext;

  static const _positiveEmotions = {'yorokobi', 'suki', 'yasu'};
  static const _negativeEmotions = {'iya', 'ikari'};

  static final _negation = RegExp(r'^(?:て|で)?(?:い)?(?:な[いく]|ません|ず|ぬ|じゃな|ではな)');

  /// 「〜じゃない？」「〜じゃね？」は反語（肯定）。
  static final _rhetorical = RegExp(r'^(?:(?:じゃ|では)(?:ない|ね)(?:の|か|かな|です)?[?？]|(?:じゃ|では)ないですか|じゃん)');
  static final _hiraganaOnly = RegExp(r'^[\u3041-\u309F]+$');
  static final _contrast = RegExp(r'でも|けど|けれど|しかし|ただし|なのに|のに');
  static final _interrogative = RegExp(r'何|なに|どこ|どう|なぜ|なんで|いつ|誰|だれ|どれ|どっち|どの');
  static final _selfRef = RegExp(r'私|僕|ぼく|俺|おれ|自分|うち');
  static final _myPiecesRef = RegExp(r'君|きみ|お前|おまえ|あなた|あんた|そっち|軍師|天才|その|この');

  static final _katakana = RegExp(r'^[\u30A1-\u30FA\u30FC]+$');
  static bool _isKatakana(String c) => _katakana.hasMatch(c);

  /// 罵倒語は表記そのままで照合。カタカナ語は前後がカタカナなら別語（ハイビスカス・カスタム）、
  /// 直後が否定なら不成立（死ねない）。
  static bool _rawHit(String text, String word) {
    final kata = _isKatakana(word);
    var from = 0;
    while (true) {
      final i = text.indexOf(word, from);
      if (i < 0) return false;
      from = i + 1;
      final end = i + word.length;
      if (kata && ((i > 0 && _isKatakana(text[i - 1])) || (end < text.length && _isKatakana(text[end])))) continue;
      if (_negation.hasMatch(text.substring(end))) continue;
      return true;
    }
  }

  static final _kanji = RegExp(r'[一-鿿々]');
  static const _pieceFollow = {
    'が',
    'を',
    'に',
    'は',
    'で',
    'も',
    'の',
    'と',
    'だ',
    'じ',
    'ち',
    'さ',
    'く',
    '、',
    '。',
    '!',
    '?',
    'ー',
    '成',
    '打',
  };

  /// 1文字の駒名（金・角・歩・馬…）は「金額」「歩く」「馬鹿」「貯金」を除くため、前後を見る。
  bool _mentionsPiece(String text) {
    if (_shogiContext.any(text.contains)) return true;
    for (final p in _pieces) {
      if (p.length >= 2) {
        if (text.contains(p)) return true;
        continue;
      }
      var from = 0;
      while (true) {
        final i = text.indexOf(p, from);
        if (i < 0) break;
        from = i + 1;
        final prevKanji = i > 0 && _kanji.hasMatch(text[i - 1]) && !'二三四五六七八九同一'.contains(text[i - 1]);
        final next = i + 1 < text.length ? text[i + 1] : null;
        if (prevKanji) continue;
        if (next == null || _pieceFollow.contains(next)) return true;
      }
    }
    return false;
  }

  IntentAnalysis analyze(String raw, {required bool hasPendingOffer}) {
    final text = normalizeJa(raw);
    final rawText = normalizeJa(raw, foldKana: false);
    final scores = {for (final k in IntentKind.values) k: 0.0};
    final matched = <String>[];
    final used = List<bool>.filled(text.length, false);
    // 逆接（でも・けど…）の後ろを重く、前を軽く（「さすが…でも悪手」は皮肉）
    final contrast = _contrast.allMatches(text).fold<int>(-1, (p, m) => m.end > p ? m.end : p);
    double pos(int i) => contrast < 0 ? 1.0 : (i >= contrast ? 1.5 : 0.7);

    // 将棋用語（長い語から、重なりは先勝ち）
    for (final term in _terms) {
      if (term.raw) {
        if (_rawHit(rawText, term.text)) {
          scores[term.kind] = scores[term.kind]! + term.weight;
          matched.add(term.text);
        }
        continue;
      }
      var from = 0;
      while (true) {
        final i = text.indexOf(term.text, from);
        if (i < 0) break;
        from = i + 1;
        if (used.sublist(i, i + term.text.length).any((u) => u)) continue;
        for (var j = i; j < i + term.text.length; j++) {
          used[j] = true;
        }
        final after = text.substring(i + term.text.length);
        final negated = _negation.hasMatch(after) && !_rhetorical.hasMatch(after);
        final keep =
            term.keepOnNegation ||
            const {
              IntentKind.threat,
              IntentKind.hangingPiece,
              IntentKind.question,
              IntentKind.abuse,
            }.contains(term.kind);
        if (negated && !keep) {
          // 「悪手じゃない」「強くない」: 褒め↔けなしを弱く反転、それ以外は打ち消し
          if (term.kind == IntentKind.praise) {
            scores[IntentKind.mock] = scores[IntentKind.mock]! + term.weight * 0.5;
          } else if (term.kind == IntentKind.blunderCall) {
            scores[IntentKind.praise] = scores[IntentKind.praise]! + term.weight * 0.3;
          }
          matched.add('${term.text}(否定)');
          continue;
        }
        scores[term.kind] = scores[term.kind]! + term.weight * pos(i);
        matched.add(term.text);
      }
    }

    // 評価極性（将棋用語で使っていない部分を最長一致で走査）
    var sentiment = 0.0;
    final emotionCounts = <String, int>{};
    var i = 0;
    while (i < text.length) {
      if (used[i]) {
        i++;
        continue;
      }
      var hit = 0;
      for (var len = _maxSentimentLen; len >= 2; len--) {
        if (i + len > text.length) continue;
        final w = text.substring(i, i + len);
        // 短いひらがな語は語の途中から拾わない（「そうそう」の うそ、「ですか」の すか、「ください」の ださい）
        if (len <= 3 && i > 0 && _hiraganaOnly.hasMatch(w) && _hiraganaOnly.hasMatch(text[i - 1])) continue;
        final emo = _emotions[w];
        if (emo != null) emotionCounts[emo] = (emotionCounts[emo] ?? 0) + 1;
        var v = _sentiment[w];
        if (v == null && emo != null) {
          if (_positiveEmotions.contains(emo)) v = 1;
          if (_negativeEmotions.contains(emo)) v = -1;
        }
        if (v == null && emo != null) {
          hit = len;
          break;
        }
        if (v != null) {
          final rest = text.substring(i + len);
          final negated = _negation.hasMatch(rest) && !_rhetorical.hasMatch(rest);
          sentiment += negated ? -v * 0.7 : v.toDouble();
          matched.add('$w${v > 0 ? '+' : '-'}${negated ? '(否定)' : ''}');
          hit = len;
          break;
        }
      }
      i += hit > 0 ? hit : 1;
    }
    final mentionsPiece = _mentionsPiece(text);
    // 駒の話をしている時の「遊んでる」「泣いてる」「プレゼント」は駒浮き寄り
    if (mentionsPiece && scores[IntentKind.hangingPiece]! > 0) {
      scores[IntentKind.hangingPiece] = scores[IntentKind.hangingPiece]! + 0.15;
    }
    final mentionsYou = _myPiecesRef.hasMatch(raw);
    if (sentiment >= 1) {
      // 相手や盤に向いていない肯定（「このケーキ美味しい」「私も買おうかな」）は褒めとして弱く
      final aimed = mentionsYou || mentionsPiece;
      final selfTalk = _selfRef.hasMatch(raw) && !mentionsYou;
      final k = aimed ? 0.55 : (selfTalk ? 0.15 : 0.3);
      scores[IntentKind.praise] = scores[IntentKind.praise]! + k * sentiment.clamp(0, 3);
    } else if (sentiment <= -1) {
      // 駒に向いた否定語は駒浮き/悪手寄り、人に向いた否定語はからかい
      final boost = 0.35 * (-sentiment).clamp(0, 3);
      if (mentionsPiece && scores[IntentKind.hangingPiece]! > 0) {
        scores[IntentKind.hangingPiece] = scores[IntentKind.hangingPiece]! + boost;
      } else if (mentionsPiece) {
        scores[IntentKind.blunderCall] = scores[IntentKind.blunderCall]! + boost;
      } else if (mentionsYou) {
        scores[IntentKind.mock] = scores[IntentKind.mock]! + boost;
      } else {
        scores[IntentKind.mock] = scores[IntentKind.mock]! + boost * 0.6;
      }
    }
    final isQuestion = raw.contains('?') || raw.contains('？') || text.endsWith('の') || text.endsWith('か');
    if (isQuestion && _interrogative.hasMatch(raw)) {
      scores[IntentKind.question] = scores[IntentKind.question]! + 0.5;
    }

    // 要求・返事
    var request = IntentRequest.none;
    if (hasPendingOffer) {
      if (_accept.any((a) => text.startsWith(a))) {
        request = IntentRequest.accept;
      } else if (_decline.any(text.contains)) {
        request = IntentRequest.decline;
      }
    }
    if (request == IntentRequest.none) {
      for (final e in _requests.entries) {
        if (e.value.any(text.contains)) {
          request = e.key;
          break;
        }
      }
    }

    // 決定: 不適切 > 最大スコア（しきい値 0.5）。質問は煽りがない時だけ。
    IntentKind kind = IntentKind.chat;
    if (scores[IntentKind.abuse]! >= 0.8) {
      kind = IntentKind.abuse;
    } else {
      final tauntKinds = [
        IntentKind.blunderCall,
        IntentKind.hangingPiece,
        IntentKind.threat,
        IntentKind.mock,
        IntentKind.praise,
      ];
      var best = IntentKind.chat;
      var bestScore = 0.49;
      for (final k in tauntKinds) {
        if (scores[k]! > bestScore) {
          best = k;
          bestScore = scores[k]!;
        }
      }
      // 「さすが…でも悪手」: けなしが褒めと拮抗したら、けなしを優先（皮肉）
      if (best == IntentKind.praise) {
        for (final k in [IntentKind.blunderCall, IntentKind.hangingPiece, IntentKind.threat]) {
          if (scores[k]! >= scores[IntentKind.praise]! * 0.7 && scores[k]! > 0.49) best = k;
        }
      }
      if (scores[IntentKind.question]! > 0.49 && scores[IntentKind.question]! > bestScore) best = IntentKind.question;
      if (request == IntentRequest.hint && best == IntentKind.question) best = IntentKind.chat;
      kind = best;
    }
    final bangs = '!'.allMatches(text).length;
    final intensifierHits = _intensifiers.where(text.contains).length;
    final aroused = (emotionCounts['ikari'] ?? 0) + (emotionCounts['takaburi'] ?? 0) + (emotionCounts['odoroki'] ?? 0);
    final top = scores[kind] ?? 0;
    final intensity =
        (0.35 +
                0.25 * top.clamp(0, 2) +
                0.12 * bangs.clamp(0, 3) +
                0.1 * sentiment.abs().clamp(0, 2) +
                0.08 * intensifierHits.clamp(0, 3) +
                0.06 * aroused.clamp(0, 2))
            .clamp(0.0, 1.0);
    return IntentAnalysis(
      PlayerIntent(kind: kind, request: request, intensity: intensity.toDouble()),
      scores,
      matched,
      sentiment,
      emotions: emotionCounts,
    );
  }
}
