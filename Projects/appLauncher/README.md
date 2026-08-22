# App Launcher

After a NixOS/Home Manager rebuild, start the launcher with:

```sh
app-launcher
```

The project owns its lifecycle manager. Every call stops all matching launcher instances across displays, removes dead runtime records, and starts exactly one copy of the configuration bundled with the package. Scripts and keybindings must use this command instead of invoking `qs` directly.

The same lifecycle guarantees apply during source-tree development:

```sh
./launch --foreground
./launch --stop
```

Keyboard controls: fuzzy type-to-search; `↑/↓`, `Ctrl+J/K`, or `Ctrl+N/P` to navigate; `Enter` to launch; `Ctrl+Space` to favorite; `Ctrl+F` for favorites-only; `Ctrl+1/2/3` to sort; `Ctrl+L` to clear; `Esc` to close. The mouse is optional.

Hyprland starts or toggles it with `Super+D`; the launcher opens on the focused monitor.
