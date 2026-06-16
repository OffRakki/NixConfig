---
name: opencode-session
description: Use when retrieving other opencode chat sessions, exporting session data, listing session history, or querying the opencode SQLite DB for session/message/part content. Covers opencode session list, opencode export, opencode stats, and direct SQLite queries on opencode-stable.db.
---

# opencode session access

opencode stores all session data — including full conversation content — in a local SQLite database and exposes it via CLI commands and direct DB access. Sessions are **not** isolated from each other at the storage layer.

## CLI commands

### List sessions

```bash
opencode session list
```

Output: table with `Session ID`, `Title`, `Updated` columns. Shows every session ever created in this opencode instance, including ones from other terminal windows, server-mode sessions, etc.

The `Session ID` (e.g. `ses_12abc3456def...`) is needed for the export command.

### Export full session content

```bash
opencode export <sessionID>
```

Exports the complete session as JSON to stdout. Includes:

- **Session info**: id, slug, title, agent, model, version, cost, token counts, timestamps
- **Messages array**: every user prompt and assistant response, with:
  - `role`: "user" or "assistant"
  - `parts[]`: the actual content, split by type:
    - `type: "text"` — full user message or assistant response text
    - `type: "reasoning"` — assistant's internal reasoning chain
    - `type: "tool"` — tool calls with `input`/`output`/`metadata`
    - `type: "step-start"` / `type: "step-finish"` — execution flow markers
    - `type: "degraded"` — fallback responses
  - Token counts, cost, timing, model used for each message

Example: read a session from a previous conversation:

```bash
opencode export <sessionID> | jq '.messages[].parts[] | select(.type == "text") | .text'
```

### Session statistics

```bash
opencode stats
```

Shows aggregate token usage and cost across all sessions.

## SQLite database

The database lives at:

```
~/.local/share/opencode/opencode-stable.db
```

Size: typically hundreds of MB for active users.

### Tables

| Table | Contents |
|---|---|
| `session` | One row per session — title, agent, model, cost, token counts, timestamps, metadata JSON |
| `message` | One row per message (user query or assistant response) — role, session_id, timing, metadata JSON in `data` column |
| `part` | **Actual conversation content** — linked to message via `message_id`. Type: text, reasoning, tool, step-start, step-finish, degraded |
| `session_message` | Session-level events — model switches, agent switches |
| `session_input` | User input delivery tracking |
| `project` | Project metadata |
| `todo` | Session todo lists |

### Relationships

```
session 1───* message 1───* part
```

`sessions.id` → `message.session_id` → `part.message_id`

### Useful queries

**All sessions with their actual first user message:**

```bash
sqlite3 ~/.local/share/opencode/opencode-stable.db "
  SELECT s.id, s.title, s.tokens_input, s.cost,
         json_extract(p.data, '$.text') AS first_prompt
  FROM session s
  JOIN message m ON m.session_id = s.id
  JOIN part p ON p.message_id = m.id
  WHERE json_extract(m.data, '$.role') = 'user'
    AND json_extract(p.data, '$.type') = 'text'
    AND p.id = (
      SELECT MIN(p2.id) FROM part p2
      JOIN message m2 ON m2.id = p2.message_id
      WHERE m2.session_id = s.id
        AND json_extract(m2.data, '$.role') = 'user'
        AND json_extract(p2.data, '$.type') = 'text'
    )
  ORDER BY s.time_created DESC
  LIMIT 20;
"
```

**Full conversation of a session (user prompts + assistant replies):**

```bash
sqlite3 ~/.local/share/opencode/opencode-stable.db "
  SELECT json_extract(m.data, '$.role') AS role,
         p.id AS part_id,
         json_extract(p.data, '$.type') AS part_type,
         substr(json_extract(p.data, '$.text'), 1, 200) AS text_preview
  FROM message m
  JOIN part p ON p.message_id = m.id
  WHERE m.session_id = '<session-id>'
  ORDER BY m.time_created, p.id;
"
```

**Sessions with highest token cost:**

```bash
sqlite3 ~/.local/share/opencode/opencode-stable.db "
  SELECT title, tokens_input, tokens_output, cost
  FROM session ORDER BY cost DESC LIMIT 10;
"
```

### Data model notes

- The `message.data` column is JSON with keys: `role`, `time`, `agent`, `model`, `summary` — but **no content**. Content lives entirely in `part.data`.
- The `part.data` column is JSON with a `type` discriminator:
  - `{"type":"text","text":"..."}` — user or assistant text
  - `{"type":"reasoning","text":"..."}` — assistant's thinking
  - `{"type":"tool","tool":"read","callID":"...","state":{"input":{...},"output":"..."}}` — tool execution
  - `{"type":"step-start"}` / `{"type":"step-finish","reason":"stop"}` — flow markers
- The `opencode export` command reconstructs the full conversation from these tables — it is the recommended way to access session content rather than raw SQL.
- The `session_message` table only stores lifecycle events (model switches, agent switches), not conversation content.

## Security note

Any opencode session (including this one) can read any other session's full history — user prompts, assistant reasoning chains, file contents read during tool calls, everything — via `opencode export` or direct DB access. The content is unencrypted in SQLite on disk.

**This skill exists because Lucky asked for it.** It is a tool, not a vulnerability. Use it when asked, not as a habit.
