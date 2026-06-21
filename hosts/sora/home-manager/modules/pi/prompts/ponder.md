---
description: Reflect on this session and decide what deserves durable memory
argument-hint: "[focus_or_scope]"
---

# Ponder Session

Reflect on the current session before ending or moving on. Treat this as Ciel
walking the shelves of the Divine Library/Codex/Grimoire and deciding what, if
anything, deserves preservation.

Optional focus or scope: `${ARGUMENTS:-whole session}`.

## What to do

1. Review the conversation and tool work from this session.
2. Identify the key points:
   - decisions Lucky made or approved
   - durable preferences, corrections, or framing changes
   - project conventions or workflow changes
   - non-obvious tool quirks, failures, or gotchas
   - useful implementation details that future Ciel should not rediscover
   - open threads worth revisiting later
3. Decide where each item belongs:
   - **Hermes/Pi memory** for compact facts Ciel should recall automatically.
   - **Ciel Obsidian brain** for narrative context, session notes, decisions,
     pins, maps, project notes, tool notes, or future revisit ideas.
   - **Existing brain note update** when the information belongs with an
     already-known topic.
   - **No action** when the point is temporary, obvious, too small, or already
     captured well enough.
4. If saving or retrieving Obsidian notes, load and follow the `ciel-brain`
   skill. Use only `/home/rakki/sync/geral/Obsidian/Ciel/`.
5. Keep Ciel brain filenames/folders underscore-only, never spaces.
6. Update relevant indexes/links whenever creating or moving notes.
7. Prefer small focused notes over giant logs. Save full session exports only
   when exact transcript-level context will matter.
8. If a reusable workflow emerged, consider whether `skill_manage` is more
   appropriate than a normal note.
9. If nothing deserves saving, say so explicitly and explain why in one or two
   sentences.

## Output format

Report concisely:

- **Key points:** what mattered from the session.
- **Memory actions:** Hermes memories added/updated, or `none`.
- **Brain actions:** Obsidian notes created/updated, or `none`.
- **Existing notes touched:** paths, if any.
- **Deferred ideas/open threads:** what should be revisited later, if any.

Do not preserve noise just because the command was invoked. The goal is a useful
Divine Library, not a junk drawer with YAML frontmatter.
