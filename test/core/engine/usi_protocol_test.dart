import 'package:aori_shogi/core/engine/usi_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('info cp / multipv / pv', () {
    final i = EngineInfo.parse(
      'info depth 12 seldepth 15 score cp -34 nodes 123456 nps 1000 multipv 2 pv 7g7f 3c3d 2g2f',
    )!;
    expect(i.depth, 12);
    expect(i.scoreCp, -34);
    expect(i.multiPv, 2);
    expect(i.nodes, 123456);
    expect(i.pv, ['7g7f', '3c3d', '2g2f']);
  });

  test('info mate と bound', () {
    expect(EngineInfo.parse('info depth 3 score mate 5 pv G*5b')!.mateIn, 5);
    expect(EngineInfo.parse('info score mate -2 pv 5a4b')!.mateIn, -2);
    expect(EngineInfo.parse('info score mate + pv P*1b')!.mateIn, 1);
    final b = EngineInfo.parse('info depth 5 score cp 100 lowerbound pv 2g2f')!;
    expect(b.bound, 'lowerbound');
    expect(b.pv, ['2g2f']);
  });

  test('info string は無視', () {
    expect(EngineInfo.parse('info string loading eval file'), isNull);
    expect(EngineInfo.parse('info depth 1 nodes 20'), isNull);
  });

  test('bestmove', () {
    final b = BestMove.parse('bestmove 7g7f ponder 3c3d')!;
    expect(b.move, '7g7f');
    expect(b.ponder, '3c3d');
    expect(BestMove.parse('bestmove resign')!.isResign, isTrue);
  });

  test('候補手の収集', () {
    final c = CandidateCollector()
      ..add(EngineInfo.parse('info depth 1 score cp 50 multipv 1 pv 2g2f')!)
      ..add(EngineInfo.parse('info depth 1 score cp 40 multipv 2 pv 7g7f')!)
      ..add(EngineInfo.parse('info depth 2 score cp 60 multipv 1 pv 7g7f 3c3d')!)
      ..add(EngineInfo.parse('info depth 2 score cp 30 lowerbound multipv 2 pv 2g2f')!);
    expect(c.candidates.map((e) => e.usi), ['7g7f', '7g7f']);
    expect(c.candidates.first.scoreCp, 60);
    expect(c.candidates[1].scoreCp, 40);
    expect(c.depth, 2);
  });
}
