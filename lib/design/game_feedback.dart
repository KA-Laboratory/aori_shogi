import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/mind/taunts.dart';
import '../core/shogi/shogi.dart';
import '../features/game/game_controller.dart';
import '../features/settings/app_settings.dart';

enum FeedbackTouch { none, selection, light, medium, heavy }

// iOS ambient already mixes with other apps; adding mixWithOthers is invalid.
AudioContext feedbackAudioContext() => AudioContext(
  android: const AudioContextAndroid(
    audioFocus: AndroidAudioFocus.none,
    usageType: AndroidUsageType.notificationRingtone,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: {}),
);

class FeedbackCue {
  const FeedbackCue(
    this.sound,
    this.touch,
    this.priority, {
    this.gain = 1,
    this.tie = 0,
  });
  final String? sound;
  final FeedbackTouch touch;
  final int priority;
  final double gain;
  final int tie;

  static FeedbackCue taunt(TauntOutcome out) {
    final changed =
        out.composureDelta != 0 ||
        out.panicDelta != 0 ||
        out.after.hubris != out.before.hubris;
    if (!changed) return const FeedbackCue(null, FeedbackTouch.none, 4);
    if (out.kind == TauntKind.praise) {
      return const FeedbackCue(null, FeedbackTouch.selection, 3);
    }
    if (out.kind == TauntKind.mock && out.composureDelta > 0) {
      return const FeedbackCue(
        'taunt_miss',
        FeedbackTouch.selection,
        2,
        gain: 0.4,
        tie: 1,
      );
    }
    return out.hit
        ? const FeedbackCue(
            'taunt_hit',
            FeedbackTouch.light,
            2,
            gain: 0.8,
            tie: 1,
          )
        : const FeedbackCue(
            'taunt_miss',
            FeedbackTouch.none,
            3,
            gain: 0.5,
            tie: 1,
          );
  }
}

/// Snapshot scalars now: GameViewState.game is mutated in place by the controller.
class FeedbackDetector {
  ShogiGame? _game;
  int _ply = 0;
  String? _selection;
  GameResult? _result;
  Object? _taunt;
  Object? _offer;
  int _slips = 0;

  List<FeedbackCue> observe(GameViewState state) {
    final game = state.game;
    final newGame = !identical(_game, game);
    final first = _game == null;
    final ply = game.moves.length;
    final selection = switch (state.selection) {
      SquareSelection s => 'square:${s.square}',
      HandSelection s => 'hand:${s.type}',
      null => null,
    };
    final slips = state.chat.where((e) => e.slip).length;
    final cues = <FeedbackCue>[];
    if (!first) {
      if (game.result != null &&
          (newGame || !identical(game.result, _result))) {
        final result = game.result!;
        final neutral = state.mode.gunshiSide == null || result.winner == null;
        final win = !neutral && result.winner != state.mode.gunshiSide;
        cues.add(
          FeedbackCue(
            win ? 'result_win' : 'result_loss',
            result.winner == null
                ? FeedbackTouch.light
                : result.reason == GameEndReason.checkmate
                ? FeedbackTouch.heavy
                : FeedbackTouch.medium,
            0,
            gain: neutral ? 0.35 : 0.7,
          ),
        );
      } else if (newGame) {
        cues.add(
          const FeedbackCue('piece_place', FeedbackTouch.light, 3, gain: 0.6),
        );
      } else {
        if (ply > _ply) {
          final move = game.moves.last;
          final capture = game.positions[ply - 1].board[move.to] != null;
          if (game.position.inCheck(game.position.turn)) {
            cues.add(
              const FeedbackCue('notice', FeedbackTouch.medium, 1, gain: 0.7),
            );
          } else if (move.promote) {
            cues.add(
              const FeedbackCue(
                'piece_promote',
                FeedbackTouch.medium,
                2,
                gain: 0.8,
              ),
            );
          } else {
            cues.add(
              FeedbackCue(
                'piece_place',
                capture ? FeedbackTouch.medium : FeedbackTouch.light,
                3,
              ),
            );
          }
        } else if (selection != null && selection != _selection) {
          cues.add(
            const FeedbackCue(
              'piece_pick',
              FeedbackTouch.selection,
              4,
              gain: 0.45,
            ),
          );
        }
        if (state.pendingOffer != null && state.pendingOffer != _offer) {
          cues.add(
            const FeedbackCue(
              'notice',
              FeedbackTouch.medium,
              1,
              gain: 0.7,
              tie: 3,
            ),
          );
        } else if (_offer != null && state.pendingOffer == null) {
          cues.add(
            const FeedbackCue(
              'piece_pick',
              FeedbackTouch.selection,
              2,
              gain: 0.45,
            ),
          );
        }
        if (slips > _slips) {
          cues.add(
            const FeedbackCue(
              'notice',
              FeedbackTouch.selection,
              2,
              gain: 0.42,
              tie: 2,
            ),
          );
        }
        if (state.lastTaunt != null && !identical(state.lastTaunt, _taunt)) {
          cues.add(FeedbackCue.taunt(state.lastTaunt!));
        }
      }
    }
    _game = game;
    _ply = ply;
    _selection = selection;
    _result = game.result;
    _offer = state.pendingOffer;
    _taunt = state.lastTaunt;
    _slips = slips;
    return cues;
  }
}

