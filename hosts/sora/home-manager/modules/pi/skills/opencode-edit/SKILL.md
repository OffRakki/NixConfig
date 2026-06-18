---
name: opencode-edit
description: Edit Ciel's opencode configuration — context, skills, agents, and settings. ALWAYS load this when creating or editing any opencode file. Covers the Nix-managed workflow.
---

## Context (`~/.config/opencode/AGENTS.md`)

AGENTS.md is a Nix-managed symlink. The real source is:
`/home/rakki/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/context.md`

**Never edit AGENTS.md directly** — it will be overwritten on the next rebuild.

### Editing context.md

1. Edit the source file at `~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/context.md`
2. Sync jj, rebuild, restart (see Build + Restart below)

### Adding extra instructions (sops-backed)

Additional context files can be loaded via the `instructions` array in the `programs.opencode` block of `opencode.nix`:

```nix
instructions = [osConfig.sops.secrets.<name>.path];
```

These are merged alongside `context.md` and can reference sops-backed files for private info (API instructions, personal notes, etc.). Not currently used, but available.

## Skills (`~/.config/opencode/skills/<name>/`)

Skills are symlinked by home-manager from their source in NixConfig. Home-manager symlinks the **entire skill directory**, so extra files (scripts, references, resources) are included automatically.

### Creating a new skill

1. Create the skill directory:
   ```
   mkdir -p ~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/skills/<name>/
   ```
2. Write the skill file at `<dir>/SKILL.md`
3. Add the skill to the `programs.opencode.skills` attribute set in `opencode.nix`:
   ```nix
   <name> = ./skills/<name>;
   ```
4. Add it to the skill routing section of `context.md` so Ciel remembers to load it
5. Sync jj, rebuild, restart

### Editing an existing skill

1. Edit the source at `~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/skills/<name>/SKILL.md`
2. Sync jj, rebuild, restart

### Adding a private resource to a skill (sops pattern)

If a skill needs sensitive data (API tokens, personal info, etc.), you can add a sops-encrypted private resource. This is not currently set up in Lucky's config, but the pattern exists in Misterio77's config and could be adapted:

1. Create the public skill content (SKILL.md + public resources) as usual
2. Encrypt the private content into a sops file (e.g., `private.yaml` at the opencode module root)
3. Add a sops secret reference in the Nix config for the host
4. Symlink it into the skill directory via `xdg.configFile`:
   ```nix
   xdg.configFile."opencode/skills/<name>/resources/private.md".source =
     "${config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.<name>-private.path}";
   ```
5. Reference `resources/private.md` from SKILL.md with a note to load on demand

This keeps the skill public while only the specific resource is encrypted.

## Agents (`~/.config/opencode/agents/<name>.md`)

Agent files are symlinked by home-manager from `~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/agents/<name>/`.

### Creating/Editing an agent

1. Create the agent directory and file:
   ```
   mkdir -p ~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/agents/<name>/
   ```
2. Write the agent file at `<dir>/<name>.md`
3. Add the agent to the `programs.opencode.agents` attribute set in `opencode.nix`:
   ```nix
   <name> = ./agents/<name>/<name>.md;
   ```
4. Sync jj, rebuild, restart

## Opencode config (`~/.config/opencode/opencode.json`)

The main settings don't live in a JSON file — they're generated from Nix at:
`~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/opencode.nix`
under `programs.opencode.settings`.

### Editing opencode settings

1. Edit `~/Projects/NixConfig/hosts/sora/home-manager/modules/opencode/opencode.nix`
2. Sync jj, rebuild, restart

## Build + Restart workflow

After any change to opencode files in NixConfig:

1. Sync jj state so the flake sees new commits:
   ```
   jj bookmark move master --to '@' && jj git export
   ```
2. Rebuild and apply:
   ```
   kitty --directory ~/Projects/NixConfig -e sh -c 'nh os switch ~/Projects/NixConfig || exec bash' &
   ```
3. Notify Lucky about what changed:
   ```
   ciel-notify prompt "<summary>"
   ```
4. Restart opencode server (last — after all other commands):
   ```
   ciel-restart-server &
   ```
