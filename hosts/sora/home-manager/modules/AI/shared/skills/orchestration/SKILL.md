---
name: orchestration
description: Coordinate multi-agent work with explicit topologies, non-overlapping file ownership, jj-safe workspace isolation, and evidence-first handoffs. Do not use for small linear tasks one agent can finish directly.
---

# Multi-Agent Orchestration

Use the smallest execution topology that completes the task reliably. Multi-agent dispatch still requires Lucky's authorization when spawning writers or long-running jobs.

{{dispatchAdapter}}

## Choose the topology

- **Single agent**: Narrow, linear work with one clear output — do not spawn subagents for ceremony.
- **Parallel read-only fanout**: Independent codebase exploration, multi-angle audits, or research lanes with zero shared writes.
- **Planner → Implementer → Reviewer crew**: Broad multi-file work where discovery and synthesis happen before any writer edits files.
- **Swarm / coordinated workers**: Dynamic membership or sharded work across disjoint file trees.

## Plan before spawning

1. Define the requested outcome, constraints, non-goals, and concrete acceptance evidence.
2. Split work into lanes with explicit, non-overlapping file ownership.
3. Mark each lane read-only or write-capable; never point two writers at the same files or working copy.
4. Give each worker a concrete return contract (changed files, exact commands run, pass/fail output, remaining risks).
5. Use the lowest sufficient reasoning effort / model tier for narrow exploration lanes.

## Isolation in Jujutsu repositories

- **Never use Git worktrees** in Jujutsu (`.jj/`) repositories.
- For isolated parallel writers, load the `jujutsu` skill and create one native Jujutsu workspace per writer (`jj workspace add <path-outside-repo> --name <unique> --revision <base>`) or use the harness's native isolated workspace mode when it supports jj.
- Keep one coordinator responsible for integrating completed worker changes (`@-`) and verifying conflicts, diffs, and builds.

## Verification

- Never claim completion from a worker's summary alone.
- Run the repository's real build, check, and test commands on the integrated state and report exact failures or unverified paths.
