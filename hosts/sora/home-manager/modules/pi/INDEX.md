# NixConfig Index — On-Demand Reference

> **SOURCE OF TRUTH.** This file in `hosts/sora/home-manager/modules/pi/INDEX.md`
> is the canonical NixConfig index. The old `~/Documents/opencode/INDEX.md` is
> now a redirect stub pointing here.
>
> READ THIS ONLY for complex multi-file tasks (audits, refactors, tracing dependencies).
> For simple "where is X?" lookups, grep/glob directly — it's faster and cheaper.
> Loaded on-demand, not automatically.
>
> All paths are relative to NixConfig root (`~/Projects/NixConfig/`).

---

## Entry Points

| File | Imports |
|------|---------|
| `flake.nix` | nixosConfigurations: `sora`, `tempest` |
| `hosts/sora/nixos/configuration.nix` | hm: `rakki`, nixos: `../../modules`, `./containers`, `./hardware-configuration.nix`, `./packages.nix`, `./fonts.nix`, `./users.nix`, `./tailscale.nix`, `./kdeconnect.nix`, `./sunshine.nix`, `./firefly.nix` |
| `hosts/sora/home-manager/home.nix` | `./modules`, `./home-packages.nix`, `./gtk.nix`, `./darkman.nix`, `./qt.nix`, `./xdg-portals.nix`, `./persistence.nix`, `./onedrive.nix` |
| `hosts/tempest/nixos/configuration.nix` | hm: `tmpst`, `../../modules/automation`, `../../modules/fish`, `../../modules/btrfs-ephemeral`, `../../modules/optin-persistence`, `./containers`, `./hardware-configuration.nix`, `./users.nix`, `./tailscale.nix`, `./packages.nix`, `./sunshine.nix` |
| `hosts/tempest/home-manager/home.nix` | `./persistence.nix`, `./fish.nix`, `./git.nix`, `./jujutsu.nix`, `./fastfetch.nix`, `./bat.nix`, `./eza.nix` |
| `hosts/modules/default.nix` | shared: steam, fish, automation, syncthing, ai, btrfs-ephemeral, optin-persistence, stock-report, usb-tether-failover, glance-dashboard |
| `hosts/sora/home-manager/modules/default.nix` | 35 modules: obs, steam, fish, hypr, rbw, mako, clipnotify, swayosd, jujutsu, zed, alacritty, helix, calendar, wofi, fastfetch, git, waybar, neovim, starship, bat, eza, kitty, qutebrowser, opencode, aerc, hytale, quickshell, river, fuzzel, noctalia, spicetify, mangohud, firefox, glance, neomutt |
| `hosts/sora/home-manager/modules/pi/default.nix` | `./pi.nix` |
| `hosts/sora/home-manager/modules/pi/pi.nix` | `programs.pi-coding-agent`, `home.file` (extensions, skills, prompts, themes, agents, Pi MCP config), `xdg.desktopEntries`, `xdg.configFile` (SOPS skill private data) |

---

## Flake Inputs

| Input | URL | Used By |
|-------|-----|---------|
| `nixpkgs` | nixos-unstable | everything |
| `disko` | nix-community/disko | `partitions.nix` (both hosts) |
| `impermanence` | nix-community/impermanence | `optin-persistence.nix` |
| `home-manager` | nix-community/home-manager | configuration.nix (both hosts) |
| `sops-nix` | Mic92/sops-nix | configuration.nix (both hosts), `secrets.yaml`, `.sops.yaml` |
| `hyprland` | hyprwm/Hyprland | sora hm: `hyprland.nix`, `sora/nixos/configuration.nix` |
| `noctalia` + `noctalia-qs` | noctalia-dev | sora hm: `noctalia.nix` |
| `spicetify-nix` | Gerg-L/spicetify-nix | sora hm: `spicetify.nix` |
| `catppuccin` | catppuccin/nix | sora hm: `gtk.nix`, `home.nix` (module) |
| `kopuz` | kopuz-org/kopuz | sora nixos: `packages.nix` |
| `nuls` | cesarferreira/nuls | sora nixos: `packages.nix` |
| `nix-minecraft` | Infinidoge/nix-minecraft | sora nixos: `mcServer.nix` |
| `hytale` | TNAZEP/HytaleLauncherFlake | sora hm: `hytale.nix` |
| `lanzaboote` | nix-community/lanzaboote | sora nixos: secure boot |
| `ministerio` | misterio77/nix-config | sora hm: `clipnotify.nix` (clip-notify pkg) |

---

## SOPS Secrets

| Secret | File | Consumer |
|--------|------|----------|
| `syncthing_cert` / `syncthing_key` | `secrets.yaml` | `syncthing.nix` |
| `soraPass` | `secrets.yaml` | `users.nix` (sora) |
| `tmpstPass` | `secrets.yaml` | `users.nix` (tempest) |
| `onedriveToken` | `secrets.yaml` | sora `configuration.nix` → `onedrive.nix` |
| `deepseekApiKey` | `secrets.yaml` | opencode (opencode module) |
| `openaiApiKey` | `secrets.yaml` | opencode (opencode module) |
| `opencodeServerPass` | `secrets.yaml` | sora `home.nix` (OPENCODE_SERVER_PASSWORD) |
| `caldavPass` | `secrets.yaml` | `calendar.nix` |
| `piholePass` | `secrets.yaml` | glance containers (both hosts) |
| `gitToken` | `secrets.yaml` | glance containers (both hosts) |
| `hyperApiKey` | `pi/private.yaml` | `pi.nix` → `models.json` (hyper provider apiKey) |
| `lucky-info` | `pi/private.yaml` | `pi.nix` → `APPEND_SYSTEM.md`; opencode (context injection) |
| `skillFireflyPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/firefly/resources/private.md` |
| `skillLumisPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/lumis/resources/private.md` |
| `webSearchJson` | `pi/private.yaml` | `pi.nix` → `home.file web-search.json` |

