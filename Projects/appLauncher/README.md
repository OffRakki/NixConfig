# App Launcher

After a NixOS/Home Manager rebuild, start the launcher with:

```sh
app-launcher
```

The Rust `app-launcher` binary owns lifecycle management, filesystem locking, typed Quickshell registry parsing, and IPC routing. Hyprland preloads one hidden instance, and each call toggles it over IPC. Stale, duplicate, or outdated instances are cleaned up before exactly one current copy starts. Scripts and keybindings must use this command instead of invoking `qs` directly. QML still owns the UI; the separate Rust password helper retains the credential boundary.

The same lifecycle guarantees apply during source-tree development. `./launch` is only an exec shim that selects the source QML directory and uses the installed lifecycle binary. To test a newly built manager before activation, set `APP_LAUNCHER_BINARY` to its absolute path:

```sh
export APP_LAUNCHER_BINARY=/tmp/app-launcher-target/debug/app-launcher
./launch --foreground
./launch --hidden
./launch --stop
```

Keyboard controls: fuzzy type-to-search; `↑/↓`, `Ctrl+J/K`, or `Ctrl+N/P` to navigate; `Enter` to launch; `Ctrl+Space` to favorite; `Ctrl+Shift+↑/↓` or `Ctrl+Shift+J/K` to reorder runtime favorites in Smart sort; `Ctrl+F` for favorites-only; `Ctrl+1/2/3` to sort; `Ctrl+L` to clear; `Esc` to close. The mouse is optional.

Declaratively pinned apps live in `$XDG_CONFIG_HOME/app-launcher/config.json` (overridable via `APP_LAUNCHER_CONFIG`) as `{"pinned": ["app-id", ...]}`; they always lead Smart sort in declared order ahead of runtime favorites.

Hyprland starts or toggles it with `Super+D`; the launcher opens on the focused monitor.

## Theme

Noctalia renders `theme.json.in` to `$XDG_STATE_HOME/noctalia/app-launcher.json` (default: `~/.local/state/noctalia/app-launcher.json`). The launcher watches that JSON through Quickshell's native `FileView`/`JsonAdapter`; text, focus borders, selections, and favorites update without restarting or clearing the search. The outer card stays neutral black at 60% opacity, with Hyprland providing blur.

Missing theme files use the built-in dark fallback; malformed JSON keeps the last valid palette. For source-tree testing, set `APP_LAUNCHER_THEME` to a separate palette file before `./launch --hidden`. Inspect the loaded colors with `./launch ipc call launcher theme`.

`bash ./test-theme FIRST_RENDERED_PALETTE SECOND_RENDERED_PALETTE` exercises live reload, fallback/error handling, atomic replacements, and single-instance ownership. It temporarily runs the source launcher and restores the installed launcher afterward.

## Password mode

`app-launcher --passwords` (`Super+Shift+P`) uses the existing rbw configuration and
pinentry; it does not migrate the vault or replace Super+D. Choose a login, then
choose **Password**, **Username**, **OTP**, **URL**, or **Fill** with a second Enter.
Escape returns from actions or closes entries without copying. Reopening reloads
metadata. Favorite/sort controls and application persistence do not apply here.
The overlay releases focus while rbw may be unlocking and before actions run.

Name, username and folder are searchable. Qutebrowser's current HTTP(S) host is
requested through an executable userscript and a private, bounded runtime socket
before the overlay opens; no URL yanking or clipboard read is used. Discord /
Vesktop variants prefill `discord.com`, Steam prefills `steampowered.com`.
Other browsers open unfiltered. These editable hints are not origin verification
and never select a login automatically. URL copies an actual stored HTTP(S) URI,
preferring the captured host, not the entry name.

