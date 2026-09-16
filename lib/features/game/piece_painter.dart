import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/shogi/shogi.dart';

/// 駒の大きさ（玉を1.0とした比率）。実物の駒の大小に合わせる。
double pieceScale(PieceType t) => switch (t.base) {
      PieceType.king => 1.0,
      PieceType.rook || PieceType.bishop => 0.96,
      PieceType.gold || PieceType.silver => 0.92,
      PieceType.knight => 0.88,
      PieceType.lance => 0.86,
      PieceType.pawn => 0.82,
      _ => 0.9,
    };

/// 五角形の将棋駒をコードで描く。後手の駒は180度回転。
class ShogiPiece extends StatelessWidget {
  const ShogiPiece({
    super.key,
    required this.type,
    required this.side,
    required this.size,
    this.highlighted = false,
  });

  final PieceType type;
  final Side side;

  /// マス（または置き場所）の一辺。
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final s = size * pieceScale(type);
    final painted = CustomPaint(
      size: Size(s * 0.86, s * 0.94),
      painter: _PiecePainter(type: type, highlighted: highlighted),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: side == Side.white
            ? Transform.rotate(angle: math.pi, child: painted)
            : painted,
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({required this.type, required this.highlighted});

  final PieceType type;
  final bool highlighted;

  static const _woodLight = Color(0xFFF8E3AE);
  static const _woodDark = Color(0xFFE0B665);
  static const _edge = Color(0xFF7A5A2E);

  Path _shape(Size sz) {
    final w = sz.width, h = sz.height;
    return Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.84, h * 0.17)
      ..lineTo(w * 0.98, h)
      ..lineTo(w * 0.02, h)
      ..lineTo(w * 0.16, h * 0.17)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size sz) {
    final path = _shape(sz);
    canvas.drawShadow(path, Colors.black, sz.height * 0.06, false);
    final rect = Offset.zero & sz;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlighted
              ? const [Color(0xFFFFF1C9), Color(0xFFF2C66F)]
              : const [_woodLight, _woodDark],
        ).createShader(rect),
    );
    // 木目っぽい細線
    final grain = Paint()
      ..color = _edge.withValues(alpha: 0.10)
      ..strokeWidth = sz.width * 0.012;
    canvas.save();
    canvas.clipPath(path);
    for (var i = 1; i < 6; i++) {
      final x = sz.width * (0.12 + i * 0.15);
      canvas.drawLine(Offset(x, 0), Offset(x - sz.width * 0.05, sz.height), grain);
    }
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, sz.width * 0.035)
        ..color = highlighted ? const Color(0xFF1E88E5) : _edge,
    );

    final label = type.boardChar;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: sz.height * 0.52,
          height: 1.0,
          fontWeight: FontWeight.w900,
          fontFamily: 'serif',
          color: type.isPromoted ? const Color(0xFFC62828) : const Color(0xFF1B1208),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((sz.width - tp.width) / 2, sz.height * 0.58 - tp.height / 2));
  }

  @override
  bool shouldRepaint(_PiecePainter old) => old.type != type || old.highlighted != highlighted;
}
