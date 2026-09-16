/// USI の出力行（info / bestmove）の解析。
class EngineInfo {
  const EngineInfo({
    this.depth,
    this.scoreCp,
    this.mateIn,
    this.multiPv = 1,
    this.nodes,
    this.pv = const [],
    this.bound,
  });

  final int? depth;

  /// 手番側から見た評価値（センチポーン）。詰みのときは null。
  final int? scoreCp;

  /// 詰み手数。正=手番側が詰ます、負=詰まされる。
  final int? mateIn;
  final int multiPv;
  final int? nodes;
  final List<String> pv;

  /// 'lowerbound' / 'upperbound'（確定値でないとき）。
  final String? bound;

  bool get hasScore => scoreCp != null || mateIn != null;

  /// 並べ替え用の数値（詰みは ±(100000 - 手数)）。
  int get sortScore {
    final m = mateIn;
    if (m != null) return m > 0 ? 100000 - m : -100000 - m;
    return scoreCp ?? 0;
  }

  static EngineInfo? parse(String line) {
    final t = line.trim().split(RegExp(r'\s+'));
    if (t.isEmpty || t.first != 'info') return null;
    int? depth, cp, mate, nodes;
    String? bound;
    var multiPv = 1;
    var pv = <String>[];
    var hasScoreOrPv = false;
    for (var i = 1; i < t.length; i++) {
      switch (t[i]) {
        case 'depth':
          depth = int.tryParse(_at(t, ++i));
        case 'nodes':
          nodes = int.tryParse(_at(t, ++i));
        case 'multipv':
          multiPv = int.tryParse(_at(t, ++i)) ?? 1;
        case 'score':
          final kind = _at(t, ++i);
          final raw = _at(t, ++i);
          hasScoreOrPv = true;
          if (kind == 'cp') {
            cp = int.tryParse(raw);
          } else if (kind == 'mate') {
            // "mate +" / "mate -" は手数不明の詰み。
            if (raw == '+' || raw == '-') {
              mate = raw == '+' ? 1 : -1;
            } else {
              mate = int.tryParse(raw);
              if (mate == 0) mate = raw.startsWith('-') ? -1 : 1;
            }
          }
          if (i + 1 < t.length &&
              (t[i + 1] == 'lowerbound' || t[i + 1] == 'upperbound')) {
            bound = t[++i];
          }
        case 'pv':
          pv = t.sublist(i + 1);
          hasScoreOrPv = true;
          i = t.length;
        case 'string':
          return null; // info string は評価情報ではない
      }
    }
    if (!hasScoreOrPv) return null;
    return EngineInfo(
      depth: depth,
      scoreCp: cp,
      mateIn: mate,
      multiPv: multiPv,
      nodes: nodes,
      pv: pv,
      bound: bound,
    );
  }

  static String _at(List<String> t, int i) => i < t.length ? t[i] : '';
}

/// bestmove 行。move は USI 指し手、'resign'、'win' のいずれか。
class BestMove {
  const BestMove(this.move, {this.ponder});
  final String move;
  final String? ponder;

  bool get isResign => move == 'resign';
  bool get isWin => move == 'win';

  static BestMove? parse(String line) {
    final t = line.trim().split(RegExp(r'\s+'));
    if (t.length < 2 || t.first != 'bestmove') return null;
    final ponderIdx = t.indexOf('ponder');
    return BestMove(t[1],
        ponder: ponderIdx >= 0 && ponderIdx + 1 < t.length ? t[ponderIdx + 1] : null);
  }
}

class Candidate {
  const Candidate({required this.usi, this.scoreCp, this.mateIn, this.pv = const []});
  final String usi;
  final int? scoreCp;
  final int? mateIn;
  final List<String> pv;

  int get sortScore => EngineInfo(scoreCp: scoreCp, mateIn: mateIn).sortScore;

  @override
  String toString() =>
      '$usi(${mateIn != null ? 'mate $mateIn' : 'cp $scoreCp'})';
}

class SearchResult {
  const SearchResult({required this.bestMove, required this.candidates, this.depth});
  final BestMove bestMove;

  /// multipv 順（最善が先頭）。
  final List<Candidate> candidates;
  final int? depth;
}

/// info 行を集めて、各 multipv の最終値から候補手リストを作る。
class CandidateCollector {
  final Map<int, EngineInfo> _latest = {};
  int? _depth;

  void add(EngineInfo info) {
    if (info.pv.isEmpty || !info.hasScore) return;
    // 確定値でない行は、同じ multipv の既存値があれば採用しない。
    if (info.bound != null && _latest.containsKey(info.multiPv)) return;
    _latest[info.multiPv] = info;
    if (info.depth != null) _depth = info.depth;
  }

  List<Candidate> get candidates {
    final keys = _latest.keys.toList()..sort();
    return [
      for (final k in keys)
        Candidate(
          usi: _latest[k]!.pv.first,
          scoreCp: _latest[k]!.scoreCp,
          mateIn: _latest[k]!.mateIn,
          pv: _latest[k]!.pv,
        ),
    ];
  }

  int? get depth => _depth;
}
