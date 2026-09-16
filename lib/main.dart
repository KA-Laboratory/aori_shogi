import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/game/game_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: AoriShogiApp()));
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
