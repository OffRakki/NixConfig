# Official Rust source map

Authority starts at <https://doc.rust-lang.org/stable/>. This skill distills
workflows, not the entire bookshelf. Fetch the relevant chapter before relying
on unfamiliar or version-sensitive details; do not imply every linked book was
read in full. Stable URLs move as Rust releases change.

## Find the answer quickly

| Question | Official source |
|---|---|
| Language concepts and guided examples | [The Book](https://doc.rust-lang.org/stable/book/) · [Rust By Example](https://doc.rust-lang.org/stable/rust-by-example/) |
| API signatures, guarantees, examples, stabilization versions | [Standard library](https://doc.rust-lang.org/stable/std/) |
| Precise language behavior | [Rust Reference](https://doc.rust-lang.org/stable/reference/) |
| Compiler errors | [Error index](https://doc.rust-lang.org/stable/error_codes/) · `rustc --explain <code>` |
| Cargo commands, manifests, features, resolution, profiles | [Cargo Book](https://doc.rust-lang.org/stable/cargo/) |
| Compiler flags, targets, linking, tests | [rustc Book](https://doc.rust-lang.org/stable/rustc/) |
| Formatting | [Style Guide](https://doc.rust-lang.org/stable/style-guide/) · `cargo fmt` |
| Lint behavior and configuration | [Clippy Book](https://doc.rust-lang.org/stable/clippy/) |
| API documentation and doctests | [rustdoc Book](https://doc.rust-lang.org/stable/rustdoc/) |
| Edition migration | [Edition Guide](https://doc.rust-lang.org/stable/edition-guide/) |
| Release/stabilization history | [Release notes](https://doc.rust-lang.org/stable/releases.html) |
| Unsafe abstractions and FFI | [Rustonomicon](https://doc.rust-lang.org/stable/nomicon/) together with the Reference |
| Bare metal/embedded | [Embedded Book](https://doc.rust-lang.org/stable/embedded-book/) |
| Explicitly requested unstable features | [Unstable Book](https://doc.rust-lang.org/stable/unstable-book/) |
| Compiler implementation/contribution | [rustc Development Guide](https://rustc-dev-guide.rust-lang.org/) |

The Reference is not a complete formal specification. Unsafe details are not
fully settled; a tutorial example does not override a documented safety contract.
Nightly/unstable documentation is not evidence that an API works on stable.

## Workflow chapters

- [cargo check](https://doc.rust-lang.org/stable/cargo/commands/cargo-check.html)
  and [cargo test](https://doc.rust-lang.org/stable/cargo/commands/cargo-test.html):
  target selection, doctests, features, reproducibility flags, harness arguments.
- [rust-version / MSRV](https://doc.rust-lang.org/stable/cargo/reference/rust-version.html)
  and [resolution](https://doc.rust-lang.org/stable/cargo/reference/resolver.html):
  compiler support policies, workspace resolvers, dependency compatibility.
- [Features](https://doc.rust-lang.org/stable/cargo/reference/features.html):
  additive design, feature unification, defaults, incompatible combinations.
- [Profiles](https://doc.rust-lang.org/stable/cargo/reference/profiles.html):
  dev/release differences, overflow checks, incremental builds, LTO/codegen.
- [Clippy usage](https://doc.rust-lang.org/stable/clippy/usage.html): lint levels,
  command-line behavior, automatic fixes, workspace selection.
- [Doctests](https://doc.rust-lang.org/stable/rustdoc/write-documentation/documentation-tests.html):
  executable examples, `no_run`, `compile_fail`, and skipped examples.
- [Rust 2024](https://doc.rust-lang.org/stable/edition-guide/rust-2024/index.html):
  released with Rust 1.85.0; inspect migration chapters before edition changes.

## Language and safety chapters

- [References and borrowing](https://doc.rust-lang.org/stable/book/ch04-02-references-and-borrowing.html)
  · [Lifetimes](https://doc.rust-lang.org/stable/book/ch10-03-lifetime-syntax.html)
  · [Traits](https://doc.rust-lang.org/stable/book/ch10-02-traits.html)
- [Error policy](https://doc.rust-lang.org/stable/book/ch09-03-to-panic-or-not-to-panic.html)
  · [Iterators](https://doc.rust-lang.org/stable/book/ch13-02-iterators.html)
- [Send and Sync](https://doc.rust-lang.org/stable/book/ch16-04-extensible-concurrency-sync-and-send.html)
  · [Async](https://doc.rust-lang.org/stable/book/ch17-00-async-await.html)
- [Undefined behavior](https://doc.rust-lang.org/stable/reference/behavior-considered-undefined.html)
  · [FFI](https://doc.rust-lang.org/stable/nomicon/ffi.html)
- [Pin](https://doc.rust-lang.org/stable/std/pin/)
  · [MaybeUninit](https://doc.rust-lang.org/stable/std/mem/union.MaybeUninit.html)

## Match documentation to the toolchain

Use installed `cargo <command> --help`, `rustc --help`, and `rustc --explain` for
actual CLI support. Check the std API's “since” version against `rust-version`.
For a pinned release, use `https://doc.rust-lang.org/<version>/` rather than
assuming `/stable/` describes that compiler. If rustup is actually installed,
`rustup doc` opens installed documentation; Nix installations may omit it.

Use `cargo doc` to build local dependency docs for resolved versions, or that
crate's exact-version docs/source. The Rust bookshelf links third-party tools
but does not document every ecosystem crate. Separate verified language/tool
behavior from project-specific recommendations and unmeasured performance claims.
