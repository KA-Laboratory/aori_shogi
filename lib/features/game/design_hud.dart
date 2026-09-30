import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mind/mind_state.dart';
import '../../core/mind/negotiation.dart';
import '../../core/mind/taunts.dart';
import '../settings/app_settings.dart';
import 'game_controller.dart';

String moodFace(Mood m) =>
    ['(￣ー￣)', '(≧▽≦)', '(；´Д｀)', '(´；ω；｀)', '(・∀・;)'][m.index];
Color moodColor(Mood m, [bool dark = false]) => Color(
  (dark
      ? const [0xFFA8CADE, 0xFFF1CF70, 0xFFFFB888, 0xFFFFB4AB, 0xFFE2B9F4]
      : const [
          0xFF395669,
          0xFF765400,
          0xFF914412,
          0xFFA52D26,
          0xFF71358D,
        ])[m.index],
);

class GunshiFace extends ConsumerStatefulWidget {
  const GunshiFace({super.key, required this.mood});
  final Mood mood;
  @override
  ConsumerState<GunshiFace> createState() => _GunshiFaceState();
}

class _GunshiFaceState extends ConsumerState<GunshiFace>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -3), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -3, end: 3), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 3, end: -2), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -2, end: 0), weight: 1),
  ]).animate(_shake);
  final _elapsed = Stopwatch()..start();
  int? _lastShake;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _shake.reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shake.dispose();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        ref.watch(settingsProvider).reduceMotion;
    ref.listen(gameControllerProvider.select((state) => state.lastTaunt), (
      previous,
      next,
    ) {
      if (next == null ||
          identical(previous, next) ||
          next.composureDelta > -.15 ||
          next.truth <= 0 ||
          next.kind == TauntKind.praise ||
          reduced ||
          !_foreground) {
        return;
      }
      final now = _elapsed.elapsedMilliseconds;
      if (_lastShake != null && now - _lastShake! < 400) return;
      _lastShake = now;
      _shake.forward(from: 0);
    });
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) => Transform.translate(
        offset: Offset(reduced || !_foreground ? 0 : _offset.value, 0),
        child: child,
      ),
      child: Semantics(
        label: '軍師、${widget.mood.label}',
        image: true,
        child: ExcludeSemantics(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFF1D5),
              border: Border.all(
                color: moodColor(
                  widget.mood,
                  Theme.of(context).brightness == Brightness.dark,
                ),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduced ? 0 : 180),
                child: Image.asset(
                  'assets/gunshi/face_${widget.mood.name}.png',
                  key: ValueKey(widget.mood),
                  width: 62,
                  height: 62,
                  fit: BoxFit.contain,
                  cacheWidth: 216,
                  errorBuilder: (_, _, _) => Center(
                    child: Text(
                      moodFace(widget.mood),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF24211E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String tauntResultLabel(TauntOutcome out) {
  if (out.kind == TauntKind.praise) return '褒めた：冷静↑・慢心↑';
  if (out.kind == TauntKind.mock &&
      out.before.hubris > TauntTable.mockBackfireHubris) {
    return '余裕を取り戻した';
  }
  if (out.truth <= 0) return '効かなかった';
  return out.composureDelta < 0 ? '動揺させた' : '変化なし';
}

String _delta(double d) => '${d >= .005 ? '+' : ''}${(d * 100).round()}';

String tauntDeltaText(TauntOutcome out) => out.kind == TauntKind.praise
    ? '冷静${_delta(out.composureDelta)}　慢心${_delta(out.after.hubris - out.before.hubris)}'
    : '冷静${_delta(out.composureDelta)}　焦り${_delta(out.panicDelta)}';

class GunshiPanel extends ConsumerStatefulWidget {
  const GunshiPanel({super.key, this.compact = false, this.onSpeech});
  final bool compact;
  final VoidCallback? onSpeech;
  @override
  ConsumerState<GunshiPanel> createState() => _GunshiPanelState();
}

class _GunshiPanelState extends ConsumerState<GunshiPanel> {
  TauntOutcome? _effect;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameControllerProvider.select((s) => s.lastTaunt), (
      previous,
      next,
    ) {
      if (next == null || identical(previous, next)) return;
      _timer?.cancel();
      setState(() => _effect = next);
      _timer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _effect = null);
      });
    });
    final s = ref.watch(gameControllerProvider);
    final m = s.mind;
    if (m == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final large = MediaQuery.textScalerOf(context).scale(12) > 12;
    final out = _effect;
    final speech = out == null
        ? (s.speech ?? 'ふむ、君のお手並みを拝見いたしましょう。')
        : '${tauntResultLabel(out)} ${tauntDeltaText(out)}';
    Widget values({bool bars = false}) => Row(
      children: [
        for (final e in [
          ('冷静', m.composure, Mood.composed),
          ('慢心', m.hubris, Mood.smug),
          ('焦り', m.panic, Mood.meltdown),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.$1} ${(e.$2 * 100).round()}',
                    maxLines: 1,
                    style: text.labelSmall,
                  ),
                  if (bars) ...[
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: e.$2, end: e.$2),
                      duration: Duration(
                        milliseconds:
                            MediaQuery.disableAnimationsOf(context) ||
                                ref.watch(settingsProvider).reduceMotion
                            ? 0
                            : 240,
                      ),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) =>
                          LinearProgressIndicator(
                            value: value,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            color: moodColor(
                              e.$3,
                              Theme.of(context).brightness == Brightness.dark,
                            ),
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
    final header = Row(
      children: [
        Text(
          m.mood.label,
          key: const ValueKey('mood'),
          style: text.labelMedium?.copyWith(
            color: moodColor(
              m.mood,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '軍師視点：${m.stance.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall,
            ),
          ),
        ],
      ],
    );
    return Column(
      children: [
        SizedBox(
          height: widget.compact ? (large ? 80 : 72) : 152,
          child: widget.compact
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GunshiFace(mood: m.mood),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: widget.onSpeech,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 24, child: header),
                            SizedBox(height: large ? 24 : 20, child: values()),
                            Text(
                              speech,
                              key: const ValueKey('speech'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 72,
                        child: Row(
                          children: [
                            GunshiFace(mood: m.mood),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  header,
                                  const SizedBox(height: 8),
                                  values(bars: true),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: InkWell(
                          onTap: widget.onSpeech,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  speech,
                                  key: const ValueKey('speech'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium,
                                ),
                              ),
                              IconButton(
                                onPressed: widget.onSpeech,
                                tooltip: 'セリフ全文',
                                icon: const Icon(Icons.chat_bubble_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (s.dealTurns > 0)
          SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '約束：あと${s.dealTurns}手　口軽 ${(m.looseLips * 100).round()}\n漏れた読みが真実とは限りません',
                maxLines: 2,
                style: text.labelSmall,
              ),
            ),
          ),
      ],
    );
  }
}

class EmotionDetails extends ConsumerWidget {
  const EmotionDetails({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final m = s.mind;
    if (m == null) return const Center(child: Text('この対局には軍師がいません'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          '軍師視点：${m.stance.label}　${m.mood.label}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final e in [
          ('冷静', m.composure, '下がると読みが乱れる'),
          ('慢心', m.hubris, '上がると隙が生まれる'),
          ('焦り', m.panic, '上がると読みが乱れる'),
          ('口軽', m.looseLips, '読みを漏らしやすい'),
          ('警戒', m.suspicion, '漏らした読みも信用しすぎない'),
        ])
          Semantics(
            label: '${e.$1}、${(e.$2 * 100).round()}、100中',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.$1} ${(e.$2 * 100).round()}　${e.$3}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: e.$2,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ),
        if (s.lastTaunt case final out?)
          Text('${tauntResultLabel(out)}\n${tauntDeltaText(out)}'),
      ],
    );
  }
}

class OfferRow extends ConsumerWidget {
  const OfferRow({super.key, required this.keyName});
  final String keyName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(
      gameControllerProvider.select((s) => s.pendingOffer),
    );
    if (offer == null) return const SizedBox.shrink();
    final label = switch (offer) {
      OfferKind.offerPlayerUndo => '待ったを受ける',
      OfferKind.requestRedo => '置き直しを認める',
      OfferKind.proposeDeal => '取引を受ける',
      OfferKind.proposeDraw => '引き分けを受ける',
    };
    return Padding(
      key: ValueKey(keyName),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Text('${offer.text}\n答えるまで指せません'),
            ),
          ),
          SizedBox(
            height: 48,
            child: FilledButton.tonal(
              onPressed: () =>
                  ref.read(gameControllerProvider.notifier).respondOffer(true),
              child: Text(label),
            ),
          ),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () =>
                  ref.read(gameControllerProvider.notifier).respondOffer(false),
              child: const Text('断る'),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({
    super.key,
    this.logOnly = false,
    this.keyboardVisible = false,
  });
  final bool logOnly, keyboardVisible;
  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _input = TextEditingController();
  final _composerKey = GlobalKey();
  int _tab = 0;
  static const _samples = [
    '次どこ指すつもり？',
    '本当は苦しいんでしょ？',
    'さすが！天才！最強！',
    '待った！今のなしで',
    'ヒント教えてよ',
    'もう投了したら？',
  ];
  static const _labels = ['悪手を指摘', '浮き駒を指摘', '玉を脅かす', '天才をからかう', '褒めて隙を作る'];
  static const _hints = [
    '冷静↓ 焦り↑（局面と耐性で変化）',
    '冷静↓ 焦り↑（局面と耐性で変化）',
    '焦りを強く揺さぶる',
    '慢心が高いと逆効果',
    '冷静も回復するが、慢心と口軽が上がる',
  ];
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send({TauntStamp? stamp}) async {
    final t = stamp?.text ?? _input.text.trim();
    if (t.isEmpty) return;
    if (ref.read(gameControllerProvider).dealTurns > 0 &&
        stamp?.kind != TauntKind.praise) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('取引の約束があります'),
          content: const Text('煽りと判断されると約束を破り、軍師が余裕を取り戻します。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('送る'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (stamp != null) {
      ref.read(gameControllerProvider.notifier).sendTaunt(stamp);
    } else {
      ref.read(gameControllerProvider.notifier).sendChat(t);
      _input.clear();
    }
    if (mounted) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(gameControllerProvider);
    final theme = Theme.of(context);
    final enabled =
        !s.thinking &&
        !s.game.isOver &&
        !s.mode.isAi(s.position.turn) &&
        s.pendingOffer == null;
    final input = Row(
      key: _composerKey,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            enabled: enabled,
            maxLength: 100,
            maxLines: 1,
            onChanged: (_) => setState(() {}),
            key: const ValueKey('chat-input'),
            decoration: const InputDecoration(
              hintText: '軍師に話しかける',
              counterText: '',
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: '送信',
          onPressed: enabled && _input.text.trim().isNotEmpty ? _send : null,
          icon: const Icon(Icons.send),
        ),
      ],
    );
    if (widget.logOnly) {
      if (s.chat.isEmpty) return const Center(child: Text('会話はここに残ります'));
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: s.chat.length,
        itemBuilder: (_, i) {
          final e = s.chat[i];
          final player = e.role == ChatRole.player;
          final dark = theme.brightness == Brightness.dark;
          return Align(
            alignment: player ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: e.role == ChatRole.system
                    ? theme.colorScheme.surfaceContainer
                    : Color(
                        player
                            ? (dark ? 0xFF22384A : 0xFFE3F0FD)
                            : (dark ? 0xFF3A3024 : 0xFFFFF4E0),
                      ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${e.role == ChatRole.system
                    ? 'お知らせ'
                    : player
                    ? '君'
                    : '軍師'}\n${e.text}${e.slip ? '\n（口が滑った…？）' : ''}',
              ),
            ),
          );
        },
      );
    }
    if (widget.keyboardVisible) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: input,
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _tab = i),
                    style: TextButton.styleFrom(
                      backgroundColor: _tab == i
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: Text(['定型', '例文', '入力'][i]),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            0 => ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (s.lastTaunt case final outcome?)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${tauntResultLabel(outcome)}\n${tauntDeltaText(outcome)}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                Text(
                  s.dealTurns > 0
                      ? '約束：あと${s.dealTurns}手。褒めることはできます'
                      : s.observing
                      ? '局面を確認中。今は感情を動かせません'
                      : s.tauntAvailable
                      ? '感情を動かせるのは1手3回まで'
                      : 'この手番は感情を動かせません',
                  style: theme.textTheme.bodySmall,
                ),
                for (var i = 0; i < tauntStamps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Tooltip(
                      message: _hints[i],
                      child: OutlinedButton(
                        key: ValueKey('taunt-${tauntStamps[i].id}'),
                        onPressed: enabled
                            ? () => _send(stamp: tauntStamps[i])
                            : null,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(_labels[i]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            1 => ListView(
              children: [
                for (final sample in _samples)
                  ListTile(
                    title: Text(sample),
                    onTap: () => setState(() {
                      _input.text = sample;
                      _tab = 2;
                    }),
                  ),
              ],
            ),
            _ => Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(
                    enabled ? '100文字まで。返答を待たずに駒を動かせます' : '自分の手番で話せます',
                    style: theme.textTheme.bodySmall,
                  ),
                  input,
                ],
              ),
            ),
          },
        ),
      ],
    );
  }
}
