import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/move_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('棋力レベルの数値は shared/skill_levels.json と一致する（Python 版と共通）', () {
    final json = jsonDecode(File('shared/skill_levels.json').readAsStringSync()) as Map<String, dynamic>;
    final levels = (json['levels'] as Map).cast<String, dynamic>();
    expect(levels.keys.toSet(), SkillLevel.values.map((l) => l.name).toSet());
    for (final l in SkillLevel.values) {
      final d = (levels[l.name] as Map).cast<String, dynamic>();
      expect(d['label'], l.label);
      expect((d['temp'] as num).toDouble(), l.temp);
      expect(d['multi_pv'], l.multiPv);
      expect((d['movetime_scale'] as num).toDouble(), l.movetimeScale);
    }
  });

  test('レベルが上がるほど最善から離れにくく、長く考える', () {
    const calm = MindState();
    var prev = double.infinity;
    var prevTime = -1;
    for (final l in SkillLevel.values) {
      final t = temperatureFor(calm, level: l);
      final ms = movetimeFor(calm, level: l);
      expect(t, lessThan(prev), reason: '${l.name} の温度');
      expect(ms, greaterThan(prevTime), reason: '${l.name} の思考時間');
      prev = t;
      prevTime = ms;
    }
  });

  test('感情の分はレベルの上に足される', () {
    const shaken = MindState(composure: 0.2, panic: 0.8);
    expect(
      temperatureFor(shaken, level: SkillLevel.allOut),
      SkillLevel.allOut.temp + PolicyParams.tempComposure * 0.8 + PolicyParams.tempPanic * 0.8,
    );
    expect(multiPvFor(shaken, level: SkillLevel.normal), SkillLevel.normal.multiPv + PolicyParams.panicMultiPvBonus);
    expect(multiPvFor(const MindState(), level: SkillLevel.normal), SkillLevel.normal.multiPv);
  });
}
