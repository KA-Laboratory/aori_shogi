// 自己対局による「感情が手に効く」ことの測定（設計書 §8, M2 受け入れ条件）。
// 実行: flutter test integration_test/selfplay_test.dart -d <emulator>
//       --dart-define=GAMES=50 --dart-define=MOVETIME=100
// 前提: 端末に評価関数 nn.bin が配置済み（docs/dev/nnue.md）。
import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/engine/nnue_store.dart';
import 'package:aori_shogi/core/engine/shogi_engine.dart';
import 'package:aori_shogi/core/mind/gunshi_brain.dart';
import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/move_policy.dart';
import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const games = int.fromEnvironment('GAMES', defaultValue: 50);
const movetime = int.fromEnvironment('MOVETIME', defaultValue: 100);
const maxPlies = int.fromEnvironment('MAX_PLIES', defaultValue: 320);
// 崩れた側の感情（既定は設計書の条件。通常時の強さを見るときは 0.8 / 0.1 を指定）。
final brokenComposure = double.parse(const String.fromEnvironment('COMPOSURE', defaultValue: '0.2'));
final brokenPanic = double.parse(const String.fromEnvironment('PANIC', defaultValue: '0.8'));
final expectMaxWinRate = double.parse(const String.fromEnvironment('EXPECT_MAX', defaultValue: '0.30'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('selfplay: 変調なし vs 崩れた軍師', () async {
    final store = NnueStore();
    if (!await store.isInstalled()) {
      // flutter test はアプリを入れ直すため、外部ストレージのアプリ領域から取り込む:
      //   adb push nn.bin /sdcard/Android/data/com.amkn.aori_shogi/files/nn.bin
      final ext = await getExternalStorageDirectory();
      final src = File('${ext!.path}/nn.bin');
      // ignore: avoid_print
      print('SELFPLAY waiting for ${src.path}');
      for (var i = 0; i < 180 && !(src.existsSync() && src.lengthSync() == NnueStore.expectedSize); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      src.copySync('${(await store.evalDir()).path}/${NnueStore.fileName}');
    }
    expect(await store.isInstalled(), isTrue, reason: 'nn.bin を配置してください');
    final engine = await YaneuraOuEngine.start(evalDir: (await store.evalDir()).path);

    var brokenWins = 0, normalWins = 0, draws = 0;
    var brokenMoves = 0, brokenLossSum = 0, blunders = 0, nonBest = 0;
    final records = <Map<String, Object?>>[];
    final sw = Stopwatch()..start();

    for (var i = 0; i < games; i++) {
      final brokenSide = i.isEven ? Side.black : Side.white;
      final brains = {
        brokenSide: GunshiBrain(
          engine: engine,
          side: brokenSide,
          seed: 1000 + i,
          fixedMind: MindState(composure: brokenComposure, panic: brokenPanic),
          fixedMovetimeMs: movetime,
        ),
        brokenSide.opponent: GunshiBrain(
          engine: engine,
          side: brokenSide.opponent,
          seed: 2000 + i,
          modulate: false,
          fixedMovetimeMs: movetime,
        ),
      };
      final game = ShogiGame();
      while (!game.isOver && game.moves.length < maxPlies) {
        final brain = brains[game.position.turn]!;
        final t = await brain.takeTurn(game);
        if (t.resign) {
          game.resign();
          break;
        }
        if (brain.side == brokenSide) {
          brokenMoves++;
          brokenLossSum += t.choice!.lossCp;
          if (t.choice!.reason == PolicyReason.blunder) blunders++;
          if (t.choice!.index != 0) nonBest++;
        }
        game.play(t.move!);
      }
      final winner = game.result?.winner;
      if (winner == null) {
        draws++;
      } else if (winner == brokenSide) {
        brokenWins++;
      } else {
        normalWins++;
      }
      final rec = {
        'game': i + 1,
        'brokenSide': brokenSide.name,
        'winner': winner?.name,
        'reason': game.result?.reason.name ?? 'maxPlies',
        'plies': game.moves.length,
      };
      records.add(rec);
      // ignore: avoid_print
      print('SELFPLAY ${jsonEncode(rec)} score broken=$brokenWins normal=$normalWins draw=$draws '
          'elapsed=${sw.elapsed.inSeconds}s');
    }

    final report = {
      'games': games,
      'movetimeMs': movetime,
      'broken': {'composure': brokenComposure, 'panic': brokenPanic},
      'brokenWins': brokenWins,
      'normalWins': normalWins,
      'draws': draws,
      'brokenWinRate': brokenWins / games,
      'brokenAvgLossCp': brokenMoves == 0 ? 0 : brokenLossSum / brokenMoves,
      'brokenNonBestRate': brokenMoves == 0 ? 0 : nonBest / brokenMoves,
      'brokenBlunderRate': brokenMoves == 0 ? 0 : blunders / brokenMoves,
      'elapsedSec': sw.elapsed.inSeconds,
      'records': records,
    };
    final dir = await getApplicationDocumentsDirectory();
    File('${dir.path}/selfplay_report_c${brokenComposure}_p$brokenPanic.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print('SELFPLAY_REPORT ${jsonEncode({...report, 'records': null})}');
    expect(brokenWins / games, lessThanOrEqualTo(expectMaxWinRate));
  }, timeout: const Timeout(Duration(hours: 2)));
}
