/**
 * LSP Client for pi-lens
 *
 * Handles JSON-RPC communication with language servers:
 * - Initialize/shutdown lifecycle
 * - Document synchronization (didOpen, didChange)
 * - Diagnostics with debouncing
 * - Request/response handling
 */
import { spawn as nodeSpawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { access } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { logLatency } from "../latency-logger.js";
// vscode-jsonrpc v9 ships an `exports` map exposing the Node entry as the
// `./node` subpath (no `.js`); the old `/node.js` file path no longer resolves.
import { createMessageConnection, StreamMessageReader, StreamMessageWriter, } from "vscode-jsonrpc/node";
import { normalizeMapKey, uriToPath } from "./path-utils.js";
import { getStrategy } from "./server-strategies.js";
// --- Constants ---
const INITIALIZE_TIMEOUT_MS = positiveIntFromEnv("PI_LENS_LSP_INIT_TIMEOUT_MS", 15_000); // 15s — npx downloads are handled by ensureTool, not here
const NAV_REQUEST_TIMEOUT_MS = positiveIntFromEnv("PI_LENS_LSP_NAV_REQUEST_TIMEOUT_MS", 10_000); // 10s — per-request ceiling; prevents heavy servers (vue, svelte) from hanging
const DIAGNOSTICS_WAIT_TIMEOUT_MS = positiveIntFromEnv("PI_LENS_LSP_DIAGNOSTICS_WAIT_MS", 10_000);
const PULL_DIAGNOSTICS_RETRY_INTERVAL_MS = positiveIntFromEnv("PI_LENS_LSP_PULL_RETRY_INTERVAL_MS", 250);
const SHUTDOWN_REQUEST_TIMEOUT_MS = positiveIntFromEnv("PI_LENS_LSP_SHUTDOWN_TIMEOUT_MS", 1000);
const LSP_CRASH_CODES = new Set([
    "ERR_STREAM_DESTROYED",
    "ERR_STREAM_WRITE_AFTER_END",
    "EPIPE",
    "ECONNRESET",
]);
let crashGuardInstalled = false;
function isIgnorableLspRuntimeCrash(err) {
    if (!(err instanceof Error))
        return false;
    const code = err.code;
    if (code && LSP_CRASH_CODES.has(code))
        return true;
    const msg = err.message.toLowerCase();
    const stack = (err.stack ?? "").toLowerCase();
    return (msg.includes("stream") ||
        msg.includes("write after end") ||
        stack.includes("vscode-jsonrpc/lib/node/ril.js"));
}
function installCrashGuard() {
    if (crashGuardInstalled)
        return;
    crashGuardInstalled = true;
    process.on("uncaughtException", (err) => {
        if (isIgnorableLspRuntimeCrash(err)) {
            return;
        }
        throw err;
    });
    process.on("unhandledRejection", (reason) => {
        if (isIgnorableLspRuntimeCrash(reason)) {
            return;
        }
        throw reason instanceof Error ? reason : new Error(String(reason));
    });
}
function isClientAlive(state) {
    return (state.isConnected && !state.isDestroyed && !state.lspProcess.process.killed);
}
function disposeClientConnection(state) {
    if (state.connectionDisposed)
        return;
    state.connectionDisposed = true;
    try {
        state.connection.dispose();
    }
    catch {
        // ignore
    }
}
async function killProcessTree(proc, pid, options = {}) {
    if (process.platform === "win32" && pid > 0) {
        try {
            // Absolute path avoids PATH-resolution: SystemRoot is set by Windows itself.
            const taskkill = `${process.env.SystemRoot ?? "C:\\Windows"}\\System32\\taskkill.exe`;
            const killer = nodeSpawn(taskkill, ["/F", "/T", "/PID", String(pid)], {
                shell: false,
                windowsHide: true,
                stdio: "ignore",
                detached: !!options.fast,
            });
            if (options.fast) {
                killer.unref();
                proc.unref?.();
                return;
            }
            await new Promise((resolve) => {
                killer.once("close", () => resolve());
                killer.once("error", () => resolve());
            });
        }
        catch {
            // ignore
        }
        return;
    }
    try {
        proc.kill("SIGTERM");
        if (options.fast) {
            const timer = setTimeout(() => {
                try {
                    if (!proc.killed) {
                        proc.kill("SIGKILL");
                    }
                }
                catch {
                    // best-effort
                }
            }, 1500);
            timer.unref?.();
            proc.unref?.();
            return;
        }
        // SIGTERM → 1.5s → SIGKILL escalation.
        // SIGTERM alone can leave zombie processes if the server hangs.
        await new Promise((resolve) => setTimeout(resolve, 1500));
        try {
            if (!proc.killed) {
                proc.kill("SIGKILL");
            }
        }
        catch {
            // best-effort
        }
    }
    catch {
        // ignore
    }
}
export function stripDiagnosticNoiseLines(message) {
    const cleaned = message
        .split(/\r?\n/)
        .filter((line) => {
        const trimmed = line.trim();
        if (/^for further information visit\b/i.test(trimmed))
            return false;
        if (/^https?:\/\/\S+$/i.test(trimmed))
            return false;
        return true;
    })
        .join("\n")
        .trim();
    return cleaned || message.trim() || message;
}
function normalizeLspDiagnostic(diagnostic) {
    const message = stripDiagnosticNoiseLines(diagnostic.message);
    return message === diagnostic.message
        ? diagnostic
        : { ...diagnostic, message };
}
function normalizeLspDiagnostics(diagnostics) {
    return diagnostics.map(normalizeLspDiagnostic);
}
function mergeDiagnosticLists(push, pull) {
    const merged = [];
    const seen = new Set();
    for (const diagnostic of [...(push ?? []), ...(pull ?? [])]) {
        const key = [
            diagnostic.range.start.line,
            diagnostic.range.start.character,
            diagnostic.range.end.line,
            diagnostic.range.end.character,
            diagnostic.code ?? "",
            diagnostic.source ?? "",
            diagnostic.message,
        ].join(":");
        if (seen.has(key))
            continue;
        seen.add(key);
        merged.push(diagnostic);
    }
    return merged;
}
function getMergedDiagnosticsForPath(state, normalizedPath) {
    const legacy = state;
    return mergeDiagnosticLists(state.pushDiagnostics?.get(normalizedPath) ??
        legacy.diagnostics?.get(normalizedPath), state.documentPullDiagnostics?.get(normalizedPath));
}
function clearDiagnosticsForPath(state, normalizedPath) {
    const legacy = state;
    state.pushDiagnostics?.delete(normalizedPath);
    state.pushDiagnosticTimestamps?.delete(normalizedPath);
    state.documentPullDiagnostics?.delete(normalizedPath);
    state.documentPullDiagnosticTimestamps?.delete(normalizedPath);
    state.diagnosticDocVersions?.delete(normalizedPath);
    legacy.diagnostics?.delete(normalizedPath);
    legacy.diagnosticTimestamps?.delete(normalizedPath);
}
// Methods that can be registered dynamically and map to operationSupport keys
const DYNAMIC_OPERATION_METHOD_MAP = {
    "textDocument/definition": "definition",
    "textDocument/references": "references",
    "textDocument/hover": "hover",
    "textDocument/signatureHelp": "signatureHelp",
    "textDocument/documentSymbol": "documentSymbol",
    "workspace/symbol": "workspaceSymbol",
    "textDocument/codeAction": "codeAction",
    "textDocument/rename": "rename",
    "textDocument/implementation": "implementation",
    "textDocument/prepareCallHierarchy": "callHierarchy",
};
export function applyDynamicCapabilities(state) {
    const registeredMethods = new Set(state.dynamicRegistrations.values());
    const hasDynamicPull = registeredMethods.has("textDocument/diagnostic") ||
        registeredMethods.has("workspace/diagnostic");
    if (hasDynamicPull) {
        state.workspaceDiagnosticsSupport = {
            advertised: true,
            mode: "pull",
            diagnosticProviderKind: "dynamic",
        };
    }
    else if (state.staticDiagnosticsMode === "push-only" &&
        state.workspaceDiagnosticsSupport.diagnosticProviderKind === "dynamic") {
        // Was only dynamically registered, now unregistered — revert to push-only
        state.workspaceDiagnosticsSupport = {
            advertised: false,
            mode: "push-only",
            diagnosticProviderKind: "none",
        };
    }
    for (const [method, key] of Object.entries(DYNAMIC_OPERATION_METHOD_MAP)) {
        if (registeredMethods.has(method)) {
            state.operationSupport[key] = true;
        }
    }
}
function setupIncomingHandlers(state, initialization) {
    state.connection.onNotification("textDocument/publishDiagnostics", (params) => {
        const filePath = uriToPath(params.uri);
        const normalizedPath = normalizeMapKey(filePath);
        const newDiags = normalizeLspDiagnostics(params.diagnostics || []);
        const docVersion = params.version;
        const strategy = getStrategy(state.serverId);
        // Record the document version these diagnostics were computed against
        // (when the server reports it) so waitForDiagnostics can reject results
        // that lag behind the latest didChange instead of serving them as fresh.
        const recordDocVersion = () => {
            if (docVersion !== undefined) {
                state.diagnosticDocVersions.set(normalizedPath, docVersion);
            }
        };
        // Seed on first push for servers whose first push is known complete.
        // Bypasses the debounce timer entirely — resolves waiting promises immediately.
        if (strategy.seedFirstPush &&
            !state.pushDiagnostics.has(normalizedPath)) {
            state.pushDiagnostics.set(normalizedPath, newDiags);
            state.pushDiagnosticTimestamps.set(normalizedPath, Date.now());
            recordDocVersion();
            state.diagnosticsVersion += 1;
            state.diagnosticEmitter.emit("diagnostics", normalizedPath);
            return;
        }
        const existingTimer = state.pendingDiagnostics.get(normalizedPath);
        if (existingTimer)
            clearTimeout(existingTimer);
        const timer = setTimeout(() => {
            state.pushDiagnostics.set(normalizedPath, newDiags);
            state.pushDiagnosticTimestamps.set(normalizedPath, Date.now());
            recordDocVersion();
            state.pendingDiagnostics.delete(normalizedPath);
            state.diagnosticsVersion += 1;
            state.diagnosticEmitter.emit("diagnostics", normalizedPath);
        }, strategy.debounceMs);
        state.pendingDiagnostics.set(normalizedPath, timer);
    });
    state.connection.onRequest("workspace/workspaceFolders", () => [
        { name: "workspace", uri: pathToFileURL(state.root).href },
    ]);
    state.connection.onRequest("client/registerCapability", async (params) => {
        for (const reg of params?.registrations ?? []) {
            if (reg.id && reg.method) {
                state.dynamicRegistrations.set(reg.id, reg.method);
            }
        }
        applyDynamicCapabilities(state);
    });
    state.connection.onRequest("client/unregisterCapability", async (params) => {
        for (const unreg of params?.unregisterations ?? []) {
            if (unreg.id) {
                state.dynamicRegistrations.delete(unreg.id);
            }
        }
        applyDynamicCapabilities(state);
    });
    state.connection.onRequest("workspace/configuration", async () => [
        initialization ?? {},
    ]);
    state.connection.onRequest("window/workDoneProgress/create", async () => { });
}
function setupConnectionLifecycle(state) {
    state.connection.onError(([error]) => {
        state.lastError = error instanceof Error ? error : new Error(String(error));
        state.isConnected = false;
        state.isDestroyed = true;
        disposeClientConnection(state);
    });
    state.connection.onClose(() => {
        state.isConnected = false;
        state.isDestroyed = true;
        disposeClientConnection(state);
    });
    state.lspProcess.process.on("exit", (code) => {
        const wasConnected = state.isConnected;
        state.isConnected = false;
        state.isDestroyed = true;
        disposeClientConnection(state);
        if (wasConnected) {
            logLatency({
                type: "phase",
                phase: "lsp_server_unexpected_exit",
                filePath: state.root,
                durationMs: 0,
                metadata: {
                    serverId: state.serverId,
                    pid: state.lspProcess.pid,
                    exitCode: code ?? null,
                },
            });
        }
    });
}
async function clientRequestPullDiagnostics(state, filePath) {
    if (!isClientAlive(state))
        return 0;
    const uri = pathToFileURL(filePath).href;
    try {
        const report = await safeSendRequest(state.connection, "textDocument/diagnostic", { textDocument: { uri } });
        if (!report)
            return 0;
        const normalizedPath = normalizeMapKey(filePath);
        const primaryItems = normalizeLspDiagnostics(report.items ?? []);
        const now = Date.now();
        state.documentPullDiagnostics.set(normalizedPath, primaryItems);
        state.documentPullDiagnosticTimestamps.set(normalizedPath, now);
        state.diagnosticsVersion += 1;
        let totalCount = primaryItems.length;
        if (report.relatedDocuments) {
            for (const [relatedUri, related] of Object.entries(report.relatedDocuments)) {
                const relatedPath = uriToPath(relatedUri);
                const relatedItems = normalizeLspDiagnostics(related?.items ?? []);
                state.documentPullDiagnostics.set(normalizeMapKey(relatedPath), relatedItems);
                state.documentPullDiagnosticTimestamps.set(normalizeMapKey(relatedPath), now);
                totalCount += relatedItems.length;
            }
        }
        state.diagnosticEmitter.emit("diagnostics", normalizedPath);
        return totalCount;
    }
    catch {
        return 0;
    }
}
export async function clientWaitForDiagnostics(state, filePath, timeoutMs, options = {}) {
    const normalizedPath = normalizeMapKey(filePath);
    const minVersion = options.minVersion;
    const hasFreshDiagnostics = () => minVersion === undefined || state.diagnosticsVersion > minVersion;
    // Version coherence: a cached push is "stale" only when the server reported
    // the document version it computed against AND that version lags the latest
    // didChange we sent. This prevents serving diagnostics from a superseded
    // version as fresh (e.g. once the redundant double-push is collapsed and the
    // dispatch wait runs without a push-counter baseline — #203). Unknown version
    // (server omits it) is treated as current so version-less servers are
    // unaffected, and the timeout remains the backstop.
    const isVersionStale = () => {
        const cachedVersion = state.diagnosticDocVersions?.get(normalizedPath);
        if (cachedVersion === undefined)
            return false;
        const currentVersion = state.documentVersions?.get(normalizedPath);
        return currentVersion !== undefined && cachedVersion < currentVersion;
    };
    if (state.workspaceDiagnosticsSupport.mode === "pull") {
        const firstPullCount = await clientRequestPullDiagnostics(state, filePath);
        if (firstPullCount > 0 || hasFreshDiagnostics())
            return;
        const strategy = getStrategy(state.serverId);
        const retryBudgetMs = strategy.pullRetryBudgetMs > 0
            ? Math.min(timeoutMs, strategy.pullRetryBudgetMs)
            : 0;
        const startedAt = Date.now();
        let latestCount = firstPullCount;
        while (latestCount === 0 && Date.now() - startedAt < retryBudgetMs) {
            await new Promise((resolve) => setTimeout(resolve, PULL_DIAGNOSTICS_RETRY_INTERVAL_MS));
            latestCount = await clientRequestPullDiagnostics(state, filePath);
        }
        if (latestCount > 0 || hasFreshDiagnostics())
            return;
    }
    if (hasFreshDiagnostics() &&
        !isVersionStale() &&
        getMergedDiagnosticsForPath(state, normalizedPath).length > 0) {
        return;
    }
    return new Promise((resolve) => {
        let debounceTimer;
        const onDiagnostics = (fp) => {
            if (normalizeMapKey(fp) !== normalizedPath)
                return;
            if (!hasFreshDiagnostics() || isVersionStale())
                return;
            if (debounceTimer)
                clearTimeout(debounceTimer);
            // Adaptive debounce: use time since last push to compute remaining
            // wait instead of always waiting the full debounce window.
            const strategy = getStrategy(state.serverId);
            const hit = state.pushDiagnosticTimestamps.get(normalizedPath);
            const timeSincePush = hit ? Date.now() - hit : Infinity;
            const remaining = Math.max(0, strategy.debounceMs - timeSincePush);
            debounceTimer = setTimeout(() => {
                state.diagnosticEmitter.off("diagnostics", onDiagnostics);
                clearTimeout(timeout);
                resolve();
            }, remaining);
        };
        state.diagnosticEmitter.on("diagnostics", onDiagnostics);
        const timeout = setTimeout(() => {
            if (debounceTimer)
                clearTimeout(debounceTimer);
            state.diagnosticEmitter.off("diagnostics", onDiagnostics);
            resolve();
        }, timeoutMs);
    });
}
export async function handleNotifyOpen(state, filePath, content, languageId, preserveDiagnostics = false, silent = false) {
    if (!isClientAlive(state))
        return;
    const uri = pathToFileURL(filePath).href;
    const normalizedPath = normalizeMapKey(filePath);
    if (state.openDocuments.has(normalizedPath) ||
        state.pendingOpens.has(normalizedPath)) {
        const version = (state.documentVersions.get(normalizedPath) ?? 0) + 1;
        state.documentVersions.set(normalizedPath, version);
        // preserveDiagnostics: skip cache clear for format-only resyncs so
        // waitForDiagnostics fast-paths instead of waiting up to 5s for TypeScript
        // to re-publish what it already knows (formatting doesn't change semantics).
        if (!preserveDiagnostics) {
            clearDiagnosticsForPath(state, normalizedPath);
        }
        await safeSendNotification(state.connection, "textDocument/didChange", {
            textDocument: { uri, version },
            contentChanges: [{ text: content }],
        });
        return;
    }
    state.pendingOpens.add(normalizedPath);
    state.documentVersions.set(normalizedPath, 0);
    clearDiagnosticsForPath(state, normalizedPath); // always clear for initial open
    // Send workspace notification first (like opencode does).
    // Skipped in silent mode — cascade reads a file for diagnostics,
    // not reporting a real filesystem change. Avoids N project-wide
    // rechecks on push-diagnostics LSPs (TypeScript, Python) per CR-1.
    if (!silent) {
        // Async existence probe (was a synchronous existsSync on the document-open
        // path — a stat that blocks the loop during first-read/warm). The notify
        // type is unchanged: 2 (Changed) when the file exists on disk, else 1
        // (Created). access() rejects when absent.
        let fileExists = true;
        try {
            await access(filePath);
        }
        catch {
            fileExists = false;
        }
        await safeSendNotification(state.connection, "workspace/didChangeWatchedFiles", { changes: [{ uri, type: fileExists ? 2 : 1 }] });
    }
    if (!isClientAlive(state))
        return;
    await safeSendNotification(state.connection, "textDocument/didOpen", {
        textDocument: { uri, languageId, version: 0, text: content },
    });
    state.pendingOpens.delete(normalizedPath);
    state.openDocuments.add(normalizedPath);
}
export async function handleNotifyChange(state, filePath, content) {
    if (!isClientAlive(state))
        return;
    const uri = pathToFileURL(filePath).href;
    const normalizedPath = normalizeMapKey(filePath);
    if (!state.openDocuments.has(normalizedPath)) {
        // Safety fallback: keep protocol ordering valid even if caller sends
        // didChange before first didOpen for this document.
        await safeSendNotification(state.connection, "textDocument/didOpen", {
            textDocument: { uri, languageId: "plaintext", version: 0, text: content },
        });
        state.documentVersions.set(normalizedPath, 0);
        state.openDocuments.add(normalizedPath);
        return;
    }
    const version = (state.documentVersions.get(normalizedPath) ?? 0) + 1;
    state.documentVersions.set(normalizedPath, version);
    // Clear stale diagnostics before sending new content so waitForDiagnostics
    // doesn't return immediately with the previous edit's results.
    clearDiagnosticsForPath(state, normalizedPath);
    await safeSendNotification(state.connection, "textDocument/didChange", {
        textDocument: { uri, version },
        contentChanges: [{ text: content }],
    });
}
export async function clientShutdown(state, options = {}) {
    state.isConnected = false;
    state.isDestroyed = true;
    for (const timer of state.pendingDiagnostics.values()) {
        clearTimeout(timer);
    }
    state.pendingDiagnostics.clear();
    state.pendingOpens.clear();
    state.openDocuments.clear();
    state.diagnosticEmitter.removeAllListeners();
    if (!options.fast) {
        try {
            await withTimeout(safeSendRequest(state.connection, "shutdown", {}), SHUTDOWN_REQUEST_TIMEOUT_MS);
        }
        catch {
            /* ignore — proceed to exit/kill so shutdown cannot hang the session */
        }
        try {
            await safeSendNotification(state.connection, "exit", {});
        }
        catch {
            /* ignore */
        }
    }
    disposeClientConnection(state);
    const pid = state.lspProcess.pid;
    // On Windows, killing the direct child first can orphan grandchildren before
    // taskkill can traverse the tree. Kill the full tree first and wait briefly.
    await killProcessTree(state.lspProcess.process, pid, options);
}
async function navRequest(state, method, params) {
    if (!isClientAlive(state))
        return null;
    return withTimeout(safeSendRequest(state.connection, method, params), NAV_REQUEST_TIMEOUT_MS).catch((err) => {
        if (err instanceof Error && err.message.startsWith("Timeout after")) {
            return undefined;
        }
        throw err;
    });
}
async function resolveCodeActionBestEffort(state, action) {
    if (!isClientAlive(state) || action.edit)
        return action;
    try {
        const resolved = await withTimeout(safeSendRequest(state.connection, "codeAction/resolve", action), NAV_REQUEST_TIMEOUT_MS);
        if (!resolved || typeof resolved !== "object")
            return action;
        return { ...action, ...resolved };
    }
    catch {
        // codeAction/resolve is optional. Keep the original lightweight action when
        // the server does not support resolve or fails to populate an edit.
        return action;
    }
}
// --- Client Factory ---
export async function createLSPClient(options) {
    installCrashGuard();
    const { serverId, process: lspProcess, root, initialization, initializeTimeoutMs = INITIALIZE_TIMEOUT_MS, } = options;
    const startupState = {
        exitCode: null,
        exitSignal: null,
        closeCode: null,
        closeSignal: null,
        stderr: "",
    };
    // Persistent stderr ring buffer — captures last ~100 lines for diagnostics.
    // Used in error messages to show what the server said before dying.
    const stderrRing = [];
    const MAX_STDERR_LINES = 100;
    const onStderr = (chunk) => {
        stderrRing.push(chunk.toString());
        if (stderrRing.length > MAX_STDERR_LINES)
            stderrRing.shift();
        // Also capture startup stderr for the initialized-failed error path
        if (startupState.stderr.length < 4096) {
            startupState.stderr += chunk.toString();
        }
    };
    const recentStderr = (lines = 10) => stderrRing.slice(-lines).join("").trim();
    // Pre-request health check — returns error string if process is dead.
    const checkProcessAlive = () => {
        const exited = lspProcess.process.exitCode;
        if (exited !== null) {
            const tail = recentStderr(20);
            return `LSP server ${serverId} exited with code ${exited}${tail ? `. stderr: ${tail}` : ""}`;
        }
        if (lspProcess.process.killed) {
            return `LSP server ${serverId} was killed`;
        }
        return undefined;
    };
    const onProcessExit = (code, signal) => {
        startupState.exitCode = code;
        startupState.exitSignal = signal;
    };
    const onProcessClose = (code, signal) => {
        startupState.closeCode = code;
        startupState.closeSignal = signal;
    };
    lspProcess.stderr.on("data", onStderr);
    lspProcess.process.on("exit", onProcessExit);
    lspProcess.process.on("close", onProcessClose);
    // Attach persistent 'error' listeners to all three stdio streams.
    //
    // Why: when the LSP process exits, Node.js destroys its stdio streams and
    // may emit 'error' (ERR_STREAM_DESTROYED / EPIPE / ECONNRESET) on them.
    // Without a listener that becomes an uncaught exception.
    //
    // vscode-jsonrpc covers stdin/stdout during the connection lifetime but
    // removes its listeners on dispose(). Our permanent listeners cover the gap.
    const streamErrorHandler = (_label) => (err) => {
        if (err.code === "ERR_STREAM_DESTROYED" ||
            err.code === "ERR_STREAM_WRITE_AFTER_END" ||
            err.code === "EPIPE" ||
            err.code === "ECONNRESET")
            return;
    };
    lspProcess.stdin.on("error", streamErrorHandler("stdin"));
    lspProcess.stdout.on("error", streamErrorHandler("stdout"));
    lspProcess.stderr.on("error", streamErrorHandler("stderr"));
    const connection = createMessageConnection(new StreamMessageReader(lspProcess.stdout), new StreamMessageWriter(lspProcess.stdin));
    // Local event emitter — signals waitForDiagnostics when new diagnostics arrive.
    // Scoped to this client instance. setMaxListeners guards against Node.js warning
    // for concurrent waitForDiagnostics calls.
    const diagnosticEmitter = new EventEmitter();
    diagnosticEmitter.setMaxListeners(50);
    const state = {
        isConnected: true,
        isDestroyed: false,
        connectionDisposed: false,
        lastError: undefined,
        connection,
        pushDiagnostics: new Map(),
        pushDiagnosticTimestamps: new Map(),
        documentPullDiagnostics: new Map(),
        documentPullDiagnosticTimestamps: new Map(),
        pendingDiagnostics: new Map(),
        diagnosticEmitter,
        diagnosticsVersion: 0,
        documentVersions: new Map(),
        diagnosticDocVersions: new Map(),
        openDocuments: new Set(),
        pendingOpens: new Set(),
        // these are filled in after initialize — cast to avoid two-phase init
        workspaceDiagnosticsSupport: undefined,
        operationSupport: undefined,
        staticDiagnosticsMode: "push-only",
        dynamicRegistrations: new Map(),
        serverId,
        root,
        lspProcess,
    };
    setupIncomingHandlers(state, initialization);
    connection.listen();
    setupConnectionLifecycle(state);
    let initResult;
    try {
        initResult = await withTimeout(safeSendRequest(connection, "initialize", {
            processId: process.pid,
            rootUri: pathToFileURL(root).href,
            workspaceFolders: [
                { name: "workspace", uri: pathToFileURL(root).href },
            ],
            capabilities: {
                window: { workDoneProgress: true },
                workspace: {
                    workspaceFolders: true,
                    configuration: true,
                    didChangeWatchedFiles: { dynamicRegistration: true },
                },
                textDocument: {
                    synchronization: { didOpen: true, didChange: true },
                    publishDiagnostics: { versionSupport: true },
                },
            },
            initializationOptions: initialization,
        }), initializeTimeoutMs);
    }
    catch (err) {
        // Hard-kill the hung process so it doesn't become a zombie.
        // SIGTERM alone is unreliable on Windows for cmd.exe/PowerShell trees.
        const pid = lspProcess.pid;
        void killProcessTree(lspProcess.process, pid);
        setTimeout(() => {
            if (!lspProcess.process.killed && process.platform !== "win32") {
                lspProcess.process.kill("SIGKILL");
            }
        }, 2000);
        throw err;
    }
    finally {
        lspProcess.stderr.off("data", onStderr);
    }
    if (initResult === undefined) {
        const compactStderr = startupState.stderr
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 320);
        const reinstallHint = serverId === "cpp"
            ? "Install clangd (LLVM/clang-tools) and ensure clangd.exe is on PATH."
            : `Try reinstalling: npm install -g ${serverId}-language-server.`;
        const telemetry = [
            `pid=${lspProcess.pid}`,
            `exitCode=${startupState.exitCode ?? "none"}`,
            `exitSignal=${startupState.exitSignal ?? "none"}`,
            `closeCode=${startupState.closeCode ?? "none"}`,
            `closeSignal=${startupState.closeSignal ?? "none"}`,
            `root=${root}`,
            compactStderr ? `stderr=${compactStderr}` : "stderr=<empty>",
        ].join(" ");
        throw new Error(`[lsp] ${serverId} failed to initialize - stream may have been destroyed. ` +
            `The server binary may be missing or crashed immediately. ${reinstallHint} ` +
            `telemetry: ${telemetry}`);
    }
    state.workspaceDiagnosticsSupport =
        detectWorkspaceDiagnosticsSupport(initResult);
    state.operationSupport = detectOperationSupport(initResult);
    state.staticDiagnosticsMode = state.workspaceDiagnosticsSupport.mode;
    await safeSendNotification(connection, "initialized", {});
    if (initialization) {
        await safeSendNotification(connection, "workspace/didChangeConfiguration", {
            settings: initialization,
        });
    }
    return {
        serverId,
        root,
        connection,
        isAlive: () => isClientAlive(state),
        /** True if the server process has exited or been killed. */
        processExited: () => lspProcess.process.exitCode !== null ||
            lspProcess.process.killed === true,
        /** Last N lines of server stderr for diagnostics. */
        recentStderr: (lines) => recentStderr(lines),
        /** Pre-request health check — returns error string if dead. */
        checkAlive: () => checkProcessAlive(),
        notify: {
            async open(filePath, content, languageId, preserveDiagnostics, silent) {
                return handleNotifyOpen(state, filePath, content, languageId, preserveDiagnostics, silent);
            },
            async change(filePath, content) {
                return handleNotifyChange(state, filePath, content);
            },
        },
        getDiagnostics(filePath) {
            return getMergedDiagnosticsForPath(state, normalizeMapKey(filePath));
        },
        getAllDiagnostics() {
            const result = new Map();
            const keys = new Set([
                ...state.pushDiagnostics.keys(),
                ...state.documentPullDiagnostics.keys(),
            ]);
            for (const key of keys) {
                result.set(key, {
                    diags: getMergedDiagnosticsForPath(state, key),
                    ts: Math.max(state.pushDiagnosticTimestamps.get(key) ?? 0, state.documentPullDiagnosticTimestamps.get(key) ?? 0),
                });
            }
            return result;
        },
        getTrackedDiagnosticPaths() {
            return [
                ...new Set([
                    ...state.pushDiagnostics.keys(),
                    ...state.documentPullDiagnostics.keys(),
                ]),
            ];
        },
        pruneDiagnostics(predicate) {
            let removed = 0;
            const keys = new Set([
                ...state.pushDiagnostics.keys(),
                ...state.documentPullDiagnostics.keys(),
            ]);
            for (const key of keys) {
                const diags = getMergedDiagnosticsForPath(state, key);
                const ts = Math.max(state.pushDiagnosticTimestamps.get(key) ?? 0, state.documentPullDiagnosticTimestamps.get(key) ?? 0);
                if (!predicate(key, ts, diags))
                    continue;
                clearDiagnosticsForPath(state, key);
                removed++;
            }
            return removed;
        },
        getWorkspaceDiagnosticsSupport() {
            return state.workspaceDiagnosticsSupport;
        },
        getOperationSupport() {
            return state.operationSupport;
        },
        get diagnosticsVersion() {
            return state.diagnosticsVersion;
        },
        async waitForDiagnostics(filePath, timeoutMs = DIAGNOSTICS_WAIT_TIMEOUT_MS, options) {
            return clientWaitForDiagnostics(state, filePath, timeoutMs, options);
        },
        async definition(filePath, line, character) {
            const result = await navRequest(state, "textDocument/definition", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
            });
            if (!result)
                return [];
            return Array.isArray(result) ? result : [result];
        },
        async references(filePath, line, character, includeDeclaration = true) {
            const result = await navRequest(state, "textDocument/references", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
                context: { includeDeclaration },
            });
            return result ?? [];
        },
        async hover(filePath, line, character) {
            const result = await navRequest(state, "textDocument/hover", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
            });
            return result ?? null;
        },
        async signatureHelp(filePath, line, character) {
            const result = await navRequest(state, "textDocument/signatureHelp", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
            });
            return result ?? null;
        },
        async documentSymbol(filePath) {
            const result = await navRequest(state, "textDocument/documentSymbol", { textDocument: { uri: pathToFileURL(filePath).href } });
            return result ?? [];
        },
        async workspaceSymbol(query) {
            if (!isClientAlive(state))
                return [];
            const result = await safeSendRequest(connection, "workspace/symbol", { query });
            return result ?? [];
        },
        async codeAction(filePath, line, character, endLine, endCharacter) {
            if (!isClientAlive(state))
                return [];
            const uri = pathToFileURL(filePath).href;
            const result = await safeSendRequest(connection, "textDocument/codeAction", {
                textDocument: { uri },
                range: {
                    start: { line, character },
                    end: { line: endLine, character: endCharacter },
                },
                context: {
                    diagnostics: getMergedDiagnosticsForPath(state, normalizeMapKey(filePath)),
                },
            });
            if (!result || !Array.isArray(result))
                return [];
            const actions = result.filter((item) => typeof item === "object" && item !== null && "title" in item);
            return Promise.all(actions.map((action) => resolveCodeActionBestEffort(state, action)));
        },
        async rename(filePath, line, character, newName) {
            const result = await navRequest(state, "textDocument/rename", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
                newName,
            });
            return result ?? null;
        },
        async willRenameFiles(oldFilePath, newFilePath) {
            const result = await navRequest(state, "workspace/willRenameFiles", {
                files: [
                    {
                        oldUri: pathToFileURL(oldFilePath).href,
                        newUri: pathToFileURL(newFilePath).href,
                    },
                ],
            });
            return result ?? null;
        },
        async didRenameFiles(oldFilePath, newFilePath) {
            if (!isClientAlive(state))
                return;
            await safeSendNotification(state.connection, "workspace/didRenameFiles", {
                files: [
                    {
                        oldUri: pathToFileURL(oldFilePath).href,
                        newUri: pathToFileURL(newFilePath).href,
                    },
                ],
            });
        },
        async implementation(filePath, line, character) {
            const result = await navRequest(state, "textDocument/implementation", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
            });
            if (!result)
                return [];
            return Array.isArray(result) ? result : [result];
        },
        async prepareCallHierarchy(filePath, line, character) {
            const result = await navRequest(state, "textDocument/prepareCallHierarchy", {
                textDocument: { uri: pathToFileURL(filePath).href },
                position: { line, character },
            });
            if (!result)
                return [];
            return Array.isArray(result) ? result : [result];
        },
        async incomingCalls(item) {
            const result = await navRequest(state, "callHierarchy/incomingCalls", { item });
            return result ?? [];
        },
        async outgoingCalls(item) {
            const result = await navRequest(state, "callHierarchy/outgoingCalls", { item });
            return result ?? [];
        },
        async shutdown(options) {
            return clientShutdown(state, options);
        },
    };
}
// Helper to safely send notifications - catches stream destruction
async function safeSendNotification(connection, method, params) {
    try {
        await connection.sendNotification(method, params);
    }
    catch (err) {
        if (isStreamError(err)) {
            // Silently ignore - stream was destroyed, connection error handlers will update state
            return;
        }
        throw err;
    }
}
// Helper to safely send requests - catches stream destruction
async function safeSendRequest(connection, method, params) {
    try {
        return (await connection.sendRequest(method, params));
    }
    catch (err) {
        if (isStreamError(err)) {
            // Silently ignore - stream was destroyed
            return undefined;
        }
        throw err;
    }
}
// Helper to detect stream destruction / connection disposal errors.
// vscode-jsonrpc throws these when the LSP server process exits while
// requests are still in flight:
//   "Connection is disposed."
//   "Pending response rejected since connection got disposed"
// Neither phrase contains "stream", "destroyed", or "closed", which is
// why we must also match "disposed" and "cancelled" here.
function isStreamError(err) {
    if (!(err instanceof Error))
        return false;
    const msg = err.message.toLowerCase();
    return (msg.includes("stream") ||
        msg.includes("destroyed") ||
        msg.includes("closed") ||
        msg.includes("disposed") ||
        msg.includes("cancelled") ||
        err.code === "ERR_STREAM_DESTROYED" ||
        err.code === "ERR_STREAM_WRITE_AFTER_END" ||
        err.code === "EPIPE");
}
// Using shared path utilities from path-utils.ts
async function withTimeout(promise, timeoutMs) {
    let timeout;
    // Suppress unhandled rejection if `promise` rejects AFTER the timeout
    // wins the race — Promise.race settles on the first result but the
    // losing promises still run, and any later rejection would be uncaught.
    promise.catch(() => { });
    try {
        return await Promise.race([
            promise,
            new Promise((_, reject) => {
                timeout = setTimeout(() => reject(new Error(`Timeout after ${timeoutMs}ms`)), timeoutMs);
            }),
        ]);
    }
    finally {
        if (timeout)
            clearTimeout(timeout);
    }
}
function positiveIntFromEnv(name, fallback) {
    const raw = process.env[name];
    if (!raw)
        return fallback;
    const parsed = Number.parseInt(raw, 10);
    if (!Number.isFinite(parsed) || parsed <= 0)
        return fallback;
    return parsed;
}
function detectWorkspaceDiagnosticsSupport(initResult) {
    const capabilities = typeof initResult === "object" && initResult !== null
        ? initResult.capabilities
        : undefined;
    const diagnosticProvider = capabilities?.diagnosticProvider;
    if (!diagnosticProvider) {
        return {
            advertised: false,
            mode: "push-only",
            diagnosticProviderKind: "none",
        };
    }
    if (typeof diagnosticProvider === "boolean") {
        return {
            advertised: diagnosticProvider,
            mode: diagnosticProvider ? "pull" : "push-only",
            diagnosticProviderKind: "boolean",
        };
    }
    if (typeof diagnosticProvider === "object") {
        return {
            advertised: true,
            mode: "pull",
            diagnosticProviderKind: "object",
        };
    }
    return {
        advertised: false,
        mode: "push-only",
        diagnosticProviderKind: typeof diagnosticProvider,
    };
}
function detectOperationSupport(initResult) {
    const capabilities = typeof initResult === "object" && initResult !== null
        ? initResult.capabilities
        : undefined;
    const hasProvider = (key) => {
        const value = capabilities?.[key];
        if (value === undefined || value === null)
            return false;
        if (typeof value === "boolean")
            return value;
        return true;
    };
    return {
        definition: hasProvider("definitionProvider"),
        references: hasProvider("referencesProvider"),
        hover: hasProvider("hoverProvider"),
        signatureHelp: hasProvider("signatureHelpProvider"),
        documentSymbol: hasProvider("documentSymbolProvider"),
        workspaceSymbol: hasProvider("workspaceSymbolProvider"),
        codeAction: hasProvider("codeActionProvider"),
        rename: hasProvider("renameProvider"),
        implementation: hasProvider("implementationProvider"),
        callHierarchy: hasProvider("callHierarchyProvider"),
    };
}
