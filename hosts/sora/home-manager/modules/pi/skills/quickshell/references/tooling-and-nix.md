# Tooling, debugging, packaging, and Nix

## Configuration discovery

Quickshell searches each XDG config directory under `quickshell/`:

```text
$XDG_CONFIG_HOME/quickshell/shell.qml          default config
$XDG_CONFIG_HOME/quickshell/<name>/shell.qml   named config
```

If the top-level `quickshell/shell.qml` exists, named subdirectories are not considered. Select explicitly when ambiguity matters:

```bash
qs -c <name>
qs -p /absolute/path/to/config-directory
qs -p /absolute/path/to/file.qml
```

For development, prefer `-p` against repository source and keep it attached to the terminal. Use a named XDG config for the deployed shell.

## CLI operations

Always inspect the installed help because subcommands and flags evolve:

```bash
qs --version
qs --help
qs list --help
qs log --help
qs ipc --help
```

Common Quickshell 0.3 operations:

```bash
qs -p /path/to/config                    # run in foreground; live reload is on
qs -p /path/to/config -n -d              # no duplicate, daemonized
qs list --all                            # include all configs
qs list --all --json                     # machine-readable instances
qs log -p /path/to/config -f             # follow selected instance log
qs kill -p /path/to/config               # stop selected instance
qs ipc -p /path/to/config show           # inspect typed IPC targets
qs ipc -p /path/to/config call T F args  # invoke a function
```

Instance selectors include `--id`, `--pid`, and usually config/path selection. Multiple instances make unqualified `kill`, `log`, or IPC calls risky; select the target explicitly.

Useful launch diagnostics:

```bash
qs -p /path/to/config -v                 # Quickshell INFO logs
qs -p /path/to/config -vv                # Quickshell DEBUG logs
qs -p /path/to/config --log-times
qs -p /path/to/config --log-rules 'quickshell.*=true'
```

`qs --debug <port>` exposes QML debugging; `--waitfordebug` waits for the debugger. Use only on a trusted local session.

## Live reload

File watching is normally enabled. A good reload-aware design:

- uses `Scope`, `Singleton`, `Variants`, and Quickshell window types so reload ownership is clear;
- uses `PersistentProperties` only for transient UI state worth preserving;
- does not leak external processes or duplicate signal connections across reloads;
- tolerates a failed reload while the previous good generation remains alive;
- exercises both soft and hard reload behavior when windows or screen topology changed.

Quickshell 0.3 supports `QS_DISABLE_FILE_WATCHER`; older versions may not. Avoid environment flags unless confirmed by the installed version/changelog.

## Editor setup

Install Qt's `qmlls` and keep an empty `.qmlls.ini` beside `shell.qml`. Quickshell replaces it with machine-specific import information. Add it to `.gitignore`; do not ship one machine's generated paths.

Helix has built-in QML syntax and qmlls support. Still expect limitations:

- malformed QML can disable useful completion/linting;
- Quickshell API documentation may not appear in LSP hover;
- some Quickshell types can remain unresolved depending on version/tooling.

Use explicit typed properties and balanced/valid files so qmlls can help. Format with the project's `qmlformat` policy; do not reformat an unrelated shell wholesale.

## Debugging sequence

1. Run the target config in the foreground with `-p` and `-vv`.
2. Fix the first parser/import/type error before interpreting cascaded errors.
3. Check for binding loops, undefined IDs, zero-sized items, null service objects, and missing imports.
4. Confirm the expected Quickshell version and compiled module exists.
5. Inspect `qs list --all --json` for duplicate or stale instances.
6. Inspect live logs with an explicit path/config/instance selector.
7. Use `qs ipc ... show` before blaming the compositor for a missing command.
8. Reproduce with a minimal window/service if a Qt or Quickshell bug is plausible.

Typical symptoms:

| Symptom | First checks |
|---|---|
| Invisible component | zero implicit/actual size, opacity, loader state, clipping |
| Binding loop warning | `childrenRect`, parent/child size cycle, two-way assignments |
| Popup in wrong place | parent window, anchor item, screen, transformed coordinates |
| Bar reserves wrong space | panel anchors, exclusive zone, margins, compositor layer |
| Duplicate updates | per-widget process/timer, duplicate singleton/import, stale instance |
| High idle CPU | polling frequency, seconds clock, animations, process restart loop |
| Missing icons | icon theme, `Quickshell.iconPath` fallback/check, SVG support |
| Reload loses UI state | `PersistentProperties` identity or state placed in a recreated object |
| Works outside Nix only | Qt/QML module closure, dependency/Qt mismatch, generated import paths |

## Nix package choice

Prefer, in order:

1. `pkgs.quickshell` from the pinned Nixpkgs when its version supports the required API.
2. The official Quickshell flake pinned to a tag/revision when a newer feature is necessary.
3. Master only when an unreleased API is deliberately accepted.

Official flake wiring:

