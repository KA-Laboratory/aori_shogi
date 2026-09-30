import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({
    super.key,
    this.onPreparation,
    this.onModels,
    this.onMemory,
    this.onAbout,
    this.onReview,
    this.onCopyKif,
    this.onDebug,
    this.gameInProgress = false,
  });
  final VoidCallback? onPreparation,
      onModels,
      onMemory,
      onAbout,
      onReview,
      onCopyKif,
      onDebug;
  final bool gameInProgress;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    void update(AppSettings Function(AppSettings) change) {
      final controller = ref.read(settingsProvider.notifier);
      controller.update(change);
      if (controller.saveError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('設定を保存できませんでした。この起動中は変更を適用します。')),
        );
      }
    }

    Widget section(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget link(String title, String subtitle, VoidCallback? callback) =>
        ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: callback == null ? null : const Icon(Icons.chevron_right),
          onTap: callback,
        );
    Widget toggle(
      String label,
      String description,
      bool value,
      void Function(bool) change,
    ) => SwitchListTile(
      title: Text(label),
      subtitle: Text(description),
      value: value,
      onChanged: change,
      contentPadding: EdgeInsets.zero,
    );
    final themeLabel = switch (settings.themeMode) {
      ThemeMode.system => '端末',
      ThemeMode.light => 'ライト',
      ThemeMode.dark => 'ダーク',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (gameInProgress) const Text('設定を開いている間も対局の時計は進みます。'),
                section('対局'),
                link('対局準備', '相手・強さ・持ち時間を選ぶ', onPreparation),
                toggle(
                  '投了確認',
                  '投了する前に確認します',
                  settings.confirmResign,
                  (v) => update((s) => s.copyWith(confirmResign: v)),
                ),
                const ListTile(
                  title: Text('成り確認'),
                  subtitle: Text('任意の成りは必ず確認します'),
                ),
                section('軍師'),
                link(
                  '軍師の言葉・モデル管理',
                  gameInProgress ? '対局中は閲覧のみ。未導入でも定型文で遊べます' : '未導入でも定型文で遊べます',
                  onModels,
                ),
                link(
                  '軍師の記憶',
                  gameInProgress ? '対局中は閲覧のみ' : '端末内の記憶を閲覧・消去',
                  onMemory,
                ),
                const ListTile(
                  title: Text('煽りとセリフ'),
                  subtitle: Text('感情を動かせるのは1手3回まで。セリフの全文は会話で読めます。'),
                ),
                section('表示'),
                link('テーマ', themeLabel, () async {
                  final result = await showModalBottomSheet<ThemeMode>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'テーマ',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            for (final mode in ThemeMode.values)
                              ListTile(
                                minTileHeight: 48,
                                leading: Icon(
                                  settings.themeMode == mode
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                ),
                                title: Text(switch (mode) {
                                  ThemeMode.system => '端末',
                                  ThemeMode.light => 'ライト',
                                  ThemeMode.dark => 'ダーク',
                                }),
                                onTap: () => Navigator.pop(context, mode),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                  if (result != null) {
                    update((s) => s.copyWith(themeMode: result));
                  }
                }),
                toggle(
                  '座標',
                  '小さい盤では盤内に重ねず、着手操作で表示します',
                  settings.showCoordinates,
                  (v) => update((s) => s.copyWith(showCoordinates: v)),
                ),
                toggle(
                  '最終手',
                  '最後に着手したマスを角括弧で示します',
                  settings.highlightLastMove,
                  (v) => update((s) => s.copyWith(highlightLastMove: v)),
                ),
                toggle(
                  '動きを減らす',
                  settings.reduceMotion ? '減らす' : 'OSに従う（端末の動き低減を常に優先）',
                  settings.reduceMotion,
                  (v) => update((s) => s.copyWith(reduceMotion: v)),
                ),
                const ListTile(
                  title: Text('文字サイズ'),
                  subtitle: Text('端末の文字サイズ設定に従います'),
                ),
                section('音と触覚'),
                Text(
                  '効果音 ${(settings.soundVolume * 100).round()}%',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: '効果音を下げる',
                      onPressed: () => update(
                        (s) => s.copyWith(
                          soundVolume: ((s.soundVolume * 10).round() - 1) / 10,
                        ),
                      ),
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Slider(
                        label: '${(settings.soundVolume * 100).round()}%',
                        value: settings.soundVolume,
                        divisions: 10,
                        onChanged: (v) =>
                            update((s) => s.copyWith(soundVolume: v)),
                      ),
                    ),
                    IconButton(
                      tooltip: '効果音を上げる',
                      onPressed: () => update(
                        (s) => s.copyWith(
                          soundVolume: ((s.soundVolume * 10).round() + 1) / 10,
                        ),
                      ),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                toggle(
                  '触覚',
                  '対応する端末で振動します。音量とは独立しています',
                  settings.haptics,
                  (v) => update((s) => s.copyWith(haptics: v)),
                ),
                const ListTile(
                  title: Text('BGM・軍師ボイス'),
                  subtitle: Text('BGMと軍師の音声はありません'),
                ),
                section('データ'),
                link('現在局のKIFをコピー', '対局はそのまま続きます', onCopyKif),
                link('現在局の感想戦', '対局履歴の自動保存はありません', onReview),
                section('その他'),
                link('アプリ情報', 'ライセンス・プライバシー・バージョン・サポート情報', onAbout),
                if (kDebugMode && onDebug != null) ...[
                  section('開発用'),
                  link('ベンチマーク', '開発ビルドのみ', onDebug),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
