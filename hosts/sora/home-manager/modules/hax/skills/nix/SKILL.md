---
name: nix
description: NixOS builds, Home Manager activation, declarative HAX package and skill changes, and temporary Nix CLI environments.
---

# Nix workflow

Source: `/home/rakki/Projects/NixConfig/`. All deployed configuration is Nix-owned;
never edit `~/.config/` outputs. Read complete source files before changes.
Prefer existing packages/modules, small solutions and nested attribute sets.
Never add generated reports or logs to NixConfig.

## HAX changes

`hosts/sora/home-manager/modules/hax/default.nix` installs HAX from the locked
llm-agents input, declares the explicit skill map, persists state, and creates a
desktop entry. `settings.nix` is nonsecret HAX configuration; `context.md` is global
instructions. Keep Pi's sibling module intact during the pilot. No UI extensions
or startup daemons should be introduced. Load `hax-tools` before changing routing.

Add skills to the source skill map, preserving required references/scripts. Never
symlink Pi's whole skill tree into HAX or advertise unsupported tools/agents.
Do not change flake inputs merely to configure a different default model.

## Validate and apply separately

1. Load `jujutsu`, inspect working-copy ownership and diff, and ensure new source
   files are tracked by jj. Do not blindly move the default bookmark or use Git.
2. Evaluate `nix flake check --no-build`.
3. Build without sudo:
   `nixos-rebuild build --flake /home/rakki/Projects/NixConfig`.
4. Only after successful build and authorization, apply in a terminal:
   `kitty --directory /home/rakki/Projects/NixConfig -e sh -c 'nh os switch /home/rakki/Projects/NixConfig || exec bash'`.

No `&`; allow ten minutes for commands. Build success is not activation. Source
settings and skills are visible to a new HAX process only after activation.
Do not push or move `master` just to run evaluation; inspect the actual jj/flake
visibility issue first if source changes appear missing.

## Temporary dependencies

Use `nix shell nixpkgs#<package> -c <command> <args>` or
`nix run nixpkgs#<package> -- <args>`. Never pass command plus arguments as one
quoted executable string. Do not install imperatively through another package
manager. If a command is missing, use Nix instead of inventing an alternative API.

## Secrets

This pilot has no SOPS-backed HAX provider wrappers/private prompt assembly yet.
Do not decrypt or copy private files merely to inspect configuration. A future
integration must use `osConfig.sops.secrets.<name>.path` or the appropriate NixOS
`config.sops.secrets.<name>.path` at runtime, never hardcoded secret paths or values
in derivations/config/argv. Do not propagate every credential into all children.
If secret work is requested, first review and adapt the repository's complete
security-sweep procedure; no claim that missing HAX routing exempts that review.
