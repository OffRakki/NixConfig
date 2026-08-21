---
name: quickshell
description: Design, implement, refactor, debug, and package desktop shells built with Quickshell and QML, including panels, widgets, popups, launchers, OSDs, notifications, IPC, compositor integrations, and NixOS/Home Manager deployment. Use whenever work touches Quickshell, qs, shell.qml, or a Quickshell-based desktop shell.
---

# Quickshell Development

Build against the installed Quickshell version, not remembered APIs. Quickshell is pre-1.0 and changes between releases.

## Start here

1. Read every existing shell file relevant to the change, including its entrypoint, imported components, services, theme/config objects, and deployment module.
2. Run `qs --version` and inspect `qs --help` plus the relevant subcommand help. Match documentation and examples to that version.
3. Identify the target compositor, display protocol, screens, scale factors, and whether the shell replaces existing bar/notification/lock/polkit services.
4. Prefer the official type reference and examples. Treat large community shells as architecture evidence, not copy-paste APIs.
5. Make the smallest coherent vertical slice and run it in the foreground before wiring autostart.

Read [references/architecture.md](references/architecture.md) for project structure, QML patterns, windows, services, performance, and security. Read [references/tooling-and-nix.md](references/tooling-and-nix.md) for CLI, debugging, editor support, packaging, Home Manager, and source builds.

## Source hierarchy

Use evidence in this order:

1. Installed `qs --version` and CLI help.
2. [Versioned official guide and type reference](https://quickshell.org/docs/).
3. [Official source](https://git.outfoxxed.me/quickshell/quickshell), especially changelogs, `BUILD.md`, and module/type documentation.
4. [Official examples](https://github.com/quickshell-mirror/quickshell-examples).
5. Maintained shells such as [Caelestia](https://github.com/caelestia-dots/shell) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), used only to compare structure and tradeoffs.

When docs, source, and the installed binary disagree, stop and resolve the version mismatch. Do not paper over it with guessed compatibility code.

## Architecture contract

Keep these layers distinct:

```text
shell.qml            composition only; starts top-level shell features
components/          small reusable visual primitives and controls
modules/             complete UI features: bar, launcher, OSD, dashboard
services/            typed singleton adapters for system state and side effects
config/ or settings/ user options, defaults, validation, persistence
theme/               colors, typography, spacing, animation tokens
assets/               icons, shaders, images, fonts
```

For a small shell, collapse empty layers. Do not build a cathedral for a clock.

- Keep visual components declarative: inputs through typed/required properties, outputs through signals.
- Put shared system state and long-lived work in `pragma Singleton` files rooted at `Singleton`.
- After checking the installed build/version, use available Quickshell native services before polling subprocesses: `SystemClock`, MPRIS, PipeWire, SystemTray, UPower, Notifications, Networking, Bluetooth, Hyprland/i3, and WindowManager.
- Create one system integration or long-lived process per service, not one per widget or monitor.
- Use `Variants` for non-`Item` objects such as one window per screen; use `Repeater` for short visual collections and `ListView` for long or scrollable collections.
- Use `Loader` for optional `Item` trees and `LazyLoader` for optional windows/non-`Item` trees. `visible: false` hides an object but does not unload it.
- Use `IpcHandler` for an explicit, typed command surface instead of filesystem flags or ad-hoc process signals.

## QML rules that prevent expensive nonsense

- Prefer typed properties and function signatures. Use `required` for caller-owned inputs and `readonly` for derived state; reserve `var` for genuinely dynamic data.
- Prefer reactive property bindings over imperative synchronization. Do not assign to a property if doing so accidentally destroys a binding.
- Qualify cross-object access with an `id`; avoid ambiguous scope and fragile `parent.parent` chains.
- Use `import qs.path.to.module`; do not introduce legacy `root:/...` imports. Nearby uppercase QML files are implicit types.
- Let implicit size flow child → parent and actual size flow parent → child. A container-managed child should not fight its layout by setting actual width/height.
- Avoid `childrenRect`-based self-sizing when children anchor to the parent; that creates binding loops. Prefer layouts or Quickshell wrapper components.
- Prefer `RowLayout`/`ColumnLayout` over `Row`/`Column` unless non-pixel-aligned positioning is intentional. Set `spacing` explicitly.
- Resolve bundled resources with `Qt.resolvedUrl()` or `Quickshell.shellPath()`. Store durable data/state/cache under `Quickshell.dataPath()`, `statePath()`, or `cachePath()`.

## Process and data rules

- `Process.command` is an argument list and does not invoke a shell: `["program", "arg"]`. Use `sh -c` only when shell syntax is truly required, and never concatenate untrusted input into it.
- Use `StdioCollector` for bounded one-shot output and `SplitParser` for long-running line/event streams.
- Prefer event streams and native services over frequent polling. Match timer precision to what the UI displays; a minute clock does not need second-level wakeups.
- Use `FileView` with `JsonAdapter` for small structured files. Enable watching deliberately and handle malformed/missing data with defaults.
- Use `PersistentProperties` only for state that should survive a live reload. It is not disk persistence.
- Keep secrets out of QML, logs, IPC, command lines, and checked-in JSON. A Quickshell config is executable code, not a sandbox.

## Implementation loop

1. Build the data/service layer with a narrow typed interface.
2. Build one visual component against fake or local state when practical.
3. Compose the feature into one window/screen.
4. Add multi-screen behavior and hotplug handling.
5. Add IPC/keybind exposure only for intentional public actions.
6. Exercise open, close, reload, screen removal, missing service, and empty/null state.
7. Inspect warnings before polishing visuals. Binding loops wearing blur are still binding loops.

## Validation

Run the checks available to the project; do not invent a universal headless test command.

```bash
qs --version
qs -p /absolute/path/to/config                 # foreground development instance
qs -p /absolute/path/to/config -vv             # verbose startup/debugging
qs list --all
qs log -p /absolute/path/to/config -f
qs ipc -p /absolute/path/to/config show
```

Also:

- Keep an empty `.qmlls.ini` beside `shell.qml`; Quickshell manages its machine-specific contents, so gitignore it.
- Use `qmlls` continuously; run `qmllint` and `qmlformat` when the project's wrapped Qt environment makes them reliable.
- Use Qt's QML Profiler for measured binding, object-creation, JavaScript, or frame-time problems instead of guessing.
- Test live reload after both valid and intentionally invalid edits.
- Check all connected screens and scale factors when window geometry changed.
- Verify that only one autostart mechanism and one instance own each desktop service.
- On Nix-managed systems, edit the declarative source rather than generated `~/.config` output, then evaluate/build before activation.

## Stop conditions

Ask Lucky before changing compositor choice, replacing an existing notification/lock/polkit agent, adding privileged PAM/polkit behavior, introducing a compiled QML plugin/backend, or selecting a moving Quickshell revision over a tagged/Nixpkgs release.
