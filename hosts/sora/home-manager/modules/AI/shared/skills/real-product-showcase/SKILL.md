---
name: real-product-showcase
description: Record real product demos from terminal, browser, or apps and ship them as verified media. Never use fake or synthetic UI for hero assets. Use when asked for real demos, hero MP4s/GIFs, asciinema or Remotion recordings, browser walkthroughs, app recordings, or README/PR media.
---

# Real Product Showcase

Record the real product. Cut the tape. Check that viewers can still tell what product it is.

Never invent synthetic UI frames, mock dashboards, or recreated terminal renderers for a hero clip when a real demo is requested.

## Hard rules

1. **Record the real thing.** Drive the actual CLI, web app, or native app and capture that session.
2. **Keep the chrome.** Terminal prompt bar, browser URL bar, or app title bar must stay in frame. If viewers cannot tell which product it is, the crop failed.
3. **Mark the beats.** Tag each proof step so one take becomes a master plus short focused clips.
4. **Ship smooth video.** Prefer 1080p H.264 `yuv420p` at 30 or 60 fps. Reject 1 fps slideshows. Do not promote a GIF as the master hero.
5. **Check before you publish.** Probe codec, size, and fps with `ffprobe`. Confirm chrome is uncut and each clip ends on a real success.

## Which surface

| Surface | Capture | Read next |
|---|---|---|
| Terminal / CLI / TUI | asciinema v3 + markers, then `agg` renders the `.cast` | [references/terminal-asciinema.md](references/terminal-asciinema.md) |
| Browser / web app | Playwright/CDP or screen recording of the live UI | [references/browser-capture.md](references/browser-capture.md) |
| Desktop / mobile apps | OS or device recorder + scene markers | [references/desktop-mobile-apps.md](references/desktop-mobile-apps.md) |
| Post | Trim scenes, fit framing, render 60 fps master | [references/remotion-post.md](references/remotion-post.md) |
| Checks | `ffprobe`, framing stills, clip contracts | [references/quality-gates.md](references/quality-gates.md) |

Pick one surface. Do not stitch fake terminal frames into a browser story.

## Workflow

1. **Write the beats**: List 3–6 concrete steps that prove the product works; each beat needs a visible win (file on disk, live status, verified output).
2. **Set up a disposable runtime**: Use the actual target binary/build/URL with an isolated home/profile so secrets stay out of the recording. Keep output artifacts outside NixConfig (e.g., `~/sync/geral/Ciel/`).
3. **Record with markers**: Start the recorder, drop a marker at the start of each beat, keep typing/idle tight, and preserve product chrome.
4. **Cut and render**: Label markers in order, compress idle waits, keep every beat readable, and render one master plus optional per-scene clips.
5. **Gate and publish**: Run the checks in [references/quality-gates.md](references/quality-gates.md) before shipping. GIF is fine for social fallback, never as the master hero.

## Refuse these

- Synthetic mock frames sold as a live session
- Prompt bar, URL bar, or nav chrome cropped off
- Long typing with no real command or UI result
- A "master" that is a stretched low-fps GIF
- Missing markers when per-scene clips are required

## Done when you can report

1. Surface and capture path
2. Scenes and durations
3. Output files plus `ffprobe` summary
4. Confirmation that product chrome is visible and each beat succeeded
