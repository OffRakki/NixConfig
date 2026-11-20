# Idiomatic Rust and common failure modes

## Ownership and lifetimes

- Each value has an owner. Moves transfer ownership; `Copy` is implicit copying
  for eligible types; `Clone` is explicit and can allocate or do arbitrary work.
- Use shared references for reading and exclusive references for mutation.
  Borrows must not outlive the referent. Shorten scopes, split disjoint fields,
  change operation order, or separate computation from mutation before cloning.
- Lifetimes describe relationships between references; annotations do not extend
  a value's lifetime. Return an owned value if the data would otherwise die in
  the function. Prefer elision until an actual relationship needs spelling out.
- `T: 'static` means T contains no non-static borrowed data; it does not mean
  the value lives forever. `&'static T` is a different constraint. Do not leak
  allocations or invent a static reference to satisfy a spawned task.
- `iter()` borrows, `iter_mut()` borrows exclusively, and `into_iter()` consumes
  the receiver (a receiver that is itself a reference can still yield borrows).
  Iterators are lazy; collecting allocates and is not always necessary.
- Match on references or use `as_ref`/`as_mut` when inspecting `Option`/`Result`
  without moving their contents. Use ownership deliberately, not compiler-error
  whack-a-mole.

## Types, traits, and public APIs

- Model alternatives with enums and validated values with newtypes/private
  fields. Derive useful traits only when their semantics are valid.
- Prefer `&str` over `&String`, `&[T]` over `&Vec<T>`, and `&Path` over a UTF-8
  string for borrowed paths. Accept owned inputs when storing/transferring them.
  Do not turn every parameter into a generic conversion trait unnecessarily.
- Use concrete types for simple code; `impl Trait`/generics for useful static
  abstraction; `dyn Trait` for needed runtime heterogeneity. Check dyn
  compatibility before building trait-object APIs. Do not promise every trait
  containing async methods can be used as a trait object.
- Keep fields and helper modules private by default. Public signatures, feature
  flags, trait implementations, and error types are compatibility commitments.
  Avoid broad `pub` visibility and bound changes unrelated to the task.
- Follow existing naming/style and rustfmt. Prefer a clear loop over a tortured
  iterator chain. Do not introduce macros or complex lifetime machinery when an
  ordinary function or owned structure is enough.

## Errors and invariants

- `Option<T>` represents absence; `Result<T, E>` represents recoverable failure.
  Use `?`, `map_err`, and existing project context/error types rather than
  swallowing errors or converting every failure to an unstructured string.
- Library errors should let callers distinguish actionable cases. Application
  boundaries can add operation/path context and choose exit codes. Preserve the
  source error; avoid logging it repeatedly at every layer.
- A panic is not ordinary control flow for malformed input. An `expect` message
  should explain why an invariant is guaranteed, not merely say "failed".
- Decide numeric semantics explicitly: `checked_*`, `saturating_*`, `wrapping_*`,
  or a propagated conversion error. Default dev and release overflow behavior
  differs; passing debug tests does not establish intended release semantics.
- Avoid unchecked narrowing `as` casts for external sizes/IDs. Validate lengths
  and limits before allocating, slicing, indexing, or decoding untrusted input.

## Strings, collections, and I/O

- `String`/`str` are UTF-8; byte length is not character count. Use `bytes`,
  `chars`, or `char_indices` according to the contract. A `char` is a Unicode
  scalar value, not necessarily a visible grapheme. String slices require UTF-8
  boundaries; use checked access for external indices.
- OS paths are not guaranteed UTF-8. Keep `Path`/`PathBuf`/`OsStr` until an API
  genuinely needs text; do not `to_str().unwrap()` arbitrary filesystem input.
- Choose `Vec`, `HashMap`, `HashSet`, or ordered `BTree*` collections based on
  access patterns and ordering needs. Hash iteration order is not a stable
  output contract. Use `entry` for conditional map updates when it simplifies code.
- Buffer repeated I/O, use `write_all` for complete byte writes, and handle
  partial reads/EOF correctly. Stream large inputs rather than always using
  `read_to_string`; binary or invalid UTF-8 input needs a byte-oriented path.
- Handle flush/close errors when durability or output completeness matters;
  destructors cannot report them through `Result`. A successful write is not
  automatically durable storage. Use the platform/format's atomicity and sync
  requirements, not a blanket promise about rename.

## Regression checklist

Test normal cases, empty input, Unicode/binary distinctions, limits/overflow,
malformed input, missing/denied I/O, and preserved error details as applicable.
Use unit tests for internal logic, integration tests for public behavior, and
runnable doctests for API examples. Keep side effects behind small boundaries;
reuse the project's testing crates rather than adding frameworks by default.
