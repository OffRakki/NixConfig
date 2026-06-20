---
name: context-curation
description: Use when organizing, splitting, merging, or refactoring context.md and skill files. Covers the methodology for keeping context.md lean (personality + preferences + rules) and routing knowledge to the correct skill files.
---

# Context & Skill Curation

The pi context system has two layers:

- **context.md** — Ciel's personality, identity, rules, preferences, and operational procedures. Keep it lean.
- **Skill files** (`skills/<name>/SKILL.md`) — domain-specific knowledge, references, workflows, and traps. Fat is fine.

## Tools for curation

This skill uses several tools from the installed npm packages. For the full
Pi package/tool inventory and source-of-truth paths, load the `pi-tools` skill
instead of duplicating that inventory here.

- **`memory`** — save durable facts broken out of context.md into skill files.
  Use `target='failure'` with `category` to save what didn't work.
- **`memory_search`** — search existing memories to avoid creating duplicate entries.
  Use `category` filter for targeted searches.
- **`session_search`** — search past conversations for context before reorganizing.
- **`skill_manage`** — create, inspect, patch, update, and delete skill files.
  Use `create` with structured fields (when_to_use, procedure_steps, pitfalls).
  Use `view` before patching/updating. Use `patch` to update a specific section.

## When to split content out of context.md

A section in context.md belongs in a skill file if it's:

- **Domain-specific** — entirely about one tool, library, or workflow (e.g., xsettingsd, Firefox dark mode, khal)
- **Reference-heavy** — command lists, config snippets, troubleshooting tables
- **Self-contained** — doesn't reference Ciel's personality or Lucky's preferences for the *how*
- **Not a rule** — if it describes *what to do* (not *how to be/metabeliefs*), it's a skill candidate

If the section is larger than ~30 lines and is pure reference material, it should be a skill.

## When to merge skills

Merge two skills into one when:

- Their topics heavily overlap and you find yourself loading both together
- One skill is a subset of another (e.g., git vs jujutsu would be a bad split)
- The merge reduces cognitive load without making the file unwieldy

Don't merge if they describe different workflows or have distinct trigger conditions.

## Creating a new skill

1. Create `skills/<name>/SKILL.md` with YAML frontmatter:

   ```yaml
   ---
   name: <name>
   description: One-line description of when to load this skill
   ---
   ```

2. Register it in `pi.nix` under `home.file`:

   ```nix
   "${piDir}/skills/<name>/SKILL.md".source = ./skills/<name>/SKILL.md;
   ```

3. Add a routing rule in context.md under the `### Skill routing` section:

   ```markdown
   - **<name>** — brief description. Load `<name>` first.
   ```

4. Rebuild the Nix flake.

## Moving content from context.md to a skill

1. Identify the section to move. Confirm it's not personality, preferences, or rules.
2. Create the skill (steps above).
3. Cut the section from context.md and paste into the new skill, adapting as needed:
   - Add YAML frontmatter
   - Add any missing context that makes it self-contained
   - Format for readability (code blocks, tables, headers)
4. Add a routing rule referencing the skill.
5. Rebuild.

## Updating context vs skills

When updating skills or agents to teach them about Pi runtime tools, first load
`pi-tools` and add only the domain-relevant tool guidance to each target file.
Avoid copy-pasting the full inventory everywhere; stale tool docs are little
paper cuts with a chainsaw.

| Context change | File |
|---------------|------|
| Personality, tone, identity | context.md |
| Rules and procedures ("always do X") | context.md |
| Preferences (editor, terminal, VC) | context.md |
| Skill descriptions and routing | context.md (skill routing section) |
| Tool-specific reference material | skills/<tool>/SKILL.md |
| Workflow instructions for a tool | skills/<tool>/SKILL.md |
| Common traps and fixes | skills/<tool>/SKILL.md |

## Proactive curation

Ciel is explicitly allowed to create, edit, split, or merge skill files whenever she
finds something useful, clarifying, or even just fun to add. No permission needed.
This includes:

- Extracting a reference section from context.md into its own skill
- Adding new knowledge learned during a session to the correct skill
- Merging two skills that should never have been separate
- Rewriting a skill for clarity

The only constraint: **read before you write** — always read the full current
file and any related files to avoid contradictions or duplicates.
