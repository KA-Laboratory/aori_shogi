import 'package:aori_shogi/core/mind/negotiation.dart';
import 'package:aori_shogi/features/game/game_controller.dart';
import 'package:aori_shogi/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 軍師が提案を出している間は盤が固まる（`tapSquare` が `_pending` で弾く）。
/// そのとき答える手段が画面に見えていないと、プレイヤーには「壊れた」としか見えない。
/// 実機でこれを踏んで、盤を何度タップしても動かず、理由も出なかった。
void main() {
  testWidgets('提案が出たら、盤より上に答える手段が出る', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: AoriShogiApp()));
    final ctx = tester.element(find.byType(Scaffold));
    final ctl = ProviderScope.containerOf(ctx).read(gameControllerProvider.notifier);

    ctl.debugSetOffer(OfferKind.offerPlayerUndo);
    await tester.pump();

    // 盤のすぐ上（軍師パネル）に出ていること。スクロールせずに見えるのが肝心。
    expect(find.byKey(const ValueKey('offer-head')), findsOneWidget);
    expect(find.text('答えるまで指せません'), findsWidgets);
    // 指せない理由が盤の下の状態表示にも出ること
    expect(find.text('軍師の提案に答えてください'), findsOneWidget);
  });

  testWidgets('断れば盤が戻る', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: AoriShogiApp()));
    final ctx = tester.element(find.byType(Scaffold));
    final ctl = ProviderScope.containerOf(ctx).read(gameControllerProvider.notifier);

    ctl.debugSetOffer(OfferKind.offerPlayerUndo);
    await tester.pump();
    expect(ctl.state.pendingOffer, isNotNull);

    // 盤より上にある方のボタンを押す
    final head = find.byKey(const ValueKey('offer-head'));
    await tester.tap(find.descendant(of: head, matching: find.text('断る')));
    await tester.pumpAndSettle();

    expect(ctl.state.pendingOffer, isNull);
    expect(find.byKey(const ValueKey('offer-head')), findsNothing);
    expect(find.text('軍師の提案に答えてください'), findsNothing);
  });

  testWidgets('提案が無いときは邪魔をしない', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: AoriShogiApp()));
    expect(find.byKey(const ValueKey('offer-head')), findsNothing);
    expect(find.text('1手目 ▲先手の番'), findsOneWidget);
  });
}
