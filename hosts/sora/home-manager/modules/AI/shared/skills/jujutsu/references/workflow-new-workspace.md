# Workflow: Start Work in an Isolated Workspace

Use one native jj workspace per worker for parallel development or tests. Files and `@` are isolated; history, bookmarks, and the operation log are shared. Start with the [canonical protocol](../SKILL.md#native-workspaces-for-parallel-agents); this walkthrough expands it without adding Git wiring or push requirements.

## 1. Inspect and select the base

Run the full required preflight in the invoking workspace:

```bash
jj root
jj st
jj log -r '@ | @-' --no-graph
jj diff
jj workspace list
jj show <base-change-id>
jj log -r '<base-change-id> | ancestors(<base-change-id>, 3)'
```

Choose an inspected, unambiguous stable base change ID that includes exactly the intended prerequisites. Preserve unrelated existing work; do not assume `main` or another worker's bookmark is the right base.

## 2. Create at an unused external path

Pick a unique workspace name and an unused absolute path **outside** the source tree. Check both `jj workspace list` and the filesystem first; do not reuse or overwrite a directory.

```bash
# Replace placeholders after inspection; this example path must be unused.
test ! -e /tmp/project-worker-unique && test ! -L /tmp/project-worker-unique
# Proceed only if both tests succeeded and the workspace name is unused.
jj workspace add /tmp/project-worker-unique \
  --name worker-unique --revision <base-change-id>
cd /tmp/project-worker-unique
```

`--revision <base-change-id>` creates a **new child** of that base, as with `jj new <base-change-id>`; it does not check out the base itself. Without `--revision`, the new child uses the invoking `@`'s parent(s), not the invoking `@`. No `.envrc`, Git worktree, or `.git/` wiring is required for native jj work.

## 3. Repeat preflight inside the worker workspace

The coordinator's inspection does not replace the worker's own preflight:

```bash
jj root
jj st
jj log -r '@ | @-' --no-graph
jj diff
# Only after classifying @ as safe for this task:
jj describe -m "Added <task scope>"
jj st
jj log -r '@ | @-' --no-graph
jj diff
```

Give the worker its exact path, workspace name, base, scope, and no-integration boundary. All worker edits and commands stay in that workspace. Bookmarks are optional shared pointers, **not workspace-local**; do not create or move them without an actual need and approval. No mandatory `main`, push, or PR step is implied.

## 4. Work, check, and hand off the completed change

Use the [blessed describe/check/new workflow](../SKILL.md#blessed-coding-workflow-describe-first-close-with-new): edit, check, review the full diff, refine the description with `-m`, verify, then `jj new`. Verify the new `@` is empty and undescribed.

```bash
jj st
jj log -r '@ | @-' --no-graph
jj show @-
jj log -r @- --no-graph -T 'change_id ++ " " ++ commit_id ++ "\n"'
```

Hand off the completed **`@-` stable change ID**, commit ID, exact changed files, check results, and recovery workspace path. The worker's empty `@` is not the deliverable. Leave the workspace available for review unless cleanup is explicitly approved.

## 5. Coordinator-only review and approved integration

Inspect from the coordinator workspace without switching the worker's `@`:

```bash
jj workspace list
jj log -r 'working_copies()'
jj log -r 'worker-unique@ | worker-unique@-' --no-graph
jj show <completed-change-id>
```

Only the coordinator integrates after approval specifies the operation and exact source/destination change IDs. Follow the [safe mutation pattern](../SKILL.md#safe-mutation-pattern): inspect both changes' full diffs, graph relationships, mutability, bookmarks, and conflicts; state the exact move, use explicit revisions and non-interactive flags, then verify again. Do not incidentally rewrite another worker's `@` or move shared bookmarks. This workflow grants no push or ref-change permission.

## 6. Retain safely before explicit cleanup

Before approved cleanup, run `jj st` and `jj diff` **inside the target workspace** to snapshot and inspect it. Preserve completed change/commit IDs and separately save any ignored/untracked artifacts; snapshots do not guarantee those artifacts are recorded. Confirm integration or a deliberate retention plan before forgetting.

Then, from a retained coordinator workspace, use the exact approved name:

```bash
jj workspace forget worker-unique
jj workspace list
```

Forget removes the workspace record but **keeps the files**. Never automatically delete the directory. Bare `jj workspace forget` targets the **current** workspace, including `default` if current; always supply the intended name.

## Troubleshooting and the interactive wrapper

- **Stale working copy:** run `jj workspace update-stale` in the affected workspace, then repeat full preflight and inspect divergence before continuing.
- **Unexpected shared rewrite:** inspect `jj op log` and historical state first. `jj op restore` affects shared repository state and can disrupt every workspace; it is not a worker-local reset.
- **Missing workspace/path:** inspect `jj workspace list` and the chosen path; do not blindly retry creation or delete a directory.
- **Tools expecting `.git/`:** native jj needs no Git wiring. Separate integration requires explicit approval, not a raw Git workaround.

`piw` is an optional **user-interactive** wrapper, not this retention workflow. It snapshots the caller, creates a workspace with `--revision "$invoking_change"`, offers interactive integration into the invoking change, then forgets **and guardedly deletes** the temporary workspace. Agents must never recursively invoke `piw`; use the assigned native workspace directly.
