# Rust execution, Cargo, and Nix

## Environment first

Use the repository's pinned dev shell and toolchain; do not mix independently
selected Cargo, rustc, Clippy, and rustfmt versions. On Lucky's NixOS setup,
load `nix` before changing the development environment. Do not use `rustup
update`, `cargo install`, or edits to generated runtime config as a workaround.
Rustup commands apply only when the project actually uses rustup.

If no Rust environment exists, a temporary fallback is:

```bash
nix shell nixpkgs#rustc nixpkgs#cargo nixpkgs#rustfmt nixpkgs#clippy -c bash
```

This follows the selected nixpkgs revision, not necessarily today's stable Rust
or the project's MSRV. For reproducibility, use the repository's pinned nixpkgs
or its existing Rust overlay/toolchain. Prefer one coherent toolchain source.
Native dependencies/linkers belong in the dev shell; missing OpenSSL/pkg-config
or cross-linkers are environment failures, not a reason to rewrite Rust code.

## Quick std-only program

With Rust on PATH, use `write` to put `main.rs` in a fresh temporary directory:

```rust
use std::io::{self, Write};

fn main() -> io::Result<()> {
    writeln!(io::stdout().lock(), "Rust is ready")
}
```

Then run (replace the directory with the actual temporary path):

```bash
rustc --edition=2024 /tmp/rust-example/main.rs -o /tmp/rust-example/example
/tmp/rust-example/example
```

Use `rustc --test --edition=2024 ... -o ...` for standalone unit tests. For crates
with dependencies, use Cargo instead of manually constructing `--extern` paths.
Do not assume nightly script execution or a third-party script runner exists.

## Small Cargo project

```bash
cargo new --vcs none --edition 2024 /tmp/rust-example
cargo run --manifest-path /tmp/rust-example/Cargo.toml -- argument
cargo test --manifest-path /tmp/rust-example/Cargo.toml
```

Use a fresh directory (the snippet and Cargo examples are alternatives).
`--vcs none` prevents an accidental nested VCS repository. For lasting projects,
use the intended repository path rather than `/tmp`. Preserve an existing
edition; 2024 is a baseline for a new project only with Rust 1.85+ available.

## Cargo selection and diagnostics

| Need | Command / approach |
|---|---|
| Describe workspace/packages/targets | `cargo metadata --no-deps --format-version 1` |
| Check one package | `cargo check -p <package>` |
| Run a named binary | `cargo run -p <package> --bin <binary> -- <args>` |
| Run an example | `cargo run -p <package> --example <example>` |
| Focus tests | `cargo test -p <package> <filter> -- --nocapture` |
| Diagnose shared-state tests | `cargo test -p <package> -- --test-threads=1` |
| Explain a compiler diagnostic | `rustc --explain E0382` (use the actual code) |
| Inspect dependency duplication/features | `cargo tree -d`; `cargo tree -e features` |
| Find why a dependency exists | `cargo tree -i <dependency>` |
| Build local version-matched API docs | `cargo doc --no-deps`; omit `--no-deps` for dependency docs |
| Build timings | `cargo build --timings` |
| Investigate build/linker commands | `cargo build -vv` (review output for sensitive data before sharing) |

Arguments before `--` belong to Cargo; after it to the binary/test harness.
`--test-threads=1` is diagnostic, not a substitute for eliminating unwanted
shared state. Tests should not rely on order, global environment mutation,
current-directory changes, or fixed ports/files.

## Reproducibility and build speed

- Honor the repository's `Cargo.lock` policy. Cargo currently recommends tracking
  lockfiles for reproducibility; a library's lockfile does not constrain downstream
  dependency resolution. Do not delete or regenerate one casually.
- `--locked` rejects missing/stale lockfiles; `--offline` prevents network access
  but can change available resolution choices; `--frozen` combines both.
- Keep target artifacts between iterations. Different features, profiles,
  compiler flags, targets, and toolchains can each trigger distinct builds.
- Use `-p`, test filters, and `cargo check` for a short feedback loop. Profile
  compilation with timings before adding caches, changing linkers, or tuning
  codegen. Avoid simultaneous Cargo jobs contending for the same target lock.
- Check `rust-version` and edition independently. A newer compiler does not
  migrate an edition, and a new edition is not permission to raise MSRV silently.
  In virtual workspaces the resolver must be explicit; resolver `"3"` is the
  normal Rust-2024 choice, subject to the workspace's toolchain policy.
- Edition migration is a separate deliberate change: follow the Edition Guide,
  review `cargo fix --edition` edits, update manifests, then re-run tests. Load
  `jujutsu` for its working-copy rules; do not force automated fixes into a dirty
  tree without inspecting what they will rewrite.

## Finish checks

Compile/link and exercise the actual deliverable (CLI, library API, service,
example), not just an incidental target. Test the changed feature configuration
both on its own and in the workspace where practical. Test docs with real,
compilable examples: `no_run` compiles without executing; `compile_fail` asserts
rejection; `ignore` skips verification and requires a reason. A green doctest
suite is not evidence that ignored examples work.
