# Architecture and implementation reference

## Minimal shape

Start with composition, one feature module, and one shared service. Split further only when responsibilities diverge.

```text
shell.qml
components/
  Surface.qml
modules/
  bar/Bar.qml
services/
  Time.qml
theme/
  Theme.qml
```

```qml
// shell.qml
import Quickshell
import qs.modules.bar

ShellRoot {
    Bar {}
}
```

```qml
// services/Time.qml
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string text: Qt.formatDateTime(clock.date, "hh:mm")

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
```

A production entrypoint should remain boring. Large maintained shells converge on a shallow entrypoint that composes feature modules, while singleton services own shared state and side effects.

## Screen lifecycle

Windows are non-visual-object roots, so create one per screen with `Variants`, not a visual `Repeater`.

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData

            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32

            Text {
                anchors.centerIn: parent
                text: Time.text
            }
        }
    }
}
```

This tracks monitor connect/disconnect reactively. Never cache screen objects indefinitely without handling removal; they can become invalid after hotplug.

Decide per window:

- target screen;
- anchored edges and margins;
- layer/stacking behavior;
- exclusive zone (reserved workspace) versus overlay;
- focus and keyboard behavior;
- input mask/click-through behavior;
- opaque versus transparent surface format.

A rounded panel is normally a transparent square window containing a rounded rectangle. An empty `Region {}` mask makes a non-interactive overlay click-through. Explicitly set overlay/exclusive behavior rather than inheriting accidental defaults.

## Popup ownership and focus

Use `PopupWindow` for shell-owned anchored popups and set its parent/anchor relationship explicitly. Centralize mutually exclusive popup state in one controller/service so two modules do not race for focus or leave invisible focus grabs behind.

For expensive popups:

```qml
LazyLoader {
    id: popupLoader
    property bool popupOpen: false

    loading: true     // optional background preparation
    active: popupOpen

    PopupWindow {
        // parentWindow and anchor/relative position here
    }
}
```

Accessing `item` before asynchronous loading finishes can force synchronous completion on the UI thread. `Variants` inside a `LazyLoader` may also negate asynchronous loading; verify behavior on the installed version.

## Component API design

A reusable visual component should expose a small public surface:

```qml
Rectangle {
    id: root

    required property string label
    property bool active: false
    readonly property real contentWidth: text.implicitWidth
    signal activated()

    implicitWidth: text.implicitWidth + 16
    implicitHeight: text.implicitHeight + 8

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
    }

    TapHandler {
        onTapped: root.activated()
    }
}
```

Prefer properties/signals over reaching into child IDs, which are private outside their QML file. Use aliases sparingly when a child property truly belongs to the component's public API.

Centralize design tokens (colors, typography, spacing, radii, timings) in one theme singleton. Avoid a universal mega-component with dozens of booleans; compose small primitives instead.

## Sizing and layout

The critical invariant is:

```text
child implicit size → parent desired size
parent actual size  → child actual size
```

- A leaf defines useful `implicitWidth`/`implicitHeight`.
- A container derives implicit size from known child implicit sizes and spacing.
- The parent/layout constrains actual child size.
- Do not bind a parent's implicit size to `childrenRect` when child actual geometry depends on that parent.
- Use `WrapperItem`, `WrapperRectangle`, `WrapperMouseArea`, and `ClippingWrapperRectangle` for common one-child containers.
- Layouts default to non-zero spacing; set it explicitly for deterministic geometry.
- Avoid mixing anchors on an axis managed by a layout.

## Service singletons

Use this boundary for shared state:

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool running: process.running
    property bool available: false // set true only after valid output
    property string value: ""

    Process {
        id: process
        command: ["example", "--stream"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.value = data;
                root.available = true;
            }
        }
        onExited: (code, status) => {
            root.available = false;
            restart.start();
        }
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: process.running = true
    }
}
```

Add bounded backoff for unreliable services instead of a hot restart loop. Expose parsed, UI-ready state; do not make every widget parse process output independently.

Before creating a process adapter, check native modules:

| Need | Preferred import/API |
|---|---|
| Time | `Quickshell` / `SystemClock` |
| Files, JSON, processes, sockets, IPC | `Quickshell.Io` |
| Icons and wrappers | `Quickshell.Widgets` |
| Audio/video graph | `Quickshell.Services.Pipewire` |
| Media players | `Quickshell.Services.Mpris` |
| Tray | `Quickshell.Services.SystemTray` |
| Batteries/power profiles | `Quickshell.Services.UPower` |
| Notification daemon | `Quickshell.Services.Notifications` |
| NetworkManager | `Quickshell.Networking` |
| BlueZ | `Quickshell.Bluetooth` |
| Generic workspaces/toplevels | `Quickshell.WindowManager` where supported |
| Wayland protocols | `Quickshell.Wayland` |
| Hyprland | `Quickshell.Hyprland` |
| i3/Sway IPC | `Quickshell.I3` |
| Authentication | `Quickshell.Services.Pam`, `Polkit`, or `Greetd` with explicit review |

