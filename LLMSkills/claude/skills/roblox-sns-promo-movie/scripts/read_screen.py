#!/usr/bin/env python3
"""Capture a small screen rectangle at physical resolution (lossless PNG, enlarged) to read tiny UI text.

computer-use screenshots and zooms are downscaled JPEGs, so CapCut's timecode ("00:03:01:26") is often
unreadable in them. This grabs the same rectangle straight from the screen at full resolution.

Coordinates are given in the computer-use screenshot frame (the "coordinate frame" it reports, e.g. 1456x819);
the script converts them to physical pixels of the primary display.

usage:
  python read_screen.py --frame 1456x819 --rect X,Y,W,H --out timecode.png [--zoom 5]
Then open the PNG with the Read tool. Only capture the window you are operating (CapCut), nothing else.
"""
import argparse
import ctypes

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

from PIL import Image, ImageGrab  # noqa: E402  (import after DPI awareness)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frame", required=True, help="screenshot coordinate frame, e.g. 1456x819")
    ap.add_argument("--rect", required=True, help="X,Y,W,H in that frame")
    ap.add_argument("--out", required=True)
    ap.add_argument("--zoom", type=int, default=5)
    a = ap.parse_args()
    fw, fh = (int(v) for v in a.frame.lower().split("x"))
    x, y, w, h = (float(v) for v in a.rect.split(","))
    sw = ctypes.windll.user32.GetSystemMetrics(0)
    sh = ctypes.windll.user32.GetSystemMetrics(1)
    kx, ky = sw / fw, sh / fh
    box = (int(x * kx), int(y * ky), int((x + w) * kx), int((y + h) * ky))
    img = ImageGrab.grab(bbox=box)
    img = img.resize((img.width * a.zoom, img.height * a.zoom), Image.NEAREST)
    img.save(a.out)
    print(f"screen {sw}x{sh}, scale {kx:.3f}x{ky:.3f}, physical box {box}, saved {a.out} {img.size}")


if __name__ == "__main__":
    main()
