---
name: obs-record-roblox-player
description: Configure OBS Studio to record the entire Roblox Player game view without the mouse cursor, and verify the resulting recording. Use for black previews, cropped game views, or excessive blank space in Roblox recordings.
---

# Record Roblox Player with OBS

Configure the existing OBS scene for the user's current Roblox Player window. Preserve unrelated scenes, audio sources, recording settings, and files. Do not start a stream.

When operating the Windows UI, load and follow the available `computer-use` skill. Inspect the current OBS and Roblox Player windows before changing anything; do not assume an earlier window size, selected source, or scene is still current.

## Capture source

- Prefer a **Window Capture** source targeting `[RobloxPlayerBeta.exe]: Roblox`. Set Capture Method to **Windows 10 (1903 and up)** / Windows Graphics Capture when Auto shows a black or white preview. On some Roblox versions OBS Game Capture cannot capture the Player; do not keep an unusable Game Capture source above the working source.
- Disable **Capture Cursor** on the working source. Choose the client-area option based on a live preview of the game, not by assumption. Avoid display capture unless window capture fails and the user accepts possible desktop or notification exposure.
- Confirm the source shows the complete live game image, including its UI at all four edges. A Roblox notification or dialog inside the Player is part of the captured image; dismiss it only when appropriate for the user's session.

## Fit the recording frame

1. Read OBS **Settings → Video** for base canvas and output resolution. Inspect the current Player window size and OBS preview. Distinguish the canvas from the dark OBS editor area around it: only the canvas is recorded.
2. Select the working Window Capture source. Remove unintended transform crop, then use **Transform → Fit to Screen** (`Ctrl+F`). This preserves the whole image. Do not use Stretch to Screen or crop merely to hide aspect-ratio bars, because these can distort or cut the game.
3. Check the source's red bounds against the canvas and inspect all four game edges. If the image remains small or clipped, inspect **Edit Transform** for position, size, bounding-box mode, and crop values; correct the observed mismatch. Do not copy numeric crop or scale values from a different Player window or display-scaling setup.
4. If the Player window is much smaller or a different aspect ratio than the intended recording, resize/maximize the Player if suitable, then recheck and refit the source. Preserve aspect ratio; explain any unavoidable bars.

## Verify and report

- Verify the live OBS preview before saying the setup is complete. For a high-confidence check, make a short local test recording, inspect its dimensions and representative frame, and confirm the complete game view is present with no cursor. Remove no existing recordings; a new test clip may be left in the configured recording folder unless the user asks otherwise.
- Report separately: source/method, cursor status, canvas/output resolution, whether the full game view was confirmed in preview, and whether an actual video file was checked. Do not call preview-only inspection a verified recording.
- If Roblox capture still fails, state the precise remaining symptom and leave the working source intact; do not silently substitute a different game or claim a successful Roblox test from an unrelated Player session.
