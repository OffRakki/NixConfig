---
name: rust
description: Write, run, debug, test, review, and optimize Rust programs and Cargo workspaces. Use for .rs files, Cargo.toml, ownership and lifetime errors, traits, async/concurrency, unsafe/FFI, feature flags, editions/MSRV, Rust tooling, and Nix-managed Rust environments. Ground language and tool behavior in the official stable Rust documentation.
---

# Rust

Build the smallest correct solution; compile early, test behavior, and measure
before optimizing. Prefer safe, idiomatic Rust and the project's existing tools
and dependencies. Rust is available for quick experiments, not just big projects.

## Load the right reference

Paths below are relative to this skill directory; read only what the task needs.

| Task | Read |
|---|---|
| Run a snippet, configure Cargo/Nix, diagnose builds, validate a change | [Workflow](references/workflow.md) |
| Ownership, lifetimes, API design, errors, collections, I/O | [Language and design](references/language.md) |
| Threads, async, unsafe, FFI, performance, specialized targets | [Advanced](references/advanced.md) |
| Find an authoritative chapter or verify version-sensitive behavior | [Official sources](references/sources.md) |

## Before touching code

1. Read repository instructions and the current implementation, callers, tests,
   manifests, lockfile policy, CI, and relevant Cargo/toolchain configuration.
   In jj workspaces, load `jujutsu` and follow its preflight.
2. Inspect `Cargo.toml` (workspace root and affected packages), `rust-version`,
   `edition`, features, `rust-toolchain.toml`/`rust-toolchain`, `.cargo/config.toml`,
   and `flake.nix`/`flake.lock` or other development-shell declarations if present.
   Do not dump credential files or unrelated environment variables.
3. Use the declared environment: `nix develop -c ...` when provided. Check
   `rustc --version --verbose` and `cargo --version` there. Respect MSRV and
   target constraints; latest stable docs can describe APIs newer than the pin.
4. Establish the failing behavior or intended contract. Capture the existing
   check/test result before changing it when practical. Read compiler diagnostics
   from the first relevant error, not the cascade.

Cargo can execute dependency build scripts and procedural macros, even during
`cargo check`. Inspect unfamiliar projects before building; a dev shell is not a
security sandbox. Do not install global tools or change toolchain pins silently.

## Fast iteration

- Standalone, std-only experiment: use `rustc --edition=2024` in a temporary
  directory, then execute the binary. Edition 2024 requires Rust 1.85+; use the
  project's edition/toolchain when reproducing its behavior.
- Dependencies, multiple files, or repeated experiments: use Cargo. In this
  NixConfig repository, put scratch crates and generated output outside the
  source tree, normally under `/tmp` or `~/sync/geral/Ciel/`.
- Iterate with `cargo check -p <package>` and one focused test before broad gates.
  `check` skips final code generation: it is not proof that linking or execution
  succeeds. Keep Cargo's build cache; do not reflexively `cargo clean`.
- Use dev builds for iteration, release builds for runtime performance claims.
  Report compile time separately from execution time; Rust isn't automatically
  faster for every workload.

## Implementation defaults

- Borrow inputs (`&str`, `&[T]`, `&Path`) when ownership is unnecessary; return
  owned values when their lifetime must outlive local data. Do not fight the
  borrow checker with reflexive `clone()`, `Arc<Mutex<_>>`, leaks, or `unsafe`.
- Prefer enums/newtypes and explicit invariants over flags and invalid states.
  Keep visibility narrow; use traits/generics for actual variation, not ceremony.
- Use `Result` plus `?` for expected failures and preserve useful error context.
  `unwrap`/`expect` are fine in tests and proven invariants; explain the invariant.
  Never use them as normal validation for user input, I/O, or network failures.
- Start with std and existing dependencies. Check a new crate's necessity,
  maintenance, license, features, MSRV, and target support before adding it.
  Official Rust docs do not establish a third-party crate's API or trustworthiness.
- Do not introduce an async runtime for a simple synchronous task. Existing
  runtime APIs must be checked against that dependency's actual version.
- Make unsafe code exceptional, small, documented, and independently reviewable.
  Safe compilation alone does not prove soundness, deadlock freedom, or correctness.

## Validation ladder

Adapt to project CI, selected packages, supported targets, features, and toolchain.
From the workspace root, a typical baseline is:

```bash
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets
cargo test --workspace
cargo doc --workspace --no-deps
```

- Fix relevant warnings; preserve the project's lint policy. Add `-- -D warnings`
  to Clippy when warnings are already a gate (or for a clean new project), not
  as an excuse for unrelated cleanup. Do not enable every Clippy lint globally.
- When `Cargo.lock` is tracked and current, add `--locked` to Cargo commands that
  support it, not `cargo fmt`. A new crate needs its lockfile generated first.
  Do not silently refresh dependencies to make a locked build pass.
- `cargo test --workspace` includes library doctests by default. Explicit target
  selection such as `--all-targets` does not include doctests; run a separate
  `cargo test --workspace --doc` for library crates when using that selection.
- Exercise relevant default, no-default, and supported feature combinations.
  `--all-features` is useful only if that combination is supported; it does not
  test each feature in isolation or prove absence of feature-unification bugs.
- Add regression tests for the changed contract, including malformed/empty input,
  boundaries, error paths, and concurrency/shutdown behavior where relevant.
- Verify declared MSRV and cross-target builds when affected and available;
  cross-compilation alone does not test runtime behavior on that target.
- Report exact commands, versions, results, and anything not executed. Never
  claim tests passed from successful compilation alone.
