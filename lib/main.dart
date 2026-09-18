import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/dialogue/player_memory_file.dart';
import 'core/dialogue/speaker.dart';
import 'core/llm/gemma_client.dart';
import 'features/game/game_controller.dart';
import 'features/game/game_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final lines = await loadLineLibrary();
  final lexicon = await loadIntentLexicon();
  final tone = await loadToneProfile();
  final dir = await getApplicationSupportDirectory();
  final memory = PlayerMemoryFile(File('${dir.path}/memory/player_memory.json')).load();
  // 端末内LLM。モデルが入っていなければ ready が false のままで、定型文で遊べる。
  final llm = GemmaLlmClient();
  await llm.load().catchError((Object _) {});
  final speaker = llm.ready ? LlmSpeaker(client: llm, tone: tone, lines: lines) : null;
  runApp(
    ProviderScope(
      overrides: [
        lineLibraryProvider.overrideWithValue(lines),
        intentLexiconProvider.overrideWithValue(lexicon),
        toneProfileProvider.overrideWithValue(tone),
        playerMemoryProvider.overrideWithValue(memory),
      ],
      child: AoriShogiApp(speaker: speaker),
    ),
  );
}

class AoriShogiApp extends ConsumerStatefulWidget {
  const AoriShogiApp({super.key, this.speaker});

  final GunshiSpeaker? speaker;

  @override
  ConsumerState<AoriShogiApp> createState() => _AoriShogiAppState();
}

class _AoriShogiAppState extends ConsumerState<AoriShogiApp> {
  @override
  void initState() {
    super.initState();
    final speaker = widget.speaker;
    if (speaker != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(gunshiSpeakerProvider.notifier).set(speaker);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '煽り将棋',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D5524)), useMaterial3: true),
      home: const GamePage(),
    );
  }
}
