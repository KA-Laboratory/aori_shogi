import 'dart:io';
import 'dart:math' as math;

import 'package:aori_shogi/core/dialogue/line_library.dart';
import 'package:aori_shogi/core/engine/usi_protocol.dart';
import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/move_policy.dart';
import 'package:aori_shogi/core/mind/taunts.dart';
import 'package:aori_shogi/core/mind/truth_judge.dart';
import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mood 表', () {
    test('取り繕いが最優先', () {
      expect(const MindState(coverUpTurns: 1, panic: 0.9).mood, Mood.coverUp);
    });
    test('大混乱', () {
      expect(const MindState(panic: 0.75).mood, Mood.meltdown);
      expect(const MindState(stance: Stance.losing, composure: 0.29, panic: 0).mood, Mood.meltdown);
    });
    test('動揺', () {
      expect(const MindState(panic: 0.45).mood, Mood.rattled);
      expect(const MindState(composure: 0.44, panic: 0).mood, Mood.rattled);
      expect(const MindState(stance: Stance.losing, composure: 0.3, panic: 0).mood, Mood.rattled);
    });
    test('ドヤ顔と平静', () {
      expect(const MindState(stance: Stance.dominant, hubris: 0.5).mood, Mood.smug);
      expect(const MindState(stance: Stance.dominant, hubris: 0.49).mood, Mood.composed);
      expect(const MindState(stance: Stance.even, hubris: 0.9).mood, Mood.composed);
    });
  });

  group('毎手の更新', () {
    test('形勢の閾値', () {
      expect(Stance.fromEval(300), Stance.dominant);
      expect(Stance.fromEval(299), Stance.even);
      expect(Stance.fromEval(-300), Stance.losing);
    });
    test('優勢で慢心、劣勢で焦り、自然回復とクリップ', () {
      final d = updateOnAiTurn(const MindState(), evalAi: 500);
      expect(d.hubris, closeTo(0.35, 1e-9));
      expect(d.composure, closeTo(0.83, 1e-9));
      expect(d.panic, closeTo(0.07, 1e-9));
      final l = updateOnAiTurn(const MindState(), evalAi: -500);
      expect(l.panic, closeTo(0.13, 1e-9));
      expect(l.hubris, closeTo(0.27, 1e-9));
      final top = updateOnAiTurn(const MindState(composure: 0.99), evalAi: 0);
      expect(top.composure, 1.0);
    });
    test('取り繕いは評価損200以上で2手', () {
      var s = updateOnAiTurn(const MindState(), evalAi: 0, lastAiMoveLossCp: 200);
      expect(s.coverUpTurns, 2);
      s = updateOnAiTurn(s, evalAi: 0);
      expect(s.coverUpTurns, 1);
      s = updateOnAiTurn(s, evalAi: 0);
      expect(s.coverUpTurns, 0);
    });
  });

  group('煽りの効果', () {
    test('図星は効く、外れは余裕', () {
      final hit = applyTaunt(const MindState(), TauntKind.blunderCall, 1.0);
      expect(hit.after.composure, closeTo(0.55, 1e-9));
      expect(hit.after.panic, closeTo(0.30, 1e-9));
      expect(hit.hit, isTrue);
      final miss = applyTaunt(const MindState(), TauntKind.blunderCall, 0);
      expect(miss.after.composure, closeTo(0.85, 1e-9));
      expect(miss.hit, isFalse);
    });
    test('同じ煽りの連発は耐性で効きが落ちる', () {
      final first = applyTaunt(const MindState(), TauntKind.threat, 1.0);
      expect(first.after.resistance, 0); // 前回なし → -0.05 でクリップ
      final a = applyTaunt(first.after, TauntKind.threat, 1.0, previousKind: TauntKind.threat);
      expect(a.after.resistance, closeTo(0.15, 1e-9));
      final b = applyTaunt(a.after, TauntKind.threat, 1.0, previousKind: TauntKind.threat);
      expect(b.panicDelta, lessThan(a.panicDelta));
    });
    test('慢心中の揶揄は逆効果、褒めると慢心', () {
      final m = applyTaunt(const MindState(hubris: 0.7), TauntKind.mock, TauntTable.mockTruth);
      expect(m.composureDelta, greaterThan(0));
      final p = applyTaunt(const MindState(), TauntKind.praise, 1.0);
      expect(p.after.hubris, closeTo(0.4, 1e-9));
    });
  });

  group('図星判定', () {
    final pos = Position.initial();
    TauntContext ctx({int? loss, List<Candidate> c = const []}) =>
        TauntContext(position: pos, playerCandidates: c, lastAiMoveLossCp: loss);
    test('悪手指摘', () {
      expect(judgeTruth(TauntKind.blunderCall, ctx(loss: 150)), 1.0);
      expect(judgeTruth(TauntKind.blunderCall, ctx(loss: 60)), 0.5);
      expect(judgeTruth(TauntKind.blunderCall, ctx(loss: 10)), 0);
    });
    test('駒浮き: 最善が駒取りか', () {
      // 7g7f 3c3d の後、角交換 8h2b+ は駒取り。
      var p = Position.initial();
      for (final m in ['7g7f', '3c3d']) {
        p = p.play(Move.fromUsi(m));
      }
      final capture = TauntContext(
        position: p,
        playerCandidates: const [Candidate(usi: '8h2b+', scoreCp: 200)],
      );
      expect(judgeTruth(TauntKind.hangingPiece, capture), 1.0);
      final quiet = TauntContext(
        position: p,
        playerCandidates: const [Candidate(usi: '2g2f', scoreCp: 200)],
      );
      expect(judgeTruth(TauntKind.hangingPiece, quiet), 0);
    });
    test('詰めろ', () {
      expect(judgeTruth(TauntKind.threat, ctx(c: const [Candidate(usi: '2g2f', mateIn: 5)])), 1.0);
      expect(judgeTruth(TauntKind.threat, ctx(c: const [Candidate(usi: '2g2f', scoreCp: 20)])), 0);
    });
  });

  group('着手変調', () {
    final pos = Position.initial();
    const cands = [
      Candidate(usi: '2g2f', scoreCp: 50),
      Candidate(usi: '7g7f', scoreCp: 40),
      Candidate(usi: '5g5f', scoreCp: -100),
      Candidate(usi: '1g1f', scoreCp: -350),
      Candidate(usi: '9g9f', scoreCp: -500),
    ];

    test('変調なしは常に最善', () {
      final r = math.Random(1);
      for (var i = 0; i < 20; i++) {
        expect(chooseMove(candidates: cands, pos: pos, mind: const MindState(), rng: r, modulate: false).index, 0);
      }
    });

    test('同じシードなら同じ結果', () {
      List<int> run() {
        final r = math.Random(42);
        return [
          for (var i = 0; i < 30; i++) chooseMove(candidates: cands, pos: pos, mind: const MindState(), rng: r).index,
        ];
      }

      expect(run(), run());
    });

    test('崩れるほど平均評価損が増える', () {
      double avgLoss(MindState m) {
        final r = math.Random(7);
        var sum = 0;
        for (var i = 0; i < 2000; i++) {
          sum += chooseMove(candidates: cands, pos: pos, mind: m, rng: r).lossCp;
        }
        return sum / 2000;
      }

      final calm = avgLoss(const MindState(composure: 1, panic: 0, hubris: 0));
      final normal = avgLoss(const MindState());
      final broken = avgLoss(const MindState(composure: 0.2, panic: 0.8, hubris: 0));
      expect(calm, lessThan(normal));
      expect(normal, lessThan(broken));
      expect(broken, greaterThan(100));
    });

    test('詰みは逃さない（大混乱でなければ）', () {
      const mate = [Candidate(usi: 'G*5b', mateIn: 1), Candidate(usi: '2g2f', scoreCp: 3000)];
      final r = math.Random(3);
      for (var i = 0; i < 50; i++) {
        final c = chooseMove(candidates: mate, pos: pos, mind: const MindState(composure: 0, panic: 0.85), rng: r);
        expect(c.reason, PolicyReason.mate);
      }
    });

    test('思考時間と温度', () {
      expect(movetimeFor(const MindState(composure: 1)), 1500);
      expect(movetimeFor(const MindState(composure: 0)), 600);
      expect(temperatureFor(const MindState(composure: 0.2, panic: 0.8)), closeTo(590, 1e-9));
      expect(multiPvFor(const MindState(panic: 0.8)), 8);
    });
  });

  group('セリフ', () {
    final lib = LineLibrary.fromJsonString(File('assets/lines/gunshi_lines.json').readAsStringSync());
    test('全 mood に move と taunt_hit がある', () {
      for (final m in Mood.values) {
        expect(lib.linesFor(m, LineTrigger.move), isNotEmpty, reason: m.name);
        expect(lib.linesFor(m, LineTrigger.tauntHit), isNotEmpty, reason: m.name);
      }
    });
    test('無い組み合わせは composed にフォールバック、置換', () {
      expect(lib.linesFor(Mood.coverUp, LineTrigger.win), lib.linesFor(Mood.composed, LineTrigger.win));
      final s = lib.pick(Mood.composed, LineTrigger.move, math.Random(0), vars: {'move': '７六歩'});
      expect(s, isNot(contains('{move}')));
    });
  });
}
