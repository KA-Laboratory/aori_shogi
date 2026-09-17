import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_controller.dart';
import 'game_controller.dart';

/// 思考エンジンの状態表示と、対局相手（人間 / AI）の切り替え。
class EnginePanel extends ConsumerWidget {
  const EnginePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(engineControllerProvider);
    final game = ref.watch(gameControllerProvider);
    final engineCtl = ref.read(engineControllerProvider.notifier);
    final gameCtl = ref.read(gameControllerProvider.notifier);
    final theme = Theme.of(context);

    final Widget statusLine = switch (status) {
      EngineChecking() => const Text('エンジンを確認中…'),
      EngineUnsupported() => const Text('この環境ではAIエンジンを使えません（人間同士で対局）'),
      EngineNeedsDownload(:final error) => Row(
        children: [
          Expanded(
            child: Text(
              error == null ? 'AI対局には評価関数（約29MB）のダウンロードが必要です' : 'ダウンロード失敗: $error',
              style: error == null ? null : TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(onPressed: engineCtl.download, child: const Text('ダウンロード')),
          IconButton(tooltip: '再確認', onPressed: engineCtl.recheck, icon: const Icon(Icons.refresh)),
        ],
      ),
      EngineDownloading(:final progress) => Row(
        children: [
          const Text('ダウンロード中 '),
          Expanded(child: LinearProgressIndicator(value: progress)),
          Text(' ${(progress * 100).toStringAsFixed(0)}%'),
        ],
      ),
      EngineStarting() => const Text('エンジン起動中…'),
      EngineReady() => const Text('エンジン準備完了（やねうら王 + Háo）'),
      EngineFailed(:final message) => Text('エンジン起動失敗: $message', style: TextStyle(color: theme.colorScheme.error)),
    };

    final ready = status is EngineReady;
    final search = game.lastSearch;
    String? searchText;
    if (search != null && search.candidates.isNotEmpty) {
      final c = search.candidates.first;
      final score = c.mateIn != null ? '詰み${c.mateIn}' : '${c.scoreCp}';
      searchText = 'AI読み: ${c.usi}  評価値 $score  深さ ${search.depth ?? '-'}';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(style: theme.textTheme.bodySmall, child: statusLine),
            const SizedBox(height: 6),
            SegmentedButton<OpponentMode>(
              key: const ValueKey('opponent'),
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: OpponentMode.human, label: Text('人間同士')),
                const ButtonSegment(value: OpponentMode.aiWhite, label: Text('AIが後手')),
                const ButtonSegment(value: OpponentMode.aiBlack, label: Text('AIが先手')),
                if (kDebugMode) const ButtonSegment(value: OpponentMode.aiBoth, label: Text('AI同士')),
              ],
              selected: {game.mode},
              onSelectionChanged: (s) {
                final mode = s.first;
                if (mode != OpponentMode.human && !ready) return;
                gameCtl.setMode(mode);
              },
            ),
            if (game.thinking)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('AI思考中…'),
                  ],
                ),
              )
            else if (searchText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(searchText, style: theme.textTheme.bodySmall),
              ),
            if (game.engineError != null) Text(game.engineError!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
