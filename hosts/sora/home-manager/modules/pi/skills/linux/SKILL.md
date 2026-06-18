---
name: linux
description: Use when working with Linux desktop configuration, systemd user services, darkman, xsettingsd/GTK theming, Firefox dark mode integration, display servers (Wayland/X11), and desktop-environment footguns. Covers runtime state management, D-Bus services, and toolkit-level quirks.
---

# Linux Desktop

## Clipboard (Wayland)

Lucky uses `wl-clipboard`. When asked to check clipboard:
1. Check mimetypes: `wl-paste -l`
2. If image → save to file, use `image-analyzer` agent
3. If text/URL → `wl-paste`

## Darkman + geoclue

Darkman automatically switches between light/dark mode based on sunrise/sundown
(via geoclue2) or manual commands.

### Setup

```nix
services.darkman = {
  enable = true;
  settings.usegeoclue = true;
  lightModeScripts = {
    # Each attr name becomes a script in ~/.local/share/light-mode.d/
    gtk-theme = ''...'';
  };
  darkModeScripts = {
    gtk-theme = ''...'';
  };
};
```

Scripts can also be placed directly at `~/.local/share/light-mode.d/` and
`~/.local/share/dark-mode.d/`. They run on startup + on each mode transition.

### Commands

```
darkman-mode light        # Switch to light mode
darkman-mode dark          # Switch to dark mode
darkman-mode toggle        # Toggle
```

### Typical theme-switch scripts

Each sed/action below is typically its own script file in the mode directory:

```bash
# GTK theme
dconf write /org/gnome/desktop/interface/gtk-theme "'Catppuccin-Mocha-Standard-Lavender-Dark'"

# xsettingsd theme/icon/cursor
sed -i 's/Net\/ThemeName ".*"/Net\/ThemeName "Catppuccin-Mocha-Standard-Lavender-Dark"/' \
  ~/.config/xsettingsd/xsettingsd.conf
pkill -USR1 xsettingsd

# Prefer dark
sed -i 's/Gtk\/PreferDarkTheme .*/Gtk\/PreferDarkTheme 1/' \
  ~/.config/xsettingsd/xsettingsd.conf
pkill -USR1 xsettingsd
```

## xsettingsd

xsettingsd provides GTK settings (theme, icons, cursor, dark preference) to
running applications via the XSETTINGS protocol. It's the primary mechanism for
runtime theme switching.

### Signal to reload

```
pkill -USR1 xsettingsd
```

Sends SIGUSR1 to xsettingsd, causing it to re-read its config file and
broadcast new settings. No stop/start needed.

### xsettingsd + home-manager = store path trap

The home-manager `services.xsettingsd` module generates the config file as a
Nix **store derivation** (`/nix/store/...-xsettingsd.conf`). The systemd
service runs with `-c <store-path>`, which is **read-only**. Any runtime
script that `sed`s `~/.config/xsettingsd/xsettingsd.conf` and restarts
xsettingsd is wasting its time — xsettingsd never reads that file.

**Fix**: Don't use the home-manager xsettingsd module. Set xsettingsd up
manually:

- Create the initial writable config via `home.activation` (only if absent)
- Define the systemd user service via `systemd.user.services.xsettingsd` with
  `ExecStart` pointing at the writable path
- Darkman (or any runtime switcher) `sed`s the writable file and restarts
  xsettingsd via `pkill -USR1 xsettingsd`

## gsettings vs dconf in systemd user services

`gsettings` fails in systemd user services with "No schemas installed" because
`GSETTINGS_SCHEMA_DIR` isn't set in that context. Use `dconf write` instead —
it doesn't need schemas, just the session D-Bus, and produces the same result.

```bash
dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
dconf write /org/gnome/desktop/interface/gtk-theme "'Catppuccin-Mocha-Standard-Lavender-Dark'"
```

Note the nested quotes: dconf expects a GVariant, so the outer quotes are shell
syntax and the inner quotes are literal GVariant string delimiters.

## Firefox dark mode

For Firefox to dynamically switch dark/light via `prefers-color-scheme`:

1. Set `widget.content.allow-gtk-dark-theme = true` in `user.js` (or about:config)
   — tells Firefox to read the GTK dark theme preference from xsettingsd
2. Set `layout.css.prefers-color-scheme.content = 2` (follow system preference)
3. xsettingsd must have `Gtk/PreferDarkTheme 1` (dark) or `0` (light)
4. The D-Bus portal (`org.freedesktop.portal.Settings`) *should* provide this
   property too via `org.freedesktop.appearance.color-scheme`, but the portal's
   Settings interface is often not activatable — xsettingsd is the reliable path

### user.js entries

```
user_pref("widget.content.allow-gtk-dark-theme", true);
user_pref("layout.css.prefers-color-scheme.content", 2);
```

## xdg-desktop-portal

`xdg-desktop-portal` exposes `org.freedesktop.portal.Settings` on D-Bus,
providing properties like `org.freedesktop.appearance.color-scheme` that
applications can query for dark/light preference.

However, the portal Settings interface is not always activatable — it depends
on which portal backend is installed (GTK, KDE, etc.) and whether the portal
service is running with the right environment. When unavailable, applications
fall back to xsettingsd for dark mode preference.

## systemd user services

### Environment variables are not inherited

systemd user services do **not** inherit the user's shell environment
(including `DISPLAY`, `WAYLAND_DISPLAY`, `PATH`, etc.). Set them explicitly:

```
[Service]
Environment="DISPLAY=:0"
Environment="WAYLAND_DISPLAY=wayland-0"
```

Or set them globally: `systemctl --user import-environment`.

### No TTY in systemd services

Systemd services (user or system) don't have an interactive TTY. Commands that
require user input (like `sudo`, SSH key prompts, or `gpg-agent` pinentry)
will fail or hang. Always use a terminal emulator for interactive commands.

## Wayland / Hyprland

Lucky uses Hyprland on Wayland. Key points:

- GTK apps use `GDK_BACKEND=wayland` by default (can be forced)
- QT apps need `QT_QPA_PLATFORM=wayland` for Wayland
- Environment variables for theming should be set in Hyprland config, not in
  shell profiles (since Hyprland starts them)
- `hyprctl` is the runtime control tool for theme-switching scripts (e.g.,
  setting wallpapers, reloading config)

## GTK theming via home-manager

### gtk.colorScheme

In home-manager's `gtk` module, the `colorScheme` option only accepts `null`,
`"light"`, or `"dark"`. `null` means "no preference / let runtime tools manage
it." Do NOT set it to `"default"` — that is not a valid value.

Set to `null` when darkman (or another runtime switcher) handles the preference:
```nix
gtk.colorScheme = null;
```
