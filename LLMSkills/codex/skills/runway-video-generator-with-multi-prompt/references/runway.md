# Runway and Seedance browser workflow

Read this only when Runway or Seedance is the selected provider.

## First clip

Use Reference mode when the user supplied authorized reference media. Confirm the uploaded thumbnail, model, aspect ratio, audio toggle, and duration before generating.

## Continuations

Use Extend mode and select the immediately preceding completed output, not an older asset with the same generated title. Asset titles commonly repeat. Scope selection to the asset picker, prefer the newest matching thumbnail or timestamp, and confirm the input player shows the expected source duration.

The duration control can display a typed value inside its popover without committing it. Commit the value, close the popover, and verify that the main settings toolbar itself shows the intended duration before pressing Generate.

## Queue handling

`In queue` in Unlimited Explore Mode is a live job. Poll that same session and occasionally reload it to refresh status. Do not submit a duplicate merely because the accessibility tree has not changed or the wait lasts many minutes. Only restart after authoritative UI state reports failure, cancellation, or a missing job.

Keep user-visible progress concise during long queues. After generation begins, monitor percentages until the completed video player and Download action appear.

## Downloads and output

Download each clip as soon as it completes and rename it deterministically outside the browser. Verify file size and media properties before removing or replacing any download. Preserve source `.mov` files alongside the stitched result when practical.

Mark the Runway session as a deliverable when supported. Uploading the locally stitched final video back to Runway is optional and requires that cloud upload to remain within the user's requested scope.
