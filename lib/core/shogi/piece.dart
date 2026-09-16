/// 駒と手番の定義。
enum Side {
  black, // 先手
  white; // 後手

  Side get opponent => this == Side.black ? Side.white : Side.black;
  String get mark => this == Side.black ? '▲' : '△';
  String get label => this == Side.black ? '先手' : '後手';
}

enum PieceType {
  pawn('P', '歩', '歩'),
  lance('L', '香', '香'),
  knight('N', '桂', '桂'),
  silver('S', '銀', '銀'),
  gold('G', '金', '金'),
  bishop('B', '角', '角'),
  rook('R', '飛', '飛'),
  king('K', '玉', '玉'),
  proPawn('+P', 'と', 'と'),
  proLance('+L', '成香', '杏'),
  proKnight('+N', '成桂', '圭'),
  proSilver('+S', '成銀', '全'),
  horse('+B', '馬', '馬'),
  dragon('+R', '龍', '龍');

  const PieceType(this.sfen, this.kifName, this.boardChar);

  /// SFEN表記（先手＝大文字）。
  final String sfen;

  /// KIFで使う駒名。
  final String kifName;

  /// 盤面表示用の1文字。
  final String boardChar;

  bool get isPromoted => index >= PieceType.proPawn.index;

  PieceType? get promoted => switch (this) {
        PieceType.pawn => PieceType.proPawn,
        PieceType.lance => PieceType.proLance,
        PieceType.knight => PieceType.proKnight,
        PieceType.silver => PieceType.proSilver,
        PieceType.bishop => PieceType.horse,
        PieceType.rook => PieceType.dragon,
        _ => null,
      };

  PieceType get base => switch (this) {
        PieceType.proPawn => PieceType.pawn,
        PieceType.proLance => PieceType.lance,
        PieceType.proKnight => PieceType.knight,
        PieceType.proSilver => PieceType.silver,
        PieceType.horse => PieceType.bishop,
        PieceType.dragon => PieceType.rook,
        _ => this,
      };

  bool get canPromote => promoted != null;

  static PieceType? fromSfenLetter(String upper) {
    for (final t in PieceType.values) {
      if (t.sfen == upper) return t;
    }
    return null;
  }
}

/// 持ち駒になりうる駒（SFENの持ち駒並び順：飛角金銀桂香歩）。
const List<PieceType> handOrder = [
  PieceType.rook,
  PieceType.bishop,
  PieceType.gold,
  PieceType.silver,
  PieceType.knight,
  PieceType.lance,
  PieceType.pawn,
];

class Piece {
  const Piece(this.type, this.side);

  final PieceType type;
  final Side side;

  String get sfen =>
      side == Side.black ? type.sfen : type.sfen.toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is Piece && other.type == type && other.side == side;

  @override
  int get hashCode => type.index * 2 + side.index;

  @override
  String toString() => sfen;
}
