#!/usr/bin/env python3
"""Deterministically stitch any number of generated audiovisual clips."""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import NoReturn, Sequence


DURATION_RE = re.compile(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)")
VIDEO_RE = re.compile(r"Stream .*?Video:.*?\b(\d{2,5})x(\d{2,5})\b")
FRAME_RE = re.compile(r"^frame=(\d+)$", re.MULTILINE)


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def run(command: Sequence[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(command),
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        detail = "\n".join((result.stderr or result.stdout).splitlines()[-80:])
        fail(f"FFmpeg command failed ({result.returncode}):\n{detail}")
    return result


def find_ffmpeg(explicit: str | None) -> str:
    candidates = [explicit, os.environ.get("FFMPEG_BINARY"), shutil.which("ffmpeg")]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(Path(candidate).resolve())
        if candidate and shutil.which(candidate):
            return str(Path(shutil.which(candidate) or candidate).resolve())
    try:
        import imageio_ffmpeg  # type: ignore

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        fail("FFmpeg was not found. Install it or pass --ffmpeg PATH.")


def parse_duration(text: str) -> float:
    match = DURATION_RE.search(text)
    if not match:
        fail("Could not read media duration from FFmpeg output.")
    hours, minutes, seconds = match.groups()
    return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


def probe(ffmpeg: str, path: Path) -> dict[str, object]:
    result = run([ffmpeg, "-hide_banner", "-i", str(path)], check=False)
    text = result.stderr + result.stdout
    video = VIDEO_RE.search(text)
    if not video:
        fail(f"No video stream found: {path}")
    return {
        "duration": parse_duration(text),
        "width": int(video.group(1)),
        "height": int(video.group(2)),
        "has_audio": " Audio:" in text,
    }


def parse_resolution(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)x(\d+)", value.lower())
    if not match:
        fail("--resolution must use WIDTHxHEIGHT, for example 1280x720.")
    width, height = map(int, match.groups())
    if width < 2 or height < 2 or width % 2 or height % 2:
        fail("Output width and height must be positive even integers.")
    return width, height


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Trim, normalize, concatenate, and verify any number of video clips."
    )
    parser.add_argument("inputs", nargs="+", type=Path, help="Ordered input clips")
    parser.add_argument("--output", required=True, type=Path, help="Final MP4 path")
    durations = parser.add_mutually_exclusive_group()
    durations.add_argument("--clip-duration", type=float, help="Seconds to use from every clip")
    durations.add_argument(
        "--durations", nargs="+", type=float, help="One duration in seconds per input clip"
    )
    parser.add_argument("--fps", type=float, default=24.0)
    parser.add_argument("--resolution", help="Output WIDTHxHEIGHT; defaults to the first clip")
    parser.add_argument("--sample-rate", type=int, default=48000)
    parser.add_argument("--audio-bitrate", default="256k")
    parser.add_argument("--crf", type=int, default=18)
    parser.add_argument("--preset", default="medium")
    parser.add_argument("--ffmpeg", help="Path to ffmpeg executable")
    parser.add_argument("--no-audio", action="store_true", help="Create an intentionally silent output")
    parser.add_argument("--contact-sheet", type=Path, help="Write boundary contact sheet PNG")
    parser.add_argument("--seam-offset-frames", type=int, default=3)
    parser.add_argument("--sheet-width", type=int, default=480)
    parser.add_argument("--overwrite", action="store_true")
    return parser


def make_contact_sheet(
    ffmpeg: str,
    output: Path,
    sheet: Path,
    frames_per_clip: Sequence[int],
    offset: int,
    sheet_width: int,
) -> None:
    total_frames = sum(frames_per_clip)
    samples = {0, max(0, total_frames - 1)}
    boundary = 0
    for count in frames_per_clip[:-1]:
        boundary += count
        samples.add(max(0, boundary - offset))
        samples.add(min(total_frames - 1, boundary + offset))
    ordered = sorted(samples)
    columns = min(4, max(1, math.ceil(math.sqrt(len(ordered)))))
    rows = math.ceil(len(ordered) / columns)
    select = "+".join(f"eq(n,{frame})" for frame in ordered)
    sheet.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            ffmpeg,
            "-y",
            "-hide_banner",
            "-i",
            str(output),
            "-vf",
            f"select='{select}',scale={sheet_width}:-2,tile={columns}x{rows}:padding=4:margin=4",
            "-frames:v",
            "1",
            "-update",
            "1",
            str(sheet),
        ]
    )


