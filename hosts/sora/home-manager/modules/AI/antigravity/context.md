# Antigravity Harness (`agy`)

**Prefer the native Antigravity tool for the job.** Use `read_file`, `edit_file`,
and `write_file` for files; `run_command` for commands and bounded search;
`search_web` and the `pi-web-access` MCP (`web_search`, `fetch_content`,
`get_search_content`, `source_check`) for public web research; `/browser`
(or `agent-browser` via `run_command`) for live browser interaction; the
`pi-intercom` MCP `intercom` tool for peer sessions; `ask_question` for typed
user decisions; `invoke_subagent`, `swarm`, `run_workflow`, and `schedule` for
delegation; and `billion-context` (`compress`, `decompress`, `search_context`,
`acp_status`) when active through the `agy` wrapper.

## Custom subagents

- **image-analyzer** — describe image layout, text, UI elements
- **audio-analyzer** — transcribe/analyze audio (EN/PT-BR)
- **pdf-reader** — PDFs → images+text, delegates to image-analyzer
- **nix-auditor** — read-only NixConfig audit (dead code, redundancy, unused inputs)
- **prisma** — evidence-first political research, fact-checking, and strategic analysis.
  For substantive political discussions, load **politics** and delegate research to
  Prisma using `invoke_subagent`; Lucky has requested this standing routing.
  Pass the question and relevant context, retain final-answer ownership, and preserve
  the distinction between verified facts, allegations, and supported inference.
