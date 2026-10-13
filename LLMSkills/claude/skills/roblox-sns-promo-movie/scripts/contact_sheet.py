#!/usr/bin/env python3
"""Contact sheets: one frame every STEP seconds between START and END, each labelled with its timestamp.

Use a coarse pass over the whole capture first (step 2, 5x7 tiles = 70 s per sheet), then finer sheets
(step 1 or 0.5) around the candidates. Read the sheets with the Read tool; the labels are source times.

usage:
  python contact_sheet.py VIDEO START END STEP --out-prefix PATH [--tile 384] [--cols 5] [--rows 7]
START/END accept seconds (183.5) or m:ss(.s) (3:03.5). Prints the written sheet paths.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def find_ffmpeg():
    env = os.environ.get("FFMPEG")
    if env and os.path.isfile(env):
        return env
    p = shutil.which("ffmpeg")
    if p:
        return p
    cache = os.path.join(os.environ.get("LOCALAPPDATA", ""), "npm-cache", "_npx")
    hits = sorted(glob.glob(os.path.join(cache, "*", "node_modules", "ffmpeg-static", "ffmpeg.exe")),
                  key=os.path.getmtime, reverse=True)
    if hits:
        return hits[0]
    sys.exit("ffmpeg not found: set FFMPEG, put ffmpeg on PATH, or run `npx ffmpeg-static` once to fetch it")


def secs(t):
    if ":" in t:
        m, s = t.split(":", 1)
        return int(m) * 60 + float(s)
    return float(t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("start")
    ap.add_argument("end")
    ap.add_argument("step", type=float)
    ap.add_argument("--out-prefix", required=True)
    ap.add_argument("--tile", type=int, default=384)
    ap.add_argument("--cols", type=int, default=5)
    ap.add_argument("--rows", type=int, default=7)
    a = ap.parse_args()
    t0, t1 = secs(a.start), secs(a.end)
    tw = a.tile
    th = tw * 9 // 16
    proc = subprocess.run([find_ffmpeg(), "-hide_banner", "-loglevel", "error", "-ss", f"{t0:.3f}",
                           "-t", f"{t1 - t0:.3f}", "-i", a.video, "-an",
                           "-vf", f"fps={1.0 / a.step},scale={tw}:{th}:force_original_aspect_ratio=decrease,"
                                  f"pad={tw}:{th}:(ow-iw)/2:(oh-ih)/2",
                           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True)
    fr = np.frombuffer(proc.stdout, dtype=np.uint8).reshape(-1, th, tw, 3)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", max(12, tw // 14))
    except OSError:
        font = ImageFont.load_default()
    per = a.cols * a.rows
    os.makedirs(os.path.dirname(os.path.abspath(a.out_prefix)), exist_ok=True)
    for k in range(0, len(fr), per):
        sheet = Image.new("RGB", (a.cols * tw, a.rows * th), (0, 0, 0))
        d = ImageDraw.Draw(sheet)
        for i, f in enumerate(fr[k:k + per]):
            x, y = (i % a.cols) * tw, (i // a.cols) * th
            sheet.paste(Image.fromarray(f), (x, y))
            t = t0 + (k + i) * a.step
            d.rectangle([x, y, x + tw // 3, y + tw // 12], fill=(0, 0, 0))
            d.text((x + 3, y + 1), f"{int(t // 60)}:{t % 60:04.1f}", fill=(255, 255, 0), font=font)
        path = f"{a.out_prefix}_{k // per:02d}.jpg"
        sheet.save(path, quality=80)
        print(path)


if __name__ == "__main__":
    main()
