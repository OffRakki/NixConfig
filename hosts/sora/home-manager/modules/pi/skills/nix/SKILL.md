---
name: nix
description: Use when working with NixOS rebuilds, Nix package management, and flake workflows. Covers nh os build/switch, nix shell/run for one-off programs, and syncing jj commits with the flake for evaluation.
---

# Nix

Ciel can also use `ctx_shell` for nix commands — output goes through lean-ctx
compression, saving tokens on verbose build output.

## LSP Warm-up

At session start (or after 240s idle timeout), pi-lens shows "LSP Inactive" in
the footer because no LSP server is connected. To warm up `nixd`:

1. Use the native `read` tool (not `ctx_read`) on a `.nix` file:
   `read("/home/rakki/Projects/NixConfig/flake.nix", {limit: 5})`
2. This fires a `tool_call` event, which pi-lens hooks to spawn `nixd`
3. The footer flips to `LSP Active (N)` within ~150ms

`ctx_*` tools (`ctx_read`, `ctx_shell`, etc.) route through MCP and skip pi's
native `tool_call` event — they do NOT trigger LSP warm-up. Always warm with
the native `read` tool first.

After warm-up, `ctx_read` works fine while the server stays alive (the 240s
idle timer resets on each file touch). On timeout, just warm again.

## File Location

Use `ctx_find`, `ctx_grep`, and targeted reads directly in NixConfig.
Prefer source-of-truth files over generated maps or broad docs.

## Pi module changes

Pi packages, custom extensions, skills, prompts, themes, custom agents, and model
providers are declared in `hosts/sora/home-manager/modules/pi/pi.nix`. Runtime
paths under `~/.pi/agent/` update only after Home Manager activation.

When adding a Nix-managed Pi skill or agent:

1. Put the source under `hosts/sora/home-manager/modules/pi/skills/` or `agents/`.
2. Add the corresponding `home.file."${piDir}/...".source = ...;` entry in `pi.nix`.
3. Add a routing line to `context.md` if the skill should be proactively loaded.
4. Build/check before claiming it is available at runtime.

Load `pi-tools` for the installed package/tool inventory.

## Rebuild

Split rebuilds into **two steps** — always, every time:

1. **Build here** (no sudo needed, output visible in chat):
   `nixos-rebuild build --flake <path>`

2. **Apply on terminal** (spawns a kitty window for interactive auth):
   `kitty --directory <workdir> -e sh -c 'nh os <option> <flake-path> || exec bash'`

Where `<option>` is `switch` or `build` and `<flake-path>` is the full path to the
flake (e.g. `/home/rakki/Projects/NixConfig`). `nh` doesn't auto-detect the
flake from the working directory — it needs it as an explicit argument or via
the `NH_OS_FLAKE` env var.

## Terminal spawning

For commands that need sudo (interactive auth), spawn kitty:

```
kitty --directory <workdir> -e sh -c '<cmd> || exec bash'
```

The `|| exec bash` keeps the window open on failure. Do NOT use `&` — the Bash
tool's process management can still kill the backgrounded kitty when the tool
times out. Instead, call kitty without `&` and use a **long timeout**
(600000ms, 10 min) on the Bash tool call. Kitty opens its own window; the Bash
tool just blocks until the command completes or the window is closed.

`DISPLAY` and `WAYLAND_DISPLAY` are inherited in the Bash tool environment.

## Package Management

Machines not running NixOS may have **Nix standalone** installed instead. For
one-off programs that aren't already available, use `nix shell` or `nix run`
rather than `apt install` or `nix profile install`.

IMPORTANT: if you run into e.g. `python3: command not found`, ALWAYS try again with nix shell/run.

### nix shell

The canonical form for running a single command in a temporary nix environment:

```
nix shell nixpkgs#<package> -c <command> [args...]
```

The `-c` flag tells `nix shell` to exec the following arguments as a command.
Everything after `-c` is passed straight to the shell, so quoting works naturally.

**CRITICAL**: NEVER double-quote `"<command> [args...]"` together. This causes bash to treat the entire thing as the executable name:

- Wrong: `nix shell nixpkgs#python3 -c "python3 foo.py arg1 arg2"`
- Right: `nix shell nixpkgs#python3 -c python3 foo.py arg1 arg2`

```bash
nix shell nixpkgs#jq -c jq '.foo' file.json
nix shell nixpkgs#yq -c yq eval '.foo.bar' file.yml
```

Multiple packages in one shell (drops into interactive shell):

```bash
nix shell nixpkgs#jq nixpkgs#yq nixpkgs#curl -c sh
```

### nix run

More concise for a tool's default binary:

```bash
nix run nixpkgs#jq -- -r '.name' file.json
```

Use `nix run` when:

- You want a single command with arguments (everything after `--` is passed to the binary)
- The package's default binary name matches what you need
- You don't need multiple packages simultaneously

Use `nix shell` when:

- You need to chain multiple commands in the same ephemeral environment
- The command name differs from the package name (e.g. `nixpkgs#nodePackages.prettier`)
- You want an interactive shell with multiple tools available

### Finding packages

```bash
nix search nixpkgs <query>
```

## Sops secrets

**Never hardcode `/run/secrets/...` paths in Nix config files.** Always
reference the path via `config.sops.secrets.<name>.path` (or `osConfig` in
home-manager modules). Example:

```nix
sops.secrets.myApiKey = {
  owner = "rakki";
  # NO "path" — let sops use its default (/run/secrets/myApiKey)
};
```

Then reference it:

```nix
# In NixOS modules:
config.sops.secrets.myApiKey.path  # → /run/secrets/myApiKey

# In home-manager modules (accessing NixOS):
osConfig.sops.secrets.myApiKey.path
```

For scripts/tools that need the path, inject it via a wrapper script rather
than hardcoding the path in the script itself:

```nix
pkgs.writeShellScriptBin "my-tool" ''
  export API_KEY=$(cat ${config.sops.secrets.myApiKey.path})
  exec ${pkgs.mytool}/bin/mytool "$@"
''
```

Add the wrapper to `home.packages` or `environment.systemPackages` so it's
available in PATH. The raw scripts can keep a generic fallback path for
standalone use — just make sure the default matches sops' convention
(`/run/secrets/<keyName>`).

## Flake and Version Control

Flake evaluation uses git under the hood via `builtins.fetchGit`. To make jj
commits visible to the flake, use `jj bookmark move master --to '@' && jj git
export` to sync jj's state into the git refs.
