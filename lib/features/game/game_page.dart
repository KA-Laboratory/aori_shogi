import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shogi/shogi.dart';
import '../about/about_page.dart';
import 'board_view.dart';
import 'engine_panel.dart';
import 'gunshi_panel.dart';
import 'memory_sheet.dart';
import 'review_page.dart';
import 'game_controller.dart';

class GamePage extends ConsumerWidget {
  const GamePage({super.key});

  Future<void> _onCandidates(BuildContext context, WidgetRef ref, List<Move> cands) async {
    final controller = ref.read(gameControllerProvider.notifier);
    if (cands.length == 1) {
      controller.play(cands.first);
      return;
    }
    final promote = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('成りますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('不成')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('成る')),
        ],
      ),
    );
    if (promote == null) return;
    controller.play(cands.firstWhere((m) => m.promote == promote));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    final pos = s.position;
    final result = s.game.result;
    final status = result != null
        ? result.label
        : '${s.game.moves.length + 1}手目 ${pos.turn.mark}${pos.turn.label}の番'
              '${pos.inCheck(pos.turn) ? '（王手）' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('煽り将棋'),
        actions: [
          IconButton(
            tooltip: 'このアプリについて',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutAppPage())),
          ),
          IconButton(
            tooltip: '感想戦',
            icon: const Icon(Icons.history_edu_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReviewPage())),
          ),
          IconButton(
            tooltip: '軍師が覚えていること',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: () => MemorySheet.show(context),
          ),
          IconButton(
            tooltip: '棋譜(KIF)をコピー',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: toKif(s.game, startedAt: DateTime.now())));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('KIFをコピーしました')));
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ListView(
                children: [
                  const GunshiPanel(),
                  const SizedBox(height: 8),
                  KomadaiView(side: Side.white, label: s.mode.isAi(Side.white) ? '軍師' : null),
                  const SizedBox(height: 6),
                  BoardView(onCandidates: (c) => _onCandidates(context, ref, c)),
                  const SizedBox(height: 6),
                  KomadaiView(side: Side.black, label: s.mode.isAi(Side.black) ? '軍師' : null),
                  const SizedBox(height: 8),
                  const ChatPanel(),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    key: const ValueKey('status'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: s.game.moves.isEmpty && result == null ? null : controller.undo,
                        icon: const Icon(Icons.undo),
                        label: const Text('待った'),
                      ),
                      OutlinedButton.icon(
                        onPressed: result == null ? controller.resign : null,
                        icon: const Icon(Icons.flag),
                        label: const Text('投了'),
                      ),
                      FilledButton.icon(
                        onPressed: controller.newGame,
                        icon: const Icon(Icons.refresh),
                        label: const Text('新規対局'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const EnginePanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
