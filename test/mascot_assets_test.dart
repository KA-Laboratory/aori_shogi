import 'dart:ui' as ui;

import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/features/game/design_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mood in Mood.values) {
    testWidgets('bundled mascot ${mood.name} decodes and renders in HUD', (
      tester,
    ) async {
      final path = 'assets/gunshi/face_${mood.name}.png';
      await tester.runAsync(() async {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        final rgba = await frame.image.toByteData();
        expect(frame.image.width, greaterThan(500));
        expect(frame.image.height, greaterThan(500));
        expect(rgba!.getUint8(3), 0, reason: 'Background must be transparent');
        frame.image.dispose();
        codec.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: GunshiFace(mood: mood)),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(GunshiFace));
        await precacheImage(AssetImage(path), context);
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(find.text(moodFace(mood)), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
