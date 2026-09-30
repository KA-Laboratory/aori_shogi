/// 軍師の「言葉」を端末内LLMにするかどうかの画面。
///
/// モデルが無くても定型文で遊べる、というのが前提。ここは足すか外すかだけを扱う。
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/dialogue/speaker.dart';
import '../../core/llm/gemma_client.dart';
import '../../core/llm/model_catalog.dart';
import '../game/game_controller.dart';
import 'bench_page.dart';

class ModelPage extends ConsumerStatefulWidget {
  const ModelPage({super.key, required this.store});

  final GunshiModelStore store;

  @override
  ConsumerState<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends ConsumerState<ModelPage> {
  bool _ready = false;
  bool _busy = false;
  int _percent = 0;
  String? _error;
  LlmModelSpec? _downloading;

  bool _active(GameViewState state) =>
      !state.game.isOver &&
      (state.game.moves.isNotEmpty ||
          state.mode != OpponentMode.human ||
          state.thinking);

  bool get _canChange => mounted && !_active(ref.read(gameControllerProvider));

  Future<bool> _confirm(String title, String message, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取り消し'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return mounted && confirmed == true && _canChange;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final ready = await widget.store.isReady().catchError((Object _) => false);
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _install(LlmModelSpec spec) async {
    if (_busy || !_canChange || spec.url.isEmpty) return;
    if (!await _confirm(
      '${spec.label}を入れますか？',
      '${spec.sizeText}の通信と保存領域を使います。Wi-Fiをおすすめします。',
      'ダウンロード',
    )) {
      return;
    }
    if (!_canChange || _busy) return;
    setState(() {
      _busy = true;
      _percent = 0;
      _error = null;
      _downloading = spec;
    });
    try {
      await widget.store.install(
        spec,
        onProgress: (p) {
          if (mounted) setState(() => _percent = p);
        },
      );
      await _swapSpeaker();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloading = null;
        });
      }
      await _refresh();
    }
  }

  Future<void> _remove() async {
    if (_busy || !_canChange) return;
    if (!await _confirm(
      'モデルを削除しますか？',
      'モデルを削除して定型文に戻します。対局と軍師の記憶は残ります。',
      'モデルを削除',
    )) {
      return;
    }
    if (!_canChange || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.removeAll();
      await _swapSpeaker();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  /// adb で push した `.litertlm` を入れる（開発用）。
  /// 置き場所: /sdcard/Android/data/com.amkn.aori_shogi/files/gunshi.litertlm
  Future<void> _installPushed() async {
    if (!kDebugMode || _busy || !_canChange) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dir = await getExternalStorageDirectory();
      if (!_canChange) return;
      final path = '${dir?.path}/gunshi.litertlm';
      await widget.store.installFromFile(path, LlmFamily.qwen3);
      await _swapSpeaker();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  /// 入れ替えたその場で軍師の口を差し替える（アプリの再起動は要らない）。
  Future<void> _swapSpeaker() async {
    if (!_canChange) return;
    final tone = ref.read(toneProfileProvider);
    final lines = ref.read(lineLibraryProvider);
    if (tone == null || lines == null) return;
    final llm = GemmaLlmClient();
    await llm.load().catchError((Object _) {});
    if (!_canChange) {
      await llm.close();
      return;
    }
    ref
        .read(gunshiSpeakerProvider.notifier)
        .set(
          llm.ready ? LlmSpeaker(client: llm, tone: tone, lines: lines) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _active(ref.watch(gameControllerProvider));
    final locked = _busy || active;
    return Scaffold(
      appBar: AppBar(title: const Text('軍師の言葉')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _ready ? '端末内のモデルで喋ります。' : 'いまは定型文で喋っています。',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (active)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('対局中は閲覧のみです。持ち時間は進み続けます。モデルの導入・削除は終局後にできます。'),
            ),
          const Text(
            'モデルを入れると、軍師は場面ごとに言葉を選んで喋るようになります。'
            '入れなくても対局・煽り・雑談はそのまま遊べます。'
            'ダウンロードは通信量が大きいので Wi-Fi をおすすめします。',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              'うまくいきませんでした: $_error',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (_busy && _downloading != null) ...[
            Text(
              _percent >= 100
                  ? 'モデルを確認しています'
                  : '${_downloading!.label} を取得中… $_percent%',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _percent <= 0 ? null : _percent / 100,
            ),
            const SizedBox(height: 16),
          ],
          if (gunshiFinetuned.url.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('学習済み軍師：配布準備中\n1.90GB。いまは他のモデル、または定型文で遊べます。'),
              ),
            ),
          for (final spec in [
            if (gunshiFinetuned.url.isNotEmpty) gunshiFinetuned,
            ...gunshiModels,
          ])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${spec.label}（${spec.sizeText}）',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(spec.note),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: locked ? null : () => _install(spec),
                      child: const Text('入れる'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          // 開発用: adb で push した .litertlm をそのまま入れて試す
          if (kDebugMode) ...[
            Text('開発用', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            OutlinedButton(
              onPressed: locked ? null : _installPushed,
              child: const Text('端末に置いたファイルから入れる'),
            ),
            OutlinedButton(
              onPressed: locked
                  ? null
                  : () {
                      if (!kDebugMode || !_canChange) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BenchPage(),
                        ),
                      );
                    },
              child: const Text('試し撃ち（速さと口調を測る）'),
            ),
          ],
          const SizedBox(height: 16),
          if (_ready)
            OutlinedButton.icon(
              onPressed: locked ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('モデルを消して定型文に戻す'),
            ),
        ],
      ),
    );
  }
}
