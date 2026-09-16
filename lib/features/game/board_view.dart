import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shogi/shogi.dart';
import 'game_controller.dart';

const _boardColor = Color(0xFFE8C77E);
const _lineColor = Color(0xFF5B4020);

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
      child: Container(
        decoration: BoxDecoration(
          color: _boardColor,
          border: Border.all(color: _lineColor, width: 2),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final cell = c.maxWidth / 9;
          return Stack(children: [
            for (var sq = 0; sq < 81; sq++)
              Positioned(
                left: (sq % 9) * cell,
                top: (sq ~/ 9) * cell,
                width: cell,
                height: cell,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final cands = ref
                        .read(gameControllerProvider.notifier)
                        .tapSquare(sq);
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
    if (lastMove) bg = const Color(0x55D2691E);
    if (selected) bg = const Color(0x8842A5F5);
    if (checked) bg = const Color(0x99E53935);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: _lineColor.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Stack(alignment: Alignment.center, children: [
        if (piece != null) PieceGlyph(piece: piece!, size: size),
        if (target)
          Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: const BoxDecoration(
              color: Color(0x9942A5F5),
              shape: BoxShape.circle,
            ),
          ),
      ]),
    );
  }
}

class PieceGlyph extends StatelessWidget {
  const PieceGlyph({super.key, required this.piece, required this.size});

  final Piece piece;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      piece.type.boardChar,
      style: TextStyle(
        fontSize: size * 0.62,
        height: 1.0,
        fontWeight: FontWeight.bold,
        color: piece.type.isPromoted ? const Color(0xFFC62828) : Colors.black,
      ),
    );
    return piece.side == Side.white
        ? Transform.rotate(angle: 3.14159265, child: text)
        : text;
  }
}

class HandView extends ConsumerWidget {
  const HandView({super.key, required this.side});

  final Side side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final pos = s.position;
    final selectedType = switch (s.selection) {
      HandSelection(:final type) when pos.turn == side => type,
      _ => null,
    };
    final active = pos.turn == side && !s.game.isOver;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFF3D6) : const Color(0xFFF1E6CF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Text('${side.mark}${side.label}',
            style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        const SizedBox(width: 8),
        Expanded(
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final t in handOrder.reversed)
              if (pos.handCount(side, t) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    key: ValueKey('hand-${side.name}-${t.name}'),
                    label: Text(
                        '${t.boardChar}${pos.handCount(side, t) > 1 ? pos.handCount(side, t) : ''}'),
                    selected: selectedType == t,
                    onSelected: (_) => ref
                        .read(gameControllerProvider.notifier)
                        .tapHand(side, t),
                  ),
                ),
          ]),
        ),
      ]),
    );
  }
}
