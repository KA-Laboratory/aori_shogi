import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/game/game_controller.dart';
import 'features/game/game_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final lines = await loadLineLibrary();
  runApp(ProviderScope(
    overrides: [lineLibraryProvider.overrideWithValue(lines)],
    child: const AoriShogiApp(),
  ));
}

class AoriShogiApp extends StatelessWidget {
  const AoriShogiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '煽り将棋',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D5524)),
        useMaterial3: true,
      ),
      home: const GamePage(),
    );
  }
}
