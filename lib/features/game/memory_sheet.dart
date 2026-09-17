import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogue/player_memory.dart';
import 'game_controller.dart';

/// 軍師が相手について覚えていることの一覧。端末内だけに残り、ここから消せる。
class MemorySheet extends ConsumerStatefulWidget {
  const MemorySheet({super.key});

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const MemorySheet());

  @override
  ConsumerState<MemorySheet> createState() => _MemorySheetState();
}

class _MemorySheetState extends ConsumerState<MemorySheet> {
  @override
  Widget build(BuildContext context) {
    final memory = ref.read(playerMemoryProvider);
    final facts = [...memory.facts.reversed];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('軍師が覚えていること', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (facts.isNotEmpty) TextButton(onPressed: () => setState(memory.clear), child: const Text('全部忘れさせる')),
              ],
            ),
            const SizedBox(height: 4),
            const Text('この端末の中だけに残ります。消したいものは右のごみ箱で消せます。', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            if (facts.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('まだ何も覚えていない。'))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: facts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) =>
                      _FactTile(fact: facts[i], onDelete: () => setState(() => memory.delete(facts[i].id))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact, required this.onDelete});

  final MemoryFact fact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(fact.sentence),
    subtitle: Text('${fact.firstSeen} に聞いた・${fact.mentions}回'),
    trailing: IconButton(tooltip: '忘れさせる', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
  );
}
