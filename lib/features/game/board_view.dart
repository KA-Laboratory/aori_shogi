import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/shogi/shogi.dart';
import '../settings/app_settings.dart';
import 'game_controller.dart';
import 'piece_painter.dart';

const _boardColor = Color(0xFFE9C47A);
const _lineColor = Color(0xFF4E3514);
const _komadaiColor = Color(0xFFC9974F);

typedef MoveCandidatesCallback = void Function(List<Move> candidates);

class BoardView extends ConsumerWidget {
  const BoardView({
    super.key,
    required this.onCandidates,
    this.interactive = true,
  });

  final MoveCandidatesCallback onCandidates;
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gameControllerProvider);
    final settings = ref.watch(settingsProvider);
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
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final coordinates = settings.showCoordinates && c.maxWidth >= 324;
            final gutter = coordinates ? 18.0 : 0.0;
            final cell = (c.maxWidth - gutter) / 9;
            return Stack(
              children: [
                // 星（3筋・6筋 × 三段・六段の交点）
                for (final (x, y) in const [(3, 3), (6, 3), (3, 6), (6, 6)])
                  Positioned(
                    left: x * cell - 3,
                    top: gutter + y * cell - 3,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _lineColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                for (var sq = 0; sq < 81; sq++)
                  Positioned(
                    left: (sq % 9) * cell,
                    top: gutter + (sq ~/ 9) * cell,
                    width: cell,
                    height: cell,
                    child: Semantics(
                      container: true,
                      label:
                          '${'９８７６５４３２１'[sq % 9]}${'一二三四五六七八九'[sq ~/ 9]} ${pos.board[sq] == null ? '空きマス' : '${pos.board[sq]!.side.label} ${pos.board[sq]!.type.kifName}'}',
                      selected: selected == sq,
                      button: interactive,
                      enabled: interactive,
                      value: [
                        if (selected == sq) '選択中',
                        if (s.legalTargets.contains(sq)) '移動可能',
                        if (checkedKing == sq) '王手',
                        if (last?.to == sq && settings.highlightLastMove) '最終手',
                      ].join('、'),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: !interactive
                            ? null
                            : () {
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
                          lastMove:
                              settings.highlightLastMove && last?.to == sq,
                          checked: checkedKing == sq,
                        ),
                      ),
                    ),
                  ),
                if (coordinates) ...[
                  for (var index = 0; index < 9; index++) ...[
                    Positioned(
                      left: index * cell,
                      top: 0,
                      width: cell,
                      height: gutter,
                      child: ExcludeSemantics(
                        child: Center(
                          child: Text(
                            '${9 - index}',
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1,
                              color: _lineColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 9 * cell,
                      top: gutter + index * cell,
                      width: gutter,
                      height: cell,
                      child: ExcludeSemantics(
                        child: Center(
                          child: Text(
                            '一二三四五六七八九'[index],
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1,
                              color: _lineColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
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
        border: Border.all(
          color: _lineColor.withValues(alpha: 0.7),
          width: 0.6,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (piece != null)
            ShogiPiece(
              type: piece!.type,
              side: piece!.side,
              size: size,
              highlighted: selected,
            ),
          if (lastMove)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: DecoratedBox(
                  key: const ValueKey('last-move-outline'),
                  decoration: BoxDecoration(
                    border: Border.all(color: _lineColor, width: 2),
                  ),
                ),
              ),
            ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF125380), width: 3),
                ),
              ),
            ),
          if (checked) ...[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF781C12),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF781C12),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (target)
            Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: piece == null
                    ? const Color(0x881E88E5)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: piece == null
                    ? null
                    : Border.all(color: const Color(0xCC1E88E5), width: 3),
              ),
            ),
        ],
      ),
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
    final types = [
      for (final t in handOrder)
        if (pos.handCount(side, t) > 0) t,
    ];
    // 後手の駒台は相手側から見た並び（右から）にする。
    final ordered = side == Side.white ? types : types.reversed.toList();

    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD7A860), _komadaiColor],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFF125380) : _lineColor,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          textDirection: side == Side.white
              ? TextDirection.rtl
              : TextDirection.ltr,
          children: [
            SizedBox(
              width: 48,
              child: Semantics(
                label: '${side.label} ${label ?? ''} 持ち駒',
                child: ExcludeSemantics(
                  child: Text(
                    '${side.mark}${label ?? side.label}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: const Color(0xFF2B1B08),
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: side == Side.white,
                child: Row(
                  textDirection: side == Side.white
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    for (final type in ordered)
                      Semantics(
                        label:
                            '${side.label}持ち駒${type.kifName}${pos.handCount(side, type)}枚',
                        selected: selectedType == type,
                        button: true,
                        child: GestureDetector(
                          key: ValueKey('hand-${side.name}-${type.name}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => ref
                              .read(gameControllerProvider.notifier)
                              .tapHand(side, type),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: ExcludeSemantics(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ShogiPiece(
                                    type: type,
                                    side: side,
                                    size: 40,
                                    highlighted: selectedType == type,
                                  ),
                                  if (selectedType == type)
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: const Color(0xFF125380),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (pos.handCount(side, type) > 1)
                                    Positioned(
                                      right: 1,
                                      bottom: 1,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2B1B08),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '${pos.handCount(side, type)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            height: 1.1,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