Availability is build- and version-dependent. Confirm the installed type reference before importing a module.

## Processes and parsers

`Process` does not invoke a shell. Correct:

```qml
command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"]
```

Incorrect:

```qml
command: ["wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"]
```

For one-shot output:

```qml
Process {
    command: ["uname", "-r"]
    running: true
    stdout: StdioCollector {
        onStreamFinished: root.kernel = text.trim()
    }
}
```

For an event stream, attach `SplitParser` and parse each record as it arrives. Keep stderr connected when failures matter. Never interpolate user-controlled content into `sh -c`; argument arrays avoid quoting and injection bugs.

## Persistence

Choose deliberately:

| Requirement | Mechanism |
|---|---|
| Survive only hot reload | `PersistentProperties` with a stable `reloadableId` |
| Small durable settings/state | `FileView` + `JsonAdapter` |
| Shell-owned durable files | `Quickshell.statePath()` or `dataPath()` |
| Rebuildable/transient data | `Quickshell.cachePath()` |
| Packaged asset | `Qt.resolvedUrl()` / `Quickshell.shellPath()` |

Watch files only when external edits should cause reload/reparse. Handle atomic replacement, missing files, invalid JSON, and write failures. Persist only user choices, not every derived property.

## IPC

Expose the smallest typed control surface:

```qml
IpcHandler {
    target: "launcher"

    function toggle(): void {
        LauncherState.open = !LauncherState.open;
    }

    function query(): bool {
        return LauncherState.open;
    }

    signal opened()
}
```

Inspect and call it with:

```bash
qs ipc -p /path/to/config show
qs ipc -p /path/to/config call launcher toggle
qs ipc -p /path/to/config prop get launcher someProperty
qs ipc -p /path/to/config wait launcher opened
qs ipc -p /path/to/config listen launcher opened
```

Functions need explicit supported argument and return types to register. Treat IPC as a user-session API: validate inputs and never expose arbitrary command execution.

## Performance

Optimize architecture before effects:

1. Eliminate duplicate processes, timers, watchers, and per-monitor services.
2. Replace polling with native/event-driven APIs.
3. Reduce update precision and expensive reactive dependency fanout.
4. Unload large optional trees; do not lazy-load tiny always-used controls.
5. Use `ListView` for large collections instead of instantiating everything.
6. Cache expensive image/metadata work with explicit invalidation.
7. Avoid huge variable-font variant sets; Quickshell 0.3 adds `DropExpensiveFonts` support, but version-check before using it.
8. Profile before deleting useful animations or visual polish.

## Failure states

Every service-backed feature needs a stable unavailable state:

- missing binary or DBus service;
- empty model/default device is null;
- process exits or emits malformed output;
- compositor protocol is unsupported;
- screen disappears;
- icon/resource is missing;
- config file is missing or invalid.

Use null-safe bindings where APIs may be absent, but do not scatter `?.` over an unclear lifecycle. Model availability explicitly.

## Security and ownership

Quickshell configurations execute code with the user's privileges and can start processes, use sockets, and talk to DBus. Disabling one feature does not sandbox a third-party shell.

- Review third-party configs and plugins before running them.
- Never embed secrets or pass them through IPC/argv/logs.
- Avoid shell command construction; validate paths and enum-like input.
- A session lock must unlock the compositor protocol before exiting and must be tested against sleep, wake, monitor hotplug, and failure paths.
- PAM and polkit changes are privileged authentication surfaces. Keep dedicated configs minimal and obtain explicit approval.
- Ensure exactly one notification daemon, lock service, polkit agent, bar, and shell instance owns each role.

## Evidence behind these patterns

- Official guide: configuration discovery, `Variants`, `Scope`, singletons, native services, and process guidance.
- Official sizing guide: implicit/actual size direction, `childrenRect` binding-loop warning, wrappers, and layout preference.
- Official FAQ: one process per widget is wasteful; loaders reduce memory; `Process`, `SplitParser`, resource paths, and IPC usage.
- Official examples: screen variants, click-through masks, layershell, PipeWire tracking, lazy OSD windows, session lock, and reload UI.
- Caelestia and DankMaterialShell: thin composition roots, feature modules, singleton service layers, reusable components, centralized state/theme, and selective loaders. Their scale is evidence for boundaries, not a mandate to reproduce their complexity.
