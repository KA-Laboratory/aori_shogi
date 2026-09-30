import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/negotiation.dart';
import 'package:aori_shogi/core/mind/taunts.dart';
import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:aori_shogi/design/app_theme.dart';
import 'package:aori_shogi/features/game/board_view.dart';
import 'package:aori_shogi/features/game/game_controller.dart';
import 'package:aori_shogi/features/game/game_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const longSpeech = '君のお手並みをじっくり見せてもらおう。まだまだ勝負はこれからだ。';
final fullSpeech = List.filled(4, longSpeech).join().substring(0, 100);

class SnapshotController extends GameController {
  SnapshotController(this.snapshot);
  final GameViewState snapshot;
  bool? response;
  String? sent;
  void setSnapshot(GameViewState snapshot) => state = snapshot;
  @override
  void sendChat(String raw, {TauntKind? forcedKind}) {
    sent = raw;
  }

  @override
  GameViewState build() => snapshot;
  @override
  void respondOffer(bool accept) {
    response = accept;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('NotoSansJP')
      ..addFont(rootBundle.load('assets/fonts/NotoSansJP-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansJP-Bold.ttf'));
    await loader.load();
  });
  Future<SnapshotController> mount(
    WidgetTester tester,
    Brightness brightness, {
    OfferKind? offer,
    int deal = 3,
    double height = 640,
    bool ended = false,
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = SnapshotController(
      GameViewState(
        game: ended ? (ShogiGame()..resign()) : ShogiGame(),
        revision: 0,
        mode: OpponentMode.aiWhite,
        mind: const MindState(panic: .65, composure: .2),
        dealTurns: deal,
        speech: fullSpeech,
        chat: [ChatEntry(ChatRole.gunshi, fullSpeech)],
        pendingOffer: offer,
        tauntAvailable: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [gameControllerProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const GamePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  void expectBoardVisible(WidgetTester tester, {double bottom = 640}) {
    final board = tester.getRect(find.byType(BoardView));
    expect(board.width, closeTo(board.height, .01));
    expect(board.left, greaterThanOrEqualTo(0));
    expect(board.top, greaterThanOrEqualTo(48));
    expect(board.right, lessThanOrEqualTo(360));
    expect(board.bottom, lessThanOrEqualTo(bottom));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'mind + deal + 100 character speech fits 360x640 1.3 $brightness',
      (tester) async {
        await mount(tester, brightness);
        expect(find.textContaining('約束：あと3手'), findsOneWidget);
        expect(find.byKey(const ValueKey('mood')), findsOneWidget);
        expectBoardVisible(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('speech')));
        await tester.pumpAndSettle();
        expect(find.textContaining(fullSpeech), findsOneWidget);
        expectBoardVisible(tester);
        expect(tester.takeException(), isNull);
      },
    );
    for (final offer in OfferKind.values) {
      testWidgets('offer ${offer.name} replies visible $brightness', (
        tester,
      ) async {
        final controller = await mount(tester, brightness, offer: offer);
        final accept = find.descendant(
          of: find.byKey(const ValueKey('offer-head')),
          matching: find.byType(FilledButton),
        );
        final decline = find.text('断る');
        expect(accept.hitTestable(), findsOneWidget);
        expect(decline.hitTestable(), findsOneWidget);
        expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
        expectBoardVisible(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(accept);
        expect(controller.response, isTrue);
        await tester.tap(decline);
        expect(controller.response, isFalse);
      });
    }
    testWidgets(
      'keyboard 280 leaves board input send close visible $brightness',
      (tester) async {
        final controller = await mount(tester, brightness, deal: 0);
        await tester.tap(find.text('煽る'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('入力'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'まだまだこれから');
        final inputState = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        expect(inputState.widget.focusNode.hasFocus, isTrue);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expectBoardVisible(tester, bottom: 360);
        expect(find.byType(TextField).hitTestable(), findsOneWidget);
        expect(find.byTooltip('盤へ戻る').hitTestable(), findsOneWidget);
        expect(find.byTooltip('送信').hitTestable(), findsOneWidget);
        expect(
          identical(
            inputState,
            tester.state<EditableTextState>(find.byType(EditableText)),
          ),
          isTrue,
        );
        expect(inputState.widget.focusNode.hasFocus, isTrue);
        await tester.tap(find.byTooltip('送信'));
        await tester.pump();
        expect(controller.sent, 'まだまだこれから');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short viewport offers and results scroll without overflow', (
    tester,
  ) async {
    for (final ended in [false, true]) {
      await mount(
        tester,
        Brightness.dark,
        height: 298,
        offer: ended ? null : OfferKind.proposeDeal,
        ended: ended,
      );
      expect(tester.takeException(), isNull);
      if (!ended) {
        await tester.ensureVisible(find.text('断る'));
        expect(find.text('断る').hitTestable(), findsOneWidget);
      } else {
        await tester.ensureVisible(find.text('感想戦へ'));
        expect(find.text('感想戦へ').hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('chat panel shows actual praise hubris and normal taunt deltas', (
    tester,
  ) async {
    final controller = await mount(tester, Brightness.light, deal: 0);
    await tester.tap(find.text('煽る'));
    await tester.pumpAndSettle();
    for (final kind in [TauntKind.praise, TauntKind.blunderCall]) {
      final outcome = applyTaunt(const MindState(), kind, 1);
      controller.setSnapshot(
        GameViewState(
          game: controller.snapshot.game,
          revision: kind.index + 1,
          mode: OpponentMode.aiWhite,
          mind: outcome.after,
          lastTaunt: outcome,
          tauntAvailable: true,
        ),
      );
      await tester.pump();
      final text = kind == TauntKind.praise ? '慢心+10' : '焦り+20';
      expect(find.textContaining(text).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large move list plays real seven-seven pawn to seven-six', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const GamePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('対局メニュー'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大きな着手操作'));
    await tester.pumpAndSettle();
    final pawn = find.byKey(const ValueKey('large-piece-56'));
    await tester.scrollUntilVisible(pawn, 100);
    await tester.tap(pawn);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('large-target-47')));
    await tester.pumpAndSettle();
    final game = container.read(gameControllerProvider).game;
    expect(game.moves, hasLength(1));
    expect(game.moves.single.from, 56);
    expect(game.moves.single.to, 47);
    expect(find.text('2手目 △後手の番'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
