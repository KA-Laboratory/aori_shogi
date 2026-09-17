import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_controller.dart';

/// 感想戦。どの手で形勢が動いたかを並べ、悪手には軍師のひとことを添える。
class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final ctl = ref.read(gameControllerProvider.notifier);
    final entries = s.review;
    final blunders = entries.where((e) => e.isBlunder).toList();
    final worst = [...entries]..sort((a, b) => (b.lossCp ?? 0).compareTo(a.lossCp ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('感想戦')),
      body: entries.isEmpty
          ? const Center(child: Text('まだ振り返る手がない。'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.game.result?.label ?? '対局中', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${entries.length}手を記録。大きく形勢を損ねた手は${blunders.length}手。'
                  '${worst.isNotEmpty && (worst.first.lossCp ?? 0) > 0 ? '一番の痛手は${worst.first.ply + 1}手目 ${worst.first.kif}（${worst.first.lossCp}点損）。' : ''}',
                ),
                const Divider(height: 24),
                for (final e in entries) _MoveTile(entry: e, comment: ctl.reviewComment(e)),
              ],
            ),
    );
  }
}

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.entry, required this.comment});

  final ReviewEntry entry;
  final String comment;

  @override
  Widget build(BuildContext context) {
    final loss = entry.lossCp;
    final color = entry.isBlunder ? Theme.of(context).colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 36, child: Text('${entry.ply + 1}')),
              Expanded(
                child: Text(
                  '${entry.side.mark}${entry.kif}${entry.byGunshi ? '（軍師）' : ''}',
                  style: TextStyle(color: color, fontWeight: entry.isBlunder ? FontWeight.bold : null),
                ),
              ),
              Text(loss == null ? '-' : (loss == 0 ? '最善' : '$loss点損'), style: TextStyle(color: color)),
            ],
          ),
          if (entry.bestKif != null && entry.isBlunder)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text('最善は ${entry.bestKif}', style: Theme.of(context).textTheme.bodySmall),
            ),
          if (comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 2),
              child: Text('軍師「$comment」', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
