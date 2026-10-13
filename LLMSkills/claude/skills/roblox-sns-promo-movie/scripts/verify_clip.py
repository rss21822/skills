#!/usr/bin/env python3
"""Verify a CapCut export against the source window it was cut from.

Checks
  1. container: duration, frame count, fps, resolution, audio present
  2. timing: the clip starts at --start in the source (audio cross-correlation, and frame matching)
  3. real frame rate: duplicate-frame ratio is not much higher than the source's (no 30 fps doubled to 60)
  4. provenance: CapCut's metadata JSON (AI-feature flags), encoder tag, and no C2PA / XMP boxes

The layout is taken from the clip resolution: landscape clips are compared with the full source frame,
portrait/square clips with a centred crop of the source of the same aspect (CapCut "fill" framing).

usage:
  python verify_clip.py --source SRC.mp4 --start 180 --clip OUT.mp4 [--duration 30] [--json report.json]
Exit code 0 when every check passes, 1 otherwise.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

import numpy as np

# CapCut desktop (product "vicut") writes is_use_vc_sing_clone = 1 on every export, even without any AI feature.
KNOWN_DEFAULT_FLAGS = {"is_use_vc_sing_clone"}


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


FF = find_ffmpeg()


def run(args):
    return subprocess.run([FF, "-hide_banner"] + args, capture_output=True, text=True, encoding="utf-8",
                          errors="replace").stderr


def info(path):
    t = run(["-i", path])
    d = re.search(r"Duration: (\d+):(\d+):([\d.]+)", t)
    v = re.search(r"Stream #\S+.*Video: (\w+).*?, (\d{2,5})x(\d{2,5})[ ,].*?([\d.]+) fps", t)
    return {
        "duration": int(d.group(1)) * 3600 + int(d.group(2)) * 60 + float(d.group(3)) if d else None,
        "vcodec": v.group(1) if v else None,
        "width": int(v.group(2)) if v else None,
        "height": int(v.group(3)) if v else None,
        "fps": float(v.group(4)) if v else None,
        "audio": "Audio:" in t,
        "raw": [ln.strip() for ln in t.splitlines() if "Stream #" in ln or "Duration" in ln or "encoder" in ln],
    }


def frame_count(path):
    t = run(["-i", path, "-map", "0:v:0", "-f", "null", "-"])
    f = re.findall(r"frame=\s*(\d+)", t)
    return int(f[-1]) if f else None


def gray(path, ss, dur, vf_pre, w, h):
    cmd = [FF, "-hide_banner", "-loglevel", "error"]
    if ss is not None:
        cmd += ["-ss", f"{ss:.3f}", "-t", f"{dur:.3f}"]
    cmd += ["-i", path, "-an", "-vf", f"{vf_pre}scale={w}:{h},format=gray", "-f", "rawvideo", "-"]
    b = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(b, dtype=np.uint8).reshape(-1, h, w).astype(np.float32)


def pcm(path, ss=None, dur=None, sr=8000):
    cmd = [FF, "-hide_banner", "-loglevel", "error"]
    if ss is not None:
        cmd += ["-ss", f"{ss:.3f}", "-t", f"{dur:.3f}"]
    cmd += ["-i", path, "-vn", "-ac", "1", "-ar", str(sr), "-f", "s16le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout,
                         dtype=np.int16).astype(np.float32)


def boxes(data):
    out, pos = [], 0
    while pos + 8 <= len(data):
        size = int.from_bytes(data[pos:pos + 4], "big")
        typ = data[pos + 4:pos + 8].decode("latin-1")
        hdr = 8
        if size == 1:
            size = int.from_bytes(data[pos + 8:pos + 16], "big")
            hdr = 16
        elif size == 0:
            size = len(data) - pos
        if size < hdr:
            break
        out.append((typ, pos, size))
        pos += size
    return out


def provenance(path):
    data = open(path, "rb").read()
    top = boxes(data)
    meta_bytes = b"".join(data[p:p + s] for t, p, s in top if t != "mdat")
    res = {"top_level_boxes": [t for t, _, _ in top], "uuid_boxes": sum(1 for t, _, _ in top if t == "uuid"),
           "markers": {}, "capcut_json": None, "flags_set": [], "unexpected_flags": [], "encoder": None}
    low = meta_bytes.lower()
    for m in [b"c2pa", b"jumb", b"<x:xmpmeta", b"aigc", b"trainedalgorithmicmedia", b"digitalsourcetype"]:
        res["markers"][m.decode()] = m in low
    i = meta_bytes.find(b'{"data":')
    if i >= 0:
        depth, j = 0, i
        while j < len(meta_bytes):
            c = meta_bytes[j:j + 1]
            depth += 1 if c == b"{" else -1 if c == b"}" else 0
            j += 1
            if depth == 0:
                break
        try:
            js = json.loads(meta_bytes[i:j].decode("utf-8"))
            res["capcut_json"] = {k: v for k, v in js.items() if k != "data"}
            flat = js.get("data", {})
            for k, v in flat.items():
                if k.startswith("is_") and str(v) not in ("0", "", "False", "false"):
                    res["flags_set"].append(f"{k}={v}")
                    if k not in KNOWN_DEFAULT_FLAGS:
                        res["unexpected_flags"].append(f"{k}={v}")
            res["capcut_product"] = flat.get("product")
        except (ValueError, UnicodeDecodeError) as e:
            res["capcut_json"] = f"unparsed: {e}"
    m = re.search(rb"Lavf[\d.]+", meta_bytes)
    res["encoder"] = m.group(0).decode() if m else None
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--start", type=float, required=True, help="window start in the source (s)")
    ap.add_argument("--clip", required=True)
    ap.add_argument("--duration", type=float, default=30.0)
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    rep = {"clip": a.clip, "source": a.source, "start": a.start, "checks": {}}
    ok = True

    ci, si = info(a.clip), info(a.source)
    n = frame_count(a.clip)
    rep["clip_info"] = {k: v for k, v in ci.items() if k != "raw"}
    rep["clip_info"]["frames"] = n
    rep["clip_streams"] = ci["raw"]
    dur_ok = ci["duration"] is not None and abs(ci["duration"] - a.duration) <= 0.05
    fr_ok = n is not None and ci["fps"] and abs(n - round(a.duration * ci["fps"])) <= 1
    rep["checks"]["duration"] = {"pass": bool(dur_ok and fr_ok), "duration": ci["duration"], "frames": n,
                                 "fps": ci["fps"], "expected": a.duration}
    ok &= bool(dur_ok and fr_ok)

    # timing by audio
    if ci["audio"] and si["audio"]:
        sr = 8000
        s = pcm(a.source, max(0.0, a.start - 1.0), a.duration + 2.0, sr)
        o = pcm(a.clip, sr=sr)
        m = 1
        while m < len(s) + len(o):
            m *= 2
        xc = np.fft.irfft(np.fft.rfft(s, m) * np.conj(np.fft.rfft(o, m)), m)
        lag = int(np.argmax(xc[: max(1, len(s) - len(o) + 1)]))
        seg = s[lag:lag + len(o)]
        corr = float(xc[lag] / (np.sqrt((seg ** 2).sum() * (o ** 2).sum()) + 1e-9))
        found = max(0.0, a.start - 1.0) + lag / sr
        a_ok = abs(found - a.start) <= 0.02 and corr >= 0.9
        rep["checks"]["audio_alignment"] = {"pass": bool(a_ok), "found_start": round(found, 4),
                                            "offset_s": round(found - a.start, 4), "correlation": round(corr, 3)}
        ok &= bool(a_ok)
    else:
        rep["checks"]["audio_alignment"] = {"pass": False, "note": "audio missing in clip or source"}
        ok = False

    # timing by frames
    portrait = ci["width"] and ci["height"] and ci["width"] < ci["height"] * 1.2
    if portrait:
        aspect = ci["width"] / ci["height"]
        w, h = 96, int(round(96 / aspect))
        src_pre = f"crop=ih*{aspect:.6f}:ih,"
    else:
        w, h = 160, 90
        src_pre = ""
    src = gray(a.source, max(0.0, a.start - 1.0), a.duration + 2.0, src_pre, w, h)
    clip = gray(a.clip, None, None, "", w, h)
    sfps = len(src) / (a.duration + 2.0)
    rows, worst = [], 0.0
    for k in sorted({0, len(clip) // 4, len(clip) // 2, 3 * len(clip) // 4, len(clip) - 1}):
        errs = np.abs(src - clip[k]).mean(axis=(1, 2))
        j = int(np.argmin(errs))
        t_clip = k / (ci["fps"] or 60)
        t_src = max(0.0, a.start - 1.0) + j / sfps
        off = t_src - a.start - t_clip
        rows.append({"clip_t": round(t_clip, 3), "source_t": round(t_src, 3), "offset_s": round(off, 3),
                     "err": round(float(errs[j]), 2)})
        if k not in (0,):  # the first frame is often a duplicate of its neighbour
            worst = max(worst, abs(off))
    f_ok = worst <= 2.5 / (ci["fps"] or 60)
    rep["checks"]["frame_alignment"] = {"pass": bool(f_ok), "layout": "center-crop" if portrait else "full",
                                        "samples": rows}
    ok &= bool(f_ok)

    # duplicated frames (30 fps content inside a 60 fps file)
    dc = np.abs(np.diff(clip, axis=0)).mean(axis=(1, 2))
    ds = np.abs(np.diff(src, axis=0)).mean(axis=(1, 2))
    rc, rs = float((dc < 0.05).mean()), float((ds < 0.05).mean())
    d_ok = rc <= rs + 0.25
    rep["checks"]["real_frame_rate"] = {"pass": bool(d_ok), "clip_duplicate_ratio": round(rc, 3),
                                        "source_duplicate_ratio": round(rs, 3)}
    ok &= bool(d_ok)

    pv = provenance(a.clip)
    p_ok = not any(pv["markers"].values()) and pv["uuid_boxes"] == 0 and not pv["unexpected_flags"] \
        and pv.get("capcut_product") is not None
    rep["checks"]["provenance"] = {"pass": bool(p_ok), **pv}
    ok &= bool(p_ok)

    rep["pass"] = bool(ok)
    for name, c in rep["checks"].items():
        print(f"[{'PASS' if c['pass'] else 'FAIL'}] {name}: " +
              json.dumps({k: v for k, v in c.items() if k != "pass"}, ensure_ascii=False))
    print("OVERALL:", "PASS" if ok else "FAIL")
    if a.json:
        json.dump(rep, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("wrote", a.json)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
