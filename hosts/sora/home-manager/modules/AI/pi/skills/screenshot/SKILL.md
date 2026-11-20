---
name: screenshot
description: Take screenshots in Wayland/Hyprland or X11 environments using grim or ImageMagick.
---

## Screenshotting

### Detection

Check the display server before choosing a tool:

- **`$XDG_SESSION_TYPE`** — `wayland` or `x11`
- **`$XDG_CURRENT_DESKTOP`** — `Hyprland`, `sway`, etc.

### Tools by environment

| Environment | Full screen | Focused monitor | Region | Browser page |
|---|---|---|---|---|
| Wayland + Hyprland | `grim` | `grim -o $(hyprctl monitors -j \| jq -r '.[] \| select(.focused) \| .name')` | `slurp \| grim -g -` | Use `browser` skill |
| Wayland + wlroots | `grim` | `grim -o <output>` | `slurp \| grim -g -` | Same |
| X11 | `import -window root` | `import -window root -crop <geo>` | `import` (click-drag) | Same |

### Browser screenshots

When the target is a **web page** (not the desktop/app), load the `browser`
skill and use `agent_browser` instead of grim. It can capture JavaScript-rendered
content and full-page screenshots. Pair the result with the `image-analyzer`
subagent when visual analysis is needed.

### Recipes

**Full screen (Wayland):**

```bash
nix run nixpkgs#grim -- /tmp/pi/screenshot.png
```

**Single monitor (Hyprland):**

```bash
monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
nix run nixpkgs#grim -- -o "$monitor" /tmp/pi/screenshot.png
```

**Region select (Wayland):**

```bash
nix run nixpkgs#slurp -- | nix run nixpkgs#grim -- -g - /tmp/pi/screenshot.png
```

**Full screen (X11):**

```bash
nix run nixpkgs#imagemagick -- import -window root /tmp/pi/screenshot.png
```

### Viewing

Open with the default image viewer:

```bash
handlr open /tmp/pi/screenshot.png
```

### Analysis

After taking a screenshot, use the `image-analyzer` subagent to describe the image:

Use `subagent` with the configured `image-analyzer` agent and pass the image path.

Note: the image-analyzer may hallucinate visual details. Treat its descriptions as approximate.
