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

## 次の作業

- [ ] 実機 Galaxy S24 で Gemma 3 1B → Gemma 4 E2B の順に、速さ（受け入れ条件 p95 < 6秒。`GemmaLlmClient.timings` で測れる）とメモリを見る。
- [ ] 実機で日本語の口調が保てるか（tools/eval_persona.py の観点で、テンプレート落ちの割合を見る）。
- [ ] モデル入替の即時反映（いまはアプリを開き直すと反映。`gunshiSpeakerProvider` を作り直す形にする）。
- [ ] 評価は tools/eval_persona.py（崩れ・テンプレート落ち・速さ）と tools/ab_compare.py（伏せたA/B）で。
