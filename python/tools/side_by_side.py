"""2つの試し撃ちログを、同じお題どうし並べて1つの UTF-8 ファイルにする。"""
import re
import sys


def parse(path: str) -> tuple[list[tuple[str, str, str]], str]:
    raw = open(path, "rb").read()
    try:
        text = raw.decode("cp932")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", "replace")
    items, tail = [], ""
    head = fact = out = None
    for line in text.splitlines():
        m = re.match(r"^\[(\S+)\]", line)
        if m:
            if head:
                items.append((head, fact or "", out or ""))
            head, fact, out = m.group(1), None, None
        elif line.startswith("  事実: "):
            fact = line.split(": ", 1)[1]
        elif line.startswith("  出力: "):
            out = line.split(": ", 1)[1]
        elif line.startswith("崩れ "):
            tail = line
    if head:
        items.append((head, fact or "", out or ""))
    return items, tail


a, ta = parse(sys.argv[1])
b, tb = parse(sys.argv[2])
lines = [f"A(現行 rank16/lr1e-4/4ep): {ta}", f"B(弱め rank8/lr5e-5/3ep): {tb}", ""]
for (ha, fa, oa), (_, _, ob) in zip(a, b):
    lines += [f"[{ha}] {fa}", f"  A: {oa}", f"  B: {ob}", ""]
open(sys.argv[3], "w", encoding="utf-8").write("\n".join(lines))
