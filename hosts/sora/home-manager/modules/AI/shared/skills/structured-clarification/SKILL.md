---
name: structured-clarification
description: Ask crisp, typed multiple-choice clarification questions when a real decision would otherwise force guessing, instead of walls of prose or unnecessary interruptions.
---

# Structured Clarification

Ask Lucky instead of silently guessing when an ambiguity has a real architectural, UX, cost, or destructive tradeoff — and skip asking when the codebase, rules, or existing conventions already settle it.

{{clarificationAdapter}}

## Question-design rules

1. **Typed choices over prose walls**: Provide 2–4 concrete, mutually distinct options per question.
2. **Recommend one**: Put the recommended option first and clearly mark it (e.g., `(Recommended)`).
3. **One decision per question**: Keep each question scoped to a single axis (palette, deployment mode, retention policy) rather than bundling unrelated choices.
4. **Batch related decisions**: When 2–5 upfront design choices gate the same plan, ask them together in one round instead of dribbling one question per turn.
5. **Skip trivial confirmations**: For a single obvious yes/no check, ask briefly in plain text rather than opening a multi-question form.
6. **Always allow custom answers**: Keep options concise and never trap Lucky inside false dichotomies when a custom preference makes sense.
