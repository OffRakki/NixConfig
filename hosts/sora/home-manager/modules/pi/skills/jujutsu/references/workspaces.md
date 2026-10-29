# Working Copy and Workspaces

## The Working Copy Is a Commit

In jj, the working copy is *always* committed to a real commit (`@`). At the start of (almost) every jj command, jj snapshots the current state of files in the working copy and updates `@` to match. At the end of (almost) every command, jj updates the working copy to match `@`.

Consequences:

- **No staging area**, no `git add`, no `git stash`. Edits are part of `@` immediately.
- **Added files are tracked by default.** New files appear in `@` once you run any jj command. Files matching `.gitignore` are ignored. (`snapshot.auto-track` controls which paths are auto-tracked; default is everything not ignored.)
- **Removed files are untracked automatically.** Delete a file from disk → it disappears from `@`.
- **Manual tracking**: if `snapshot.auto-track` is non-default, use `jj file track` to explicitly track a file. `jj file untrack` to stop tracking (but first ignore it, otherwise the next snapshot will re-track).

`.gitignore` files work as in Git, both at the repo root, in subdirectories, and via `$XDG_CONFIG_HOME/git/ignore` and `$GIT_DIR/info/exclude`. There is no `.jjignore`. Files that were already tracked stay tracked even if they later match an ignore pattern — `jj file untrack` to remove them.

## Conflicts in the Working Copy

When you check out a conflicted commit, jj writes the conflicts into the working copy as **conflict markers**. When you next run a jj command, jj re-parses the markers and reconstructs the conflict state. So you can resolve a conflict simply by editing the file to remove the markers — no special "mark resolved" command. See [conflicts](conflicts.md) for marker format.

## Workspaces — Multiple Working Copies, One Repo

A **workspace** is a working copy + an associated `.jj/` directory. A single repo can have many workspaces, each with its own `@`. This is jj's equivalent of `git worktree`.

Useful for: running long tests in one workspace while continuing to develop in another; one workspace per AI agent. Files and `@` are isolated, but history, bookmarks, and the operation log are shared: a rewrite or operation restore can affect other workspaces. Bookmarks are optional shared pointers, never workspace-local.

Follow the [canonical quickstart](../SKILL.md#native-workspaces-for-parallel-agents) for preflight and creation, or the [detailed workflow](workflow-new-workspace.md). Use an inspected explicit base, an unused absolute external path, and a unique name:

```bash
jj workspace add /tmp/project-worker-unique --name worker-unique --revision <base>
jj workspace list
jj workspace root
jj log -r 'worker-unique@ | worker-unique@-' --no-graph
jj log -r 'working_copies()'
```

The new workspace's `.jj/` is linked to the shared commit and operation storage. Each workspace has its own `@` referenced as `<name>@` in revsets. `--revision <base>` creates a new child of the base; omitting it uses the invoking `@`'s parent(s), not `@` itself. Repeat full preflight inside the new workspace before editing.

### Forgetting and re-adding

Before an approved `jj workspace forget <explicit-name>`, run `jj st` to snapshot and `jj diff` to inspect **inside the target workspace**. Record completed change/commit IDs (normally `@-` after closing with `jj new`) and separately preserve ignored/untracked artifacts. Forget removes the workspace from the repo's records but does **not** delete files. Never automatically delete its directory.

**Don't run `jj workspace forget` with no arguments** — that forgets the *current* workspace, including `default` if it is current.

### Workspaces in colocated repos

`jj workspace add` creates its own `.jj/` but no `.git/`. Native jj work needs no Git wiring or `.envrc`; use the [canonical quickstart](../SKILL.md#native-workspaces-for-parallel-agents), not nested `.worktrees` recipes. Tools requiring `.git/` need separate, explicitly approved integration; do not run raw Git as a workaround.

## Stale Working Copy

A jj command goes through three phases:

1. **Snapshot** the working copy (records an operation).
2. **Mutate** the in-memory state (records a new operation).
3. **Materialize** the new `@` to the working copy.

If step 3 doesn't happen — e.g. you `^C`'d the command, or another workspace rewrote `@` between snapshot and materialize — the working copy is **stale**: it points at an older operation than the repo's current head.

```bash
jj workspace update-stale
```

…re-syncs the working copy to the current `@`. If the operation that ran in step 3 has been *lost* (e.g. by `jj op abandon`), `update-stale` creates a recovery commit containing the working copy contents parented to the current `@`, so you don't lose anything.

A common cause: workspace A's `@` was rewritten by `jj edit` or `jj squash` in workspace B. Run `jj workspace update-stale` in A, then repeat full preflight and inspect divergence. The operation log is shared: `jj op restore` can affect every workspace, not just the caller.

## Colocated Repos

A repo where `.jj/` and `.git/` live side-by-side. Both jj and git tools can read it.

- **Use `jj` exclusively for VCS operations**, including inspection. Do not run raw Git even in colocated repos.
- Git interoperability does not authorize ref changes, pushing, or recovery outside the skill's approval gates.
- If views appear out of sync, inspect with native jj commands and integrated help before any approved mutation; do not automatically import/export refs.

## Tracked vs Auto-tracked

The `snapshot.auto-track` config option (a fileset expression) controls which *new* paths are tracked automatically. Default is "everything not ignored." For example, to disable auto-tracking entirely:

```toml
# ~/.config/jj/config.toml
[snapshot]
auto-track = "none()"
```

Then you must `jj file track <path>` to start tracking a file.
