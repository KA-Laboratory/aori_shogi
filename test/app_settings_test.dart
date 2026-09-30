import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aori_shogi/features/settings/app_settings.dart';
import 'package:aori_shogi/design/app_theme.dart';

void main() {
  test('settings survive a restart and malformed input falls back safely', () {
    final dir = Directory.systemTemp.createTempSync('aori-settings-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/settings.json');
    final store = AppSettingsFile(file);
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        settingsInitialProvider.overrideWithValue(store.load()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            themeMode: ThemeMode.dark,
            soundVolume: .2,
            introSeen: true,
            showCoordinates: true,
          ),
        );
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(reduceMotion: true));
    expect(container.read(settingsProvider.notifier).saveError, isNull);
    final restarted = store.load();
    expect(restarted.themeMode, ThemeMode.dark);
    expect(restarted.soundVolume, .2);
    expect(restarted.introSeen, isTrue);
    expect(restarted.showCoordinates, isTrue);
    file.writeAsStringSync(
      '{"soundVolume":2,"themeMode":"future","haptics":"bad"}',
    );
    expect(store.load().soundVolume, 1);
    expect(store.load().themeMode, ThemeMode.system);
    expect(store.load().haptics, isTrue);
    file.writeAsStringSync('broken json');
    expect(store.load().introSeen, isFalse);
  });
  test('both themes provide readable text on specified surfaces', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness);
      final scheme = theme.colorScheme;
      for (final background in [scheme.surface, scheme.surfaceContainer]) {
        for (final foreground in [scheme.onSurface, scheme.onSurfaceVariant]) {
          final values = [
            background.computeLuminance(),
            foreground.computeLuminance(),
          ]..sort();
          expect(
            (values.last + .05) / (values.first + .05),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(theme.textTheme.bodyMedium!.fontFamily, 'NotoSansJP');
      expect(theme.textTheme.bodyMedium!.height, 1.5);
      expect(theme.appBarTheme.toolbarHeight, 48);
    }
  });
}
