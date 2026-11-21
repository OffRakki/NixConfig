---
name: council-mode
description: Run a bounded supervisor-mediated advisor council for material decisions with real tradeoffs. Use when asked to convene advisors, debate a design decision, or cross-examine competing recommendations.
---

# Council Mode

Council mode is parent-supervised advice for a material decision with real tradeoffs. It is not free-form agent chat, implementation work, or mutation authority.

The parent selects the roster, relays only curated claims, decides validity, and writes the final decision memo. Advisors stay read-only and do not see peer transcripts by default.

Before launching advisors, read [references/pass-contracts.md](references/pass-contracts.md).

{{councilDispatch}}

## Roster

- Choose 2–3 distinct read-only advisor perspectives (never more than 4).
- Prefer genuinely different models or orthogonal stances (e.g., correctness/reliability, simplicity/YAGNI, security/operations) over duplicate generic clones.
- Keep every advisor read-only and prevent advisors from spawning nested children.

## Passes

- **Pass 1**: Independent reports from each advisor using the Pass 1 contract.
- **Pass 2**: One bounded cross-examination relaying only disputed claims, conflicting evidence, missing proof, and owner decisions (attributed neutrally as "another advisor", never raw peer transcripts).
- **Pass 3**: Only when explicitly requested (`--max-passes 3`) and a material dispute can still be settled by concrete evidence. Never run an unbounded debate loop.

## Protocol

1. Draft the council brief: question, scope, non-goals, evidence targets, roster, and pass cap.
2. Launch Pass 1 advisors in parallel against the same evidence targets.
3. Synthesize the Pass 1 claim matrix in the parent: agreements, disputed claims, missing proof, owner decisions, and at most 5 material relay claims per advisor.
4. If material disputes remain, run Pass 2 with a concise challenge packet per advisor.
5. Write the final memo: clear recommendation, verified evidence, unresolved tradeoffs requiring Lucky's decision, and what evidence would change the recommendation.
