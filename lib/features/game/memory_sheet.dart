import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogue/player_memory.dart';
import 'game_controller.dart';

/// 軍師が相手について覚えていることの一覧。端末内だけに残り、ここから消せる。
class MemorySheet extends ConsumerStatefulWidget {
  const MemorySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const MemorySheet(),
  );

  @override
  ConsumerState<MemorySheet> createState() => _MemorySheetState();
}

class _MemorySheetState extends ConsumerState<MemorySheet> {
  bool _active(GameViewState state) =>
      !state.game.isOver &&
      (state.game.moves.isNotEmpty ||
          state.mode != OpponentMode.human ||
          state.thinking);

  Future<void> _forget({MemoryFact? fact}) async {
    if (_active(ref.read(gameControllerProvider))) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fact == null ? '記憶を全部忘れさせますか？' : 'この記憶を忘れさせますか？'),
        content: SingleChildScrollView(
          child: Text(fact?.sentence ?? '軍師がこの端末で覚えたことをすべて削除します。元には戻せません。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取り消し'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(fact == null ? '記憶をすべて削除' : 'この記憶を削除'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        _active(ref.read(gameControllerProvider))) {
      return;
    }
    final memory = ref.read(playerMemoryProvider);
    setState(() {
      if (fact == null) {
        memory.clear();
      } else {
        memory.delete(fact.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _active(ref.watch(gameControllerProvider));
    final memory = ref.read(playerMemoryProvider);
    final facts = [...memory.facts.reversed];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ListView(
            children: [
              const Text(
                '軍師が覚えていること',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (facts.isNotEmpty)
                TextButton(
                  onPressed: active ? null : () => _forget(),
                  child: const Text('全部忘れさせる'),
                ),
              const SizedBox(height: 4),
              Text(
                'この端末の中だけに残ります。消したいものは右のごみ箱で消せます。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (active)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('対局中は閲覧のみです。持ち時間は進み続けます。記憶の削除は終局後にできます。'),
                ),
              const SizedBox(height: 8),
              if (facts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('まだ何も覚えていない。'),
                )
              else
                for (final fact in facts) ...[
                  _FactTile(
                    fact: fact,
                    onDelete: active ? null : () => _forget(fact: fact),
                  ),
                  const Divider(height: 1),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact, required this.onDelete});

  final MemoryFact fact;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(fact.sentence),
    subtitle: Text('${fact.firstSeen} に聞いた・${fact.mentions}回'),
    trailing: IconButton(
      tooltip: '忘れさせる',
      icon: const Icon(Icons.delete_outline),
      onPressed: onDelete,
    ),
  );
}
