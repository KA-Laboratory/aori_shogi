/// 入玉宣言法（24点法の一般的な運用＝宣言側 先手28点・後手27点）。
///
/// 条件（すべて満たすと宣言側の勝ち）:
/// 1. 宣言側の玉が敵陣（3段目以内）に入っている
/// 2. 宣言側の玉に王手がかかっていない
/// 3. 玉を除く宣言側の駒が、敵陣に10枚以上ある
/// 4. 大駒5点・小駒1点で数えた点数（敵陣内の駒＋持ち駒、玉は数えない）が
///    先手なら28点以上、後手なら27点以上
/// 5. 詰んでいない（詰みは通常の終局が先に成立する）
library;

import 'piece.dart';
import 'position.dart';
import 'square.dart';

/// 宣言の可否と、満たせていない条件。
class Declaration {
  const Declaration({
    required this.side,
    required this.inEnemyCamp,
    required this.notInCheck,
    required this.piecesInCamp,
    required this.points,
    required this.requiredPoints,
  });

  final Side side;

  /// 玉が敵陣にいるか。
  final bool inEnemyCamp;
  final bool notInCheck;

  /// 敵陣にいる玉以外の駒の数。
  final int piecesInCamp;

  /// 点数（大駒5点・小駒1点）。
  final int points;
  final int requiredPoints;

  bool get enoughPieces => piecesInCamp >= 10;
  bool get enoughPoints => points >= requiredPoints;
  bool get canDeclare => inEnemyCamp && notInCheck && enoughPieces && enoughPoints;

  /// 満たせていない条件を日本語で並べる（画面にそのまま出せる）。
  List<String> get missing => [
    if (!inEnemyCamp) '玉が敵陣に入っていない',
    if (!notInCheck) '王手がかかっている',
    if (!enoughPieces) '敵陣の駒が足りない（$piecesInCamp枚／10枚）',
    if (!enoughPoints) '点数が足りない（$points点／$requiredPoints点）',
  ];
}

int _pointOf(PieceType t) => switch (t) {
  PieceType.bishop || PieceType.rook || PieceType.horse || PieceType.dragon => 5,
  _ => 1,
};

/// [side]（省略時は手番側）が入玉宣言できるかを調べる。
Declaration checkDeclaration(Position pos, {Side? side}) {
  final me = side ?? pos.turn;
  // 敵陣: 先手は1〜3段目、後手は7〜9段目
  bool inCamp(int sq) => me == Side.black ? rankOf(sq) <= 3 : rankOf(sq) >= 7;

  var kingInCamp = false;
  var pieces = 0;
  var points = 0;
  for (var sq = 0; sq < 81; sq++) {
    final p = pos.board[sq];
    if (p == null || p.side != me || !inCamp(sq)) continue;
    if (p.type == PieceType.king) {
      kingInCamp = true;
      continue;
    }
    pieces++;
    points += _pointOf(p.type);
  }
  for (final t in [
    PieceType.pawn,
    PieceType.lance,
    PieceType.knight,
    PieceType.silver,
    PieceType.gold,
    PieceType.bishop,
    PieceType.rook,
  ]) {
    points += pos.handCount(me, t) * _pointOf(t);
  }
  return Declaration(
    side: me,
    inEnemyCamp: kingInCamp,
    notInCheck: !pos.inCheck(me),
    piecesInCamp: pieces,
    points: points,
    requiredPoints: me == Side.black ? 28 : 27,
  );
}
