# Flake, Modules & Security Audit

Generated: 2026-06-18 by Ciel
Scope: `flake.nix` inputs/outputs, NixOS modules, imports, overlays, security/secrets, dead/redundant config
Method: Read-only file inspection — no changes made.

---

## 🔴 Blocker — Security

### 1. RCON password in plaintext
- **File:** `hosts/sora/nixos/mcServer.nix:18`
- `"rcon.password" = "123123";` — the Minecraft server RCON password is a hardcoded guessable string. Anyone with LAN or Tailscale access to port 25575 (if exposed) can take over the server console.
- **Fix:** Load from `config.sops.secrets.<name>.path` or at minimum use a strong random value stored in `secrets.yaml`.

### 2. n8n auth token in plaintext
- **File:** `hosts/tempest/nixos/containers/n8n.nix:10,24`
- `N8N_RUNNERS_AUTH_TOKEN = "283b2ec20d89c001cd2c7d6393e0d53976f2424977e862e5";` — this token is identical in both the runner and main n8n container definitions, checked into version control as raw text.
- **Fix:** Use `config.sops.secrets.<name>.path` and environment file injection instead.

### 3. SSH password authentication enabled on sora
- **File:** `hosts/sora/nixos/configuration.nix:303`
- `PasswordAuthentication = true;` — sora exposes SSH with password auth. This is inconsistent with tempest which has it disabled (`PasswordAuthentication = false;` + `KbdInteractiveAuthentication = false;`). Since sora is a laptop that may connect to untrusted networks, password auth is a risk.
- **Fix:** Set to `false` or limit to key-only auth. If you need it for recovery, restrict to LAN addresses via `Match` blocks.

### 4. Permitted insecure Electron version
- **File:** `hosts/sora/nixos/configuration.nix:33`
- `"electron-39.8.10"` is in `permittedInsecurePackages`. This version is old enough that it likely has unpatched CVEs. No package name is documented alongside it.
- **Fix:** Document *which* package needs this (add a comment) or remove it if the depending package has been updated.

---

## 🟡 Dependency Bloat

### 5. `ministerio` input used for a single package (clip-notify)
- **Files:** `flake.nix:52` → `hosts/sora/home-manager/modules/clipnotify.nix:8`
- The entire `github:misterio77/nix-config` flake (41KB+ flake.lock, 13 sub-inputs including nixos-mailserver with blobs, themes, hardware, etc.) is pulled in exclusively for `clip-notify`.
- **Impact:** Adds ~10 unnecessary locked inputs (hytale_2, impermanence_2, nix-colors, nix-gl, nixos-mailserver + blobs + git-hooks, themes, website, firefox-addons, disko_2, home-manager_2, lanzaboote_2, nix-minecraft) to the lock file — all for one tiny clipboard daemon.
- **Fix:** Vendor `clip-notify` locally as a simple derivation, or find it in nixpkgs directly. This removes ~13 lock entries and speeds up evaluation.

---

## 🟠 Duplication & Inconsistencies

### 6. Duplicate `uinput` udev rules
- **File:** `hosts/sora/nixos/hardware-configuration.nix:107-108`
  ```
  KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
  KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
  ```
  Two identical-meaning rules for the same device, one under `GROUP="uinput"` and one under `GROUP="input"`. The `hardware.uinput.enable = true` (line 124) already handles this correctly through upstream NixOS modules. Also `sunshine.nix` adds yet another `KERNEL=="uinput"` rule.
- **Fix:** Deduplicate to one rule in one place, or rely on `hardware.uinput.enable`.

### 7. `nixpkgs` source mismatch between flake.nix and flake.lock (root)
- **flake.nix:** `nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";`
- **flake.lock (root → nixpkgs_7) original:** `"type": "tarball", "url": "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz"`
- The lock file's `original` field does not match the URL in `flake.nix`. This means a `nix flake lock --update-input nixpkgs` may behave unexpectedly, or the lock was manually edited/tampered with.
- **Fix:** Run `nix flake lock --update-input nixpkgs` to regenerate the lock entry from the declared `github:` URL.

### 8. `services.xserver.enable = true` on sora alongside Hyprland
- **File:** `hosts/sora/nixos/configuration.nix:269`
- Enabling `services.xserver` alongside Hyprland can cause conflict: `xserver` starts an X display server that may interfere with Hyprland's XWayland, and pulls in unnecessary X11 infrastructure. On sora, this appears to be only for NVIDIA CoolBits (device section, line 272-274). Tempest also enables it for Plasma6 (expected).
- **Note:** If CoolBits is the only reason, consider if there's a Wayland-native path for that. Minor issue but worth noting.

