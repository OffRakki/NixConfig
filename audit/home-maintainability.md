# Home Manager Maintainability Audit

**Audited by:** Ciel  
**Date:** 2026-06-18  
**Scope:** `hosts/sora/home-manager/`, `hosts/sora/nixos/`, shared modules under `hosts/modules/`, and the flake root.  
**Method:** Read-only inspection of every `.nix` file in the scope, plus grep-backed pattern search.  
**Overall verdict:** Clean core, moderate bloat in disabled-import surface area, hardcoded paths are the main risk. No blockers.

---

## 1. `with pkgs;` — widespread, low-risk, but scope-polluting

Every package list in the config uses `with pkgs;`:

| File | Line(s) |
|---|---|
| `home-manager/home-packages.nix` | 2 |
| `nixos/packages.nix` | 6 |
| `home-manager/modules/aerc.nix` | 110 |
| `home-manager/modules/calendar.nix` | 9 |
| `home-manager/modules/pi/pi.nix` | 27 |
| `nixos/hardware-configuration.nix` | 79, 128 |
| `nixos/fonts.nix` | 3 |
| `nixos/users.nix` | 38 |
| `nixos/configuration.nix` | 332, 475 |

**Risk:** Low. `with pkgs;` is idiomatic and standard in NixOS/home-manager configs. It doesn't cause issues here because none of these files define local variables that could shadow.  
**Recommendation:** Acceptable as-is. If scope pollution ever becomes a problem, switch to `inherit (pkgs) foo bar;` or explicit `pkgs.foo` references.

---

## 2. `rec` keyword — small, generally avoidable

**File:** `home-manager/modules/qutebrowser.nix`

```nix
searchEngines = rec {
  kagi = "https://kagi.com/search?q={}";
  # ... aliases
  DEFAULT = kagi;   # self-reference — works with rec
};
```

Also in the `url` block inside `settings`:

```nix
url = rec {
  default_page = "192.168.15.12:1202/fernando";
  start_pages = [default_page];
};
```

**Risk:** Negligible in these small cases. `rec` is safe here.  
**Recommendation:** Fine as-is. If the record grows, consider pulling the reference out inline to avoid lazy-evaluation footguns.

---

## 3. Commented-out / dead config — moderate accumulation

These are config blocks that serve no runtime purpose but remain in the source. They build mental overhead and suggest unfinished experiments.

| File | Lines | Block |
|---|---|---|
| `modules/qutebrowser.nix` | 2–7 | Entire `xdg.mimeApps.defaultApplications` block for qutebrowser commented out |
| `modules/fish/fish.nix` | 52–62 | `# plugins = lib.optional useHelix { ... }` — helix fish-plugin |
| `modules/pi/pi.nix` | 43–59 | `# retry = { ... }` and `# enabledModels = [ ... ]` |
| `modules/jujutsu.nix` | 30–48 | `# template-aliases = { ... }` |
| `modules/git.nix` | 11 | `# credential.helper = ...` |
| `modules/hypr/hyprland.nix` | 207–211 | Commented-out `inhibit-idle-fullscreen` window rule |
| `modules/hypr/hyprland.nix` | 369 | `-- hl.exec_cmd("Telegram")` |
| `modules/hypr/hyprland.nix` | 448 | `-- hl.bind("Caps_Lock", ...)` |
| `modules/hypr/hyprland.nix` | 460 | `-- "${mod} + SHIFT + D", ...` (wofi menu — replaced by noctalia shell) |
| `modules/hypr/hyprlock.nix` | 54–60 | Commented-out logo label |
| `modules/hypr/hyprdefault.nix` (hypr/) | 4 | `# ./hyprpaper.nix` commented out of imports while `hyprpaper.nix` is enabled via `services.hyprpaper.enable = true` in its file |
| `modules/noctalia.nix` | 307 | `# { id = "Battery"; }` |
| `modules/fish/fish.nix` | 94, 106–107 | Commented-out aliases (`nhos`, `celmount`, `celumount`) |
| `modules/waybar.nix` | 37–38 | Commented-out scroll bindings |

**Recommendation:**  
- **Remove** commented-out code that has been replaced (e.g., wofi launcher replaced by noctalia shell, old scroll bindings).  
- **Keep or move to a branch** any blocks that represent revertible experiments.  
- **Git history exists** — there is no need to keep commented-out code for reference.

---

## 4. Hardcoded paths — the primary maintainability risk

