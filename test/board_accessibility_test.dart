import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:aori_shogi/features/game/board_view.dart';
import 'package:aori_shogi/features/game/game_controller.dart';
import 'package:aori_shogi/features/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class HandFixture extends GameController {
  @override
  GameViewState build() => GameViewState(
    game: ShogiGame(Position.fromSfen('4k4/9/9/9/9/9/9/9/4K4 b RBGSNLP 1')),
    revision: 0,
  );
}

void main() {
  testWidgets('coordinates and last move respect settings at enlarged text', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsInitialProvider.overrideWithValue(
          const AppSettings(showCoordinates: true),
        ),
      ],
    );
    final game = container.read(gameControllerProvider).game;
    game.playUsi('7g7f');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 324,
                  child: BoardView(onCandidates: (_) {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('9'), findsOneWidget);
    expect(find.byKey(const ValueKey('last-move-outline')), findsOneWidget);
    expect(tester.takeException(), isNull);
    container
        .read(settingsProvider.notifier)
        .update(
          (settings) => settings.copyWith(
            showCoordinates: false,
            highlightLastMove: false,
          ),
        );
    await tester.pump();
    expect(find.text('9'), findsNothing);
    expect(find.byKey(const ValueKey('last-move-outline')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  testWidgets(
    'seven hand pieces keep 48dp targets and fixed tray on narrow screen',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gameControllerProvider.overrideWith(HandFixture.new)],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: KomadaiView(side: Side.black),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(KomadaiView)).height, 48);
      for (final type in handOrder) {
        expect(
          tester.getSize(find.byKey(ValueKey('hand-black-${type.name}'))),
          const Size(48, 48),
        );
      }
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all 81 cells expose coordinate and piece semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 324, child: BoardView(onCandidates: (_) {})),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('９一 後手 香'), findsOneWidget);
    expect(find.bySemanticsLabel('５九 先手 玉'), findsOneWidget);
    for (var sq = 0; sq < 81; sq++) {
      expect(find.byKey(ValueKey('sq$sq')), findsOneWidget);
    }
    semantics.dispose();
  });
}
