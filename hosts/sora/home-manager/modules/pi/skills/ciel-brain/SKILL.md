---
name: ciel-brain
description: Use when saving or retrieving Ciel's long-term Obsidian brain notes,
  session summaries, chat pins, durable decisions, or organized narrative memory.
---

# Ciel Brain

Ciel's Obsidian brain lives at:

```text
/home/rakki/sync/geral/Obsidian/Ciel/
```

This is a standalone Obsidian vault folder beside `Main` and `Summaries`, not
inside either vault.

## Role

Use this vault for long-term, human-readable memory:

- session summaries and handoffs
- chat pins and memorable instructions
- project lore and architecture decisions
- tool quirks and workflows
- research notes and narrative context

Use Pi/Hermes memory for compact facts Ciel should recall automatically.
Obsidian is the deeper memory palace; Hermes is the reflex layer.

## Folder layout

- `Ciel Brain Index.md` — top-level map.
- `Session Notes/` — end-of-session summaries and handoffs.
- `Pins/` — durable chat pins, explicit instructions, key decisions.
- `Projects/` — project/domain-specific notes.
- `Tools/` — MCP, Pi, shell, editor, and workflow notes.
- `Assets/` — images and attachments that support notes.
- `Canvases/` — Obsidian canvas files for visual thinking.
- `Exports/` — PDFs, rendered previews, diagrams, and generated artifacts.

Create subfolders only when they reduce search/read cost.

## Naming rules

Use filenames that reveal the note's purpose without opening it.

Good:

- `2026-06-21 - NixConfig Pi Memory Setup.md`
- `Obsidian MCP Vault Boundaries.md`
- `Always Use Obsidian Ciel Brain.md`

Bad:

- `notes.md`
- `misc.md`
- `session.md`

## Link hygiene

Keep links useful for both Ciel and Lucky:

- Use Obsidian `[[Wiki Links]]` where they improve navigation.
- Update `Ciel Brain Index.md` and relevant category indexes when creating,
  moving, renaming, or deleting notes.
- Prefer MCP note move/rename tools when available so links stay intact.
- If moving files directly, search for old links and update them manually.
- Add short context around links so pages remain readable outside graph view.

## Artifacts

Ciel may use anything useful inside this brain: images, PDFs, canvases,
diagrams, exports, screenshots, and generated previews.

Rules:

- Store supporting files in `Assets/`, `Canvases/`, or `Exports/`.
- Use descriptive artifact names, same as Markdown notes.
- Add or update a Markdown note explaining why an artifact exists.
- Do not dump large artifacts without a small navigational note.

## Size rules

Avoid huge notes. Split by topic, project, tool, or session.

Preferred shapes:

- pins: 10-40 lines
- session summaries: concise, skimmable, one session/topic per file
- tool/project notes: focused on one recurring workflow or decision

Full chat logs are allowed only when exact transcript matters. Otherwise
summarize and link outward.

## End-of-session habit

Near the end of useful sessions, decide whether to save:

1. a session summary in `Session Notes/`
2. one or more pins in `Pins/`
3. project notes in `Projects/`
4. tool/workflow notes in `Tools/`
5. compact Hermes memory for facts that must be agent-native

Do not wait for Lucky to ask when the session produced durable knowledge.

## Retrieval workflow

1. Search filenames/folders first.
2. Read only the smallest likely note.
3. Prefer index notes for navigation.
4. If using MCP, prefer the standalone `Ciel` vault once registered.
5. If MCP cannot see the vault yet, use file tools directly at the path above.
