import 'dart:async';

import 'package:aori_shogi/core/llm/single_flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('走っている間は断る（実機の SIGSEGV はこれが無くて起きた）', () {
    final gate = SingleFlight();
    expect(gate.tryEnter(), isTrue);
    expect(gate.tryEnter(), isFalse);
    expect(gate.tryEnter(), isFalse);
    expect(gate.dropped, 2);
    gate.leave();
    expect(gate.tryEnter(), isTrue);
    expect(gate.dropped, 2);
  });

  test('投げっぱなしで重ねても、実際に走るのは1つだけ', () async {
    final gate = SingleFlight();
    var ran = 0;
    final finish = Completer<void>();

    Future<void> attempt() async {
      if (!gate.tryEnter()) return;
      ran++;
      try {
        await finish.future;
      } finally {
        gate.leave();
      }
    }

    // GameController._upgradeWithLlm と同じで、待たずに続けて投げる
    final a = attempt();
    final b = attempt();
    final c = attempt();
    await Future<void>.delayed(Duration.zero);
    expect(ran, 1);
    expect(gate.dropped, 2);

    finish.complete();
    await Future.wait([a, b, c]);
    expect(gate.busy, isFalse);
  });

  test('失敗しても門は開く', () async {
    final gate = SingleFlight();
    expect(gate.tryEnter(), isTrue);
    try {
      throw StateError('生成に失敗');
    } on StateError {
      // 呼び出し側は握りつぶす
    } finally {
      gate.leave();
    }
    expect(gate.tryEnter(), isTrue);
  });
}
