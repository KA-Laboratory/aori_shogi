import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mind/mind_state.dart';
import '../../core/mind/taunts.dart';
import 'game_controller.dart';

String moodFace(Mood m) => switch (m) {
      Mood.composed => '(￣ー￣)',
      Mood.smug => '(≧▽≦)',
      Mood.rattled => '(；´Д｀)',
      Mood.meltdown => '(´；ω；｀)',
      Mood.coverUp => '(・∀・;)',
    };

Color moodColor(Mood m) => switch (m) {
      Mood.composed => const Color(0xFF5D7A8C),
      Mood.smug => const Color(0xFFB8860B),
      Mood.rattled => const Color(0xFFE67E22),
      Mood.meltdown => const Color(0xFFC0392B),
      Mood.coverUp => const Color(0xFF8E44AD),
    };

/// 軍師の表情・吹き出し・感情メーター。
class GunshiPanel extends ConsumerWidget {
  const GunshiPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final mind = s.mind;
    if (mind == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final mood = mind.mood;
    final taunt = s.lastTaunt;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: moodColor(mood).withValues(alpha: 0.15),
                border: Border.all(color: moodColor(mood), width: 2),
              ),
              child: Text(moodFace(mood), style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 4),
            Text('軍師・${mood.label}',
                key: const ValueKey('mood'),
                style: theme.textTheme.labelSmall?.copyWith(color: moodColor(mood), fontWeight: FontWeight.bold)),
            Text('形勢: ${mind.stance.label}', style: theme.textTheme.labelSmall),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                key: const ValueKey('speech'),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(s.thinking ? '（ふむ……）' : (s.speech ?? ''), style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 6),
              _Meter(label: '冷静', value: mind.composure, color: const Color(0xFF2E86C1), delta: taunt?.composureDelta),
              _Meter(label: '慢心', value: mind.hubris, color: const Color(0xFFB8860B)),
              _Meter(label: '焦り', value: mind.panic, color: const Color(0xFFC0392B), delta: taunt?.panicDelta),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value, required this.color, this.delta});

  final String label;
  final double value;
  final Color color;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(children: [
        SizedBox(width: 30, child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v.clamp(0, 1),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            (delta == null || delta!.abs() < 0.005) ? '' : '${delta! > 0 ? '+' : ''}${(delta! * 100).round()}',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ]),
    );
  }
}

/// 煽りスタンプ列。
class TauntBar extends ConsumerWidget {
  const TauntBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    if (s.mind == null) return const SizedBox.shrink();
    final ctl = ref.read(gameControllerProvider.notifier);
    final myTurn = !s.thinking && !s.game.isOver && !s.mode.isAi(s.position.turn);
    final hint = s.observing
        ? '軍師が局面を確認中…'
        : s.tauntAvailable
            ? '煽る（1手に1回）'
            : (myTurn && s.lastTaunt != null ? 'この手番はもう煽りました' : 'あなたの手番に煽れます');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(hint, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in tauntStamps)
          ActionChip(
            key: ValueKey('taunt-${t.id}'),
            label: Text(t.text),
            onPressed: s.tauntAvailable ? () => ctl.sendTaunt(t) : null,
          ),
      ]),
    ]);
  }
}
