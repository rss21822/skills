#!/usr/bin/env python3
"""Create this run's output folder: <project movie folder>/[DailyPV] <YYYY-MM-DD_HHMMSS>/ and print it as JSON.

The movie folder is the project's existing folder named "movie" (SpinOut: artifacts/movie). If none exists,
<project root>/movie is created. Pass --movie-dir to override. A folder is never reused: every run gets a new
one named "[DailyPV] " + the local date and time it started, so the daily promo folders stand out
from the other promo videos in the movie folder.

usage:
  python new_run.py [PROJECT_ROOT] [--movie-dir REL_OR_ABS]
"""
import argparse
import datetime
import json
import os
import subprocess
import sys

PREFIX = "[DailyPV] "
SKIP = {".git", "node_modules", ".codex-tmp", "__pycache__", ".claude", "Packages"}


def project_root(start):
    try:
        out = subprocess.run(["git", "-C", start, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                             encoding="utf-8", errors="replace", check=True).stdout.strip()
        return os.path.normpath(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return os.path.abspath(start)


def find_movie_dirs(root, max_depth=3):
    found = []
    for dirpath, dirnames, _ in os.walk(root):
        depth = os.path.relpath(dirpath, root).count(os.sep)
        dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".")]
        for d in dirnames:
            if d.lower() == "movie":
                found.append(os.path.join(dirpath, d))
        if depth >= max_depth - 1:
            dirnames[:] = []
    return found


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=os.getcwd())
    ap.add_argument("--movie-dir", default=None)
    a = ap.parse_args()
    root = project_root(a.root)
    if a.movie_dir:
        movie = a.movie_dir if os.path.isabs(a.movie_dir) else os.path.join(root, a.movie_dir)
    else:
        hits = find_movie_dirs(root)
        if len(hits) > 1:
            print(json.dumps({"error": "several movie folders; pass --movie-dir", "candidates": hits},
                             ensure_ascii=False))
            sys.exit(2)
        movie = hits[0] if hits else os.path.join(root, "movie")
    os.makedirs(movie, exist_ok=True)
    stamp = PREFIX + datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    run = os.path.join(movie, stamp)
    k = 2
    while os.path.exists(run):
        run = os.path.join(movie, f"{stamp}_{k}")
        k += 1
    os.makedirs(run)
    print(json.dumps({"project_root": root, "movie_dir": os.path.normpath(movie), "run_dir": os.path.normpath(run)},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
