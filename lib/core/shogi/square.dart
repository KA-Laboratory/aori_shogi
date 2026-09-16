/// マス番号: index = (段-1)*9 + (9-筋)。左上(9一)が0、右下(1九)が80。
/// x = 9-筋（0..8, 盤の左→右）、y = 段-1（0..8, 盤の上→下）。
int squareOf(int file, int rank) => (rank - 1) * 9 + (9 - file);
int fileOf(int sq) => 9 - sq % 9;
int rankOf(int sq) => sq ~/ 9 + 1;

const _rankLetters = 'abcdefghi';

String usiSquare(int sq) => '${fileOf(sq)}${_rankLetters[rankOf(sq) - 1]}';

int parseUsiSquare(String s) {
  if (s.length != 2) throw FormatException('bad square: $s');
  final file = int.tryParse(s[0]);
  final rank = _rankLetters.indexOf(s[1]) + 1;
  if (file == null || file < 1 || file > 9 || rank < 1) {
    throw FormatException('bad square: $s');
  }
  return squareOf(file, rank);
}