The Rust helper alone handles raw rbw responses. QML/IPC receive allowlisted
metadata and status codes, never passwords, OTPs, notes, custom fields or history.
Actions validate the requested UUID against the returned entry. Password/OTP
bytes go to `wl-copy --sensitive --type text/secret` through stdin; multiline and
literal backslashes are preserved. clip-notify matches upstream's masking: the
first three characters remain visible, with one asterisk per remaining character
(short values of up to three characters are fully visible). Invalid UTF-8 stays
hidden and preview size limits still apply. This preview can remain in notification
history; clipboard-history exclusion is separate and tested with disposable data.
**Sensitive clipboard hints are not access control:** other applications can
still request the contents. There is no clipboard timer or automatic clearing.

Fill restores the captured window identity (address, PID and class), checks focus
and released Enter/modifier keys before each stage, then types username, Tab,
password, **never Enter**. Existing input-device permissions are required; no
privileges are added. ydotool 1.0.4 only faithfully supports printable ASCII here:
non-ASCII and multiline/control values fail closed with a Copy fallback.
Hyprland pins only `ydotoold-virtual-device` to plain English (US); the helper
validates that device's layout and requires Caps Lock off on every keyboard.
Physical keyboards retain their configured layouts. A configured OTP is copied sensitively afterward; an OTP
failure reports that the credentials were already filled. An interrupted Fill
may have typed a prefix: inspect the form instead of retrying blindly. Global
input always has a focus race between checks; this is not browser-extension-grade
origin security. Dummy-editor verification on the actual Hyprland/ydotool stack
is still a manual acceptance gate; it was not exercised against running apps.
The real Qutebrowser instance was likewise not contacted during implementation;
the userscript transport was exercised with fake processes only.

For source-tree development, build both Rust binaries first. Point the exec shim
at the new lifecycle binary; password mode additionally needs the helper's
unwrapped binary (normal app-only mode does not fetch password context):

```sh
CARGO_TARGET_DIR=/tmp/app-launcher-target cargo build --locked --manifest-path Cargo.toml
export APP_LAUNCHER_BINARY=/tmp/app-launcher-target/debug/app-launcher
APP_LAUNCHER_PASSWORD_HELPER=/tmp/app-launcher-target/debug/app-launcher-passwords ./launch --passwords
```

Do not use a real vault for automated checks. From the repository root:

```sh
export CARGO_TARGET_DIR=/tmp/app-launcher-target
cargo fmt --manifest-path Projects/appLauncher/Cargo.toml -- --check
cargo test --locked --manifest-path Projects/appLauncher/Cargo.toml
cargo clippy --locked --manifest-path Projects/appLauncher/Cargo.toml --all-targets -- -D warnings
cargo build --locked --manifest-path Projects/appLauncher/Cargo.toml
python3 Projects/appLauncher/tests/integration.py "$CARGO_TARGET_DIR/debug/app-launcher-passwords"
python3 Projects/appLauncher/tests/lifecycle.py "$CARGO_TARGET_DIR/debug/app-launcher"
bash -n Projects/appLauncher/launch Projects/appLauncher/test-theme
```

Optional installed-stack regression checks use a **separate headless Sway**, a
fresh HOME/runtime/state/cache, fake helper processes, and a disposable cliphist
DB. They never connect to the existing Wayland clipboard or input service. They
also run `test-theme` only in that private session, not the desktop. Requirements:
Sway, Quickshell, wl-clipboard, cliphist, wtype, jq and Python. Compile the
clip-notify source for the notification assertion, then run:

```sh
rustc --edition=2024 hosts/sora/home-manager/modules/clip-notify/src/main.rs -o /tmp/fixture-clip-notify
APP_LAUNCHER_BINARY="$CARGO_TARGET_DIR/debug/app-launcher" python3 Projects/appLauncher/tests/runtime.py /absolute/path/to/sway /tmp/fixture-clip-notify "$CARGO_TARGET_DIR/debug/app-launcher-passwords"
```

The optional third argument must be an **unwrapped ELF**: a package wrapper could
override the fake rbw PATH. No ydotool process runs in this harness. Build and
review the declarative package before integration; none of these commands
activate a configuration.
