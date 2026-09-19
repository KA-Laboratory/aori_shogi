# M3: 端末内LLM（flutter_gemma）の組み込み方針

調査日 2026-09-18（opus-5）。一次情報は pub.dev / GitHub / ai.google.dev。キャラ追加学習の計画は docs/dev/m3_character_finetune.md、データ生成は docs/dev/finetune_data_prompt.md。

## 分かったこと（出典つき）

- flutter_gemma 最新 1.8.3（2026-09-15）、ライセンス MIT、Dart 3.12 以上（本アプリは 3.12.2 なので可）。Android / iOS / macOS / Windows / Linux / Web 対応。https://pub.dev/packages/flutter_gemma
  - GitHub のタグは v1.1.0 止まりで pub.dev と表記がずれている。採用時はバージョンを固定する。
- モデルは `.litertlm` が標準形式（`.task` は旧 MediaPipe 形式で、移行時の不具合報告あり: https://github.com/DenisovAV/flutter_gemma/issues/150）。
  列挙されている中で小さいのは Qwen3 0.6B ≈586MB、Gemma 4 E2B ≈2.4GB、Gemma 4 E4B ≈4.3GB。https://fluttergemma.dev/docs/models
- API は `FlutterGemma.initialize` → `FlutterGemma.installModel(...).fromNetwork(url).withProgress(...).install()` → `FlutterGemma.getActiveModel(maxTokens:, preferredBackend:)` → `model.createChat(systemInstruction:)` → `generateChatResponse()` / `generateChatResponseAsync()`。maxTokens は 1024 未満でも 1024 に切り上げ。https://fluttergemma.dev/docs/getting-started
- Gemma のライセンス（Gemma Terms of Use）は条件つきで再配布・組み込みを許す（利用制限の引き継ぎ、規約の提示、改変の明示、Notice の同梱）。https://ai.google.dev/gemma/terms
- **LoRA アダプタは flutter_gemma の公開APIには無い**。LiteRT-LM 側も公開API化は未完（Issue #1188 が Open、C API の PR #2508 が進行中）。https://github.com/google-ai-edge/LiteRT-LM/issues/1188
- iOS シミュレータは CPU のみ・Metal 256MB 制限。最低RAM/OSの公式な数値は見つからず（実機検証が必要）。
- 軽量モデルの日本語は英語より弱いという報告が複数あり、自前の評価が必要（→ tools/eval_persona.py）。

## 決めたこと

1. **LoRA はマージして配る**。アダプタを実行時に差す方法は当てにできないので、PC で QLoRA → ベースにマージ → `.litertlm` へ変換した1つのモデルを配る。LiteRT-LM の LoRA API が安定したら差し替えを検討する。
2. **形式は `.litertlm`**、配布は**アプリ内ダウンロード**（2.4GB をストアのパッケージに同梱はしない）。NNUE と同じく初回ダウンロード＋端末内キャッシュにする（nnue_store.dart の作りをそのまま使う）。
3. **モデルは Gemma 4 E2B を第一候補**。E4B は 4.3GB で対象端末が狭まるため、E2B の日本語で足りるかを評価で先に見る。足りなければ Qwen3 0.6B（小さい・日本語が比較的強いとの報告）も候補に入れる。
4. **LLM が無くても遊べる**を維持する。セリフの出口は `lib/core/dialogue/speaker.dart` の `GunshiSpeaker` に一本化し、`TemplateSpeaker`（定型文）と `LlmSpeaker`（`LlmClient` 経由）を差し替える。flutter_gemma は `LlmClient` の実装として後から足すだけでよく、ゲーム側は触らない。
5. **口調は生成後もコードで守る**。`LlmSpeaker` は 生成 → `ToneProfile.rewrite` → 崩れが残れば作り直し（既定2回）→ それでも駄目なら null（呼び出し側がテンプレートに落とす）。90字超も落とす。
6. Notice（Gemma Terms と Prohibited Use Policy）はアプリ内の「このアプリについて」に載せる。

## 組み込み（2026-09-18 実装）

依存は `flutter_gemma 1.8.3` ＋ `flutter_gemma_litertlm 1.6.4`（litertlm 側は 1.6.4 が最新で、pub の解決もこの組み合わせになる）。

| ファイル | 役割 |
|---|---|
| `lib/core/llm/model_catalog.dart` | モデル一覧（URL・容量・種類）。純粋なデータなので、プラグイン無しで読めるしテストもできる |
| `lib/core/llm/gemma_client.dart` | **flutter_gemma に触れる唯一のファイル**。`GunshiModelStore`（導入・削除・状態）と `GemmaLlmClient`（`LlmClient` 実装） |
| `lib/features/llm/model_page.dart` | 「軍師の言葉」画面。モデルを選んで入れる／消す。進捗は 0〜100 |
| `lib/features/game/game_controller.dart` | `gunshiSpeakerProvider` と `_upgradeWithLlm` / `_facts` |

