# デザイン実装計画・作業記録

2026-09-20。ユーザーから「Flutterへの組み込みまで」の指示あり。

Goal: 01〜06の仕様を既存将棋アプリの画面・素材・設定・フィードバックとして動作させる。
Architecture: 既存GameControllerのルールとenumは維持し、表示と端末内設定を分離する。盤と下部領域の高さを割り当て、交渉・終局を常時見える領域で扱う。
Tech Stack: Flutter / Riverpod、端末内ファイル、既存Android/iOS構成。
Spec: [01](01-character.md) / [02](02-expressions.md) / [03](03-visual-system.md) / [04](04-hud.md) / [05](05-screens.md) / [06](06-feedback.md)。

## 作業単位

- [x] 素材: imagegenで同一人物の5表情を生成し、プロジェクトへ保存。プロンプト・元画像・出自を残す。生成物をレイヤー原画やCC0取得済みと称さない。
- [x] 基盤: lib/features/settings/app_settings.dart にAppSettings、settingsProvider、端末内保存を実装。lib/design/app_theme.dart に buildAppTheme(Brightness)。設定画面にテーマ・動き・音量・触覚・表示を接続。
- [x] HUD: design_hud.dart を画像フォールバック、3値＋詳細、固定高の発話、タブ入力へ整理。TauntOutcomeの実差分だけを表示。
- [x] 画面: game_shell.dart を盤固定・下部領域へ変更。初回導入・対局準備・終局・大きな着手操作を接続。model_pageとmemory_sheetは進行中の変更を制限。
- [x] 演出: lib/design/game_feedback.dart で状態差分から1回だけ音と触覚を実行。音源を8個生成、バックグラウンド・ミュート・重複を制御。
- [x] 確認: 既存ルール試験＋小画面/文字1.3/暗色/交渉4種のwidgetテスト、flutter analyze、Androidビルド、利用可能な端末で起動・スクリーンショット。

## 共有インターフェース

AppSettings: themeMode(ThemeMode), reduceMotion(bool), soundVolume(double 0〜1), haptics(bool), showCoordinates(bool), highlightLastMove(bool), confirmResign(bool), introSeen(bool)。settingsProviderはNotifierProviderで、notifier.update(AppSettings Function(AppSettings))を公開。persistence初期化はルートがmainで接続する。

buildAppTheme(Brightness)をMaterialAppのtheme/darkThemeで使用。
GameFeedbackはWidgetでchildを受け取り、gameControllerProviderとsettingsProviderを監視する。
画像は assets/gunshi/face_{Mood.name}.png を初期統合パスとし、供給できた形式を目録に記録する。

## 検証と判断

Ruling: 新規コードはこの既存チェックアウトで作業する。開始時の変更は前ターン作成のdocs/designのみ。
Ruling: 画像生成ではPSDレイヤーの納品を偽装しない。画像形式・サイズが発注仕様と異なる場合は実納品条件を記録する。
Ruling: 作業中にcommit/pushは行わず、確認可能な差分と成果物を残す。

実装結果・仕様との差・検証範囲は [IMPLEMENTATION-REPORT.md](IMPLEMENTATION-REPORT.md) を参照。チェックは統合作業を示し、外注アセット仕様・触感の受け入れ完了を意味しない。
