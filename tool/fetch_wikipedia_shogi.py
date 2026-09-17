"""Wikipedia（CC BY-SA 4.0）から将棋の戦法・囲い・用語の記事名と冒頭文を取得して tool/lexicon_src/wikipedia_shogi.json へ。
実行: uv run --project python python tool/fetch_wikipedia_shogi.py
"""
import json
import re
import time
import urllib.parse
import urllib.request

API = "https://ja.wikipedia.org/w/api.php"
UA = {"User-Agent": "aori-shogi-lexicon/0.1 (https://github.com/KA-Laboratory/aori_shogi)"}
ROOTS = {"将棋の戦法": "strategy", "将棋の囲い": "castle", "将棋用語": "term"}


def api(**params):
    params.update(format="json", formatversion="2")
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def members(cat):
    out, cont = [], {}
    while True:
        d = api(action="query", list="categorymembers", cmtitle="Category:" + cat, cmlimit="500", **cont)
        out += d["query"]["categorymembers"]
        if "continue" not in d:
            return out
        cont = {"cmcontinue": d["continue"]["cmcontinue"]}


def main():
    pages = {}
    for root, kind in ROOTS.items():
        queue, seen = [(root, 0)], set()
        while queue:
            cat, depth = queue.pop()
            if cat in seen:
                continue
            seen.add(cat)
            for m in members(cat):
                if m["ns"] == 14 and depth < 2:
                    queue.append((m["title"].split(":", 1)[1], depth + 1))
                elif m["ns"] == 0:
                    pages.setdefault(m["title"], kind)
            time.sleep(0.2)
    titles = list(pages)
    result = []
    for i in range(0, len(titles), 20):
        batch = titles[i:i + 20]
        d = api(action="query", prop="extracts", exintro="1", explaintext="1", exsentences="2", titles="|".join(batch))
        for p in d["query"]["pages"]:
            ext = (p.get("extract") or "").strip()
            result.append({"title": p["title"], "kind": pages.get(p["title"], "term"), "extract": ext[:200]})
        time.sleep(0.2)
    json.dump({"source": "ja.wikipedia.org (CC BY-SA 4.0)", "fetched": time.strftime("%Y-%m-%d"), "pages": result},
              open("tool/lexicon_src/wikipedia_shogi.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(len(result), {k: sum(1 for r in result if r["kind"] == k) for k in ROOTS.values()})


if __name__ == "__main__":
    main()
