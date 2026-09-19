/// 同時に1つだけ通す門。2つ目以降は待たせずに断る。
///
/// 端末内LLMは**同時に2つ走らせると落ちる**。実機（S24）で対局中に SIGSEGV になり、
/// 壊れたアドレス 0x3a22656c6f7222d1 の中身は `"role":` という文字列だった。
/// スタックは `litert::lm::Conversation::GetSingleTurnText` → `SendMessageAsync`、
/// つまり解放済みの会話の JSON をポインタとして読んでいる。
///
/// 試し撃ち（`BenchPage`）は1件ずつ順番に投げるので落ちなかった。対局中だけ落ちたのは、
/// `GameController._upgradeWithLlm` が `unawaited` で投げっぱなしにしているため。
/// 開始の一言を生成している最中に指し手の一言が重なると2つ走る。
///
/// 待たせずに断るのは、遅れて出てくるセリフに価値が無いから。軍師は先に定型文を
/// 喋っているので、断られた回はその定型文のままになるだけで、対局は何も止まらない。
library;

class SingleFlight {
  bool _busy = false;

  /// 重なって断った回数（開発用の目安）。
  int dropped = 0;

  bool get busy => _busy;

  /// 通れたら true。すでに走っていれば false を返し、[dropped] を1つ増やす。
  bool tryEnter() {
    if (_busy) {
      dropped++;
      return false;
    }
    _busy = true;
    return true;
  }

  void leave() => _busy = false;
}
