"""Checks that a rendered menu uses only the three pigments (washi, sumi, shu) and their mixtures.

Every pixel must lie inside the RGB triangle spanned by the pigments (anti-aliasing, transparency and
ink dilution only ever produce convex mixtures of them). Reports the share of pixels outside it.
usage: python verify_palette.py image.png [...]
"""
import sys
import numpy as np
from PIL import Image

WASHI = np.array([240, 234, 219], float)
SUMI = np.array([27, 26, 24], float)
SHU = np.array([192, 55, 38], float)
TOL = 6.0  # RGB units of slack for PNG rounding

def outside_share(path):
    px = np.asarray(Image.open(path).convert("RGB"), float).reshape(-1, 3)
    # least-squares barycentric coordinates in the plane of the triangle
    a, b = SUMI - WASHI, SHU - WASHI
    m = np.stack([a, b], axis=1)  # 3x2
    rel = px - WASHI
    coef, *_ = np.linalg.lstsq(m, rel.T, rcond=None)  # 2xN
    u, v = coef
    u_c = np.clip(u, 0, 1)
    v_c = np.clip(v, 0, 1)
    over = u_c + v_c > 1
    s = u_c[over] + v_c[over]
    u_c[over] /= s
    v_c[over] /= s
    nearest = WASHI + np.outer(u_c, a) + np.outer(v_c, b)
    dist = np.linalg.norm(px - nearest, axis=1)
    bad = dist > TOL
    return bad.mean(), dist.max()

ok = True
for path in sys.argv[1:]:
    share, worst = outside_share(path)
    verdict = "PASS" if share < 0.001 else "FAIL"
    ok &= verdict == "PASS"
    print(f"{verdict} {path.split('/')[-1]}: {share*100:.3f}% of pixels off-palette (max distance {worst:.1f})")
sys.exit(0 if ok else 1)