### 9. `nixConfigRoot` hardcoded to an absolute path in flake.nix
- **File:** `flake.nix:99`: `nixConfigRoot = "/home/rakki/Projects/NixConfig";`
- **File:** `flake.nix:106`: `nixConfigRoot = "/home/tmpst/Documents/NixConfig";`
- These paths won't resolve correctly if the repo is cloned elsewhere (e.g., for CI, temporary builds, or if Lucky reinstalls with a different home). The HM `NH_FLAKE` session variable depends on this.
- **Fix:** Use `builtins.toString ./.` or `./.` directly instead of the literal string.

---

## ⚪ Dead / Commented-Out Config

### 10. `mcServer.nix` import commented out
- **File:** `hosts/sora/nixos/configuration.nix:20`
- `# ./mcServer.nix` — but the file still exists with content and `nix-minecraft` / `hytale` inputs are still locked.
- **Impact:** `hytale` flake input (~220KB in lock) is pulled for nothing if the Minecraft server is unused. The `nix-minecraft` overlay is still applied (line 35).

### 11. Commented-out SSD (ssd-sata) in partitions.nix
- **File:** `hosts/sora/nixos/partitions.nix:56-82`
- Entire second disk block is commented out. If the disk is no longer in the machine, remove the dead code. If it might return, add a note.

### 12. Millennium flake input & overlay references
- **File:** `flake.nix:55`: commented `# millennium.url = ...`
- **File:** `hosts/sora/nixos/configuration.nix:40`: `# inputs.millennium.overlays.default`
- Dead reference. Remove the commented line from flake.nix and the overlay comment.

### 13. Commented OpenRGB profile service
- **File:** `hosts/sora/nixos/hardware-configuration.nix:130-139`
- `systemd.services.openrgb-load-profile` — entire block commented out. Dead code.

### 14. `steam.nix` has commented `millennium` package reference
- **File:** `hosts/sora/nixos/modules/steam.nix:3`: `# package = pkgs.inputs.millennium.steam-millennium;`
- Plus `catppuccin-cursors.mochaPeach` in `extraCompatPackages` which is not a compatibility tool and won't work there — it's a cursor theme. This likely causes a build warning or silent no-op.

---

## 📝 Notes & Observations

### 15. OpenLDAP and Perl override without documentation
- **File:** `hosts/sora/nixos/configuration.nix:37-45`
- `openldap` and `DBDCSV` have their `doCheck` disabled via overrides. No comment explains why tests are skipped. If there's a genuine upstream failure, document which test fails.

### 16. `result/` directory present in project root
- **File:** `result/` is a build artifact (symlink tree from `nixos-rebuild build`). `.gitignore` has `result*` so it's not tracked, but it takes ~1-2GB of inode space and can confuse tools. Remove it when not actively debugging a build.

### 17. `hosts/sora/home-manager/modules/steam.nix` duplicates NixOS-level steam config
- **File:** `hosts/sora/home-manager/modules/steam.nix` vs `hosts/modules/steam.nix` (NixOS level)
- Two separate steam module files. The HM one likely duplicates or conflicts with the NixOS-level `programs.steam` settings. Verify which one is actually in effect.

### 18. `sops-nix` SSH key path assumes persist structure
- **File:** `hosts/sora/nixos/configuration.nix:79`: `/persist/etc/ssh/ssh_host_ed25519_key`
- Same path in `hosts/tempest/nixos/configuration.nix`. This is correct for the impermanence setup *if* the file actually exists at that path. If the host key is regenerated on every boot because the file is missing, SSH host keys will change, breaking known_hosts. Verify persist setup includes this path.

---

**Summary tally:**
- 🔴 Blocker: 4 (RCON, n8n tokens, SSH password auth, Electron version)
- 🟡 Bloat: 1 (ministerio → clip-notify)
- 🟠 Inconsistency: 4 (nixpkgs source, uinput rules, xserver + hyprland, hardcoded paths)
- ⚪ Dead: 5 (mcServer, ssd-sata, millennium, openrgb, steam cursor)
- 📝 Note: 4 (unexplained overrides, result/, duplicate steam, SSH key path)

No project source files were modified during this audit.
