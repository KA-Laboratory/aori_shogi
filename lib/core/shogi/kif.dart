import 'game.dart';
import 'move.dart';
import 'position.dart';
import 'square.dart';

const _zenkaku = ['', '１', '２', '３', '４', '５', '６', '７', '８', '９'];
const _kanjiRank = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 1手を KIF 形式の指し手文字列にする（例: ７六歩(77)、同　角成(88)、５五角打）。
String kifMoveText(Position before, Move move, {Move? previous}) {
  final sb = StringBuffer();
  if (previous != null && previous.to == move.to) {
    sb.write('同　');
  } else {
    sb.write('${_zenkaku[fileOf(move.to)]}${_kanjiRank[rankOf(move.to)]}');
  }
  if (move.isDrop) {
    sb.write('${move.drop!.kifName}打');
    return sb.toString();
  }
  final piece = before.board[move.from!]!;
  sb.write(piece.type.kifName);
  if (move.promote) {
    sb.write('成');
  } else if (piece.type.canPromote &&
      (Position.inPromotionZone(move.from!, piece.side) ||
          Position.inPromotionZone(move.to, piece.side))) {
    sb.write('不成');
  }
  sb.write('(${fileOf(move.from!)}${rankOf(move.from!)})');
  return sb.toString();
}

String toKif(
  ShogiGame game, {
  String blackName = '先手',
  String whiteName = '後手',
  DateTime? startedAt,
}) {
  final sb = StringBuffer()
    ..writeln('# ---- 煽り将棋 棋譜ファイル ----');
  if (startedAt != null) {
    final d = startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    sb.writeln(
        '開始日時：${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}');
  }
  final start = game.startPosition;
  if (start.repetitionKey == Position.initial().repetitionKey) {
    sb.writeln('手合割：平手');
  } else {
    sb.writeln('手合割：平手');
    sb.writeln('#SFEN：${start.toSfen()}');
  }
  sb
    ..writeln('先手：$blackName')
    ..writeln('後手：$whiteName')
    ..writeln('手数----指手---------消費時間--');

  final moves = game.moves;
  final positions = game.positions;
  for (var i = 0; i < moves.length; i++) {
    final text = kifMoveText(positions[i], moves[i],
        previous: i > 0 ? moves[i - 1] : null);
    sb.writeln('${(i + 1).toString().padLeft(4)} ${_pad(text, 14)}( 0:00/00:00:00)');
  }
  final result = game.result;
  if (result != null) {
    final n = moves.length + 1;
    switch (result.reason) {
      case GameEndReason.resign:
        sb.writeln('${n.toString().padLeft(4)} 投了');
        sb.writeln('まで${moves.length}手で${result.winner!.label}の勝ち');
      case GameEndReason.checkmate:
        sb.writeln('${n.toString().padLeft(4)} 詰み');
        sb.writeln('まで${moves.length}手で${result.winner!.label}の勝ち');
      case GameEndReason.repetition:
        sb.writeln('${n.toString().padLeft(4)} 千日手');
        sb.writeln('まで${moves.length}手で千日手');
      case GameEndReason.perpetualCheck:
        sb.writeln('${n.toString().padLeft(4)} 反則負け');
        sb.writeln('まで${moves.length}手で${result.winner!.label}の勝ち（連続王手の千日手）');
    }
  }
  return sb.toString();
}

String _pad(String s, int width) {
  // 全角を2幅として右を空白で埋める。
  var w = 0;
  for (final r in s.runes) {
    w += r < 0x80 ? 1 : 2;
  }
  return w >= width ? '$s ' : s + ' ' * (width - w);
}

