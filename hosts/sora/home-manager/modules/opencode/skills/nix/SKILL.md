---
name: nix
description: Use when working with NixOS rebuilds, Nix package management, and flake workflows. Covers nh os build/switch, nix shell/run for one-off programs, and syncing jj commits with the flake for evaluation.
---

# Nix

## Rebuild

Split rebuilds into **two steps** — always, every time:

1. **Build here** (no sudo needed, output visible in chat):
   `nixos-rebuild build --flake <path>`

2. **Apply on terminal** (spawns a kitty window for interactive auth):
   `kitty --directory <workdir> -e sh -c 'nh os <option> <flake-path> || exec bash' &`

   Where `<option>` is `switch` or `build` and `<flake-path>` is the full path to the
   flake (e.g. `/home/rakki/Documents/NixConfig`). `nh` doesn't auto-detect the
   flake from the working directory — it needs it as an explicit argument or via
   the `NH_OS_FLAKE` env var.

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

## Flake and Version Control

Flake evaluation uses git under the hood via `builtins.fetchGit`. To make jj
commits visible to the flake, use `jj bookmark move master --to '@' && jj git
export` to sync jj's state into the git refs.
