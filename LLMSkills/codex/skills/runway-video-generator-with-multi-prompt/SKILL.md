---
name: runway-video-generator-with-multi-prompt
description: Generate a coherent long-form Runway video from an ordered multi-prompt chain, then stitch and verify any number of generated clips. Use when a requested video exceeds one model generation or multiple clips must behave as one continuous audiovisual sequence; do not use for a single unstitched clip.
---

# Runway Video Generator with Multi-Prompt

Produce one continuous deliverable, not merely a collection of clips.

## Establish the contract

Before generating, resolve the total duration, aspect ratio, delivery resolution and frame rate, model/provider, reference assets, audio requirement, output location, and whether clip lengths are uniform. Check credit or cost implications before starting paid generation when the user's request has not already authorized that spend.

Calculate an ordered duration list `d1..dN`; do not assume three clips. Use the provider's maximum reliable duration and make the final segment shorter when necessary.

## Design the prompt chain

Read [references/continuity.md](references/continuity.md) before writing a multi-clip prompt chain. Keep one immutable continuity bible and an explicit end-state ledger. The first prompt establishes the world; every later prompt extends the actual preceding output from its exact final frame. Reserve narrative resolution and audio cadence for the final segment.

When using Runway or Seedance through the browser, also read [references/runway.md](references/runway.md).

## Generate serially

1. Generate the first segment from the requested reference material or text.
2. Inspect its real final state before writing or submitting the next segment.
3. Select that exact completed asset as the continuation source. Confirm the visible source duration, requested output duration, aspect ratio, model, and audio toggle.
4. Submit each job once. A live `In queue` or progress state is a wait condition, not a reason to restart or duplicate the job.
5. Download each completed source immediately as `clip001`, `clip002`, and so on. Preserve the original files.
6. Repeat until all `N` segments are complete.

If a generated segment contradicts identity, geography, action causality, or the required end state, regenerate that segment or introduce an intentional bridge. Stitching cannot repair semantic discontinuity.

## Stitch any number of clips

Use the included deterministic script. Supply the planned duration so container padding or an extra source frame cannot change the final runtime:

```powershell
python scripts/stitch_clips.py clip001.mov clip002.mov clip003.mov clip004.mov `
  --output final.mp4 --clip-duration 15 --fps 24 `
  --contact-sheet final_seams.png
```

For unequal segment lengths, replace `--clip-duration` with one value per input:

```powershell
python scripts/stitch_clips.py clip001.mov clip002.mov clip003.mov `
  --output final.mp4 --durations 12 15 8.5 --fps 24 `
  --contact-sheet final_seams.png
```

Pass `--ffmpeg PATH` when FFmpeg is not on `PATH`. Use `--no-audio` only when the requested deliverable is intentionally silent. The script trims each input to an integer frame count, normalizes geometry and audio, concatenates all inputs in order, verifies the decoded frame count, and optionally creates a seam contact sheet.

## Completion gate

Do not call the result complete until all of the following hold:

- The script reports the expected input count, total frames, total duration, resolution, frame rate, and audio state.
- The final file decodes without error and has the requested audio stream.
- The contact sheet shows frames immediately before and after every boundary, regardless of `N`.
- Full playback confirms identity, set topology, motion direction, action causality, music continuity, and the intended ending.
- Any model deviations are reported plainly; technical concatenation success is not evidence of semantic continuity.

Keep cloud uploads, publishing, sharing, and deletion within the user's explicit scope. A local stitched result does not need to be uploaded back to the provider unless requested.
