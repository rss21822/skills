#!/usr/bin/env python3
"""Rough per-second excitement signals for a gameplay capture, and the windows they rank highest.

The signals are hints, not the answer. Background music, camera pans, menus and the intro fly-over also score
high, so always confirm a pick with contact sheets (contact_sheet.py) before cutting.

usage:
  python heat_scan.py VIDEO [--from SEC] [--to SEC] [--window 30] [--top 8] [--json OUT.json]

Prints 5-second blocks (loudness, transient count, motion) and the top windows inside [--from, --to].
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

import numpy as np


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


def mmss(s):
    return f"{int(s) // 60}:{int(s) % 60:02d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--from", dest="lo", type=float, default=None, help="earliest window start (s)")
    ap.add_argument("--to", dest="hi", type=float, default=None, help="latest window end (s)")
    ap.add_argument("--window", type=float, default=30.0)
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    ff = find_ffmpeg()

    # audio: mono 8 kHz, 50 ms RMS frames; a transient = a frame > median of the previous 1 s + 6 dB
    sr = 8000
    raw = subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-i", a.video, "-vn", "-ac", "1", "-ar", str(sr),
                          "-f", "s16le", "-"], capture_output=True, check=True).stdout
    au = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    hop = sr // 20
    fr = au[: len(au) // hop * hop].reshape(-1, hop)
    db = 20 * np.log10(np.sqrt((fr ** 2).mean(axis=1) + 1e-12))
    onset = np.zeros_like(db)
    for i in range(20, len(db)):
        onset[i] = max(0.0, db[i] - np.median(db[i - 20:i]) - 6.0)

    # video: 6 fps, 192x108 gray, mean absolute frame difference
    w, h, fps = 192, 108, 6
    vb = subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-i", a.video, "-an", "-vf",
                         f"fps={fps},scale={w}:{h},format=gray", "-f", "rawvideo", "-"],
                        capture_output=True, check=True).stdout
    v = np.frombuffer(vb, dtype=np.uint8).reshape(-1, h, w).astype(np.float32)
    diff = np.concatenate([[0.0], np.abs(np.diff(v, axis=0)).mean(axis=(1, 2))])

    n = int(min(len(db) // 20, len(diff) // fps))
    sec_db = np.array([db[s * 20:(s + 1) * 20].mean() for s in range(n)])
    sec_on = np.array([float((onset[s * 20:(s + 1) * 20] > 0).sum()) for s in range(n)])
    sec_mo = np.array([diff[s * fps:(s + 1) * fps].mean() for s in range(n)])

    print(f"duration ~{n} s ({mmss(n)})\n\nblock  dB     onsets motion")
    for s in range(0, n, 5):
        b = slice(s, min(n, s + 5))
        print(f"{mmss(s):>5}  {sec_db[b].mean():6.1f} {sec_on[b].sum():6.0f} {sec_mo[b].mean():6.2f}  "
              + "#" * int(sec_on[b].sum() / 2))

    def z(x):
        return (x - x.mean()) / (x.std() + 1e-9)

    heat = z(sec_on) + z(sec_mo) + 0.5 * z(sec_db)
    W = int(round(a.window))
    lo = int(a.lo) if a.lo is not None else 0
    hi = int(a.hi) if a.hi is not None else n
    cands = []
    for s in range(lo, max(lo, hi - W) + 1):
        if s + W > n:
            break
        cands.append({"start": s, "score": float(heat[s:s + W].mean()), "onsets": float(sec_on[s:s + W].sum()),
                      "motion": float(sec_mo[s:s + W].mean()), "db": float(sec_db[s:s + W].mean())})
    cands.sort(key=lambda c: -c["score"])
    picked = []
    for c in cands:
        if all(abs(c["start"] - p["start"]) >= W / 2 for p in picked):
            picked.append(c)
        if len(picked) >= a.top:
            break
    print(f"\ntop {W} s windows in {mmss(lo)}-{mmss(hi)} (hints only - confirm with contact sheets):")
    for c in picked:
        print(f"  {c['score']:+.3f}  {mmss(c['start'])}-{mmss(c['start'] + W)}  onsets={c['onsets']:.0f} "
              f"motion={c['motion']:.2f} dB={c['db']:.1f}")
    if a.json:
        json.dump({"video": a.video, "seconds": n, "sec_db": sec_db.tolist(), "sec_onset": sec_on.tolist(),
                   "sec_motion": sec_mo.tolist(), "top": picked}, open(a.json, "w", encoding="utf-8"), indent=1)
        print("wrote", a.json)


if __name__ == "__main__":
    main()
