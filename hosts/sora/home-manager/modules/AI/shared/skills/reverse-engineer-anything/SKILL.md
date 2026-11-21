---
name: reverse-engineer-anything
description: Reverse engineer native, managed, Electron/JavaScript, packaged, firmware, and browser targets with REA using shipped-artifact or requested runtime evidence. Skip REA for ordinary source-repository analysis.
---

# REA (Reverse Engineer Anything)

Use REA when a claim depends on a shipped binary, package, ASAR/JavaScript bundle, firmware image, decompilation, or requested runtime evidence not established by available source. Skip REA for ordinary analysis of a complete source repository.

{{reaAdapter}}

## Sora NixConfig rules

- `rea` is Nix-managed on `PATH` using Sora's pinned Node 24 runtime (`AI/shared/tools.nix`).
- **Never run `rea setup` or `rea update`** — Nix owns the installation and configuration.
- Native decompilers (Ghidra, IDA, JADX, Binwalk, etc.) and optional instrumentation engines are not auto-installed; inspect available tools/providers before promising deep decompilation.
- Save evidence exports, extracted artifacts, and reports under `~/sync/geral/Ciel/` (never inside `NixConfig`).

## Workflow discipline

1. **Inspect `rea --help`** (or the connected MCP tool catalog) before calling unfamiliar subcommands.
2. **Work summary-first**: start with `detail: "summary"` on large archives, binaries, or ASAR bundles before drilling into selected files, symbols, or functions.
3. **Preserve evidence boundaries**: distinguish directly observed artifact/runtime facts from inference, and record limitations, missing providers, or unverified paths explicitly.
4. **Never execute untrusted targets** unless Lucky explicitly authorizes runtime observation.

## Read only the relevant reference

| Target / Topic | Reference |
|---|---|
| Electron, ASAR, Bun/Deno, or JavaScript bundles | [references/javascript-applications.md](references/javascript-applications.md) |
| Native binaries, archives, firmware, managed assemblies | [references/native-and-artifacts.md](references/native-and-artifacts.md) |
| Android APKs, classes, manifests, and methods | [references/android-applications.md](references/android-applications.md) |
| Live runtime / browser / process observation | [references/runtime-observation.md](references/runtime-observation.md) |
| Evidence graphs, retained facts, and reporting | [references/evidence-workflows.md](references/evidence-workflows.md) |
| AgentEnv / web or desktop app environment bundles | [references/environments.md](references/environments.md) |
| Desktop build inspection | [references/desktop-build.md](references/desktop-build.md) |
| Connection, timeouts, and recovery | [references/connection-and-recovery.md](references/connection-and-recovery.md) |
