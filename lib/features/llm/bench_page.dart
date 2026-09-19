/// 端末内LLMの試し撃ち（開発用）。
///
/// 受け入れ条件 p95 < 6秒 を実機で測るための画面。評価用のお題10件を順に投げ、
/// かかった時間と、口調を整えたあとのセリフを並べる。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogue/speaker.dart';
import '../../core/llm/gemma_client.dart';
import '../game/game_controller.dart';

class BenchResult {
  BenchResult({
    required this.scene,
    required this.mood,
    required this.ms,
    required this.raw,
    required this.fixed,
    required this.violations,
  });

  final String scene;
  final String mood;
  final int ms;
  final String raw;
  final String fixed;
  final List<String> violations;
}

class BenchPage extends ConsumerStatefulWidget {
  const BenchPage({super.key});

  @override
  ConsumerState<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends ConsumerState<BenchPage> {
  final _results = <BenchResult>[];
  bool _busy = false;
  String _status = '';

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _results.clear();
      _status = 'モデルを読み込み中…';
    });
    final tone = ref.read(toneProfileProvider);
    try {
      final raw = await rootBundle.loadString('assets/dev/bench_prompts.json');
      final items = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final client = GemmaLlmClient();
      final loadStart = DateTime.now();
      await client.load();
      final loadMs = DateTime.now().difference(loadStart).inMilliseconds;
      if (!client.ready) {
        setState(() => _status = 'モデルが入っていません（「軍師の言葉」で入れてください）');
        return;
      }
      setState(() => _status = '読み込み ${(loadMs / 1000).toStringAsFixed(1)}秒。生成中…');
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final mood = it['mood'] as String;
        final t0 = DateTime.now();
        final out = await client.generate(system: LlmSpeaker.systemPrompt, user: it['user'] as String);
        final ms = DateTime.now().difference(t0).inMilliseconds;
        final text = (out ?? '（出せなかった）').replaceAll(RegExp(r'\s*\n+\s*'), ' ');
        final fixed = tone?.rewrite(text, mood: mood) ?? text;
        setState(() {
          _results.add(
            BenchResult(
              scene: it['scene'] as String,
              mood: mood,
              ms: ms,
              raw: text,
              fixed: fixed,
              violations: tone?.violations(fixed, mood: mood) ?? const [],
            ),
          );
          _status = '${i + 1}/${items.length} 件';
        });
      }
      await client.close();
      setState(() => _status = '読み込み ${(loadMs / 1000).toStringAsFixed(1)}秒 / 生成 ${_results.length}件');
    } on Object catch (e) {
      setState(() => _status = '失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 昇順に並べた n 番目（p95 は件数が少ないので「上から2番目に遅い」に近い）。
  int _percentile(double p) {
    if (_results.isEmpty) return 0;
    final xs = _results.map((r) => r.ms).toList()..sort();
    final i = ((xs.length - 1) * p).round();
    return xs[i];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bad = _results.where((r) => r.violations.isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(title: const Text('試し撃ち（開発用）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.play_arrow),
            label: const Text('お題10件を投げる'),
          ),
          const SizedBox(height: 8),
          Text(_status),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '中央値 ${(_percentile(0.5) / 1000).toStringAsFixed(1)}秒 / '
                  'p95 ${(_percentile(0.95) / 1000).toStringAsFixed(1)}秒 / '
                  '最遅 ${(_percentile(1.0) / 1000).toStringAsFixed(1)}秒\n'
                  '口調の崩れ $bad/${_results.length}件',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final r in _results)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.scene} / ${r.mood}  ${(r.ms / 1000).toStringAsFixed(1)}秒',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(r.fixed),
                    if (r.violations.isNotEmpty)
                      Text('崩れ: ${r.violations.join(", ")}', style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
