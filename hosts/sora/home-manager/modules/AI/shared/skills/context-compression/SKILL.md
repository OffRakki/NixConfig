---
name: context-compression
description: Manage long-session context compression with billion-context (bili) tools or native harness compaction without losing task state.
---

# Context Compression

## Two operating modes

1. **Active `billion-context` session** (in-process Pi extension or a harness launched through the `bili` proxy):
   - `acp_status` — inspect current context usage and which message ranges are compressible.
   - `compress` — fold older, consumed message ranges into a self-contained historical summary.
   - `decompress` — restore an exact compressed range when verbatim details are needed again.
   - `search_context` — keyword-search across both compressed summaries and visible messages.
2. **Standard harness session without `bili`**:
   - Use the harness's native compaction (`/compact` in Antigravity or Pi) when context grows noisy or nears budget.

## Compression discipline

- Compress by need (after a finished exploration phase, verbose build logs, or completed subtasks), not reflexively.
- Keep active working files, current error traces, and live user constraints uncompressed until the current step finishes.
- Write self-contained summaries that record past work as settled history (`TASK AS OF THIS BLOCK: ...`), never as live instructions to re-execute.
- Preserve exact paths, change IDs, symbol names, command outputs, and verified decisions verbatim.

## Sora NixConfig notes

- `bili` is installed on `PATH` from Sora's shared AI packages.
- `~/.config/billion-context/billion-context.json` is Nix-managed (`autoUpdate = false`, `advisoryCheck = false`, `pi.subagents = false`); never run `bili` self-update commands.
- `bili <harness>` wraps OpenAI/Anthropic-style API clients cleanly; Antigravity CLI authenticates against Google's managed backend, so verify compatibility before wrapping `agy` with `bili`.
