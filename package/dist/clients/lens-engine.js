/**
 * LensEngine — the single internal-facing seam for pi-lens host adapters.
 *
 * The maintainability rule: host adapters (the MCP server today; index.ts can
 * adopt incrementally) talk ONLY to this module, never reaching into pi-lens
 * internals directly. So when an internal API is refactored, the break surfaces
 * HERE (one file, TypeScript-loud), not scattered across the adapter. New
 * mirrored capabilities (cascade, call-graph, …) get a method here and the
 * adapter just routes to it — coupling stays capped at this interface instead of
 * growing per tool.
 *
 * It re-exports the per-concern facades (analyze / review / session / ipc) and
 * adds thin wrappers over the remaining internal reach-ins (latency, project
 * scan, LSP status, diagnostic stats, LSP config).
 */
import { getDiagnosticTracker } from "./diagnostic-tracker.js";
import { getLatencyReports, } from "./dispatch/integration.js";
import { initLSPConfig } from "./lsp/config.js";
import { getLSPService } from "./lsp/index.js";
import { scanProjectDiagnostics } from "./project-diagnostics/scanner.js";
import * as path from "node:path";
import { normalizeMapKey } from "./path-utils.js";
import { loadProjectSnapshot } from "./project-snapshot.js";
import { centralityFromReverseDeps, deserializeWordIndex, searchWordIndex, } from "./word-index.js";
// --- Facades (re-exported so adapters import only this module) ---------------
export { analyzeFile, } from "./mcp/analyze.js";
export { createMcpHost } from "./mcp/host-shim.js";
export { ipcPathForCwd, requestWarmAnalyze, } from "./mcp/ipc.js";
export { analyzeFileFresh, resolveRebuildScript, runRebuild, summarizeScan, } from "./mcp/review.js";
export { runSessionStart, runTurnEnd, } from "./mcp/session.js";
// --- Query wrappers (own the remaining internal reach-ins) -------------------
/** Recent dispatch latency reports (latency.log schema), newest first. */
export function recentLatency(limit = 5, fileFilter) {
    let reports = getLatencyReports();
    if (fileFilter) {
        const needle = fileFilter.replace(/\\/g, "/");
        reports = reports.filter((report) => report.filePath.replace(/\\/g, "/").endsWith(needle));
    }
    return reports.slice(-limit).reverse();
}
/** Cheap project-wide scan (tree-sitter + fact rules). */
export function projectScan(cwd, maxFiles) {
    return scanProjectDiagnostics({ cwd, tier: "cheap", maxFiles });
}
/** Alive LSP client count + per-server status. */
export function lspStatus() {
    const lsp = getLSPService();
    return { aliveClients: lsp.getAliveClientCount(), servers: lsp.getStatus() };
}
/** Session diagnostic counters (shown / auto-fixed / unresolved …). */
export function diagnosticStats() {
    return getDiagnosticTracker().getStats();
}
/** Initialise LSP config for a workspace (idempotent at the LSP layer). */
export function ensureLspConfig(cwd) {
    return initLSPConfig(cwd);
}
/**
 * Ranked identifier search over the persisted word index (#162). Stateless:
 * loads the index from the project snapshot (built by the session scan, in
 * either the pi extension or the MCP session), so it works without a warm
 * runtime. Returns `available: false` when no index exists yet.
 */
export function symbolSearch(query, cwd, limit = 20) {
    const snapshot = loadProjectSnapshot(cwd);
    const index = deserializeWordIndex(snapshot?.wordIndex);
    if (!index)
        return { available: false, query, results: [] };
    // Boost well-connected files using the snapshot's reverse-dependency
    // (importedBy) counts; snapshot keys are normalized, index keys are raw.
    const centrality = centralityFromReverseDeps(index, snapshot?.reverseDeps, (file) => normalizeMapKey(path.resolve(file)));
    return {
        available: true,
        query,
        results: searchWordIndex(index, query, { limit, centrality }),
    };
}
/**
 * Transitive, depth-bounded impact of a file ("what depends on this") over the
 * review graph's call/reference/import edges (#162). Builds/loads the review
 * graph (3-tier cached, so cheap after the first build) and walks incoming
 * edges. Read-only.
 */
export async function symbolImpact(file, cwd, options) {
    const { buildOrUpdateGraph } = await import("./review-graph/builder.js");
    const { computeTransitiveImpact } = await import("./review-graph/query.js");
    const { FactStore } = await import("./dispatch/fact-store.js");
    const graph = await buildOrUpdateGraph(cwd, [], new FactStore());
    const result = computeTransitiveImpact(graph, path.resolve(cwd, file), options);
    return { available: graph.nodes.size > 0, ...result };
}