```nix
{
  inputs.quickshell = {
    url = "github:quickshell-mirror/quickshell?ref=<tag>";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

The package is `inputs.quickshell.packages.${pkgs.system}.default`. Making its `nixpkgs` input follow the system Nixpkgs is important: Quickshell uses private Qt APIs and a Qt ABI mismatch can crash it.

When additional QML modules are required, the official package supports a `withModules` form. Confirm its current signature in the pinned flake before writing Nix; module packaging changes are version-sensitive.

Optional runtime Qt modules depend on actual assets/features:

- Qt SVG for SVG icons/images;
- Qt image formats for WebP and uncommon formats;
- Qt Multimedia for media playback;
- Qt5Compat only for effects that still require it; prefer Qt Quick Effects `MultiEffect` where practical.

Do not add every Qt module preemptively.

## Home Manager deployment

In Lucky's environment, edit source under `~/Projects/NixConfig/`, never generated `~/.config` output.

Prefer Home Manager's maintained module when the pinned Home Manager provides it:

```nix
{pkgs, ...}: {
  programs.quickshell = {
    enable = true;
    package = pkgs.quickshell;
    configs.main = ./quickshell; # directory containing shell.qml
    activeConfig = "main";
    systemd.enable = true;
  };
}
```

`configs` deploys named source directories under `$XDG_CONFIG_HOME/quickshell`; names cannot contain `/`. `activeConfig` selects the config used by the generated service. The service runs Quickshell in the foreground, restarts on failure, and attaches to `programs.quickshell.systemd.target`, which defaults to Home Manager's Wayland session target.

On an older Home Manager without this module, fall back to `home.packages` plus `xdg.configFile."quickshell/main".source = ./quickshell`. Adapt to existing repository patterns after reading related modules. Keep shell source in NixConfig and use a named config so `qs -c main` is deterministic.

Quickshell derives shell identity from the config path. Version 0.3 stopped canonicalizing config paths, which fixed Nix store-target changes altering shell identity when the stable symlink path stays constant. On older releases, or after changing the visible path, state/cache identity can move. For a deliberately stable identity, verify support for `//@ pragma ShellId <id>` in the installed version before adding it.

Optional current-version pragmas belong at the beginning of `shell.qml` and must be version-checked, for example:

```qml
//@ pragma ShellId main
//@ pragma AppId org.example.shell
```

Do not copy environment/performance pragmas from another shell without understanding them.

## Autostart ownership

Choose one mechanism:

- compositor `exec-once`/startup command, or
- a Home Manager/systemd user service tied to the graphical session.

Never configure both. A baseline command is:

```bash
qs -c main -n -d
```

For a systemd unit, do not daemonize; let systemd own the foreground process, restart policy, and logs. Prefer `programs.quickshell.systemd` over hand-writing the unit when available. Make it part of the compositor/graphical session lifecycle rather than a generic boot target if it requires Wayland display environment. Ensure compositor systemd integration is enabled when selecting a compositor-specific target, and read existing compositor/service patterns before adding it.

When replacing another desktop component, remove its autostart only after the Quickshell equivalent works. Check for ownership collisions with Waybar, notification daemons, lock services, wallpaper tools, OSDs, and polkit agents.

## Nix validation

For a Pi/NixConfig skill or shell change, use the repository's configured Nix workflow. At minimum:

```bash
nix flake check --no-build
```

For actual host integration, build before applying. Do not claim runtime availability until Home Manager/NixOS activation updates generated paths.

## Building Quickshell itself

Most shell work does not require compiling Quickshell. If packaging or hacking Quickshell is explicitly required, read the pinned source's complete `BUILD.md` first.

Current upstream essentials:

- CMake + Ninja; Qt 6.6 or newer in current source;
- base dependencies include Qt Base/Declarative, libdrm, shader tools, SPIR-V tools, pkg-config, and CLI11;
- private Qt APIs mean Quickshell must be rebuilt for each Qt release;
- feature flags control Wayland/X11, layer shell, session lock, screencopy, PipeWire, tray, MPRIS, PAM, polkit, Hyprland, and i3 support;
- omitted dependencies require explicitly disabling their features;
- package builds should set a descriptive `DISTRIBUTOR` value;
- upstream recommends keeping the crash handler and jemalloc unless there is a concrete packaging reason not to.

Generic upstream build shape:

```bash
cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release <feature flags>
cmake --build build
cmake --install build
```

Do not transplant these commands into Nix packaging. Use the upstream flake/derivation as the reference and preserve Qt closure consistency.

## Version-sensitive facts to re-check

Quickshell is pre-1.0. Before relying on any of these, consult the exact changelog/type reference:

- module/type names and compositor protocol coverage;
- CLI selectors and IPC signal/property subcommands;
- preprocessors and pragmas (`ShellId`, `AppId`, `DefaultEnv`, version gates);
- Networking, Bluetooth, generic WindowManager, polkit, screencopy, and newer Wayland APIs;
- loader/reload behavior and known monitor hotplug bugs;
- Nix `withModules` interface;
- minimum Qt version and build flags.

Official sources:

- Guide/type reference: https://quickshell.org/docs/
- Git source: https://git.outfoxxed.me/quickshell/quickshell
- GitHub mirror: https://github.com/quickshell-mirror/quickshell
- Examples: https://github.com/quickshell-mirror/quickshell-examples
- Home Manager module: https://github.com/nix-community/home-manager/blob/master/modules/programs/quickshell.nix
- Qt QML reference: https://doc.qt.io/qt-6/qtqml-index.html
- Qt Quick reference: https://doc.qt.io/qt-6/qtquick-index.html
- Qt Quick performance/profiling: https://doc.qt.io/qt-6/qtquick-performance.html