実際に使った API（1.8.3 で確認）:

```dart
await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
await FlutterGemma.installModel(modelType: ..., fileType: ModelFileType.litertlm)
    .fromNetwork(url, foreground: true).withProgress((p) {}).install();   // p は 0..100
final model = await FlutterGemma.getActiveModel(maxTokens: 1024, preferredBackend: PreferredBackend.gpu);
final s = await model.createSession(systemInstruction: ..., maxOutputTokens: 120);
await s.addQueryChunk(Message.text(text: user, isUser: true));
final text = await s.getResponse();
await s.close();
```

- 入っているかどうかは `FlutterGemma.hasActiveModel()`（端末に保存される）。削除は `listInstalledModels()` → `uninstallModel(id)` → `clearActiveInferenceIdentity()`。
- `maxTokens` は 1024 未満にしない（`.litertlm` はテンソル確保に失敗する）。返答の長さは `maxOutputTokens` で絞る。
- セリフ1本ごとに session を作って捨てる。軍師は毎ターン気分が変わるので履歴を持たない方が素直で、端末のメモリも抱え込まない。
- Android: `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` / `POST_NOTIFICATIONS` を AndroidManifest に追加（大きなモデルを画面外でも落とし切るため）。debug APK のビルドは通っている。

### 待たせない出し方

`_say` は **まず定型文をその場で出す**。そのうえで端末内LLMが間に合ったら、同じ発言をそっと言い換える
（`_upgradeWithLlm`）。生成が遅い・失敗した・対局が変わったときは定型文のまま。
LLM に渡す「事実」は `_facts` が作り、学習データ（`data/finetune_gen_edit`）と同じ書き方に揃えてある。

## エミュレータでの確認（2026-09-19）

AVD `ybn_test`（Android 35 google_apis **x86_64**）で debug APK を入れて確認した（`tool/run_emu.cmd`、`tool/shot.cmd`、`tool/tap.cmd`）。

- 起動・対局・軍師のセリフはこれまでどおり。flutter_gemma を足しても壊れていない。
- 「軍師の言葉」画面は開き、モデル未導入なので「いまは定型文で喋っています。」と正しく出る。
  `FlutterGemma.initialize` は x86_64 でも例外にならない。
- ▲7六歩 → AI △1四歩 → 軍師「１四歩。計算どおりでございます。」。改訂した紳士口調のテンプレートが出ている。

**⚠ 端末内LLM自体はエミュレータでは動かせない。** APK の中身を見ると LiteRT-LM のネイティブ
ライブラリ（`libLiteRtLm.so` ほか8個）は **arm64-v8a にしか入っていない**（x86_64 は Flutter の
4ファイルのみ）。ビルドログの `litertlm libs cached to .../android_arm64` もこれと合う。
したがって生成の確認は実機（Galaxy S24）でしかできない。arm64 の AVD は x86 ホスト上で
命令エミュレーションになり、LLM の速さを測る用途には使えない。

### エミュレータで動かせないことの裏取り（2026-09-19）

「エミュレータで見たい」という要望を受けて、抜け道が無いか調べた。**無かった。**

1. **パッケージが arm64 しか作っていない。** `flutter_gemma_litertlm` のネイティブ側
   （`native/litert_lm/build_*.sh`）が作るのは android_arm64 / macOS arm64 / iOS arm64 だけで、
   **android x86_64 のビルド定義が存在しない**。APK の中身とも一致する。
   x86_64 で動かすには LiteRT-LM を Bazel で自前ビルドすることになり、割に合わない。
2. **PC 上で代わりに動かす案も駄目だった。** WSL に入れた `litert-lm run` で
   `.litertlm` を直接喋らせようとしたが、「こんにちは。あなたは誰ですか。」という10トークン程度の
   プロンプトでも **6分以上返らない**（24コアCPU）。速さの判定はもちろん、
   量子化後の日本語を見る用途にも使えない。

**→ 量子化後の品質と速さ（p95 < 6秒）は実機 Galaxy S24 でしか測れない。**
それ以外（アプリが壊れていないこと、モデル未導入でも遊べること、テンプレートの口調）は
エミュレータで確認済み。

## 実機（Galaxy S24 / SM-S721）で測った（2026-09-19）

追加学習した Qwen3 1.7B（`.litertlm`、1.90GB）を adb で置いて、アプリの「試し撃ち」画面から
評価用のお題10件を投げた。

| | 結果 |
|---|---|
| 生成時間 | 中央値 **4.3秒** / **p95 4.7秒** / 最遅 4.7秒 |
| **受け入れ条件 p95 < 6秒** | **満たしている** |
| 口調の崩れ | **0/10件** |
| メモリ（生成後の PSS） | 548MB（RSS 424MB） |

