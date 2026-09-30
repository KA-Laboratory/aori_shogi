import 'package:aori_shogi/core/mind/negotiation.dart';
import 'package:aori_shogi/features/game/board_view.dart';
import 'package:aori_shogi/features/game/game_controller.dart';
import 'package:aori_shogi/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('360x640 keeps board and primary controls visible at 1.3 text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: AoriShogiApp()));
    expect(find.text('対局メニュー'), findsOneWidget);
    expect(tester.getRect(find.byType(BoardView)).bottom, lessThan(592));
    expect(find.text('強さ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final offer in OfferKind.values) {
    testWidgets('360px offer ${offer.name} is actionable without page scrolling', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: AoriShogiApp()));
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      final ctl = container.read(gameControllerProvider.notifier);
      ctl.debugSetOffer(offer);
      await tester.pumpAndSettle();
      expect(find.text('断る').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byType(BoardView)).bottom, lessThan(640));
      await tester.tap(find.text('断る'));
      await tester.pumpAndSettle();
      expect(ctl.state.pendingOffer, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
