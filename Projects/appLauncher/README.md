# App Launcher

The deployed launcher is available after a NixOS/Home Manager rebuild:

```sh
qs -c appLauncher -n
```

For foreground development directly from this checkout:

```sh
qs -p ~/Projects/NixConfig/Projects/appLauncher -n
```

Toggle an already-running deployed launcher:

```sh
qs ipc -c appLauncher call launcher toggle
```

Keyboard controls: fuzzy type-to-search; `↑/↓`, `Ctrl+J/K`, or `Ctrl+N/P` to navigate; `Enter` to launch; `Ctrl+Space` to favorite; `Ctrl+F` for favorites-only; `Ctrl+1/2/3` to sort; `Ctrl+L` to clear; `Esc` to close. The mouse is optional.

Hyprland starts or toggles it with `Super+D`; the launcher opens on the focused monitor.
