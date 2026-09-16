"""cshogi まわりの小道具（マス番号・KIF風表記・UI用の盤面JSON）。

cshogi のマス: sq = (筋-1)*9 + (段-1)。
"""
from __future__ import annotations

import cshogi

ZEN = "０１２３４５６７８９"
KAN = "〇一二三四五六七八九"
# cshogi の駒種 1..14
PIECE_KANJI = {1: "歩", 2: "香", 3: "桂", 4: "銀", 5: "角", 6: "飛", 7: "金", 8: "玉",
               9: "と", 10: "成香", 11: "成桂", 12: "成銀", 13: "馬", 14: "龍"}
PIECE_CHAR = {1: "歩", 2: "香", 3: "桂", 4: "銀", 5: "角", 6: "飛", 7: "金", 8: "玉",
              9: "と", 10: "杏", 11: "圭", 12: "全", 13: "馬", 14: "龍"}
HAND_ORDER = [6, 5, 7, 4, 3, 2, 1]  # 飛角金銀桂香歩
HAND_INDEX = {1: 0, 2: 1, 3: 2, 4: 3, 7: 4, 5: 5, 6: 6}  # 駒種 → pieces_in_hand の添字
SIDE_LABEL = {cshogi.BLACK: "先手", cshogi.WHITE: "後手"}


def sq_file(sq: int) -> int:
    return sq // 9 + 1


def sq_rank(sq: int) -> int:
    return sq % 9 + 1


def piece_type(piece: int) -> int:
    return piece & 0x0F if piece else 0


def piece_color(piece: int) -> int:
    return cshogi.WHITE if piece >= 17 else cshogi.BLACK


def kif_text(board: cshogi.Board, usi: str, prev_usi: str | None = None) -> str:
    """指す前の局面で、USI 指し手を「７六歩」「同　角成」「５五角打」にする。"""
    m = board.move_from_usi(usi)
    to = cshogi.move_to(m)
    if prev_usi and len(prev_usi) >= 4 and prev_usi[2:4] == usi[2:4]:
        head = "同　"
    else:
        head = f"{ZEN[sq_file(to)]}{KAN[sq_rank(to)]}"
    if cshogi.move_is_drop(m):
        pt = {"P": 1, "L": 2, "N": 3, "S": 4, "G": 7, "B": 5, "R": 6}[usi[0]]
        return f"{head}{PIECE_KANJI[pt]}打"
    frm = cshogi.move_from(m)
    pt = piece_type(board.piece(frm))
    s = head + PIECE_KANJI[pt]
    if cshogi.move_is_promotion(m):
        s += "成"
    return s


def is_capture(board: cshogi.Board, usi: str) -> bool:
    m = board.move_from_usi(usi)
    return (not cshogi.move_is_drop(m)) and board.piece(cshogi.move_to(m)) != 0


def is_attacking_move(board: cshogi.Board, usi: str) -> bool:
    m = board.move_from_usi(usi)
    if cshogi.move_is_promotion(m) or is_capture(board, usi):
        return True
    board.push(m)
    check = board.is_check()
    board.pop()
    return check


def captured_name(board: cshogi.Board, usi: str) -> str | None:
    if not is_capture(board, usi):
        return None
    return PIECE_KANJI[piece_type(board.piece(cshogi.move_to(board.move_from_usi(usi))))]


def board_json(board: cshogi.Board) -> dict:
    """UI 用: 表示順（上段=一段、左=9筋）の81マスと持ち駒。"""
    cells = []
    for rank in range(1, 10):
        for file in range(9, 0, -1):
            sq = (file - 1) * 9 + (rank - 1)
            p = board.piece(sq)
            if p:
                pt = piece_type(p)
                cells.append({"sq": f"{file}{'abcdefghi'[rank-1]}", "c": PIECE_CHAR[pt], "w": piece_color(p) == cshogi.WHITE,
                              "pro": pt >= 9, "k": pt})
            else:
                cells.append({"sq": f"{file}{'abcdefghi'[rank-1]}"})
    hands = board.pieces_in_hand
    hand_json = []
    for color in (cshogi.BLACK, cshogi.WHITE):
        hand_json.append([{"k": pt, "c": PIECE_CHAR[pt], "n": hands[color][HAND_INDEX[pt]],
                           "usi": {1: "P", 2: "L", 3: "N", 4: "S", 7: "G", 5: "B", 6: "R"}[pt]}
                          for pt in HAND_ORDER if hands[color][HAND_INDEX[pt]] > 0])
    return {"cells": cells, "hands": hand_json, "turn": board.turn}


def legal_moves_json(board: cshogi.Board) -> list[str]:
    return [cshogi.move_to_usi(m) for m in board.legal_moves]
