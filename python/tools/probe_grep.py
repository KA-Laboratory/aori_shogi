"""UTF-8 のソースを素直に grep する（findstr は cp932 で日本語を取りこぼす）。"""
import sys
from pathlib import Path

needle = sys.argv[1]
out = []
for p in sys.argv[2:-1]:
    for f in sorted(Path().glob(p)) if "*" in p else [Path(p)]:
        try:
            text = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if needle in line:
                out.append(f"{f}:{i}: {line.strip()}")
open(sys.argv[-1], "w", encoding="utf-8").write("\n".join(out) + "\n")
