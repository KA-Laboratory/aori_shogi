import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/taunts.dart';
import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:aori_shogi/design/game_feedback.dart';
import 'package:aori_shogi/features/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aori_shogi/features/settings/app_settings.dart';

class TestGameController extends GameController {
  void emit(GameViewState value) => state = value;
}

void main() {
  test(
    'iOS audio context respects silent switch without invalid mix option',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final context = feedbackAudioContext();
      expect(context.iOS.category, AVAudioSessionCategory.ambient);
      expect(context.iOS.options, isEmpty);
      expect(context.android.audioFocus, AndroidAudioFocus.none);
    },
  );
  testWidgets(
    'background cancels pending cue, then fresh foreground events still work',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') calls.add(call);
          return null;
        },
      );
      final game = ShogiGame();
      final controller = TestGameController();
      final container = ProviderContainer(
        overrides: [
          gameControllerProvider.overrideWith(() => controller),
          settingsInitialProvider.overrideWithValue(
            const AppSettings(soundVolume: 0),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const GameFeedback(child: SizedBox()),
        ),
      );
      controller.emit(GameViewState(game: game, revision: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, isEmpty);
      controller.emit(
        GameViewState(
          game: game,
          revision: 2,
          selection: const SquareSelection(54),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, isEmpty);
      controller.emit(
        GameViewState(
          game: game,
          revision: 3,
          selection: const SquareSelection(55),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
  testWidgets('haptics OFF plus volume zero suppresses platform effects', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      },
    );
    final controller = TestGameController();
    final container = ProviderContainer(
      overrides: [
        gameControllerProvider.overrideWith(() => controller),
        settingsInitialProvider.overrideWithValue(
          const AppSettings(soundVolume: 0, haptics: false),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GameFeedback(child: SizedBox()),
      ),
    );
    final game = container.read(gameControllerProvider).game;
    controller.emit(
      GameViewState(
        game: game,
        revision: 1,
        selection: const SquareSelection(54),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  test('mutable game move is detected once across clock refreshes', () {
    final game = ShogiGame();
    final detector = FeedbackDetector();
    detector.observe(GameViewState(game: game, revision: 0));
    game.playUsi('7g7f');
    expect(
      detector.observe(GameViewState(game: game, revision: 1)).single.sound,
      'piece_place',
    );
    expect(detector.observe(GameViewState(game: game, revision: 2)), isEmpty);
  });
  test('new terminal result outranks a move and is not replayed', () {
    final game = ShogiGame();
    final detector = FeedbackDetector();
    detector.observe(GameViewState(game: game, revision: 0));
    game.playUsi('7g7f');
    game.resign(side: Side.white);
    final state = GameViewState(
      game: game,
      revision: 1,
      mode: OpponentMode.aiWhite,
    );
    expect(detector.observe(state).single.sound, 'result_win');
    expect(detector.observe(state), isEmpty);
  });
  test('mock backfire precedes truth-based hit classification', () {
    final outcome = applyTaunt(
      const MindState(hubris: 0.8),
      TauntKind.mock,
      0.3,
    );
    expect(outcome.hit, isTrue);
    expect(FeedbackCue.taunt(outcome).sound, 'taunt_miss');
    expect(FeedbackCue.taunt(outcome).gain, 0.4);
  });
}
