# App Launcher

After a NixOS/Home Manager rebuild, start the launcher with:

```sh
app-launcher
```

The project owns its lifecycle manager. Hyprland preloads one hidden instance, and each call toggles it over IPC. Stale, duplicate, or outdated instances are cleaned up before exactly one current copy starts. Scripts and keybindings must use this command instead of invoking `qs` directly.

The same lifecycle guarantees apply during source-tree development:

```sh
./launch --foreground
./launch --hidden
./launch --stop
```

Keyboard controls: fuzzy type-to-search; `↑/↓`, `Ctrl+J/K`, or `Ctrl+N/P` to navigate; `Enter` to launch; `Ctrl+Space` to favorite; `Ctrl+F` for favorites-only; `Ctrl+1/2/3` to sort; `Ctrl+L` to clear; `Esc` to close. The mouse is optional.

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
literal backslashes are preserved. Existing clip-notify hides them completely,
and the installed clipboard stack has been tested with disposable cliphist data.
**Sensitive clipboard hints are not access control:** other applications can
still request the contents. There is no clipboard timer or automatic clearing.

Fill restores the captured window identity (address, PID and class), checks focus
and released Enter/modifier keys before each stage, then types username, Tab,
password, **never Enter**. Existing input-device permissions are required; no
privileges are added. ydotool 1.0.4 only faithfully supports printable ASCII here:
non-ASCII, multiline/control values, non-plain-US keymaps or Caps Lock fail closed
with a Copy fallback. A configured OTP is copied sensitively afterward; an OTP
failure reports that the credentials were already filled. An interrupted Fill
may have typed a prefix: inspect the form instead of retrying blindly. Global
input always has a focus race between checks; this is not browser-extension-grade
origin security. Dummy-editor verification on the actual Hyprland/ydotool stack
is still a manual acceptance gate; it was not exercised against running apps.
The real Qutebrowser instance was likewise not contacted during implementation;
the userscript transport was exercised with fake processes only.

For source-tree password development, build the helper first and point at its
unwrapped binary (normal app-only source mode needs no helper):

```sh
CARGO_TARGET_DIR=/tmp/app-launcher-target cargo build --locked --manifest-path Cargo.toml
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
bash -n Projects/appLauncher/launch Projects/appLauncher/test-theme
```

Optional installed-stack regression checks use a **separate headless Sway**, a
fresh HOME/runtime/state/cache, fake helper processes, and a disposable cliphist
DB. They never connect to the existing Wayland clipboard or input service. They
also run `test-theme` only in that private session, not the desktop. Requirements:
Sway, Quickshell, wl-clipboard, cliphist, wtype, jq, flock and Python. Compile the
unchanged clip-notify source for the notification assertion, then run:

```sh
rustc --edition=2024 hosts/sora/home-manager/modules/clip-notify/src/main.rs -o /tmp/fixture-clip-notify
python3 Projects/appLauncher/tests/runtime.py /absolute/path/to/sway /tmp/fixture-clip-notify "$CARGO_TARGET_DIR/debug/app-launcher-passwords"
```

The optional third argument must be an **unwrapped ELF**: a package wrapper could
override the fake rbw PATH. No ydotool process runs in this harness. Build and
review the declarative package before integration; none of these commands
activate a configuration.
