---
name: tiktok-draft-uploader
description: Upload one user-specified local video to TikTok Studio, enter the supplied caption, and leave the composer open as an unpublished draft. Use when the user asks to create or prepare a TikTok video-post draft; do not use for publishing an already prepared post.
---

# TikTok Draft Uploader

Create an unpublished TikTok Studio upload from two required inputs:

- One local video file path.
- The exact caption text to enter.

If either input is missing or the video cannot be found, stop and request only the missing item. Resolve the video to an absolute path before browser work.

## Browser workflow

Use the `computer-use:computer-use` skill and its browser controls. Read its required guidance, confirmation policy, and file-upload documentation before acting.

1. Inspect open browser tabs. Reuse a TikTok Studio upload tab only when it is empty or already contains the same completed video and caption. Never overwrite or discard another unfinished post; open a separate TikTok Studio upload tab instead.
2. Open `https://www.tiktok.com/tiktokstudio/upload?from=webapp&tab=video` when no suitable composer exists. Use the user's named browser when specified; otherwise prefer the current in-app browser.
3. If login is required, use the existing signed-in session. Hand control to the user for passwords, one-time codes, CAPTCHAs, or other authentication challenges.
4. Upload the exact supplied file through the page's file chooser. Arm the browser `filechooser` wait before clicking **Select video**, then call the returned chooser's `setFiles` with the absolute path. The user's request to create a draft with a specifically identified video authorizes that upload; otherwise obtain confirmation immediately before transmission.
5. Wait until TikTok visibly reports upload completion. If TikTok offers to enable persistent automatic content-check settings, cancel by default; changing account settings is outside draft creation.
6. Replace TikTok's filename-derived description with the supplied caption exactly. Preserve line breaks, emoji, punctuation, mentions, and hashtags. Verify the visible description and ensure it is within TikTok's displayed character limit.
7. Leave cover, location, audience, schedule, comments, copyright checks, music, and all other posting options unchanged unless the user explicitly supplied values for them.

## Completion contract

A completed draft requires visible evidence of all three:

- The requested filename and an upload-complete state.
- The caption exactly present in the description field.
- The **Post** button remains unclicked.

Do not click **Post**. Publishing is representational communication and is outside this skill. If the user separately asks to publish, follow the active confirmation policy and request action-time confirmation immediately before clicking **Post**.

TikTok Studio on the web may not provide a server-side **Save draft** button. In that case, keep the populated upload composer open and mark its tab as a deliverable or handoff. Report it accurately as an unpublished composer retained in the open tab, not as a confirmed server-saved draft.

Finish with a compact report: filename, upload status, caption status, and `not published`.
