import 'package:aori_shogi/design/app_theme.dart';
import 'package:aori_shogi/features/settings/app_settings.dart';
import 'package:aori_shogi/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'large Japanese text scrolls without overflow and volume buttons update settings',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const SettingsPage(gameInProgress: true),
          ),
        ),
      );
      expect(find.text('設定を開いている間も対局の時計は進みます。'), findsOneWidget);
      await tester.scrollUntilVisible(find.byTooltip('効果音を上げる'), 300);
      await tester.tap(find.byTooltip('効果音を上げる'));
      await tester.pump();
      expect(container.read(settingsProvider).soundVolume, .7);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('アプリ情報'), 250);
      expect(tester.takeException(), isNull);
    },
  );
}