### 4a. `__GL_SHADER_DISK_CACHE_PATH`

**File:** `hosts/sora/nixos/configuration.nix`, line 155

```nix
__GL_SHADER_DISK_CACHE_PATH = "/home/rakki/.nv/shaderCache";
```

**Issue:** Absolute path with username. Breaks if the username changes or this config is reused for another user. This path is already persisted via `home-manager/persistence.nix` line 6 (`".nv"`), so it could be derived from `config.home.homeDirectory`.

**Recommendation:** Change to:

```nix
__GL_SHADER_DISK_CACHE_PATH = "${config.users.users.rakki.home}/.nv/shaderCache";
```

### 4b. Firefly backup output directory

**File:** `hosts/sora/nixos/firefly.nix`, line 74

```nix
OUTDIR="/home/rakki/sync/geral/FireflyBKP"
```

**Recommendation:** Derive from `config.users.users.rakki.home` or pass through a variable.

### 4c. Minecraft server paths

**File:** `hosts/sora/nixos/mcServer.nix`, lines 24–26

```nix
"mods" = /home/rakki/mcServer/mods;
"config" = /home/rakki/mcServer/config;
"defaultconfigs" = /home/rakki/mcServer/defaultconfigs;
```

**Note:** This file is commented out from `configuration.nix` imports (`# ./mcServer.nix`), so it's dead code. Still worth fixing if reactivated.

**Recommendation:** Either remove or use `config.users.users.rakki.home`.

### 4d. Glance container config paths

**File:** `hosts/sora/nixos/containers/containers.nix`, line 47
**File:** `hosts/tempest/nixos/containers/containers.nix`, line 46

```nix
path = "/home/rakki/.config/glance/glance.yaml";
# and
path = "/home/tmpst/.config/glance/glance.yaml";
```

**Recommendation:** Hardcoded per-host is acceptable here since each host has its own file. If refactored into a shared module, these would need parameterization.

### 4e. Stock report output directory

**File:** `hosts/modules/stock-report.nix`, line 79

```nix
OUTPUT_DIR = "/home/rakki/Documents/Stocks";
```

**Recommendation:** Derive from the user's home directory.

### 4f. Syncthing sync directory

**File:** `hosts/modules/syncthing.nix`, line 2

```nix
syncDir = "/home/rakki/sync";
```

**Recommendation:** Parameterize or derive from user home.

### 4g. OpenCode archive template path

**File:** `home-manager/modules/opencode/opencode.nix`, line 145

```
template = "Summarize this entire chat session into a beautiful markdown note and save it to the /home/rakki/sync/Obsidian/Summaries folder.";
```

**Recommendation:** This is a prompt template string, not Nix-evaluated. Could be parameterized if the path ever changes.

### 4h. MPD music directory

**File:** `hosts/sora/nixos/configuration.nix`, line 288

```nix
music_directory = "/home/rakki/Music";
```

**Recommendation:** Derive from `config.users.users.rakki.home + "/Music"`.

### 4i. N8n container volume path

**File:** `hosts/tempest/nixos/containers/n8n.nix`, line 25

```nix
"/home/tmpst/Documents/DockerVolumes/n8n:/home/node/.n8n:z"
```

**Note:** Host-specific, in a host-specific file. Acceptable.

---

## 5. Brittle relative-path references from deep module trees

Several modules reach up multiple directories to reference assets or scripts:

| File | Reference | Depth |
|---|---|---|
| `modules/hypr/hyprland.nix:436` | `'${../../../macros/autoClicker.sh}'` | 4 levels up |
| `modules/hypr/hyprland.nix:455` | `'${../../../../../scripts/pass-wofi.sh}'` | 6 levels up |
| `modules/hypr/hyprlock.nix:19` | `"${../../../../../assets/wallpapers/knnw.jpg}"` | 6 levels up |
| `modules/noctalia.nix:520` | `"${../../../../assets/svgs/pelucio.jpg}"` | 5 levels up |
| `modules/qutebrowser.nix:67–68` | `hint links spawn ${../../../../scripts/yt_mpv.sh}` | 5 levels up |
| `nixos/configuration.nix:85` | `../../../secrets.yaml` | 3 levels up |

**Risk:** These paths break if the module directory structure is reorganized. The `../../../../../scripts/` pattern in particular is fragile.

**Recommendation:** Add a `rootDir` or `nixConfigRoot` special argument (already used in `noctalia.nix` via `nixConfigRoot` — replicate that pattern) and reference assets/scripts as:

