# App Launcher

After a NixOS/Home Manager rebuild, start the launcher with:

```sh
app-launcher
```

The project owns its lifecycle manager. Hyprland preloads one hidden instance, and each call toggles it over IPC. Stale, duplicate, or outdated instances are cleaned up before exactly one current copy starts. Scripts and keybindings must use this command instead of invoking `qs` directly.

The same lifecycle guarantees apply during source-tree development:

```sh
./launch --foreground
./launch --hidden
./launch --stop
```

Keyboard controls: fuzzy type-to-search; `↑/↓`, `Ctrl+J/K`, or `Ctrl+N/P` to navigate; `Enter` to launch; `Ctrl+Space` to favorite; `Ctrl+F` for favorites-only; `Ctrl+1/2/3` to sort; `Ctrl+L` to clear; `Esc` to close. The mouse is optional.

Hyprland starts or toggles it with `Super+D`; the launcher opens on the focused monitor.

## Theme

Noctalia renders `theme.json.in` to `$XDG_STATE_HOME/noctalia/app-launcher.json` (default: `~/.local/state/noctalia/app-launcher.json`). The launcher watches that JSON through Quickshell's native `FileView`/`JsonAdapter`; text, focus borders, selections, and favorites update without restarting or clearing the search. The outer card stays neutral black at 60% opacity, with Hyprland providing blur.

Missing theme files use the built-in dark fallback; malformed JSON keeps the last valid palette. For source-tree testing, set `APP_LAUNCHER_THEME` to a separate palette file before `./launch --hidden`. Inspect the loaded colors with `./launch ipc call launcher theme`.

`bash ./test-theme FIRST_RENDERED_PALETTE SECOND_RENDERED_PALETTE` exercises live reload, fallback/error handling, atomic replacements, and single-instance ownership. It temporarily runs the source launcher and restores the installed launcher afterward.
