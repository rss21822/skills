#!/usr/bin/env python3
"""Pull a starting palette out of a motif image (reference art, mood board, screenshot).

  python extract_palette.py motif.png [--colors 12] [--json out.json]

Prints the dominant colours with their share, HLS and a role hint, then a draft `palette` block
for the skin spec. The draft is a starting point: push the candies to full saturation, tint the
ink toward the motif, and re-run skin_preview.py to check contrast. Requires Pillow.
"""
import argparse
import colorsys
import json
from pathlib import Path

from PIL import Image


def hls(c):
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
    return h * 360, l, s


def hexc(c):
    return "#%02X%02X%02X" % tuple(int(v) for v in c)


def from_hls(h, l, s):
    return tuple(round(v * 255) for v in colorsys.hls_to_rgb(h / 360, l, s))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--colors", type=int, default=32, help="quantisation buckets (small accents need many)")
    ap.add_argument("--json")
    args = ap.parse_args()
    img = Image.open(args.image).convert("RGB")
    img.thumbnail((160, 160))
    quant = img.quantize(colors=args.colors, method=Image.Quantize.MEDIANCUT)
    palette = quant.getpalette()
    counts = sorted(quant.getcolors(), reverse=True)
    total = sum(n for n, _ in counts)
    rows = []
    for n, index in counts:
        c = tuple(palette[index * 3:index * 3 + 3])
        h, l, s = hls(c)
        if l < 0.22:
            hint = "ink candidate (dark)"
        elif l > 0.86:
            hint = "paper candidate (light)"
        elif s > 0.45 and 0.3 < l < 0.75:
            hint = "candy / accent"
        else:
            hint = "muted / texture"
        rows.append({"hex": hexc(c), "share": round(n / total, 3), "h": round(h), "l": round(l, 2), "s": round(s, 2), "hint": hint})
    print("share  hex      H    L    S    hint")
    for r in rows[:16]:
        print(f"{r['share']:5.1%}  {r['hex']}  {r['h']:3d}  {r['l']:.2f} {r['s']:.2f}  {r['hint']}")
    darks = sorted((r for r in rows if r["l"] < 0.35), key=lambda r: r["l"])
    lights = sorted((r for r in rows if r["l"] > 0.8), key=lambda r: -r["share"])
    # Accents: saturated mid-light colours; small areas count (a candy button is a small area).
    accents = sorted((r for r in rows if r["s"] > 0.35 and 0.3 < r["l"] < 0.8 and r["share"] >= 0.004),
                     key=lambda r: -(r["s"] * (0.02 + r["share"])))
    # Draft roles: ink = darkest colour pushed darker but kept tinted; paper = most common light, warmed.
    ink = from_hls(darks[0]["h"], 0.14, min(0.55, max(0.3, darks[0]["s"]))) if darks else (48, 22, 58)
    paper = from_hls(lights[0]["h"], 0.97, min(0.7, lights[0]["s"] + 0.2)) if lights else (255, 250, 242)
    candies, used = [], []
    for r in accents:
        if all(min(abs(r["h"] - u), 360 - abs(r["h"] - u)) > 28 for u in used):
            used.append(r["h"])
            candies.append([f"accent{len(candies) + 1}", hexc(from_hls(r["h"], min(max(r["l"], 0.52), 0.62), max(r["s"], 0.8)))])
        if len(candies) == 5:
            break
    draft = {"ink": hexc(ink), "paper": hexc(paper), "panel": "#FFFFFF",
             "primary": candies[0][1] if candies else "#FFD033",
             "candies": candies[1:]}
    print("\nDraft palette (rename accents after the motif, add danger/success/muted/disabled/dim/quiet):")
    print(json.dumps(draft, indent=2))
    if args.json:
        Path(args.json).write_text(json.dumps({"colours": rows, "draft": draft}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
