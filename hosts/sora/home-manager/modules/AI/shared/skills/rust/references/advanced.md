# Concurrency, safety, and performance

## Threads and async

- Start synchronous unless concurrency is needed. std threads, scoped threads,
  and channels often suffice. Async is for cooperative concurrent work; it does
  not automatically parallelize CPU work or make blocking operations nonblocking.
- `Send` permits transfer between threads; `Sync` permits sharing references
  between threads (`T: Sync` means `&T: Send`). Bounds depend on contained types.
  `Rc` is single-threaded; `Arc` makes reference counting atomic, not arbitrary
  inner data thread-safe. Use safe synchronization appropriate to that data.
- Keep locks short; avoid nested lock-order cycles and holding guards across
  suspension. Do not claim absence of data races implies absence of deadlocks,
  logical races, starvation, or missed shutdown signals.
- An async function produces a future; it needs polling to progress. Use the
  runtime already chosen by the project and consult its exact-version docs.
  Spawned tasks often need owned data and `Send + 'static`; local tasks differ.
  A future's `Send` status depends on values retained across suspension points.
- Use runtime-specific blocking facilities or dedicated threads for blocking
  I/O/CPU work. Bound concurrency/queues, define backpressure, deadlines,
  cancellation, shutdown, and error propagation. Handle/join task results.
- Cancellation can drop a future before completion. Review partially applied
  side effects and cancellation safety; a timeout is not transactional rollback.
  Detached tasks can outlive callers and require an explicit lifecycle policy.
- `Pin` is about preventing invalid moves of pinned values, not a magic lifetime
  fix. Prefer safe pinning and runtime helpers; read the relevant std/reference
  documentation before manual future implementations or pin projection.

## Unsafe and FFI

Read the Rust Reference and Rustonomicon chapters linked in `sources.md` before
introducing or changing unsafe abstractions. Their models evolve; do not invent
complete aliasing/provenance guarantees from a mnemonic.

- Unsafe permits specific operations, never undefined behavior. Explain why a
  safe existing API is insufficient. Keep unsafe blocks minimal and put the
  actual invariant/proof beside each one in a `SAFETY:` comment.
- Document an unsafe function's caller obligations in a `# Safety` section.
  Safe public wrappers must enforce all preconditions for every safe caller.
  An unsafe function body still benefits from explicit unsafe operation blocks.
- Review pointer provenance, alignment, initialization, validity, bounds,
  aliasing, lifetimes, ownership, allocation/deallocation pairing, and thread
  access. `MaybeUninit` does not make uninitialized `T` valid; `transmute`, raw
  pointers, `static mut`, and manual `Send`/`Sync` need real proofs.
- FFI requires the correct ABI, layout (`repr(C)` where appropriate), calling
  convention, ownership, callback lifetime/threading, and unwind behavior.
  `repr(C)` does not make a Rust `String` or `Vec` an interoperable C field.
  Use appropriate C-compatible types, explicit lengths and nullability, and
  checked conversions. Do not let panics cross a non-unwinding FFI boundary.
- Rust 2024 has additional unsafe obligations around extern blocks/attributes
  and some standard APIs. Verify the project's edition and exact API docs.
- Use Miri when available for relevant unsafe tests; sanitizers/fuzzing can add
  evidence. These may require separately provisioned/nightly tooling and are
  not assumed installed. A passing run does not prove soundness or cover all
  executions. Never switch the main toolchain to nightly silently.

## Performance

1. Reproduce the real workload, target, input size, and correctness baseline.
2. Measure optimized builds (`cargo build --release` / `cargo run --release`).
   Exclude compilation and process startup where the comparison requires it;
   distinguish cold/warm caches and end-to-end latency from steady-state work.
3. Profile the bottleneck before changing algorithms, allocations, buffering,
   layouts, synchronization, or task granularity. Use tools already present;
   external profilers/benchmark crates need their own versioned documentation.
4. Prefer an algorithmic improvement over unsafe micro-optimization. Do not
   assume iterator chains are slower than loops or clones always dominate.
5. Re-run correctness tests and comparable measurements, reporting variance and
   regressions. Check release behavior when overflow/debug assertions matter.

Keep default profiles until measurements justify a change. LTO, codegen units,
`target-cpu=native`, panic strategy, allocator choices, and custom linkers trade
build speed, portability, debugging, size, and runtime behavior. Host-native
binaries may not run on deployment CPUs. std's `#[bench]` custom benchmark
facility is unstable; do not present it as a stable test-harness capability.

## Specialized targets

For `no_std`/embedded, inspect target support, `core`/`alloc`, allocator and panic
strategy, linker scripts, hardware access, and available target runners. Follow
the Embedded Book rather than importing desktop assumptions. For cross builds,
inspect `--target` configuration and native dependencies. A host check cannot
validate target-specific cfg branches or hardware behavior.
