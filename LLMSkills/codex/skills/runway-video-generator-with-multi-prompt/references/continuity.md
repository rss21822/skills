# Multi-clip continuity design

Use this reference when a video is generated from two or more prompts.

## Plan from duration, not a fixed clip count

Given target duration `T` and the model's reliable maximum segment length `L`, choose `N = ceil(T / L)` unless the user specifies a different structure. Record the exact ordered durations `d1..dN` and require `sum(d) = T`. The stitching script accepts any `N`.

## Build an immutable continuity bible

Repeat the facts most vulnerable to model drift in every prompt:

- character geometry, colors, clothing, identity markers, and count;
- fixed set topology, landmark positions, scale, lighting, weather, and time of day;
- camera language, aspect ratio, rendering style, and color treatment;
- physical rules, prohibited transformations, and safety/tone limits;
- music BPM, instrumentation, ambience, voice policy, and effect vocabulary.

Treat reference images as authoritative where the provider supports them. Continue to state critical visual invariants in text because a preceding generated frame may already contain drift.

## Maintain an end-state ledger

After each completed generation, inspect the output and record:

| Field | Required observation |
|---|---|
| Characters | Who is visible, identity markers, pose, expression |
| Geography | Exact position, facing, travel direction, nearby landmarks |
| Action | Pending attack, collision, camera move, or other unresolved motion |
| Camera | Shot size, angle, movement, lens feel, composition |
| Effects | Active trails, particles, light, debris, decay state |
| Audio | Beat phase, musical energy, ambience, active effect or reverb tail |

Write prompt `k+1` from the observed final state of clip `k`, not solely from the original plan. Preserve the story goal while adapting the first seconds to the actual handoff.

## Prompt roles

### First segment

- Establish references, cast, world scale, fixed landmarks, and starting geography.
- Start the music and ambience once.
- End with a readable pending action or camera movement that the next segment can complete.

### Intermediate segment

Start with language equivalent to:

> Extend the selected video forward by exactly `{duration}` seconds. Continue its exact final camera frame, character positions, movement, effects, and audio without restarting.

Then restate the continuity bible, complete the pending action during the opening seconds, advance the story, and end on another explicit handoff. Avoid resolving the soundtrack or cutting to an unrelated location.

### Final segment

Continue the same way, but explicitly resolve the narrative and soundtrack inside the final duration. Define the last composition and prohibit new characters, locations, or open actions.

## Visual and audio seam rules

- Prefer true source extension and a hard frame boundary. A dissolve can create ghost limbs and does not fix changed identities or geography.
- Keep motion direction and camera velocity compatible across the boundary.
- Show physical cause and effect continuously: contact, acceleration, travel, arrival, then disappearance or recovery.
- Request continuation of the exact beat phase, instrumentation, ambience, and reverb. Generated audio may still drift; if phase-accurate music is mandatory, use a separately controlled music master in post-production.
- Avoid full-screen flashes or occlusion exactly at a seam unless intentionally used as a motivated transition.

## Review every boundary

For every cumulative boundary, inspect at least one frame shortly before and shortly after it, then play the surrounding seconds with audio. The number of checks grows with the number of clips; never limit review to the first two seams.
