# Anthropic への許可申請（下書き）

送り先: Claude Help Center（https://support.claude.com）右下の「Send us a message」から、アカウント amkn.main@gmail.com でログインして送信。
専用の申請窓口は公開情報で見つからなかったため、サポート経由で担当部署へ回してもらう。返信は記録してこのファイルに追記する。

---

**Subject:** Request for prior authorization: using Claude-written character lines to fine-tune a small on-device model for a shogi game

Hello Anthropic team,

I am an independent app developer (KA-Laboratory, https://ka-laboratory.github.io). I am building "Aori Shogi", a Flutter shogi game for iOS/Android, published under GPLv3. The player talks to an in-game character (a boastful but clumsy "self-proclaimed genius strategist") while playing against a shogi engine.

Under the Usage Policy ("Utilization of inputs and outputs to train an AI model ... without prior authorization from Anthropic"), I would like to ask for authorization for the following narrow use:

- **What:** About 500 short Japanese dialogue lines (1–3 sentences each) for this single fictional character, written with Claude (Claude Opus via Claude Cowork) in my paid account.
- **Training:** A LoRA adapter (QLoRA, 3–5 epochs) on Google's open Gemma 4 E2B/E4B model, used only as the voice of this one character inside the game.
- **Deployment:** Runs on the user's device (flutter_gemma / LiteRT). Output is limited to short in-character lines about the shogi game and light small talk with the player; the game logic, safety filters (NG-word filter, tone rules) and game state are handled by deterministic code.
- **Not:** a general-purpose chatbot or assistant, not offered as a model/API, not distributed separately from the game, not used to train any other model. The adapter and the dataset will not be published as general resources.
- **Attribution:** The app's About screen can note that character lines were written with Claude, if desired.

If this use is not permitted, I will instead create the training data myself or with open-weight models (Apache 2.0), and will only use Claude-written lines as in-prompt examples at inference time. Please let me know whether authorization is granted, and any conditions.

Best regards,
Kentaro Amauchi (KA-Laboratory)
amkn.main@gmail.com

---

## 日本語の要約（控え）
- 目的: 煽り将棋の軍師キャラ1人分の日本語セリフ約500本（Claude で作成）で、Gemma 4 E2B/E4B の LoRA を作り、アプリ内の端末上でそのキャラの声としてだけ使う許可を求める。
- 汎用チャットボットではない・モデルやデータを単体配布しない・他のモデル学習に使わない、と明記。
- 不許可なら、学習データは自作か Apache 2.0 モデルで作り、Claude 作のセリフは推論時の見本だけに使う。
