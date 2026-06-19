---
name: jujutsu
description: "REQUIRED for any VCS operation in jj repositories (`.jj/` directory present). Activate on: commit, push, pull, status, diff, log, branch/bookmark, PR, merge, rebase, stash, conflict, undo, or any version-control task. In jj repos, use jj exclusively — running git commands can corrupt or confuse state."
---

# jj Guide for AI Agents

Jujutsu (jj) is a Git-compatible VCS with mutable commits, automatic snapshotting, no staging area, and first-class conflicts. This skill teaches you how to use it safely from a non-interactive agent environment.

If `.jj/` exists in the repo root, this is a jj repo. **Use `jj` commands, not `git`.** In a colocated repo (`.jj/` *and* `.git/`), git tools can read the state, but mutations should go through `jj` so the operation log stays consistent.

**Use `ctx_shell` for all jj commands** — the output goes through lean-ctx compression, saving significant tokens on verbose `jj log` output, diff listings, and status checks. Prefer `ctx_shell` over `bash` for VCS operations.

## Critical Rules

- **ALWAYS load this skill** when working in a jj repo. Every VCS operation should consult this guide first. This is non-negotiable.
- **NEVER** use interactive flags (`-i`, `--interactive`). TUI prompts hang in agent environments. This applies to `jj split -i`, `jj squash -i`, `jj commit -i`, `jj resolve`, `jj diffedit`, etc.
- **ALWAYS** pass `-m "msg"` when describing/committing. Without `-m`, an editor opens and hangs.
- **Editor trap:** `jj squash` (and other commands that combine descriptions) opens an editor when **both** source and destination have non-empty descriptions. In non-interactive environments, `hx`/Helix panics with "reader source not set". **Always clear the destination's description first** with `jj describe -m ""` before squashing, so jj uses the source's description automatically. If `jj describe --stdin -r <rev>` is available, pipe multiline descriptions via stdin to avoid shell quoting issues.
- **Step-by-step over batch:** When collapsing a chain of commits, **never** squash a range at once (`jj squash --from 'range'`). Do it one commit at a time: `jj edit <commit>`, `jj describe -m ""`, `jj squash`, repeat. This is safer and easier to undo if something goes wrong.
- **`jj undo` first, ask questions later.** If an operation produces unexpected output — especially editor panics or "sideways" history — `jj undo` immediately. Don't try to fix forward.
- **VERIFY** mutations with `jj st` and `jj log` after `squash`, `abandon`, `rebase`, `restore`, `commit`. jj will silently do exactly what you asked, even if it wasn't what you meant.
- **PREFER change IDs** (letters, e.g. `nmwwolux`) over commit IDs (hex). Change IDs are stable across rewrites.
- **NEVER** rebase or describe an immutable commit (e.g. `main` if it's tracking a remote). Target the commit *above* it, or use `main@origin` as `--destination`.
- If you get stuck, `jj undo` reverses the last operation. `jj op log` shows everything; `jj op restore <op-id>` rewinds the whole repo.

## Mental Model

- **The working copy is a commit (`@`).** File edits auto-amend `@` on every `jj` command — there is no staging area, no `git add`, no stashing.
- **Commits are mutable** until pushed. You build commits by editing the working copy and refining with `squash`/`absorb`/`describe`/`restore`.
- **Change ID vs commit ID.** A change has a stable change ID (k-z letters). Each rewrite produces a new commit ID (hex) but the change ID is preserved.
- **Bookmarks ≈ git branches**, but they do **not** auto-advance when you make new commits. You move them yourself with `jj bookmark set` or `jj bookmark move`.
- **Conflicts live in commits.** Operations never fail on merge conflict; the conflict is recorded in the resulting commit and you resolve it later by editing files.
- **Operation log replaces reflog.** Every state change is an operation. `jj undo` / `jj op restore` make almost any mistake recoverable.

## Two Workflow Styles

There are two equivalent ways to make commits. Pick one and be consistent within a session.

### Style A — `jj commit` (closest to git)

```bash
# Make edits in @ (auto-tracked)
echo "..." > file.rs
jj st                       # verify tracked changes
jj commit -m "feat: ..."    # finalize @ as a real commit; new empty @ is created
```

After `jj commit`, the *content* lives in `@-` (the parent) and `@` is a new empty change. Bookmarks and pushes target `@-`.

### Style B — describe-first (recommended for refining)

```bash
jj st                       # if @ already has content, run `jj new` first
jj describe -m "feat: ..."  # set message before coding
# ... edit files; they auto-amend into @ ...
jj st                       # review
# Leave @ as-is. The next task starts with `jj new`.
```

Style B keeps the message in the same change you're editing, which is convenient for `jj squash`/`jj absorb` refinement. **Don't run `jj new` at the end** — leave that for the start of the next task.

## Common Workflows

### Inspect

```bash
jj st                # status
jj log               # graph of recent changes
jj log -r '::@ & ~::main@origin'   # just YOUR commits not in main
jj diff              # diff of @
jj show <change-id>  # description + diff for a commit
```

### Refine the current change

```bash
jj describe -m "better message"   # rewrite message only
jj squash                         # fold @ into its parent (amend equivalent)
jj squash --from <A> --into <B>   # move all of A into B
jj absorb                         # auto-route hunks of @ to ancestors that last touched those lines
jj restore path/to/file           # discard changes to a file (restore from parent)
jj restore --from <change-id> path/to/file   # take file from another commit
jj abandon <change-id>            # delete a commit; descendants reparent
```

### Split a change non-interactively

`jj split -i` is interactive — don't use it. Instead:

```bash
jj split file1.rs file2.rs           # named files become first commit; rest stays in @
jj split 'glob:tests/**'             # by fileset pattern
```

### Bookmarks (branches)

```bash
jj bookmark list
jj bookmark create my-feature -r @       # tracks the change ID; survives rewrites of that change
jj bookmark set my-feature -r @-         # move an existing bookmark (e.g. after `jj commit`)
jj bookmark delete my-feature
```

### Push and pull

```bash
jj git fetch                              # fetch all remotes
jj git push -b my-feature                 # push a specific bookmark
jj git push                               # push all tracked bookmarks (auto force-push on rewrites)

# Sync main, fast-forward
jj git fetch
jj bookmark set main -r main@origin

# Sync main and rebase your work onto it
jj git fetch
jj rebase -d main@origin                  # rebase YOUR commits (not main) onto remote main
```

### Address PR review

Rewrite (clean history):

```bash
jj edit <change-id>          # working copy becomes that commit
# ... fix ...
jj new                       # leave the commit
jj git push                  # auto force-pushes the rewritten bookmark
```

Additive (preserve review history):

```bash
jj new <bookmark>            # new commit on top of bookmark tip
# ... fix ...
jj commit -m "address review"
jj bookmark set <bookmark> -r @-
jj git push -b <bookmark>
```

### Conflicts

jj never fails on conflict. After a `rebase`/`new`/`squash`, run `jj st` — conflicted files are listed. Open them and resolve by hand: jj's markers look like Git's but with extra sections (`%%%%%%% diff from:` / `+++++++` / `>>>>>>>`). See `references/conflicts.md` for the marker format. Do **not** use `jj resolve` (interactive). After editing, `jj st` will show the conflict cleared automatically.

### Recovery

```bash
jj undo                      # reverse last operation
jj op log                    # full operation history
jj op restore <op-id>        # rewind the whole repo to that point
jj workspace update-stale    # fix "working copy is stale" errors
```

## Git → jj Quick Reference

Full mapping (including grep, bisect, fileset patterns, file restoration): `references/git-to-jj.md`.
Load on demand — do not preload.

Common translations:

| Task | git | jj |
|---|---|---|
| Status | `git status` | `jj st` |
| Diff | `git diff` | `jj diff` |
| Stage + commit | `git add . && git commit -m "msg"` | `jj commit -m "msg"` |
| Amend message | `git commit --amend -m "msg"` | `jj describe -m "msg"` |
| Amend content | `git commit --amend --no-edit` | `jj squash` |
| Push bookmark | `git push origin <branch>` | `jj git push -b <bookmark>` |
| Fetch | `git fetch` | `jj git fetch` |
| Pull (rebase) | `git pull --rebase` | `jj git fetch && jj rebase -d main@origin` |
| Switch branch | `git checkout <branch>` | `jj new <rev>` |
| Undo last op | (varies) | `jj undo` |

## Revset Quick Reference

Full revset language reference: `references/revsets.md`. Load on demand.

Key expressions:

| Expression | Meaning |
|---|---|
| `@` | working copy commit |
| `@-` | parent of @ |
| `mine()` | commits authored by current user |
| `empty()` | commits with no diff |
| `conflicts()` | commits with unresolved conflicts |
| `::x` | ancestors of `x` |
| `x..y` | set difference (y minus x) |
| `x::y` | DAG range (commits between x and y) — NOT interchangeable with `..` |

## Common Pitfalls

1. **Bookmarks don't auto-advance.** After `jj commit`, you must `jj bookmark set <name> -r @-`. (`jj bookmark create <name> -r @` before working *also* works because it tracks the change ID, which follows the commit.)
2. **`@` after `jj commit` is empty.** Don't push `@`; the content is in `@-`.
3. **`jj new` ≠ `git commit`.** `jj new` creates a new empty change on top. `jj commit` finalizes `@` as a real commit and creates a new empty `@`.
4. **`::` vs `..`.** `::` is a DAG range (all ancestors of). `..` is set difference. They are *not* interchangeable.
5. **Empty commits are normal.** They mean "ready to work here."
6. **`Commit is immutable` error** — you targeted a tracked bookmark like `main` directly. Target the commit above it, or use `main@origin` as the destination.
7. **Bookmark may not exist.** `jj bookmark move <name>` fails with "No matching bookmarks" if the bookmark doesn't exist locally. Check first with `jj bookmark list`. If deleted locally but exists on remote (`deleted` + `@origin`), recreate it: `jj bookmark set <name> -r <name>@origin`.
8. **Stale working copy** — usually caused by another workspace rewriting the working-copy commit. Run `jj workspace update-stale`.
9. **Don't run `git checkout`/`git commit`/`git reset` in a colocated repo.** Use jj for mutations; use git only for read-only operations or things jj doesn't have (e.g. `git submodule`).
10. **Rebase can orphan commits.** `jj rebase -r <rev> -d <dest>` detaches `<rev>` from its old parent chain and reattaches it to `<dest>`. The intermediate parent chain (commits between old parent and old grandparent) is **left behind as an orphan** — they become disconnected from the main DAG. **Always verify after rebase:**
    - `jj log -r '::<rebased-rev>'` — chain should connect down to trunk
    - `jj log -r 'orphan()'` — shows commits with no lineage to any bookmark/remote
    - Recovery: `jj rebase -r <orphan> -d <new-dest>` reattaches it
11. **`jj abandon` of a middle commit places `@` unpredictably.** After abandoning a non-tip commit, jj may place `@` on a sibling instead of the chain tip. Always check `jj st` after `jj abandon`, then use `jj new -r <correct-tip>` explicitly. If a fork appears (two children of same parent), abandon the wrong one and `jj new -r <correct-tip>`.
12. **Bookmark drift: moving `master` to an empty `@` hides real changes.** If `@` is a fresh working copy (diff = empty) and you run `jj bookmark move master --to @`, the bookmark now points to an empty commit. The real changes are in `@-`. Fix with `jj bookmark set master -r <change-id> --allow-backwards` to point it back to the commit with content.

## Progressive Disclosure — When to Read More

Load these references on demand (don't preload):

**Language & commands**

- `references/git-to-jj.md` — full Git ⇄ jj command mapping including history rewriting, stashing, worktrees, fileset patterns
- `references/revsets.md` — complete revset language: operators, functions, string/date patterns, examples
- `references/glossary.md` — formal definitions (change, view, head, divergent, hidden, root commit, etc.)

**Topic deep-dives**

- `references/bookmarks.md` — bookmark tracking, remotes, conflicted bookmarks, multiple-remote workflows (fork vs integrator)
- `references/conflicts.md` — first-class conflicts, marker formats (jj / snapshot / git styles), long markers, missing-newline conflicts
- `references/operation-log.md` — `jj op log`, `--at-op`, recovering files from past snapshots (the "snapshot scan" trick)
- `references/workspaces.md` — multiple working copies, stale working copy recovery, colocated repos, ignored files

**Action playbooks** — read when starting one of these tasks

- `references/workflow-commit-push-pr.md` — exact step-by-step for: commit → push → open PR (with `gh`)
- `references/workflow-new-workspace.md` — create an isolated workspace + bookmark for parallel work
- `references/troubleshooting.md` — diagnostic protocol, problem→fix table, rebase matrix, op-log forensics. Use this whenever something has gone sideways.
