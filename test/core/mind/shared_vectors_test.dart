// Python 版（python/aori_lab/mind.py）と数値が一致することを共通ベクタで検証する。
import 'dart:convert';
import 'dart:io';

import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/move_policy.dart';
import 'package:aori_shogi/core/mind/taunts.dart';
import 'package:flutter_test/flutter_test.dart';

MindState _state(Map<String, dynamic> j) => MindState(
      composure: (j['composure'] as num).toDouble(),
      hubris: (j['hubris'] as num).toDouble(),
      panic: (j['panic'] as num).toDouble(),
      resistance: (j['resistance'] as num).toDouble(),
      stance: Stance.values.byName(j['stance'] as String),
      coverUpTurns: j['coverUpTurns'] as int,
      looseLips: (j['looseLips'] as num).toDouble(),
      suspicion: (j['suspicion'] as num).toDouble(),
      praiseStreak: j['praiseStreak'] as int,
    );

void main() {
  final data = jsonDecode(File('shared/mind_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final cases = (data['cases'] as List).cast<Map<String, dynamic>>();

  test('共通ベクタ ${cases.length} 件が Python 版と一致', () {
    for (final (i, c) in cases.indexed) {
      final s = _state(c['in'] as Map<String, dynamic>);
      expect(s.mood.name, (c['in'] as Map)['mood'], reason: 'case $i mood(in)');
      final MindState out;
      if (c['op'] == 'update') {
        out = updateOnAiTurn(s, evalAi: c['evalAi'] as int, lastAiMoveLossCp: c['loss'] as int?);
      } else {
        final prev = c['prev'] == null ? null : TauntKind.values.byName(c['prev'] as String);
        out = applyTaunt(s, TauntKind.values.byName(c['kind'] as String), (c['truth'] as num).toDouble(),
                previousKind: prev, intensity: (c['intensity'] as num).toDouble())
            .after;
      }
      final e = c['out'] as Map<String, dynamic>;
      expect(out.composure, closeTo((e['composure'] as num).toDouble(), 1e-9), reason: 'case $i composure');
      expect(out.hubris, closeTo((e['hubris'] as num).toDouble(), 1e-9), reason: 'case $i hubris');
      expect(out.panic, closeTo((e['panic'] as num).toDouble(), 1e-9), reason: 'case $i panic');
      expect(out.resistance, closeTo((e['resistance'] as num).toDouble(), 1e-9), reason: 'case $i resistance');
      expect(out.stance.name, e['stance'], reason: 'case $i stance');
      expect(out.coverUpTurns, e['coverUpTurns'], reason: 'case $i cover');
      expect(out.mood.name, e['mood'], reason: 'case $i mood');
      expect(out.looseLips, closeTo((e['looseLips'] as num).toDouble(), 1e-9), reason: 'case $i lips');
      expect(out.suspicion, closeTo((e['suspicion'] as num).toDouble(), 1e-9), reason: 'case $i suspicion');
      expect(out.praiseStreak, e['praiseStreak'], reason: 'case $i streak');
      expect(movetimeFor(s), c['movetime'], reason: 'case $i movetime');
      expect(multiPvFor(s), c['multipv'], reason: 'case $i multipv');
      expect(temperatureFor(s), closeTo((c['temperature'] as num).toDouble(), 1e-9), reason: 'case $i temp');
    }
  });
}
