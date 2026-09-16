import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shogi/shogi.dart';
import 'game_controller.dart';
import 'piece_painter.dart';

const _boardColor = Color(0xFFE9C47A);
const _lineColor = Color(0xFF4E3514);
const _komadaiColor = Color(0xFFC9974F);

typedef MoveCandidatesCallback = void Function(List<Move> candidates);

class BoardView extends ConsumerWidget {
  const BoardView({super.key, required this.onCandidates});

  final MoveCandidatesCallback onCandidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final pos = s.position;
    final last = s.lastMove;
    final selected = switch (s.selection) {
      SquareSelection(:final square) => square,
      _ => null,
    };
    final checkedKing = pos.inCheck(pos.turn) ? pos.kingSquare(pos.turn) : null;

    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0CF8A), _boardColor, Color(0xFFDDB05F)],
          ),
          border: Border.all(color: _lineColor, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: LayoutBuilder(builder: (context, c) {
          final cell = c.maxWidth / 9;
          return Stack(children: [
            // 星（3筋・6筋 × 三段・六段の交点）
            for (final (x, y) in const [(3, 3), (6, 3), (3, 6), (6, 6)])
              Positioned(
                left: x * cell - 3,
                top: y * cell - 3,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: _lineColor, shape: BoxShape.circle),
                ),
              ),
            for (var sq = 0; sq < 81; sq++)
              Positioned(
                left: (sq % 9) * cell,
                top: (sq ~/ 9) * cell,
                width: cell,
                height: cell,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final cands = ref.read(gameControllerProvider.notifier).tapSquare(sq);
                    if (cands.isNotEmpty) onCandidates(cands);
                  },
                  child: _Cell(
                    key: ValueKey('sq$sq'),
                    piece: pos.board[sq],
                    size: cell,
                    selected: selected == sq,
                    target: s.legalTargets.contains(sq),
                    lastMove: last?.to == sq,
                    checked: checkedKing == sq,
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.piece,
    required this.size,
    required this.selected,
    required this.target,
    required this.lastMove,
    required this.checked,
  });

  final Piece? piece;
  final double size;
  final bool selected, target, lastMove, checked;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    if (lastMove) bg = const Color(0x44D2691E);
    if (checked) bg = const Color(0x88E53935);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: _lineColor.withValues(alpha: 0.7), width: 0.6),
      ),
      child: Stack(alignment: Alignment.center, children: [
        if (piece != null)
          ShogiPiece(type: piece!.type, side: piece!.side, size: size, highlighted: selected),
        if (target)
          Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(
              color: piece == null ? const Color(0x881E88E5) : Colors.transparent,
              shape: BoxShape.circle,
              border: piece == null ? null : Border.all(color: const Color(0xCC1E88E5), width: 3),
            ),
          ),
      ]),
    );
  }
}

/// 駒台（取った駒の置き場所）。盤の上（後手）と下（先手）に置く。
class KomadaiView extends ConsumerWidget {
  const KomadaiView({super.key, required this.side, this.label});

  final Side side;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final pos = s.position;
    final selectedType = switch (s.selection) {
      HandSelection(:final type) when pos.turn == side => type,
      _ => null,
    };
    final active = pos.turn == side && !s.game.isOver;
    final types = [for (final t in handOrder) if (pos.handCount(side, t) > 0) t];
    // 後手の駒台は相手側から見た並び（右から）にする。
    final ordered = side == Side.white ? types : types.reversed.toList();

    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth - 16) / 8.5;
      return Container(
        height: slot + 20,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFD7A860), _komadaiColor]),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? const Color(0xFF1E88E5) : _lineColor, width: active ? 2 : 1),
        ),
        child: Row(
          textDirection: side == Side.white ? TextDirection.rtl : TextDirection.ltr,
          children: [
            SizedBox(
              width: slot * 1.1,
              child: Text(
                '${side.mark}${label ?? side.label}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFF2B1B08),
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Expanded(
              child: ordered.isEmpty
                  ? const SizedBox()
                  : Row(
                      textDirection: side == Side.white ? TextDirection.rtl : TextDirection.ltr,
                      children: [
                        for (final t in ordered)
                          GestureDetector(
                            key: ValueKey('hand-${side.name}-${t.name}'),
                            onTap: () => ref.read(gameControllerProvider.notifier).tapHand(side, t),
                            child: Stack(clipBehavior: Clip.none, children: [
                              ShogiPiece(type: t, side: side, size: slot, highlighted: selectedType == t),
                              if (pos.handCount(side, t) > 1)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2B1B08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('${pos.handCount(side, t)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                            ]),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      );
    });
  }
}
