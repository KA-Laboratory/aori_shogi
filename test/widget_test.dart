import 'package:aori_shogi/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('盤をタップして▲7六歩を指せる', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: AoriShogiApp()));

    expect(find.text('1手目 ▲先手の番'), findsOneWidget);
    // 7七 = index (7-1)*9 + (9-7) = 56、7六 = 47
    await tester.tap(find.byKey(const ValueKey('sq56')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sq47')));
    await tester.pumpAndSettle();
    expect(find.text('2手目 △後手の番'), findsOneWidget);

    await tester.tap(find.text('待った'));
    await tester.pump();
    expect(find.text('1手目 ▲先手の番'), findsOneWidget);
  });
}