```nix
"${nixConfigRoot}/assets/wallpapers/knnw.jpg"
```

The `nixConfigRoot` argument is already available in the flake and passed through to home-manager. It just needs to be threaded into these modules.

---

## 6. Disabled-but-imported modules — noisy surface area

These modules are imported but immediately `enable = false`:

| Module | Status |
|---|---|
| `hypridle.nix` | `enable = false` |
| `hyprlock.nix` | `enable = false` |
| `hyprpanel.nix` | `enable = false` |
| `mako.nix` | `enable = false` |
| `quickshell/quickshell.nix` | `enable = false` |
| `starship.nix` | `enable = false` |
| `waybar.nix` | `enable = false` (via `mkForce`) |
| `hyprpaper.nix` | imported in `default.nix` but commented out — however the file itself has `enable = true`; it's imported anyway via the `default.nix` import list skipping it — **actually checked**: `hypr/default.nix` has `# ./hyprpaper.nix` commented out, so it's NOT imported. But `hyprpaper.nix` itself has `enable = true`. |

The waybar module is particularly notable — it uses `lib.mkForce` to force `enable = false`:

```nix
programs.waybar = lib.mkForce {
  enable = false;
  settings = { ... };
  style = ''...'';
};
```

**Issues:**
- `mkForce` on a `programs.waybar` attribute set that's already disabled defensively suggests something else is trying to enable it. That something should be found and removed instead.
- 7 disabled modules add import overhead and create a misleading impression of what's actually running. Noctalia shell replaced hyprpanel, waybar, mako, etc. — those modules' settings are dead config.

**Recommendation:** Either:
1. Remove these files from their respective `default.nix` import lists, or
2. Delete the files entirely (git history preserves them).

At minimum, remove the `mkForce` from waybar — `enable = false` is sufficient.

---

## 7. `mkDefault` and `mkForce` — usage audit

### `lib.mkDefault` on entire attribute set

**File:** `home-manager/modules/zed.nix`, line 3

```nix
programs.zed-editor = lib.mkDefault { ... };
```

**Issue:** `mkDefault` on the entire attribute set is unusual. It means another module could override the whole thing. Usually you want `mkDefault` on individual values within the set, not the whole set. If the intent is "enable zed but allow override," `enable` should be `lib.mkDefault true` instead.

### `lib.mkForce` on disabled waybar

**File:** `home-manager/modules/waybar.nix`, line 2

```nix
programs.waybar = lib.mkForce { enable = false; ... };
```

**Issue:** Defensive `mkForce` on something already off. Either something is fighting to enable waybar (fix the cause), or this is cargo-culting. Remove `mkForce`.

---

## 8. Persistence declaration sprawl — 7 sources for `/persist`

`home.persistence."/persist".directories` is appended to from:

1. `home-manager/home.nix` — 7 dirs
2. `home-manager/persistence.nix` — 30+ dirs (the main chunk)
3. `home-manager/modules/pi/pi.nix` — 2 dirs
4. `home-manager/modules/opencode/opencode.nix` — 2 dirs
5. `home-manager/modules/calendar.nix` — 3 dirs (uses `mkAfter`)
6. `home-manager/modules/aerc.nix` — 2 dirs
7. `home-manager/modules/noctalia.nix` — 2 dirs

**Risk:** Low — Nix merges lists by concatenation. But it means there's no single source of truth for what persists. Finding all persisted paths requires grepping.

**Recommendation:** This is an architectural tradeoff. Module-local persistence (each module declares its own) is the more modular approach and is arguably correct. If consolidation is desired, keep the `persistence.nix` as the single source and move small module declarations there. But this is style, not correctness.

---

## 9. Inconsistent home directory references

Three different styles are used to reference the home directory:

| Style | Examples |
|---|---|
| `config.home.homeDirectory` | `aerc.nix`, `home.nix` |
| `"~/"` or `~/` | `calendar.nix` (khal config, mbsync paths) |
| `/home/rakki/...` (absolute) | `configuration.nix`, `firefly.nix`, `mcServer.nix`, `stock-report.nix`, `syncthing.nix` |
| `$HOME` | `opencode.nix` (in prompt template), `home.nix` (SOPS key path via string) |

**Recommendation:** Standardize on `config.home.homeDirectory` (for home-manager) or `config.users.users.rakki.home` (for NixOS). The `~` tilde-expansion in `calendar.nix` works because vdirsyncer/khal/khard expand it at runtime, but mixing tilde and explicit paths creates confusion.

