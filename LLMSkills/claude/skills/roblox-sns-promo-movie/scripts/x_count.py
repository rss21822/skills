#!/usr/bin/env python3
"""Count a post the way X does (twitter-text v3 weighting) so drafts fit the 280 limit of a non-Premium account.

Rules approximated: characters in the Latin/general ranges weigh 1, everything else (CJK, most emoji) weighs 2,
every URL counts as 23, emoji modifiers/joiners/variation selectors weigh 0.

usage:
  python x_count.py FILE            (counts the post text of a draft file: everything above a line starting
                                    with "# ----"; other lines starting with "# " (hash + space) are skipped,
                                    hashtags such as "#Roblox" are counted)
  python x_count.py --text "..."
"""
import argparse
import re
import sys

LIGHT = [(0, 4351), (8192, 8205), (8208, 8223), (8242, 8247)]
ZERO = {0x200D, 0xFE0E, 0xFE0F} | set(range(0x1F3FB, 0x1F400))
URL = re.compile(r"(?i)\b(?:https?://|www\.)\S+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|net|org|gg|io|co|jp|ly|be)"
                 r"(?:/\S*)?")


def weighted(text):
    total = 0
    urls = URL.findall(text)
    rest = URL.sub("", text)
    for ch in rest:
        cp = ord(ch)
        if cp in ZERO:
            continue
        total += 1 if any(lo <= cp <= hi for lo, hi in LIGHT) else 2
    return total + 23 * len(urls), urls


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?")
    ap.add_argument("--text")
    a = ap.parse_args()
    if a.text is not None:
        text = a.text
    elif a.file:
        lines = []
        for ln in open(a.file, encoding="utf-8").read().splitlines():
            if ln.startswith("# ----"):
                break
            if not ln.startswith("# "):
                lines.append(ln)
        text = "\n".join(lines)
    else:
        text = sys.stdin.read()
    n, urls = weighted(text.strip())
    print(f"weighted length {n}/280 ({'OK' if n <= 280 else 'TOO LONG'}), urls counted as 23: {len(urls)}")
    sys.exit(0 if n <= 280 else 1)


if __name__ == "__main__":
    main()
