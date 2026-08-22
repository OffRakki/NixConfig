# Ciel Bar

A Quickshell 0.3 status bar using the same visual language as the app launcher. The layout adapts to all four screen edges and includes workspaces, the active window, MPRIS media controls, system metrics, SystemTray items, PipeWire volume, and a clock.

Run the preview directly from this checkout:

```sh
qs -p ~/Projects/NixConfig/Projects/bar
```

The source default is `left`. Change the running preview without restarting it:

```sh
qs ipc -p ~/Projects/NixConfig/Projects/bar call bar setPosition top
qs ipc -p ~/Projects/NixConfig/Projects/bar call bar setPosition right
qs ipc -p ~/Projects/NixConfig/Projects/bar call bar cyclePosition
qs ipc -p ~/Projects/NixConfig/Projects/bar call bar position
```

Valid positions are `left`, `right`, `top`, and `bottom`. The selected position is persisted under Quickshell's state directory.

This first pass deliberately runs as an overlay with the layer namespace `ciel-bar-preview`; it does not reserve workspace space or replace Noctalia yet.