---

## File Index (by category)

### System (sora nixos/)

| File | Keywords |
|------|----------|
| `hosts/sora/nixos/configuration.nix` | greetd, autologin, hyprland, portal, lix, sudo-rs, polkit, zram, nvidia-env, pipewire, mpd, blueman, flatpak, fstrim, waydroid, gpu-screen-recorder, openssh, printing(ipp-usb,cnijfilter2), lanzaboote(secure-boot), sopstemplate(rclone-onedrive), ydotool |
| `hosts/sora/nixos/hardware-configuration.nix` | zen-kernel, amd-pstate, systemd-boot, bluetooth(poweron), openrgb(udev), plymouth, hostname=sora, imports:drivers+partitions |
| `hosts/sora/nixos/packages.nix` | ~150 systemPackages, gaming, podman, gnupg-ssh, virt-manager, nm-applet-indicator, kopuz, nuls |
| `hosts/sora/nixos/fonts.nix` | 27 fonts, jetbrainsmono-nerd default, noto, fira-code, material-icons, cjk |
| `hosts/sora/nixos/users.nix` | rakki, immutableUsers, fish-shell, 20+ groups(input,uinput,corectrl,wheel,docker,libvirtd), sops-hashed-password |
| `hosts/sora/nixos/tailscale.nix` | tailscale-client, udp-41641, routing |
| `hosts/sora/nixos/kdeconnect.nix` | tcp/udp-1714:1764 |
| `hosts/sora/nixos/sunshine.nix` | sunshine-streaming, uinput, capSysAdmin, autoStart |
| `hosts/sora/nixos/firefly.nix` | firefly-iii, mariadb(mysql), nginx, persistence, backup-timer(30d), sops-APP_KEY |
| `hosts/sora/nixos/mcServer.nix` | minecraft, neoforge-1.20.1, 3G-heap, rcon, mods-symlink |
| `hosts/sora/nixos/partitions.nix` | disko, luks, btrfs(subvolumes:/, /nix, /persist, /swap), 8GB-swapfile, zstd, nvme, esp-512M |
| `hosts/sora/nixos/containers/default.nix` | podman, dockerCompat, nvidia-container-toolkit, dns-enabled |
| `hosts/sora/nixos/containers/containers.nix` | oci-glance, host-net, sops-template(glance.yaml) |
| `hosts/sora/nixos/containers/data/glance/glance.yml` | glance-dashboard, 5-pages, pihole, rss, youtube, twitch, steam-specials, github-releases, reddit, weather, calendar, bookmarks |
| `hosts/sora/nixos/drivers/default.nix` | imports: nvidia-drivers + undervolt |
| `hosts/sora/nixos/drivers/nvidia-drivers.nix` | nvidia, modesetting, open-kernel-module, latest-driver, powerManagement=off |
| `hosts/sora/nixos/drivers/undervolt.nix` | lact-daemon, gpu-210W, clock+150, mem+2000, fan-curve, /etc/lact/config.yaml |

### System (tempest nixos/)

| File | Keywords |
|------|----------|
| `hosts/tempest/nixos/configuration.nix` | kde-plasma6, sddm-wayland, sudo-rs, sops, openssh, zram, avahi, open-firewall, sops-secrets(tmpstPass), hm-user=tmpst |
| `hosts/tempest/nixos/hardware-configuration.nix` | latest-kernel, systemd-boot, intel-graphics, bluetooth(poweron), ip-forward(sysctl), hostname=tempest |
| `hosts/tempest/nixos/packages.nix` | firefox, python311, podman-compose, btop, intel-gpu-tools, nvitop, helix, mpv, imv, zoxide, fonts |
| `hosts/tempest/nixos/partitions.nix` | disko, luks, btrfs(subvolumes), zstd, 8GB-swapfile, nvme |
| `hosts/tempest/nixos/users.nix` | tmpst, rakki(system), immutableUsers, fish, ssh-key(shared) |
| `hosts/tempest/nixos/tailscale.nix` | tailscale-exit-node, advertise, gro-fix(ethtool), kdeconnect-firewall |
| `hosts/tempest/nixos/sunshine.nix` | sunshine-streaming, uinput, moonlight-qt |
| `hosts/tempest/nixos/containers/default.nix` | podman, dockerCompat, n8n |
| `hosts/tempest/nixos/containers/containers.nix` | oci-glance, sops-glance.yaml |
| `hosts/tempest/nixos/containers/data/glance/glance.yml` | glance-dashboard, 4-pages, pihole, rss, youtube, twitch, steam, reddit, kpop, speedtest |
| `hosts/tempest/nixos/containers/n8n.nix` | n8n, python-runner, workflow-automation, custom-podman-network |

### Shared Modules (hosts/modules/)

