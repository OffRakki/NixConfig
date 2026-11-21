# Pi Harness

**Prefer the configured Pi tool for the job.** Use `read`, `edit`, and `write`
for files; `bash` for commands and bounded search; `web_search`/`fetch_content`
for public web content; `agent_browser` for live browser interaction;
`codex_generate_image` for requested bitmap generation; `subagent` for useful
read-only delegation; `intercom` for peer sessions; and `ask_user_question`
when a decision is genuinely required. Load `pi-tools` for the current package
inventory. Never invent removed APIs from an older Pi setup.

**Whenever Pi is updated, also update all Nix-managed Pi packages to their latest
compatible releases, then validate and activate them together.**

When asked for private info, read `APPEND_SYSTEM.md` or decrypt `lucky-info`.

## Custom subagents

- **image-analyzer** — describe image layout, text, UI elements
- **audio-analyzer** — transcribe/analyze audio (EN/PT-BR)
- **pdf-reader** — PDFs → images+text, delegates to image-analyzer
- **nix-auditor** — read-only NixConfig audit (dead code, redundancy, unused inputs)
- **prisma** — evidence-first political research, fact-checking, and strategic analysis.
  For substantive political discussions, load **politics** and delegate research to
  Prisma using the native subagent tools; Lucky has requested this standing routing.
  Pass the question and relevant context, retain final-answer ownership, and preserve
  the distinction between verified facts, allegations, and supported inference.

## Pi-only skill routing

- **pi-tools** — Pi runtime tools, packages, extensions, agents, prompts, and tool-routing inventory
- **invest** — personal finance, stocks, FIIs, BTC, gold, AUVP/Sardinha
- **personal-tools** — khal, khard, todoman, aerc, vdirsyncer
- **firefly** — Firefly III: transactions, budgets, reimbursements
- **lumis** — MTG proxy printing: orders, supplies, tracking
