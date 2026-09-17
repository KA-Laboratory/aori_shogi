"""ウィクショナリー日本語版（CC BY-SA 4.0）の「日本語 慣用句」「日本語 ことわざ」から見出しと最初の語義を取得。
→ tool/lexicon_src/wiktionary_idioms.json   実行: python tool/fetch_wiktionary_idioms.py
"""
import json
import re
import time
import urllib.parse
import urllib.request

API = "https://ja.wiktionary.org/w/api.php"
UA = {"User-Agent": "aori-shogi-lexicon/0.1 (https://github.com/KA-Laboratory/aori_shogi)"}
CATS = {"日本語 慣用句": "idiom", "日本語 ことわざ": "proverb", "日本語 四字熟語": "yoji"}


def api(**params):
    params.update(format="json", formatversion="2")
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def members(cat):
    out, cont = [], {}
    while True:
        d = api(action="query", list="categorymembers", cmtitle="Category:" + cat, cmlimit="500", cmnamespace="0", **cont)
        out += [m["title"] for m in d["query"]["categorymembers"]]
        if "continue" not in d:
            return out
        cont = {"cmcontinue": d["continue"]["cmcontinue"]}
        time.sleep(0.2)


def first_sense(wikitext: str) -> str:
    # 日本語セクションの最初の「# 」行（語義）
    sec = wikitext.split("==日本語==", 1)[-1]
    for line in sec.splitlines():
        if re.match(r"^#[^#*:]", line):
            s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", line[1:])
            s = re.sub(r"\{\{[^}]*\}\}", "", s)
            s = re.sub(r"'''?|<[^>]+>", "", s).strip()
            if s:
                return s[:160]
    return ""


def main():
    titles = {}
    for cat, kind in CATS.items():
        for t in members(cat):
            titles.setdefault(t, kind)
    items = []
    names = list(titles)
    for i in range(0, len(names), 40):
        batch = names[i:i + 40]
        d = api(action="query", prop="revisions", rvprop="content", rvslots="main", titles="|".join(batch))
        for p in d["query"]["pages"]:
            text = (p.get("revisions") or [{}])[0].get("slots", {}).get("main", {}).get("content", "")
            items.append({"title": p["title"], "kind": titles.get(p["title"], "idiom"), "sense": first_sense(text)})
        time.sleep(0.3)
    json.dump({"source": "ja.wiktionary.org (CC BY-SA 4.0)", "fetched": time.strftime("%Y-%m-%d"), "items": items},
              open("tool/lexicon_src/wiktionary_idioms.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(len(items), {k: sum(1 for x in items if x["kind"] == k) for k in CATS.values()})


if __name__ == "__main__":
    main()
