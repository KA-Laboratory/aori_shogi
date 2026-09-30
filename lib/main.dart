import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/dialogue/player_memory_file.dart';
import 'core/dialogue/speaker.dart';
import 'core/llm/gemma_client.dart';
import 'features/game/game_controller.dart';
import 'features/game/game_shell.dart';
import 'features/game/game_setup_page.dart';
import 'features/game/intro_page.dart';
import 'features/llm/model_page.dart';
import 'features/settings/app_settings.dart';
import 'design/app_theme.dart';
import 'design/game_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final lines = await loadLineLibrary();
  final lexicon = await loadIntentLexicon();
  final tone = await loadToneProfile();
  final dir = await getApplicationSupportDirectory();
  final settingsStore = AppSettingsFile(File('${dir.path}/settings.json'));
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans JP',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final memory = PlayerMemoryFile(
    File('${dir.path}/memory/player_memory.json'),
  ).load();
  // 端末内LLM。モデルが入っていなければ ready が false のままで、定型文で遊べる。
  final llm = GemmaLlmClient();
  await llm.load().catchError((Object _) {});
  final speaker = llm.ready
      ? LlmSpeaker(client: llm, tone: tone, lines: lines)
      : null;
  runApp(
    ProviderScope(
      overrides: [
        lineLibraryProvider.overrideWithValue(lines),
        intentLexiconProvider.overrideWithValue(lexicon),
        toneProfileProvider.overrideWithValue(tone),
        playerMemoryProvider.overrideWithValue(memory),
        settingsStoreProvider.overrideWithValue(settingsStore),
        settingsInitialProvider.overrideWithValue(settingsStore.load()),
      ],
      child: AoriShogiApp(speaker: speaker, showIntro: true),
    ),
  );
}

class AoriShogiApp extends ConsumerStatefulWidget {
  const AoriShogiApp({super.key, this.speaker, this.showIntro = false});

  final GunshiSpeaker? speaker;
  final bool showIntro;

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
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '煽り将棋',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: Builder(
        builder: (context) {
          if (widget.showIntro && !settings.introSeen) {
            return IntroPage(
              onStart: () {
                ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(introSeen: true));
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GameSetupPage(),
                  ),
                );
              },
              onModels: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModelPage(store: GunshiModelStore()),
                ),
              ),
            );
          }
          return const GameFeedback(child: GamePage());
        },
      ),
    );
  }
}
