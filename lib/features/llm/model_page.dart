/// 軍師の「言葉」を端末内LLMにするかどうかの画面。
///
/// モデルが無くても定型文で遊べる、というのが前提。ここは足すか外すかだけを扱う。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogue/speaker.dart';
import '../../core/llm/gemma_client.dart';
import '../../core/llm/model_catalog.dart';
import '../game/game_controller.dart';

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ready = await widget.store.isReady().catchError((Object _) => false);
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _install(LlmModelSpec spec) async {
    setState(() {
      _busy = true;
      _percent = 0;
      _error = null;
      _downloading = spec;
    });
    try {
      await widget.store.install(spec, onProgress: (p) {
        if (mounted) setState(() => _percent = p);
      });
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

  /// 入れ替えたその場で軍師の口を差し替える（アプリの再起動は要らない）。
  Future<void> _swapSpeaker() async {
    final box = ref.read(gunshiSpeakerProvider.notifier);
    final tone = ref.read(toneProfileProvider);
    final lines = ref.read(lineLibraryProvider);
    if (tone == null || lines == null) return;
    final llm = GemmaLlmClient();
    await llm.load().catchError((Object _) {});
    box.set(llm.ready ? LlmSpeaker(client: llm, tone: tone, lines: lines) : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          const Text(
            'モデルを入れると、軍師は場面ごとに言葉を選んで喋るようになります。'
            '入れなくても対局・煽り・雑談はそのまま遊べます。'
            'ダウンロードは通信量が大きいので Wi-Fi をおすすめします。',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('うまくいきませんでした: $_error', style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          if (_busy && _downloading != null) ...[
            Text('${_downloading!.label} を取得中… $_percent%'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _percent <= 0 ? null : _percent / 100),
            const SizedBox(height: 16),
          ],
          for (final spec in gunshiModels)
            Card(
              child: ListTile(
                title: Text('${spec.label}（${spec.sizeText}）'),
                subtitle: Text(spec.note),
                trailing: FilledButton(
                  onPressed: _busy ? null : () => _install(spec),
                  child: const Text('入れる'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_ready)
            OutlinedButton.icon(
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('モデルを消して定型文に戻す'),
            ),
        ],
      ),
    );
  }
}