| File | Keywords |
|------|----------|
| `hosts/modules/steam.nix` | steam, gamescope(237hz), proton-ge, catppuccin-cursors, remote-play |
| `hosts/modules/fish.nix` | fish, completions, vendor-config |
| `hosts/modules/tide-config.nix` | tide, fish-prompt, shared-tide-config, imported-by-sora+tempest |
| `hosts/modules/automation.nix` | auto-upgrade(weekly), nix-optimise, gc(daily,keep-7d) |
| `hosts/modules/syncthing.nix` | syncthing(user=rakki), sops(cert+key), peer=shiro, folders=geral+sops |
| `hosts/modules/ai.nix` | ollama-cuda, open-webui(:8090), llama3.1, deepseek-r1:8b, keep-alive=20s |
| `hosts/modules/btrfs-ephemeral.nix` | btrfs-root-wipe-on-boot, root-blank-snapshot, dont-wipe-flag, initrd+systemd |
| `hosts/modules/optin-persistence.nix` | impermanence, /persist(machine-id,systemd,nixos,tailscale,containers,waydroid,sbctl,OpenRGB,logs) |
| `hosts/modules/stock-report.nix` | stocks, bovespa(~55 tickers), yfinance, AUVP11-benchmark, systemd-timer(daily-0900,disabled) |
| `hosts/modules/usb-tether-failover.nix` | rndis_host, cdc_ether, watchdog(ping-1.1.1.1/15s), enp*u*u, udev-hotplug, dhcpcd-fallback |
| `hosts/modules/glance-dashboard.nix` | glance, dashboard, yaml-config, 2-pages, pihole, rss, youtube, reddit, twitch, steam, github, weather, bookmarks, calendar |

### Home-Manager Top-Level (sora)

| File | Keywords |
|------|----------|
| `hosts/sora/home-manager/home-packages.nix` | ~125 user-pkgs: obsidian, firefox, vesktop, teams-for-linux, onlyoffice, vscode-fhs, pyprland, wallust, cli-utils, wayland-tools |
| `hosts/sora/home-manager/gtk.nix` | catppuccin-mocha-lavender, gruvbox-plus-dark-icons, catppuccin-cursor(peach,24px), xsettingsd-daemon |
| `hosts/sora/home-manager/darkman.nix` | darkmode-autoswitch, geoclue(sunset), Piracicaba(-22.72/-47.64), gtk+icons+cursor+dconf+xsettingsd+hyprland-cursor toggle |
| `hosts/sora/home-manager/qt.nix` | QT_STYLE_OVERRIDE=gtk3, qt5+qt6 |
| `hosts/sora/home-manager/xdg-portals.nix` | xdg-desktop-portal-gtk, hyprland-portal(commented), file-chooser=gtk |
| `hosts/sora/home-manager/persistence.nix` | 35+ dirs: sync, Games, .ssh, .steam, .config/jj, .config/dconf, .mozilla, .config/mozilla, flatpak, containers |
| `hosts/sora/home-manager/onedrive.nix` | rclone-mount(user-service), vfs-cache(32G,24h), sops-config, ~/Onedrive |
| `hosts/sora/home-manager/qtstyleplugins-gtk3-key.patch` | qtstyleplugins-patch, gtk3-key-support |

### Home-Manager Modules (sora)