実機でしか分からなかったこと:

- **Qwen3 の思考チャネルの印が本文に混ざる。** `<|channel>thought <channel|> 君、形勢がどうだ？`
  の形で返ってくる（`enableThinking: false` でも出る）。`GemmaLlmClient.stripControlTokens` で
  最後の制御トークンより後ろだけを使うようにした（test/core/llm/gemma_client_test.dart）。
- 口調は完全に出ている。「ふむ、これも計算のうちでございますな」（取り繕い）、
  「うるせえ！ 天気はいいんだけど…」（大混乱）と、気分ごとに正しく切り替わる。
- 日本語の中身はまだ粗い。「いたずこむ不器用さ」「たぎらん」のような語や、
  同じ文を2回繰り返す例がある。**速さと口調は合格、中身が次の課題。**

### 対局の流れでも動いた

試し撃ちは1件ずつ投げるだけなので、**実際の対局**でも確かめた（`tool\dev_both.cmd`）。
モデルを入れて「AIが後手」で ▲7六歩 を指すと、軍師が LLM のセリフで応じ、
エンジンの思考と端末内LLMが同じプロセスで同時に動いても落ちない。
このときアプリのメモリは pss 2.2GB 程度（モデルは mmap）。

**ただしここで、エンジン側の重いバグが実機で出た**（M1/M2 から潜んでいた）。
やねうら王の探索スレッドがスタック不足で落ちる。直し方は docs/dev/nnue.md の
「実機で落ちた話」に書いた（`USE_PTHREADS` を定義する1語）。
LLM とは無関係で、**LLM を入れなくても落ちていた**。

試し方: `tool\run_device.cmd`（APK を入れてモデルを push）→ アプリの「軍師の言葉」→
「端末に置いたファイルから入れる」→「試し撃ち」。

## 対局中に落ちた: 生成は同時に2つ走らせてはいけない（2026-09-19）

実機（S24）で、AI対局を始めて一手指すと SIGSEGV で落ちた。**2回とも同じ所**。

```
Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x3a22656c6f7222d1
  #00 libLiteRtLm.so  litert::lm::Conversation::GetSingleTurnText(json const&, OptionalArgs const&)+12
  #01 libLiteRtLm.so  litert::lm::Conversation::SendMessageAsync(...)
  #02 libLiteRtLm.so  litert_lm_conversation_send_message_stream+196
  #03 [anon:dart-code]
```

壊れたアドレス `0x3a22656c6f7222d1` はバイトを並べ替えると `"role":` という**文字列**。
つまりポインタではなく会話の JSON の中身を読んでいる。解放済みの会話を触っている。

**試し撃ち（`BenchPage`）では落ちない。** あちらは1件ずつ順番に投げるから。
対局中だけ落ちるのは `GameController._upgradeWithLlm` が `unawaited` で投げっぱなしに
するため。開始の一言を生成している最中に指し手の一言が重なると、同じ `InferenceModel`
の上で session が2つ走り、片方が閉じるともう片方が壊れる。

直し方は `SingleFlight`（`lib/core/llm/single_flight.dart`）。走っている間は**待たせずに断る**。
遅れて出てくるセリフに価値は無く、軍師は先に定型文を喋っているので、断られた回は
その定型文のままになるだけで、対局は何も止まらない。断った回数は
`GemmaLlmClient.droppedWhileBusy` に出る。

確かめ方: `tool\dev_play_setup.cmd` → AIが後手 → ▲7六歩 → `tool\dev_alive.cmd`。
直す前は2回とも落ち、直した後は3回とも生き残った。重なりの起きる間合いに依るので
「3回通った」以上のことは言えないが、落ち方と筋は合っている。

なお最初この落ち方を、**端末を触られてアプリが閉じられたのだと読み違えた。**
`pidof` が空で、`adb logcat -b crash` を見て初めて落ちていたと分かった。
画面から消えていたら、まず `tool\dev_alive.cmd` を見ること。

## 次の作業

- [x] 実機で速さ（p95 4.7秒）・口調（崩れ0）・メモリ（548MB）を測った。
- [x] モデル入替の即時反映（`gunshiSpeakerProvider` は差し替えできる `GunshiSpeakerBox` になった）。
- [ ] 日本語の中身を上げる。データを増やす／ベースを大きくする（Gemma 4 E2B）／繰り返しを抑える
      （repetition penalty 相当の設定が LiteRT-LM 側にあるか調べる）。
- [ ] 配布経路を決める（1.90GB。nn.bin と同じ未決事項）。
- [ ] 評価は tools/eval_persona.py（崩れ・テンプレート落ち・速さ）と tools/ab_compare.py（伏せたA/B）で。
