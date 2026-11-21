---
name: context-curation
description: Use when organizing, splitting, merging, deleting, or refactoring context.md and Pi skill files.
---

# Context & Skill Curation

AI guidance lives under `hosts/sora/home-manager/modules/AI/`:

- `shared/context.md` and `shared/operator.md` — portable identity, rules, and operator preferences.
- `pi/context.md` — Pi conventions and skill routing. Antigravity still receives this layer for compatibility.
- `shared/skills/<name>/SKILL.md` — domain guidance for all harnesses, with references kept alongside.

Use `read` before changing a file, `bash` for bounded search, and `edit` or
`write` for source changes. Load `pi-tools` before changing tool guidance.

## Routing rules

Keep identity, tone, and harness-independent rules in shared context. Put
Pi-specific tool and skill routing in `pi/context.md`.

Move content into a skill when it is domain-specific, reference-heavy,
self-contained, or only useful for one workflow. Merge skills when one is a
subset of another or both are routinely loaded together. Delete a skill when
its product/runtime no longer exists and no current workflow depends on it.

## Creating a skill

1. Create `SKILL.md` in the appropriate skill tree with valid `name` and `description` frontmatter.
2. Add scripts or references only when the workflow actually needs them.
3. Add a routing line in `pi/context.md` only if Ciel should load it proactively.
4. Run Pi/Nix validation; activate Home Manager only when authorized.

`pi/resources.nix` assembles Pi's installed skills; do not add per-skill
`home.file` entries. `antigravity/workflows.nix` owns the separate agy allowlist.

## Editing rules

- Read the full target and related files first.
- Keep domain skills focused; do not copy the full tool inventory into them.
- Replace removed harness/tool names with APIs currently listed by `pi-tools`.
- Never put secrets, decrypted private data, reports, or generated artifacts in NixConfig.
- Prefer deletion and small edits over compatibility prose for tools that no longer exist.