---

## 10. /tmp/session.lock — shared state, no shared variable

**Files:**
- `modules/hypr/hyprland.nix:363, 368` — `touch /tmp/session.lock`
- `modules/hypr/hypridle.nix:6` — `rm -f /tmp/session.lock`
- `modules/hypr/hyprland.nix` — used in lock command strings
- `modules/noctalia.nix` — `screenUnlock = "rm -f /tmp/session.lock"`

**Issue:** The lock file path `/tmp/session.lock` is hardcoded as a string literal in 4+ places. If it ever needs to change, it must be updated everywhere.

**Recommendation:** Define once as a variable in `hypr/default.nix` (or a common module) and reference it. Since these are embedded in Lua strings, it's more involved, but a `let` binding at the top of `hyprland.nix` would centralize it.

---

## 11. Package list hygiene

### `home-packages.nix` — notable items

- **`firefox`** is in home-packages but also has a `modules/firefox.nix` config file. The config file only sets chrome/user.js/profiles.ini, no `programs.firefox` enablement. These work fine together.
- **`starship`** is in home-packages but `modules/starship.nix` has `enable = false`. The package is what's used, the module is dead config.
- **`waybar-mpris`** is in home-packages while `modules/waybar.nix` has `enable = false` with `mkForce`. The package may be pulled in but waybar itself isn't running. Check if waybar's mpris module conflicts or if the package is simply unused.
- **`rofi`** is in home-packages but replaced by wofi/noctalia launcher. Dead package.
- **`ranger`** is in home-packages but `filesGUI` uses nemo and `files` uses yazi. Dead.
- **`xwayland-satellite` and `xwayland` and `xwayland-run`** — all three xwayland variants in `packages.nix`. `xwayland-satellite` may replace the others, but having all three is noisy. Verify intent.

---

## 12. Minor findings

### 12a. Duplicate `hl.bind` key `"${mod} + SHIFT + Q"`

**File:** `hypr/hyprland.nix`, lines 438 and 462

```lua
hl.bind("${mod} + SHIFT + Q", hl.dsp.window.close())   -- line 438
hl.bind("${mod} + SHIFT + Q", hl.dsp.window.kill)        -- line 462
```

The second overwrites the first. The first was likely intended as a gentler close before kill was added. Dead code.

### 12b. `hl.bind` with `hl.dsp.window.kill` vs `hl.dsp.window.kill()`

**File:** `hypr/hyprland.nix`, line 462

```lua
hl.bind("${mod} + SHIFT + Q", hl.dsp.window.kill)
```

Other binds call functions with `()`. This one passes the function reference. Check if hyprland's bind handler calls the function or expects a thunk.

### 12c. `max_lenght` typos in waybar config

**File:** `modules/waybar.nix`, lines 87 and 388

```nix
min-lenght = 6;     # should be min-length
max-lenght = 30;    # should be max-length
```

Waybar may silently ignore these, meaning the length constraints don't work for those modules.

---

## Summary

| Category | Severity | Action |
|---|---|---|
| Hardcoded paths | **High** (5+ files) | Replace with `config.home.homeDirectory` or `config.users.users.rakki.home` |
| Brittle relative path references | **Medium** (5 files) | Switch to `nixConfigRoot`-based paths |
| Commented-out dead config | **Low-Medium** (12+ blocks) | Remove — git history preserves everything |
| Disabled modules still imported | **Low** (7 modules) | Remove from default.nix imports or delete files |
| `mkForce` abuse in waybar | **Low** | Remove `lib.mkForce` |
| `mkDefault` on zed attrset | **Low** | Move to individual `lib.mkDefault` on `enable` |
| `/tmp/session.lock` sprawl | **Low** | Centralize into a shared `let` binding |
| `/persist` declaration sprawl | **Low** | Architectural choice — keep as-is or consolidate |
| `with pkgs;` usage | **Informational** | Idiomatic, no action needed |
| `rec` keyword | **Informational** | Safe in current usage |
| Package deadwood (rofi, ranger, starship module, waybar) | **Low** | Audit and remove unnecessary packages |
| Typo in waybar attr names | **Medium** | Fix `min-lenght` → `min-length`, `max-lenght` → `max-length` |

**Overall:** No blockers. The config is well-structured with clear module separation. The main maintenance burden is the scattered hardcoded paths and the accumulation of dead/disabled config that makes it harder to see what's actually running.
