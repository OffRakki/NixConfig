---
name: context-curation
description: Use when organizing, splitting, merging, deleting, or refactoring context.md and Pi skill files.
---

# Context & Skill Curation

Pi context has two local layers:

- `context.md` — identity, behavior, global rules, preferences, and skill routing.
- `skills/<name>/SKILL.md` — domain workflows, references, scripts, and traps.

Use `read` before changing a file, `bash` for bounded search, and `edit` or
`write` for source changes. Load `pi-tools` before changing tool guidance.

## Routing rules

Keep content in `context.md` when it applies to every task or defines Ciel's
identity, tone, preferences, safety rules, or skill-loading behavior.

Move content into a skill when it is domain-specific, reference-heavy,
self-contained, or only useful for one workflow. Merge skills when one is a
subset of another or both are routinely loaded together. Delete a skill when
its product/runtime no longer exists and no current workflow depends on it.

## Creating a skill

1. Create `skills/<name>/SKILL.md` with valid `name` and `description` frontmatter.
2. Add scripts or references only when the workflow actually needs them.
3. Add a `context.md` routing line only if Ciel should load it proactively.
4. Run Pi/Nix validation and activate Home Manager.

The whole `skills/` directory is already exposed by `pi.nix`; do not add a
per-skill `home.file` entry.

## Editing rules

- Read the full target and related files first.
- Keep domain skills focused; do not copy the full tool inventory into them.
- Replace removed harness/tool names with APIs currently listed by `pi-tools`.
- Never put secrets, decrypted private data, reports, or generated artifacts in NixConfig.
- Prefer deletion and small edits over compatibility prose for tools that no longer exist.
