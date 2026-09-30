import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mind/move_policy.dart';
import '../../core/shogi/shogi.dart';
import 'engine_controller.dart';
import 'game_controller.dart';

class GameSetupPage extends ConsumerStatefulWidget {
  const GameSetupPage({super.key, this.repeat = false});
  final bool repeat;
  @override
  ConsumerState<GameSetupPage> createState() => _GameSetupPageState();
}

class _GameSetupPageState extends ConsumerState<GameSetupPage> {
  late OpponentMode _mode;
  late SkillLevel _level;
  late TimeControl _time;
  bool _starting = false;
  @override
  void initState() {
    super.initState();
    final game = ref.read(gameControllerProvider);
    _mode = widget.repeat ? game.mode : OpponentMode.human;
    _level = game.level;
    _time = ref.read(gameControllerProvider.notifier).timeControl;
  }

  String modeLabel(OpponentMode mode) => switch (mode) {
    OpponentMode.human => '人間同士',
    OpponentMode.aiWhite => '軍師が後手（自分は先手）',
    OpponentMode.aiBlack => '軍師が先手（自分は後手）',
    OpponentMode.aiBoth => 'AI同士（開発用）',
  };
  Future<void> _choose<T>(
    String title,
    List<T> options,
    T current,
    String Function(T) label,
    void Function(T) change,
  ) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              for (final option in options)
                ListTile(
                  minTileHeight: 48,
                  leading: Icon(
                    option == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(label(option)),
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => change(selected));
  }

  Future<void> _start() async {
    if (_starting || ref.read(gameControllerProvider).thinking) return;
    setState(() => _starting = true);
    final game = ref.read(gameControllerProvider).game;
    if (game.moves.isNotEmpty || game.result != null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('新しい対局を始めますか？'),
          content: const Text('現在局の棋譜は新規対局で置き換わります。必要ならKIFをコピーしてください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('戻る'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: toKif(game, startedAt: DateTime.now())),
                );
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('KIFをコピーしました')));
                }
              },
              child: const Text('KIFをコピー'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(widget.repeat ? '再戦' : '新しい対局を開始'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (discard != true) {
        setState(() => _starting = false);
        return;
      }
    }
    if (!mounted) return;
    if (ref.read(gameControllerProvider).thinking ||
        (_mode != OpponentMode.human &&
            ref.read(engineControllerProvider) is! EngineReady)) {
      setState(() => _starting = false);
      return;
    }
    final controller = ref.read(gameControllerProvider.notifier);
    controller.setMode(OpponentMode.human);
    controller.setLevel(_level);
    controller.setTimeControl(_time);
    controller.newGame();
    controller.setMode(_mode);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineControllerProvider);
    final game = ref.watch(gameControllerProvider);
    final ready = _mode == OpponentMode.human || engine is EngineReady;
    final engineController = ref.read(engineControllerProvider.notifier);
    Widget progress(String label, [double? value]) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: value),
      ],
    );
    final engineWidget = switch (engine) {
      EngineChecking() => progress('評価関数を確認しています'),
      EngineUnsupported() => const Text('この端末ではAIエンジンを使えません。人間同士を選んで対局できます。'),
      EngineNeedsDownload(:final error) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'AI対局には評価関数の取得が必要です。ダウンロード約29MB、展開後64,217,066バイト（約64MB）です。',
          ),
          const SizedBox(height: 8),
          const Text('軍師の言葉のモデルとは別です。Wi-Fiでの取得をおすすめします。'),
          if (error != null)
            Text(
              '取得に失敗しました: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: engineController.download,
            child: const Text('評価関数をダウンロード'),
          ),
          TextButton(
            onPressed: engineController.recheck,
            child: const Text('再確認'),
          ),
        ],
      ),
      EngineDownloading(:final progress) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('評価関数をダウンロード中 ${(progress * 100).toStringAsFixed(0)}%'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
        ],
      ),
      EngineStarting() => progress('エンジンを起動しています'),
      EngineReady() => const Text('AIエンジンの準備ができました'),
      EngineFailed(:final message) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'エンジンを起動できませんでした: $message',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: engineController.recheck,
            child: const Text('再確認'),
          ),
        ],
      ),
    };
    final levelDescription = switch (_level) {
      SkillLevel.beginner => '将棋を始めた人向け',
      SkillLevel.easy => '煽りの効果を試したい人向け',
      SkillLevel.normal => '基準の強さ',
      SkillLevel.strong => '読みの強い相手',
      SkillLevel.allOut => '最も強い設定。感情による変調は残る',
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.repeat ? '再戦の準備' : '対局準備')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('開始するまで現在の対局設定は変わりません。対局中の時計は進みます。'),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('相手'),
                  subtitle: Text(modeLabel(_mode)),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () => _choose(
                    '相手',
                    OpponentMode.values
                        .where(
                          (mode) => kDebugMode || mode != OpponentMode.aiBoth,
                        )
                        .toList(),
                    _mode,
                    modeLabel,
                    (mode) => _mode = mode,
                  ),
                ),
                ListTile(
                  title: const Text('強さ'),
                  subtitle: Text('${_level.label}\n$levelDescription'),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () => _choose(
                    '強さ',
                    SkillLevel.values,
                    _level,
                    (level) => level.label,
                    (level) => _level = level,
                  ),
                ),
                ListTile(
                  title: const Text('持ち時間'),
                  subtitle: Text(_time.label),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () => _choose(
                    '持ち時間',
                    const [
                      TimeControl.none,
                      TimeControl.threeMinutes,
                      TimeControl.tenMinutes,
                    ],
                    _time,
                    (time) => time.label,
                    (time) => _time = time,
                  ),
                ),
                if (_mode != OpponentMode.human) ...[
                  const SizedBox(height: 24),
                  engineWidget,
                ],
                const SizedBox(height: 24),
                if (game.thinking) const Text('軍師が思考中のため、今は新しい対局を開始できません。'),
                if (!ready) const Text('AIエンジンの準備後に開始できます。人間同士なら取得せずに始められます。'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: ready && !game.thinking && !_starting
                      ? _start
                      : null,
                  child: Text(ready && !game.thinking ? '開始' : '開始（現在使用不可）'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
