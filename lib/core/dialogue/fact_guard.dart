/// 生成されたセリフが「事実」と食い違っていないか見る。
///
/// 口調（[ToneProfile]）は言い方を守るが、中身までは見ない。実機の試し撃ちでは、
/// 口調が完璧なまま内容だけ間違っているセリフが出た:
/// - 事実に無い升目を作る
/// - 勝ち負けの取り違え:「相手が投了。大差での勝ち。」に対して「参りました」
/// - 悪手を最善と言い張る:「約-2461点損」に対して「これも最善の手でございます」
///
/// 学習データを増やせば減る類だが、減るだけで消えはしない。ここで落として
/// 作り直させ、それでも駄目なら定型文に戻す（[LlmSpeaker.speak]）。
/// 判定は Python 側の `build_edit_set.flags()` と同じ見方にしてある。
library;

/// 盤の升目（「７六」「76」「七六」）を拾う。駒名が続くものだけを升目とみなす。
final _square = RegExp(r'([1-9１-９一二三四五六七八九])([1-9１-９一二三四五六七八九])(?=[歩香桂銀金角飛玉王と馬龍竜成])');
const _kanjiDigit = {'〇': '0', '一': '1', '二': '2', '三': '3', '四': '4', '五': '5',
                     '六': '6', '七': '7', '八': '8', '九': '9'};
const _fullDigit = {'０': '0', '１': '1', '２': '2', '３': '3', '４': '4', '５': '5',
                    '６': '6', '７': '7', '８': '8', '９': '9'};

String _digit(String c) => _kanjiDigit[c] ?? _fullDigit[c] ?? c;

Set<String> squaresIn(String s) =>
    _square.allMatches(s).map((m) => _digit(m.group(1)!) + _digit(m.group(2)!)).toSet();

// 「事実に無い駒の名前を出したら落とす」も試したが、**使えないので入れていない**。
// 手書きの527件に当てたら 61件（12%）が引っかかった。理由は2つあって、どちらも
// 直しようがない:
//   1. 「と」が駒（と金）ではなく助詞として至る所に出る（「〜といたしましょう」）。
//   2. 軍師が盤上の他の駒に触れるのは当たり前で、事実は直前の一手しか挙げていない。
//      「相手の角の隙を開く」「相手の飛車を牽制できる」は正しいセリフなのに落ちる。
// 実機で出た「六桂の飛車」（桂を飛車と言い間違える）はこの規則なら拾えるが、
// 正しいセリフを1割以上落としてまで拾う価値は無い。数（2周目の126件）で減らす。

/// 事実が「私の勝ち」を言っているか。
final _factsWin = RegExp(r'相手が投了|相手玉が詰み|私の勝ち|勝利');
final _factsLose = RegExp(r'私が投了|私の玉が詰み|敗北|私の負け');
/// セリフが負けを認めている言い方。
final _saysLost = RegExp(r'参りました|負けました|私の負け|降参|敗北');
final _saysWon = RegExp(r'私の勝ち|勝利でござい|勝ちました');

/// 事実が悪手だと言っているか / セリフが最善だと言い張っているか。
final _factsBadMove = RegExp(r'悪手|点損');
final _saysBest = RegExp(r'最善(の手|手)?(で|だ|です|でござい)');

/// 事実と食い違っているところを並べる。空なら問題なし。
///
/// [facts] は `game_controller.dart` の `_facts` が作る文、[playerText] は相手の発言。
/// 相手が口にした駒や升目は、軍師が受けて言い返してよいので許す。
List<String> factViolations(String line, {required String facts, String playerText = ''}) {
  final out = <String>[];

  final extraSquares = squaresIn(line).difference(squaresIn(facts)).difference(squaresIn(playerText));
  if (extraSquares.isNotEmpty) out.add('事実にない升目:${(extraSquares.toList()..sort()).join(",")}');

  if (_factsWin.hasMatch(facts) && _saysLost.hasMatch(line)) out.add('勝っているのに負けを認めている');
  if (_factsLose.hasMatch(facts) && _saysWon.hasMatch(line)) out.add('負けているのに勝ちを名乗っている');

  // 事実の側も「最善」と言っている場合は言い張りではない。エンジンの最善手を指して
  // なお損をすることはある（「△６六桂打（最善手と同じ） は悪手（約-100点損）」）。
  if (_factsBadMove.hasMatch(facts) && !facts.contains('最善') && _saysBest.hasMatch(line)) {
    out.add('悪手を最善と言っている');
  }

  return out;
}
