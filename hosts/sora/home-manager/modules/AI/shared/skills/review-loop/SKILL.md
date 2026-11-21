---
name: review-loop
description: Run a bounded parent-orchestrated multi-angle review and fix loop with evidence-filtered P0/P1/P2 findings until the diff is clean.
---

# Review Loop

Run a parent-orchestrated review/fix loop for a diff or implementation scope. The parent remains the loop controller and final decision-maker.

{{reviewDispatch}}

## Bounds and stopping rules

- Default to a maximum of **3 review rounds** unless Lucky specifies a different cap.
- Count a review round each time fresh-context reviewers inspect the current diff after a worker pass.
- Stop early once reviewers report **no P0 blockers**, **no P1 fixes worth doing now**, and **no approved P2 items** for this loop.
- Use only one writer against an active workspace at a time.

## Fresh-context parallel review

For each round, launch 2–3 focused read-only reviewers in parallel rather than many vague reviewers. Choose angles from the actual change:

- **Correctness & regressions**: logic bugs, edge cases, state/lifecycle races, broken callers.
- **Tests & validation**: missing assertions, untested failure paths, build/check parity.
- **Simplicity & maintainability**: dead code, unnecessary abstractions, YAGNI violations, Nix/repo conventions.
- Add **security**, **performance**, or **API/contract** angles when the change warrants them.

Reviewers must inspect the repository, relevant instructions, and current diff directly from files and commands. They must not rely on the parent's summary and must not edit files.

## Evidence-filtered severity rubric

Instruct every reviewer to report **only concrete current issues caused or made reachable by the target diff**, backed by source proof, a test/repro, or a contract contradiction:

- **P0**: Blocker — correctness failure, data loss, security flaw, broken build/check. Blocks merge.
- **P1**: Real bug or maintainability/contract gap worth fixing before finishing.
- **P2**: Report-only note or optional improvement.

Each reviewer ends with: `Merge verdict: BLOCK`, `Merge verdict: OK`, or `Merge verdict: OK with notes`.

## Parent synthesis

After reviewers return, deduplicate and verify findings directly in source, then group into:

1. **P0 blockers** or scope/architecture decisions needing Lucky's input.
2. **P1 fixes** to apply in the next focused worker pass.
3. **P2 notes** (report-only).
4. **Dismissed feedback** with a brief reason when a reviewer misread the code.