class GameFeedback extends ConsumerStatefulWidget {
  const GameFeedback({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<GameFeedback> createState() => _GameFeedbackState();
}

class _GameFeedbackState extends ConsumerState<GameFeedback>
    with WidgetsBindingObserver {
  final _detector = FeedbackDetector();
  AudioPlayer? _player;
  Timer? _window;
  FeedbackCue? _pending;
  FeedbackCue? _playing;
  DateTime? _lastTouch;
  DateTime? _soundEnd;
  bool _foreground = true;
  int _generation = 0;
  Future<void> _audioWork = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _detector.observe(ref.read(gameControllerProvider));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _window?.cancel();
      _window = null;
      _pending = null;
      _stop();
    }
  }

  void _stop() {
    _generation++;
    _playing = null;
    _soundEnd = null;
    _audioWork = _audioWork
        .then((_) async {
          await _player?.stop();
        })
        .catchError((Object _) {});
  }

  void _queue(FeedbackCue cue) {
    if (!_foreground) return;
    final old = _pending;
    if (old == null ||
        cue.priority < old.priority ||
        (cue.priority == old.priority && cue.tie >= old.tie)) {
      _pending = cue;
    }
    _window ??= Timer(const Duration(milliseconds: 80), () {
      _window = null;
      final selected = _pending;
      _pending = null;
      if (selected != null) _emit(selected);
    });
  }

  void _emit(FeedbackCue cue) {
    if (!mounted || !_foreground) return;
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();
    if (settings.haptics &&
        cue.touch != FeedbackTouch.none &&
        (_lastTouch == null ||
            now.difference(_lastTouch!).inMilliseconds >= 150)) {
      _lastTouch = now;
      final future = switch (cue.touch) {
        FeedbackTouch.selection => HapticFeedback.selectionClick(),
        FeedbackTouch.light => HapticFeedback.lightImpact(),
        FeedbackTouch.medium => HapticFeedback.mediumImpact(),
        FeedbackTouch.heavy => HapticFeedback.heavyImpact(),
        FeedbackTouch.none => Future<void>.value(),
      };
      unawaited(future.catchError((Object _) {}));
    }
    if (settings.soundVolume <= 0 || cue.sound == null) return;
    if (_playing != null &&
        _soundEnd != null &&
        now.isBefore(_soundEnd!) &&
        cue.priority > _playing!.priority) {
      return;
    }
    final generation = ++_generation;
    _audioWork = _audioWork
        .then((_) async {
          if (!mounted || !_foreground || generation != _generation) return;
          final player = _player ??= AudioPlayer();
          if (_playing != null) {
            final volume = player.volume;
            for (var step = 3; step >= 0; step--) {
              await player.setVolume(volume * step / 4);
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            await player.stop();
          }
          if (!mounted ||
              !_foreground ||
              generation != _generation ||
              ref.read(settingsProvider).soundVolume <= 0) {
            return;
          }
          await player.setAudioContext(feedbackAudioContext());
          if (!mounted || !_foreground || generation != _generation) return;
          _playing = cue;
          const durations = {
            'piece_pick': 60,
            'piece_place': 100,
            'piece_promote': 180,
            'notice': 160,
            'taunt_hit': 180,
            'taunt_miss': 100,
            'result_win': 650,
            'result_loss': 500,
          };
          _soundEnd = DateTime.now().add(
            Duration(milliseconds: durations[cue.sound] ?? 0),
          );
          await player.play(
            AssetSource('audio/${cue.sound}.wav'),
            volume: ref.read(settingsProvider).soundVolume * cue.gain,
          );
        })
        .catchError((Object _) {
          _playing = null;
        });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameControllerProvider, (_, next) {
      for (final cue in _detector.observe(next)) {
        _queue(cue);
      }
    });
    ref.listen(settingsProvider, (_, next) {
      if (next.soundVolume <= 0) _stop();
    });
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _window?.cancel();
    _generation++;
    unawaited(
      _audioWork
          .then((_) async {
            await _player?.dispose();
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
