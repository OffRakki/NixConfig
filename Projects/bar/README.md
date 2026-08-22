# Bar

A Quickshell 0.3 status bar using the same visual language as the app launcher. The layout adapts to all four screen edges and includes workspaces, the active window, MPRIS media controls, system metrics, SystemTray items, PipeWire volume, and a clock.

After a NixOS/Home Manager rebuild, start one canonical packaged instance:

```sh
bar
```

The project owns its lifecycle manager. Every invocation stops all matching instances across displays, removes their dead runtime records, and starts exactly one copy of the configuration bundled with the package. The same manager works directly from this checkout:

```sh
./launch
./launch --foreground
./launch --stop
```

Control whichever packaged or source-tree instance is running through the project command:

```sh
bar ipc call bar setPosition top
bar ipc call bar setPosition right
bar ipc call bar cyclePosition
bar ipc call bar position
```

Valid positions are `left`, `right`, `top`, and `bottom`. The source default is `left`; the selected position persists under Quickshell's state directory.

This first pass deliberately runs as an overlay with the layer namespace `bar-preview`; it does not reserve workspace space or replace Noctalia yet.
