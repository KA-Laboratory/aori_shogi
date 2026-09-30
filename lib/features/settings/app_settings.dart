import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
    this.soundVolume = .6,
    this.haptics = true,
    this.showCoordinates = false,
    this.highlightLastMove = true,
    this.confirmResign = true,
    this.introSeen = false,
  });
  final ThemeMode themeMode;
  final bool reduceMotion,
      haptics,
      showCoordinates,
      highlightLastMove,
      confirmResign,
      introSeen;
  final double soundVolume;
  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? reduceMotion,
    double? soundVolume,
    bool? haptics,
    bool? showCoordinates,
    bool? highlightLastMove,
    bool? confirmResign,
    bool? introSeen,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    soundVolume: soundVolume == null
        ? this.soundVolume
        : (soundVolume.isFinite ? soundVolume.clamp(0, 1).toDouble() : .6),
    haptics: haptics ?? this.haptics,
    showCoordinates: showCoordinates ?? this.showCoordinates,
    highlightLastMove: highlightLastMove ?? this.highlightLastMove,
    confirmResign: confirmResign ?? this.confirmResign,
    introSeen: introSeen ?? this.introSeen,
  );
  Map<String, Object> toJson() => {
    'themeMode': themeMode.name,
    'reduceMotion': reduceMotion,
    'soundVolume': soundVolume,
    'haptics': haptics,
    'showCoordinates': showCoordinates,
    'highlightLastMove': highlightLastMove,
    'confirmResign': confirmResign,
    'introSeen': introSeen,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    final volume = json['soundVolume'];
    return AppSettings(
      themeMode:
          ThemeMode.values
              .where((mode) => mode.name == json['themeMode'])
              .firstOrNull ??
          ThemeMode.system,
      reduceMotion: flag('reduceMotion', false),
      soundVolume: volume is num && volume.isFinite
          ? volume.toDouble().clamp(0, 1)
          : .6,
      haptics: flag('haptics', true),
      showCoordinates: flag('showCoordinates', false),
      highlightLastMove: flag('highlightLastMove', true),
      confirmResign: flag('confirmResign', true),
      introSeen: flag('introSeen', false),
    );
  }
}

class AppSettingsFile {
  AppSettingsFile(this.file);
  final File file;
  AppSettings load() {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
    } on FileSystemException {
      /* Fresh install or inaccessible settings. */
    } on FormatException {
      /* A damaged file does not prevent startup. */
    }
    return const AppSettings();
  }

  void save(AppSettings settings) {
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(jsonEncode(settings.toJson()), flush: true);
    temporary.renameSync(file.path);
  }
}

final settingsStoreProvider = Provider<AppSettingsFile?>((ref) => null);
final settingsInitialProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  Object? saveError;
  @override
  AppSettings build() => ref.watch(settingsInitialProvider);
  void update(AppSettings Function(AppSettings) change) {
    final next = change(state);
    saveError = null;
    try {
      ref.read(settingsStoreProvider)?.save(next);
    } on FileSystemException catch (error) {
      saveError = error;
    }
    state = next;
  }
}
