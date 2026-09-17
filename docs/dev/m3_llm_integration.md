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

## 次の作業

- [ ] `packages/`（または lib/core/llm）に flutter_gemma を使う `LlmClient` 実装を足す。まずはエミュレータで Qwen3 0.6B を動かして口を確認する。
- [ ] モデルのダウンロードUI（進捗・Wi-Fi のみ・あとで）と保存先。NNUE の `nnue_store.dart` と共通化できるか見る。
- [ ] 実機 Galaxy S24 で E2B の速さ（受け入れ条件 p95 < 6秒）とメモリを測る。
- [ ] 評価は tools/eval_persona.py（崩れ・テンプレート落ち・速さ）と tools/ab_compare.py（伏せたA/B）で。