def main() -> None:
    args = build_parser().parse_args()
    ffmpeg = find_ffmpeg(args.ffmpeg)
    inputs = [path.resolve() for path in args.inputs]
    output = args.output.resolve()

    if args.fps <= 0:
        fail("--fps must be greater than zero.")
    if args.sample_rate <= 0:
        fail("--sample-rate must be greater than zero.")
    if args.seam_offset_frames < 1:
        fail("--seam-offset-frames must be at least 1.")
    missing = [str(path) for path in inputs if not path.is_file()]
    if missing:
        fail("Missing input files:\n" + "\n".join(missing))
    if output in inputs:
        fail("Output path must not overwrite an input clip.")
    if output.exists() and not args.overwrite:
        fail(f"Output already exists; pass --overwrite to replace it: {output}")

    media = [probe(ffmpeg, path) for path in inputs]
    if args.durations is not None:
        if len(args.durations) != len(inputs):
            fail(f"--durations requires {len(inputs)} values, received {len(args.durations)}.")
        requested = args.durations
    elif args.clip_duration is not None:
        requested = [args.clip_duration] * len(inputs)
    else:
        requested = [float(item["duration"]) for item in media]

    if any(value <= 0 for value in requested):
        fail("All clip durations must be greater than zero.")
    for path, wanted, item in zip(inputs, requested, media):
        available = float(item["duration"])
        if wanted > available + (1.0 / args.fps):
            fail(f"Requested {wanted:.6f}s from {path.name}, but only {available:.6f}s is available.")
        if not args.no_audio and not bool(item["has_audio"]):
            fail(f"Audio is required but no audio stream was found: {path}")

    frames_per_clip = [int(math.floor(value * args.fps + 0.5)) for value in requested]
    if any(count < 1 for count in frames_per_clip):
        fail("Every clip must contribute at least one output frame.")
    effective = [count / args.fps for count in frames_per_clip]

    if args.resolution:
        width, height = parse_resolution(args.resolution)
    else:
        width, height = int(media[0]["width"]), int(media[0]["height"])
        width -= width % 2
        height -= height % 2

    filters: list[str] = []
    concat_inputs: list[str] = []
    fps_text = f"{args.fps:.12g}"
    for index, (frames, seconds) in enumerate(zip(frames_per_clip, effective)):
        filters.append(
            f"[{index}:v]trim=start=0:duration={seconds:.12g},setpts=PTS-STARTPTS,"
            f"fps={fps_text},trim=start_frame=0:end_frame={frames},setpts=PTS-STARTPTS,"
            f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v{index}]"
        )
        concat_inputs.append(f"[v{index}]")
        if not args.no_audio:
            filters.append(
                f"[{index}:a]atrim=start=0:end={seconds:.12g},asetpts=PTS-STARTPTS,"
                f"aresample={args.sample_rate},aformat=sample_rates={args.sample_rate}:"
                f"channel_layouts=stereo,apad=whole_dur={seconds:.12g},"
                f"atrim=start=0:end={seconds:.12g}[a{index}]"
            )
            concat_inputs.append(f"[a{index}]")

    if args.no_audio:
        filters.append("".join(concat_inputs) + f"concat=n={len(inputs)}:v=1:a=0[vout]")
    else:
        filters.append("".join(concat_inputs) + f"concat=n={len(inputs)}:v=1:a=1[vout][aout]")

    output.parent.mkdir(parents=True, exist_ok=True)
    command = [ffmpeg, "-y", "-hide_banner"]
    for path in inputs:
        command.extend(["-i", str(path)])
    command.extend(["-filter_complex", ";".join(filters), "-map", "[vout]"])
    if not args.no_audio:
        command.extend(["-map", "[aout]"])
    expected_frames = sum(frames_per_clip)
    expected_duration = expected_frames / args.fps
    command.extend(
        [
            "-r",
            fps_text,
            "-fps_mode",
            "cfr",
            "-c:v",
            "libx264",
            "-preset",
            args.preset,
            "-crf",
            str(args.crf),
            "-pix_fmt",
            "yuv420p",
        ]
    )
    if args.no_audio:
        command.append("-an")
    else:
        command.extend(
            [
                "-c:a",
                "aac",
                "-b:a",
                args.audio_bitrate,
                "-ar",
                str(args.sample_rate),
                "-ac",
                "2",
            ]
        )
    command.extend(["-t", f"{expected_duration:.12g}", "-movflags", "+faststart", str(output)])
    run(command)

    decoded = run(
        [
            ffmpeg,
            "-hide_banner",
            "-nostats",
            "-progress",
            "pipe:1",
            "-i",
            str(output),
            "-map",
            "0:v:0",
            "-f",
            "null",
            "-",
        ]
    )
    frames = [int(value) for value in FRAME_RE.findall(decoded.stdout)]
    actual_frames = frames[-1] if frames else -1
    verified = probe(ffmpeg, output)
    actual_duration = float(verified["duration"])
    if actual_frames != expected_frames:
        fail(f"Frame verification failed: expected {expected_frames}, decoded {actual_frames}.")
    if abs(actual_duration - expected_duration) > max(0.01, 0.5 / args.fps):
        fail(
            f"Duration verification failed: expected {expected_duration:.6f}s, "
            f"container reports {actual_duration:.6f}s."
        )
    if not args.no_audio and not bool(verified["has_audio"]):
        fail("Final output is missing its required audio stream.")

    sheet_path: Path | None = args.contact_sheet.resolve() if args.contact_sheet else None
    if sheet_path:
        if sheet_path == output or sheet_path in inputs:
            fail("Contact sheet path must not overwrite a media file.")
        make_contact_sheet(
            ffmpeg,
            output,
            sheet_path,
            frames_per_clip,
            args.seam_offset_frames,
            args.sheet_width,
        )

    report = {
        "output": str(output),
        "input_count": len(inputs),
        "inputs": [str(path) for path in inputs],
        "frames_per_clip": frames_per_clip,
        "total_frames": actual_frames,
        "fps": args.fps,
        "duration_seconds": expected_duration,
        "resolution": f"{width}x{height}",
        "audio": not args.no_audio,
        "sample_rate": None if args.no_audio else args.sample_rate,
        "contact_sheet": str(sheet_path) if sheet_path else None,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