| File | Keywords |
|------|----------|
| `hosts/sora/home-manager/modules/obs.nix` | obs-studio, wlrobs, wayland-capture |
| `hosts/sora/home-manager/modules/steam.nix` | protontricks |
| `hosts/sora/home-manager/modules/fish/default.nix` | import: fish.nix |
| `hosts/sora/home-manager/modules/fish/fish.nix` | fish, tide-plugin(shared-tide-config), direnv, zoxide, fastfetch, color-scheme, aliases, abbrs, custom-functions(jj,nix3-shell) |
| `hosts/sora/home-manager/modules/fish/hist-merge.fish` | fish-function, history-merge, multi-instance |
| `hosts/sora/home-manager/modules/hypr/default.nix` | imports: hyprland, hyprlock, hypridle, hyprpanel, pyprland |
| `hosts/sora/home-manager/modules/hypr/hyprland.nix` | hyprland(lua-config), xwayland, scrolling-layout(0.5), dp-1+hdmi-a-1, persistent-workspaces, window-rules(float-bitwarden,idle-fullscreen,steam-ws3-4), blur(3,2,0.1696), rounded(12px), animations(bezier), touchpad-gestures, exec-on-start(noctalia,clipse,nm-applet,openrgb,ags,blueman,pypr,www-daemon,cliphist,steam,vesktop), 50+keybinds |
| `hosts/sora/home-manager/modules/hypr/hypridle.nix` | disabled, on_unlock(rm /tmp/session.lock) |
| `hosts/sora/home-manager/modules/hypr/hyprlock.nix` | disabled, blurred-wallpaper(knnw.jpg), time-label(SF-Pro), input-field(290x60) |
| `hosts/sora/home-manager/modules/hypr/hyprpaper.nix` | catppuccin-mocha-solid-background, github(OffRakki/walls), all-monitors |
| `hosts/sora/home-manager/modules/hypr/hyprpanel.nix` | disabled, ags-panel, bar([dashboard,workspaces,ram,cpu],media,[volume,systray,notifications]), jetbrainsmono, transparent |
| `hosts/sora/home-manager/modules/hypr/pyprland.nix` | scratchpads(kitty-dropdown 75%x60%, pwvucontrol, spotify), lost_windows, toggle_special, shift_monitors, magnify, expose |
| `hosts/sora/home-manager/modules/rbw.nix` | bitwarden-cli, pinentry-gnome3, lock-300s, <fernandomarques1505@gmail.com> |
| `hosts/sora/home-manager/modules/mako.nix` | disabled, top-center, 400x150, 12s-timeout, catppuccin-mocha-colors |
| `hosts/sora/home-manager/modules/clipnotify.nix` | wl-paste--watch, clip-notify(pipe), systemd-user-service, wayland-target |
| `hosts/sora/home-manager/modules/swayosd.nix` | onscreen-display, volume, brightness, css-styled |
| `hosts/sora/home-manager/modules/jujutsu.nix` | jj, snapshot-50MiB, git-name-email, log-default, curved-graph, less-FRX, custom-draft-template |
| `hosts/sora/home-manager/modules/zed.nix` | zed-editor(dkDefault), extensions(nix,toml,rust,docker), catppuccin-mocha, vim_mode, lsp(rust-analyzer,nixd,elixir-ls) |
| `hosts/sora/home-manager/modules/alacritty.nix` | terminal, fish-shell, jetbrainsmono-11, blur, #11111b-bg |
| `hosts/sora/home-manager/modules/helix.nix` | hx-editor, default-editor, alejandra-formatter, nixd+nil+uwu-colors, kaolin-valley-dark, cursorline, soft-wrap, relative-number, indent-guides |
| `hosts/sora/home-manager/modules/calendar.nix` | vdirsyncer, khal, khard, todoman, google-calDAV/cardDAV(3-pairs), systemd-timer(30min), mbsync, persistence |
| `hosts/sora/home-manager/modules/wofi.nix` | launcher, multi-contains-matching, dark-css(#161825), allow_images, no_actions |
| `hosts/sora/home-manager/modules/waybar.nix` | disabled, top-bar, hyprland-workspaces, cpu/gpu/memory(nvidia-smi), mpris-media, clock, tray, audio(pulseaudio,wpctl), network(wifi), custom-css(#24242C) |
| `hosts/sora/home-manager/modules/neovim.nix` | nvim, python3+ruby, clipboard(unnamed), relativenumber, shiftwidth=2 |
| `hosts/sora/home-manager/modules/starship.nix` | disabled, fish+nushell, catppuccin-mocha-palette, nixos-snowflake, custom-characters |
| `hosts/sora/home-manager/modules/bat.nix` | bat(syntax-highlighting) |
| `hosts/sora/home-manager/modules/eza.nix` | eza, icons, git, colors, group-directories-first, header |
| `hosts/sora/home-manager/modules/kitty.nix` | kitty-terminal, vague-theme, jetbrainsmono-12, opacity(0.9), blur(2), fish-shell, shell+git-integration, cursor-trail |
| `hosts/sora/home-manager/modules/qutebrowser.nix` | vim-browser, kagi-search(default), duckduckgo, youtube, modrinth, scryfall, nix, steamrip, yt_mpv-script, dark-mode, left-tabs-10%, homer-dashboard(:1202) |
| `hosts/sora/home-manager/modules/aerc.nix` | email-client, mbsync, xoauth2(gmail-3-accounts), sasl, urlscan, imv, hx-editor, w3m, systemd-timer(5min), mailto-handler, persistence |
| `hosts/sora/home-manager/modules/firefox.nix` | userChrome(hide-tabs), dark-mode(user.js), profile=Rakki |
| `hosts/sora/home-manager/modules/fastfetch.nix` | system-info, small-logo, 4-color-sections(system=blue,desktop=mauve,hardware=peach,status=green) |
| `hosts/sora/home-manager/modules/git.nix` | git, hx-editor, master-branch, <offrakki@gmail.com>, commit-verbose |
| `hosts/sora/home-manager/modules/neomutt.nix` | email-tui, sidebar(30,60s), khard-integration, solarized-dark, alternates, mailto-handler |
| `hosts/sora/home-manager/modules/hytale.nix` | hytale-launcher(pkgs.inputs.hytale.default) |
| `hosts/sora/home-manager/modules/quickshell/quickshell.nix` | disabled |
| `hosts/sora/home-manager/modules/river.nix` | river-compositor, keybindings(super-Q-close,D-wofi-drrun,J/K-focus), tiling |
| `hosts/sora/home-manager/modules/fuzzel.nix` | launcher, firasans-14, gruvbox-plus-dark-icons, bg(#24242c), border(2,4) |
| `hosts/sora/home-manager/modules/noctalia.nix` | shell, bar(floating,0.93opacity), wallpaper(crop,assets/wallpapers), launcher(kitty,firefox,opencode), lockscreen(blur-0.8,10s-countdown), weather(Piracicaba), audio(mpv-preferred,overdrive), persistence |
| `hosts/sora/home-manager/modules/spicetify.nix` | spotify, catppuccin-mocha, fullAppDisplay, shuffle, marketplace, lyricsPlus, rotatingCoverart |
| `hosts/sora/home-manager/modules/mangohud.nix` | overlay(gpu,cpu,ram,vram,fps,frametime), legacy-layout, top-left, fps-limit(237,120,0), thresholds(yellow-50%,red-90%) |
| `hosts/sora/home-manager/modules/glance.nix` | glance-service(hm), page=Dashboard, small-column, empty-widgets |
| `hosts/sora/home-manager/modules/opencode/*` | see Opencode Module section below |
| `hosts/sora/home-manager/modules/pi/*` | see Pi Module section below |

### Home-Manager Modules (tempest)

| File | Keywords |
|------|----------|
| `hosts/tempest/home-manager/persistence.nix` | /persist: .config, .local/share, .ssh(mode=0700) |
| `hosts/tempest/home-manager/fish.nix` | fish, tide, direnv, zoxide, fastfetch, custom-cursors, full-color-scheme, aliases(ls→eza, cat→bat, du→duf, grep=colors), abbrs(jj,nix,editor,yt-dl) |
| `hosts/tempest/home-manager/git.nix` | git, hx-editor, master, <offrakki@gmail.com>, commit-verbose |
| `hosts/tempest/home-manager/jujutsu.nix` | jj, snapshot-50MiB, git-name-email, log-default, curved-graph, less-FRX, custom-draft-template |
| `hosts/tempest/home-manager/fastfetch.nix` | animePurpleHair-logo, red/green/yellow-color-groups, os/kernel/packages/shell/wm/hardware |
| `hosts/tempest/home-manager/bat.nix` | bat |
| `hosts/tempest/home-manager/eza.nix` | eza, icons, git, colors, group-directories-first, header |

### Opencode Module

| File | Keywords |
|------|----------|
| `hosts/sora/home-manager/modules/opencode/default.nix` | opencode, agents, skills, config, binary |
| `hosts/sora/home-manager/modules/opencode/opencode.nix` | opencode-package, config-file, compaction(prune+tail_turns:1), tool_output(1000l/30kb) |
| `hosts/sora/home-manager/modules/opencode/ciel.nix` | ciel-personality, context-injection, heartbeat(free-roam,2min-timer,systemd), sops-secrets(deepseek,openai,opencode-server,caldav,lucky-info,skill-firefly,skill-lumis) |
| `hosts/sora/home-manager/modules/opencode/context.md` | AGENTS.md-symlink-source, Ciel-personality-rules, first-person-third-person-rule, nix-flake-path, jujutsu-workflow, skill-routing, notification-scripts, index-sync-rule |
| `hosts/sora/home-manager/modules/pi/private.yaml` | sops-encrypted, lucky-info, skillFireflyPrivate, skillLumisPrivate, webSearchJson |
| `hosts/sora/home-manager/modules/opencode/bin/notify.sh` | ciel-notify, dunstify-desktop-notification, log(~/sync/geral/Ciel/notifications/) |
| `hosts/sora/home-manager/modules/opencode/bin/restart-server.sh` | ciel-restart-server, systemctl--user, opencode-reconnect |
| `hosts/sora/home-manager/modules/opencode/bin/freeroam.sh` | ciel-freeroam, free-roam, opencode-run--attach, summon-like-heartbeat |
| `hosts/sora/home-manager/modules/opencode/agents/*` | agents: audio-analyzer(whisper-cli,ffprobe), image-analyzer(gpt-4o-mini-vision), nix-auditor(readonly-nix-audit), pdf-reader(pdftotext+image) |
| Skills: (17 total) | jujutsu, nix, nix-refactor, linux, invest, firefly, lumis, personal-tools, browser, opencode-edit, opencode-session, context-curation, seo, screenshot, customize-opencode, security-sweep |
| `skills/firefly/scripts/*` | firefly_client.py, expenses.py, import_mp.py, mercado_pago.py |
| `skills/firefly/resources/*` | auditing.md, btg.md, mercado-pago.md, nubank-ofx.md |
| `skills/jujutsu/references/*` | bookmarks, conflicts, git-to-jj, glossary, operation-log, revsets, troubleshooting, workflow-commit-push-pr, workflow-new-workspace, workspaces |
| `skills/browser/scripts/browser.py` | playwright-browser-automation |

### Pi Module

| File | Keywords |
|------|----------|
| `hosts/sora/home-manager/modules/pi/default.nix` | pi-coding-agent, config |
| `hosts/sora/home-manager/modules/pi/pi.nix` | pi-coding-agent-enable, settings(deepseek-provider,openai,model,compaction,retry,branchSummary,treeFilterMode,terminal,images,theme(gruvbox-dark-hard)), models.json, home.file(extensions,skills-symlinks,prompts,themes(catppuccin-mocha,ciel-cursor,gruvbox-dark-hard),keybindings,mcp.json(obsidian-mcp -> /home/rakki/sync/geral/Obsidian),APPEND_SYSTEM.md), packages(pi-drawio,pi-intercom,pi-lean-ctx,pi-lens,pi-chrome,pi-simplify,pi-namespace,pi-ask-user,pi-web-access,pi-mcp-adapter,pi-markdown-preview,pi-powerline-footer,pi-hermes-memory,pi-invisible-continue,pi-subagents,pi-sketch,tintinweb-pi-subagents,rpiv-pi,rpiv-todo,rpiv-args,rpiv-btw,rpiv-i18n,rpiv-advisor,rpiv-workflow,rpiv-ask-user-question,piolium), sops-secrets(deepseek,openai,lucky-info,skill-firefly,skill-lumis,webSearchJson), persistence(.pi,.local/share/pi,.pi-lens,.config/lean-ctx,.local/share/lean-ctx), xdg.configFile(lean-ctx/config.toml) |
| `hosts/sora/home-manager/modules/pi/models.json (generated in pi.nix)` | custom-provider, hyper-charm-land, openai-completions, 18-models, deepseek-v4-flash, deepseek-v4-pro, qwen3.6, qwen3.7, kimi-k2.5, kimi-k2.6, glm-5, glm-5.1, gemma-4, llama-3.3, llama-4, minimax-m2.7, gpt-oss-120b, qwen3-coder, qwen3-next |
| `hosts/sora/home-manager/modules/pi/context.md` | Ciel-personality, pi-specific tool-discipline(read,bash,edit,write,grep,find,ls), skill-routing(pi-tools), nix-managed, sops-refs, speak-up-rule, read-before-write, YAGNI, one-liner-solutions, keep-index-in-sync, subagents-list |
| `hosts/sora/home-manager/modules/pi/extensions/notify.ts` | pi-extension, desktop-notifications, notify-send, agent-end-event, /notify-command |
| `hosts/sora/home-manager/modules/pi/prompts/archive.md` | pi-prompt, session-summary, obsidian-save, frontmatter |
| `hosts/sora/home-manager/modules/pi/prompts/nix-rebuild.md` | pi-prompt, nixos-rebuild, jj-sync, nh-os-switch |
| `hosts/sora/home-manager/modules/pi/prompts/nix-audit.md` | pi-prompt, nix-auditor, flake-audit, dead-code, redundancy |
| `hosts/sora/home-manager/modules/pi/prompts/commit.md` | pi-prompt, jj-commit, describe, commit-message |
| `hosts/sora/home-manager/modules/pi/themes/catppuccin-mocha.json` | pi-theme, catppuccin-mocha, mocha-palette, 51-tokens |
| `hosts/sora/home-manager/modules/pi/themes/ciel-cursor.json` | pi-theme, catppuccin-mocha, cursor-theme-colors, 51-tokens |
| `hosts/sora/home-manager/modules/pi/themes/gruvbox-dark-hard.json` | pi-theme, gruvbox, dark-hard-palette, 51-tokens |

#### Pi Agents

| File | Keywords |
|------|----------|
| `hosts/sora/home-manager/modules/pi/agents/nix-auditor.md` | pi-agent, nix-config-audit, read-only, structured-report, dead-code, redundancy |
| `hosts/sora/home-manager/modules/pi/agents/image-analyzer/image-analyzer.md` | pi-agent, image-analysis, vision, layout, text-extraction, UI-description |
| `hosts/sora/home-manager/modules/pi/agents/audio-analyzer/audio-analyzer.md` | pi-agent, audio-analysis, ffprobe, whisper-cli, transcription, en-pt |
| `hosts/sora/home-manager/modules/pi/agents/pdf-reader/pdf-reader.md` | pi-agent, pdf-analysis, pdftoppm, pdftotext, image-analyzer-delegate, structured-output |

#### Pi Skills

| Skill | Source (relative to pi module) |
|-------|--------------------------------|
| jujutsu | `skills/jujutsu/` |
| nix | `skills/nix/` |
| nix-refactor | `skills/nix-refactor/` |
| linux | `skills/linux/` |
| invest | `skills/invest/` |
| personal-tools | `skills/personal-tools/` |
| screenshot | `skills/screenshot/` |
| firefly | `skills/firefly/` |
| lumis | `skills/lumis/` |
| browser | `skills/browser/` |
| seo | `skills/seo/` |
| context-curation | `skills/context-curation/` |
| security-sweep | `skills/security-sweep/` |
| pi-tools | `skills/pi-tools/` |
| opencode-edit | `skills/opencode-edit/` |
| opencode-session | `skills/opencode-session/` |
| nix-auditor | `skills/nix-auditor/` (pi-specific) |

### Scripts & Macros

| File | Keywords |
|------|----------|
| `scripts/calculadoraJurosVibecodadassa.html` | compound-interest, CDI/SELIC, inflation, IR-table, chartjs, CDB/LCI/LCA/poupanca, URL-state, CSV |
| `scripts/ffmpeg_accel.sh` | ffmpeg, speed-up-video, setpts, strip-audio |
| `scripts/hyperionRoll.sh` | dotool-automation, copy-paste-loop(100x), hyperion |
| `scripts/pass-wofi.sh` | rbw+wofi, bitwarden-client, app-detection(hyprctl/swaymsg), clipboard(wl-copy), otp, fill |
| `scripts/wkspcSwitch.sh` | hyprctl, workspace-monitor-focus, prevent-jump |
| `scripts/yt_mpv.sh` | mpv, yt-dlp, 1080p, mp4, best-video |
| `hosts/sora/macros/autoClicker.sh` | ydotool, autoclicker-toggle, /tmp/autoclicker_running, left-click-spam |

### Assets

| File | Keywords |
|------|----------|
| `assets/fastfetch/*` | fastfetch-configs(compact,standard,v2), nixos-logo |
| `assets/gtk-3.0/settings.ini` | gtk3-settings |
| `assets/svgs/*` | animePurpleHair.png(fastfetch-tempest), hypr.png, nixosBanner.png, nixosLogo.png, nix-snowflake-*.svg, pelucio.jpg(noctalia-avatar) |
| `assets/Thunar/*` | thunar-config(accels, uca-xml) |
| `assets/wallpapers/*` | aesthetic, agbg, blackHole, Kath, knnw(hyprlock), lake, miku, pdw, solidBackground(hyprpaper), tokyo-night, tye |
| `assets/xfce4/helpers.rc` | xfce4-helpers |

---

## Keyword → File Cross-Reference

### Core Infrastructure

- **btrfs** → `partitions.nix`(both), `btrfs-ephemeral.nix`
- **luks/encryption** → `partitions.nix`(both), `.sops.yaml`
- **impermanence** → `optin-persistence.nix`, `persistence.nix`(sora-hm), `persistence.nix`(tempest-hm)
- **sops/secrets** → `.sops.yaml`, `secrets.yaml`, `configuration.nix`(both), `pi/private.yaml`, `calendar.nix`, `syncthing.nix`, `onedrive.nix`, `ciel.nix`
- **sudo | sudo-rs** → `configuration.nix`(both)
- **lix** → `configuration.nix`(sora)
- **zram** → `configuration.nix`(both)
- **nvidia** → `nvidia-drivers.nix`, `undervolt.nix`, `configuration.nix`(sora-env-vars)
- **intel-graphics** → `hardware-configuration.nix`(tempest)
- **lanzaboote/secure-boot** → `configuration.nix`(sora)

### Display & WM

- **hyprland** → `hyprland.nix`, `configuration.nix`(sora), `pyprland.nix`, `hyprpaper.nix`, `hypridle.nix`, `hyprlock.nix`, `hyprpanel.nix`, `wkspcSwitch.sh`
- **noctalia** → `noctalia.nix`
- **river** → `river.nix`
- **wayland** → many files, notably `xdg-portals.nix`, `clipnotify.nix`, env vars in `configuration.nix`(sora)
- **dark-mode | darkman** → `darkman.nix`, `gtk.nix`, `firefox.nix`
- **catppuccin** → `gtk.nix`, `spicetify.nix`, `fastfetch.nix`(sora), `starship.nix`, `mako.nix`, `hyprpaper.nix`, `zed.nix`

### Launchers & Bars

- **wofi** → `wofi.nix`, `pass-wofi.sh`
- **fuzzel** → `fuzzel.nix`
- **waybar** → `waybar.nix`(disabled)
- **hyprpanel** → `hyprpanel.nix`(disabled)

### Shell & Terminal

- **fish** → `fish.nix`(sora), `fish.nix`(tempest), `fish.nix`(shared-module)
- **kitty** → `kitty.nix`
- **alacritty** → `alacritty.nix`
- **starship** → `starship.nix`(disabled)
- **fastfetch** → `fastfetch.nix`(sora), `fastfetch.nix`(tempest)

### Editors & VCS

- **helix | hx** → `helix.nix`, `git.nix`(both), `aerc.nix`, `neomutt.nix`
- **neovim | nvim** → `neovim.nix`
- **zed** → `zed.nix`
- **jujutsu | jj** → `jujutsu.nix`(sora), `jujutsu.nix`(tempest)
- **git** → `git.nix`(sora), `git.nix`(tempest)

### Email & Calendar

- **aerc | email** → `aerc.nix`
- **neomutt** → `neomutt.nix`
- **calendar | caldav | vdirsyncer** → `calendar.nix`
- **khal | khard | todoman** → `calendar.nix`

### Browsers

- **firefox** → `firefox.nix`
- **qutebrowser** → `qutebrowser.nix`

### Gaming

- **steam** → `steam.nix`(shared-module), `steam.nix`(sora-hm)
- **mangohud** → `mangohud.nix`
- **gamescope** → `steam.nix`(shared-module)
- **sunshine/moonlight** → `sunshine.nix`(both)
- **minecraft** → `mcServer.nix`(commented-out in sora)
- **hytale** → `hytale.nix`

### Finance & Stocks

- **firefly-iii** → `firefly.nix`
- **stocks | bovespa** → `stock-report.nix`
- **compound-interest** → `calculadoraJurosVibecodadassa.html`

### AI & LLM

- **ollama** → `ai.nix`
- **open-webui** → `ai.nix`, glance-dashboards(both)

### Pi (Ciel's coding agent)

- **pi-coding-agent** → `pi/pi.nix`, `pi/context.md`, `pi/AGENTS.md`
- **ciel-personality** → `pi/context.md`, `pi/AGENTS.md`
- **pi-extensions** → `pi/extensions/`
- **pi-prompts** → `pi/prompts/`
- **pi-skills** → `pi/skills/`
- **pi-agents** → `pi/agents/`
- **pi-themes** → `pi/themes/`
- **pi-tools | pi-packages | tool-routing** → `pi/skills/pi-tools/SKILL.md`, `pi/pi.nix`
- **nix-auditor** → `pi/agents/nix-auditor.md`, `pi/skills/nix-auditor/SKILL.md`
- **notify-send | desktop-notifications** → `pi/extensions/notify.ts`
- **models | hyper-charm-land | openai-completions** → `pi/pi.nix` (generated models.json)

### Containers & Virtualization

- **podman** → `containers/default.nix`(both), `containers/containers.nix`(both)
- **glance-dashboard** → `glance-dashboard.nix`, `containers/data/glance/glance.yml`(both), `glance.nix`(hm)
- **n8n** → `containers/n8n.nix`(tempest)
- **waydroid** → `configuration.nix`(sora)

### Networking

- **tailscale** → `tailscale.nix`(both)
- **syncthing** → `syncthing.nix`
- **usb-tether** → `usb-tether-failover.nix`
- **kdeconnect** → `kdeconnect.nix`(sora, firewall only)
- **openssh** → `configuration.nix`(both)

### Multimedia

- **pipewire** → `configuration.nix`(sora)
- **mpd** → `configuration.nix`(sora)
- **obs-studio** → `obs.nix`
- **gpu-screen-recorder** → `configuration.nix`(sora)
- **mpv | yt-dlp** → `yt_mpv.sh`, `qutebrowser.nix`

### Automation & Services

- **auto-upgrade** → `automation.nix`
- **garbage-collection** → `automation.nix`
- **fstrim** → `configuration.nix`(sora)
- **printing** → `configuration.nix`(sora, cnijfilter2, ipp-usb)
- **flatpak** → `configuration.nix`(sora), `persistence.nix`(sora-hm)

### User Identity

- **rakki** → sora, most files
- **tmpst** → tempest
- **<offrakki@gmail.com>** → `git.nix`(both)
- **<fernandomarques1505@gmail.com>** → `rbw.nix`

---

## File Dependency Graph (imports → imported-by)

Key for quick traversal. `→` means "imports/references".

```
flake.nix
  └→ sora: hosts/sora/nixos/configuration.nix
  └→ tempest: hosts/tempest/nixos/configuration.nix

hosts/sora/nixos/configuration.nix
  → hosts/modules/ (default.nix → steam, fish, automation, syncthing, ai, btrfs-ephemeral, optin-persistence, stock-report, usb-tether-failover)
  → hosts/sora/nixos/containers/ (default.nix → containers.nix → glance-dashboard.nix)
  → hosts/sora/nixos/hardware-configuration.nix (→ drivers/default.nix → nvidia-drivers, undervolt; → partitions.nix)
  → hosts/sora/nixos/packages.nix
  → hosts/sora/nixos/fonts.nix
  → hosts/sora/nixos/users.nix
  → hosts/sora/nixos/tailscale.nix
  → hosts/sora/nixos/kdeconnect.nix
  → hosts/sora/nixos/sunshine.nix
  → hosts/sora/nixos/firefly.nix
  → sops: secrets.yaml, pi/private.yaml
  → home-manager: hosts/sora/home-manager/home.nix

hosts/sora/home-manager/home.nix
  → hosts/sora/home-manager/modules/ (default.nix → 35 modules)
  → hosts/sora/home-manager/home-packages.nix
  → hosts/sora/home-manager/gtk.nix
  → hosts/sora/home-manager/darkman.nix
  → hosts/sora/home-manager/qt.nix
  → hosts/sora/home-manager/xdg-portals.nix
  → hosts/sora/home-manager/persistence.nix
  → hosts/sora/home-manager/onedrive.nix → sops template rclone-onedrive.conf

hosts/tempest/nixos/configuration.nix
  → ../../modules/automation.nix, ../../modules/fish.nix, ../../modules/btrfs-ephemeral.nix, ../../modules/optin-persistence.nix
  → hosts/tempest/nixos/containers/ (default.nix → n8n.nix [containers.nix commented out])
  → hosts/tempest/nixos/hardware-configuration.nix (→ partitions.nix)
  → hosts/tempest/nixos/packages.nix
  → hosts/tempest/nixos/users.nix
  → hosts/tempest/nixos/tailscale.nix
  → hosts/tempest/nixos/sunshine.nix
  → home-manager: hosts/tempest/home-manager/home.nix

hosts/tempest/home-manager/home.nix
  → persistence.nix, fish.nix, git.nix, jujutsu.nix, fastfetch.nix, bat.nix, eza.nix
```

---

## Quick-Find Cheat Sheet

| What you're looking for | Look in |
|-------------------------|---------|
| Flake inputs/overlays | `flake.nix` |
| System packages (systemPackages) | `hosts/*/nixos/packages.nix`, `hosts/sora/home-manager/home-packages.nix` |
| Nvidia GPU config | `hosts/sora/nixos/drivers/nvidia-drivers.nix`, `undervolt.nix` |
| Hyprland keybinds | `hosts/sora/home-manager/modules/hypr/hyprland.nix` |
| Hyprland scratchpads | `hosts/sora/home-manager/modules/hypr/pyprland.nix` |
| Fish aliases/abbrs | `hosts/sora/home-manager/modules/fish/fish.nix`, `hosts/tempest/home-manager/fish.nix` |
| GTK/icon/cursor theme | `hosts/sora/home-manager/gtk.nix` |
| Dark/light mode toggle | `hosts/sora/home-manager/darkman.nix` |
| SOPS secrets | `.sops.yaml`, `secrets.yaml`, `pi/private.yaml` |
| Persistence/impermanence | `optin-persistence.nix`, `persistence.nix`(hm both) |
| Firefly III finance | `hosts/sora/nixos/firefly.nix` |
| Stock report | `hosts/modules/stock-report.nix` |
| Email config | `hosts/sora/home-manager/modules/aerc.nix`, `neomutt.nix` |
| Calendar/contacts/todos | `hosts/sora/home-manager/modules/calendar.nix` |
| Opencode personality/skills | `hosts/sora/home-manager/modules/opencode/` |
| Pi coding agent config | `hosts/sora/home-manager/modules/pi/` — this file's home |
| Pi advisor tool | `pi/pi.nix` → `npm:@juicesharp/rpiv-advisor` (in packages); configured via `/advisor` slash command
| Pi settings/providers | `pi/pi.nix` → `programs.pi-coding-agent.settings` |
| Pi custom model providers | `pi/pi.nix` → `home.file models.json` (generated inline) |
| Pi extensions | `pi/extensions/*.ts` |
| Pi custom keybindings | `pi/pi.nix` → `home.file keybindings.json` (generated inline) |
| Pi prompt templates | `pi/prompts/*.md` |
| Pi theme definitions (catppuccin-mocha, ciel-cursor, gruvbox-dark-hard) | `pi/themes/*.json` |
| Pi skill definitions | `pi/skills/*/SKILL.md` |
| Pi Ciel personality/context | `pi/context.md` |
| Shared skills (jujutsu, nix, etc.) | `opencode/skills/*/` (symlinked via pi.nix) |
| SOPS secrets used by pi | `secrets.yaml`, `pi/private.yaml` |
| Ciel free-roam (/freeroam) | `opencode.nix`(command.freeroam), `bin/freeroam.sh`, `ciel.nix`(heartbeat-timer) |
| Glance dashboard YAML | `hosts/*/nixos/containers/data/glance/glance.yml` |
| NixOS containers | `hosts/*/nixos/containers/default.nix`, `containers/containers.nix` |
| Wallpapers | `assets/wallpapers/` |
| Utility scripts | `scripts/` |
| Minecraft server | `hosts/sora/nixos/mcServer.nix` |
| Printers | `configuration.nix`(sora) → cnijfilter2, ipp-usb |
| AI/LLM (Ollama) | `hosts/modules/ai.nix` |
| Sunshine streaming | `hosts/*/nixos/sunshine.nix` |
| Secure boot (lanzaboote) | `configuration.nix`(sora) |
| Partition/disko | `hosts/*/nixos/partitions.nix` |

---

*Last updated: 2026-06-18 by Ciel. This file in `pi/INDEX.md` is now the canonical NixConfig index — the old `opencode/INDEX.md` is a redirect stub.*
