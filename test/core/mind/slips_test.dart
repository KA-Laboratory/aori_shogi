import 'dart:math' as math;

import 'package:aori_shogi/core/dialogue/intent.dart';
import 'package:aori_shogi/core/engine/usi_protocol.dart';
import 'package:aori_shogi/core/mind/mind_state.dart';
import 'package:aori_shogi/core/mind/negotiation.dart';
import 'package:aori_shogi/core/mind/slips.dart';
import 'package:aori_shogi/core/mind/taunts.dart';
import 'package:aori_shogi/core/shogi/shogi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('褒め倒すと口が軽くなり、やがて警戒される', () {
    var m = const MindState();
    for (var i = 0; i < 6; i++) {
      m = applyTaunt(m, TauntKind.praise, 1.0).after;
    }
    expect(m.praiseStreak, 6);
    expect(m.looseLips, greaterThan(0.6));
    expect(m.suspicion, greaterThan(0.2));
    expect(applyTaunt(m, TauntKind.blunderCall, 0).after.praiseStreak, 0);
  });

  test('ボロ: 本当はエンジン最善、嘘は最悪候補', () {
    var p = Position.initial();
    for (final u in ['7g7f', '3c3d']) {
      p = p.play(Move.fromUsi(u));
    }
    const cands = [
      Candidate(usi: '2g2f', scoreCp: 50, pv: ['2g2f', '8c8d']),
      Candidate(usi: '8h2b+', scoreCp: 20, pv: ['8h2b+', '3a2b']),
      Candidate(usi: '1g1f', scoreCp: -120, pv: ['1g1f', '4a3b']),
    ];
    final rng = math.Random(0);
    var t = 0, f = 0;
    for (var i = 0; i < 400; i++) {
      final s = decideSlip(
        mind: const MindState(looseLips: 1, panic: 0.9, suspicion: 0.5),
        position: p,
        playerCandidates: cands,
        aiLossCp: 0,
        prevUsi: '3c3d',
        rng: rng,
      );
      if (s?.kind == SlipKind.fear) {
        expect(s!.moveUsi, s.truthful ? '2g2f' : '1g1f');
        expect(s.fact, contains('こわい'));
        s.truthful ? t++ : f++;
      }
      if (s?.kind == SlipKind.plan) expect(s!.fact, contains('次は'));
    }
    expect(t, greaterThan(0));
    expect(f, greaterThan(0));
    expect(
      slipChance(const MindState(looseLips: 0.9, hubris: 0.9)),
      greaterThan(slipChance(const MindState(looseLips: 0, hubris: 0.3)) * 5),
    );
  });

  test('キーワード分類', () {
    expect(classifyKeywords('次どこ指すつもり？', hasPendingOffer: false).kind, IntentKind.question);
    expect(classifyKeywords('その角タダじゃん', hasPendingOffer: false).kind, IntentKind.hangingPiece);
    expect(classifyKeywords('待った！今のなし', hasPendingOffer: false).request, IntentRequest.undo);
    expect(classifyKeywords('ヒント教えて', hasPendingOffer: false).request, IntentRequest.hint);
    expect(classifyKeywords('いいよ', hasPendingOffer: true).request, IntentRequest.accept);
    expect(classifyKeywords('だめ', hasPendingOffer: true).request, IntentRequest.decline);
  });

  test('交渉の条件', () {
    const smug = MindState(stance: Stance.dominant, hubris: 0.8);
    final offers = availableOffers(
      NegotiationContext(mind: smug, ply: 10, playerGainCp: 300, aiLossCp: 200, lastOfferPly: -99, counts: const {}),
    );
    expect(offers, containsAll([OfferKind.offerPlayerUndo, OfferKind.requestRedo]));
    expect(requestAllowed(PlayerRequest.undo, smug, evalAi: 500, undoCount: 0, hasCandidates: true), isTrue);
    expect(
      requestAllowed(PlayerRequest.undo, const MindState(), evalAi: 0, undoCount: 0, hasCandidates: true),
      isFalse,
    );
    expect(
      requestAllowed(PlayerRequest.resign, const MindState(), evalAi: -2500, undoCount: 0, hasCandidates: true),
      isTrue,
    );
  });
}
