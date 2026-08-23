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

Open the full settings dashboard from the gear button or IPC:

```sh
bar ipc call bar toggleSettings
bar ipc call bar showSettings
bar ipc call bar hideSettings
bar ipc call bar resetSettings
```

The dashboard controls font family and scale, horizontal and vertical bar size, opacity, radius, margins, widget visibility, edge position, metrics refresh rate, network units, clock format, date visibility, and theme colors. Changes apply live and persist under Quickshell's state directory.

Other controls remain available through IPC:

```sh
bar ipc call bar setPosition top
bar ipc call bar cyclePosition
bar ipc call bar position
```

Valid positions are `left`, `right`, `top`, and `bottom`; the source default is `left`.

This first pass deliberately runs as an overlay with the layer namespace `bar-preview`; it does not reserve workspace space or replace Noctalia yet.
