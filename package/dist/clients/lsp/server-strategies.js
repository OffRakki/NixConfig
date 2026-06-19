/**
 * Per-Server Diagnostic Strategies for pi-lens LSP
 *
 * Codifies known server behavior so timing decisions (debounce, retry budget,
 * first-push seeding) are automatic rather than one-size-fits-all.
 *
 * Env var overrides (PI_LENS_LSP_*) always take precedence over strategy values.
 */
export const SERVER_DIAGNOSTIC_STRATEGIES = {
    typescript: {
        seedFirstPush: true,
        pullRetryBudgetMs: 0,
        debounceMs: 50,
        aggregateWaitMs: 1000,
        expectSemanticSecondPush: false,
    },
    "rust-analyzer": {
        seedFirstPush: false,
        pullRetryBudgetMs: 500,
        debounceMs: 150,
        aggregateWaitMs: 3000,
        expectSemanticSecondPush: true,
    },
    // PythonServer (pyright / basedpyright) — openFilesOnly mode: lazy per-file
    // analysis, startup similar to jedi. seedFirstPush: true because pyright's
    // first publishDiagnostics after didOpen is the complete result for that file.
    python: {
        seedFirstPush: true,
        pullRetryBudgetMs: 0,
        debounceMs: 100,
        aggregateWaitMs: 1500,
        expectSemanticSecondPush: false,
    },
    "python-jedi": {
        seedFirstPush: true,
        pullRetryBudgetMs: 0,
        debounceMs: 100,
        aggregateWaitMs: 1000,
        expectSemanticSecondPush: false,
    },
    eslint: {
        seedFirstPush: true,
        pullRetryBudgetMs: 0,
        debounceMs: 200,
        aggregateWaitMs: 2000,
        expectSemanticSecondPush: false,
    },
};
/** Fallback for unknown servers. Conservative defaults. */
export const DEFAULT_STRATEGY = {
    seedFirstPush: false,
    pullRetryBudgetMs: 250,
    debounceMs: 150,
    aggregateWaitMs: 1500,
    expectSemanticSecondPush: false,
};
export function getStrategy(serverId) {
    return SERVER_DIAGNOSTIC_STRATEGIES[serverId] ?? DEFAULT_STRATEGY;
}
