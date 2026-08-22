# App Launcher

After a NixOS/Home Manager rebuild, start the launcher with:

```sh
app-launcher
```

Every call stops any existing launcher instance and starts one fresh canonical instance. Use this command from scripts and keybindings instead of invoking `qs` directly.

For foreground development directly from this checkout, stop the deployed instance first:

```sh
qs kill -c appLauncher --any-display || true
qs -p ~/Projects/NixConfig/Projects/appLauncher
```

Keyboard controls: fuzzy type-to-search; `↑/↓`, `Ctrl+J/K`, or `Ctrl+N/P` to navigate; `Enter` to launch; `Ctrl+Space` to favorite; `Ctrl+F` for favorites-only; `Ctrl+1/2/3` to sort; `Ctrl+L` to clear; `Esc` to close. The mouse is optional.

Hyprland starts or toggles it with `Super+D`; the launcher opens on the focused monitor.
