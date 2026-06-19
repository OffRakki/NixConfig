import { randomBytes } from "node:crypto";
import * as path from "node:path";
import { normalizeMapKey } from "./path-utils.js";
import { ReadGuard } from "./read-guard.js";
import { RUNTIME_CONFIG } from "./runtime-config.js";
export class RuntimeCoordinator {
    _projectRoot = normalizeMapKey(process.cwd());
    _sessionGeneration = 0;
    _sessionStartedAt = Date.now();
    _errorDebtBaseline = null;
    _pipelineCrashCounts = new Map();
    _cachedExports = new Map();
    _startupScansInFlight = new Map();
    _cascadeRuns = [];
    _cascadeSessionStats = {
        runs: 0,
        diagnosticsSurfaced: 0,
        coldSnapshotTouches: 0,
    };
    _complexityBaselines = new Map();
    _fixedThisTurn = new Set();
    _reportedThisTurn = new Set();
    _projectRulesScan = {
        rules: [],
        hasCustomRules: false,
    };
    _telemetrySessionId = `lens-${Date.now().toString(36)}`;
    _lifecycleReason;
    _hasStableSessionId = false;
    _telemetryModel = "unknown";
    _turnIndex = 0;
    _writeIndex = 0;
    _projectSeq = 0;
    _turnStartProjectSeq = 0;
    _fileSeq = new Map();
    _gitGuardHasBlockers = false;
    _gitGuardSummary = "";
    callGraph = null;
    wordIndex = null;
    _readGuard = null;
    _pendingDeferredFormatFiles = new Map();
    _lspReadWarmState = new Map();
    _pendingInlineBlockers = new Map();
    _actionableWarningsThisTurn = new Map();
    _codeQualityWarningsThisTurn = new Map();
    resetForSession() {
        this._sessionGeneration += 1;
        this._sessionStartedAt = Date.now();
        this._complexityBaselines.clear();
        this._pipelineCrashCounts.clear();
        this._cachedExports.clear();
        this.wordIndex = null;
        this._startupScansInFlight.clear();
        this._cascadeRuns = [];
        this._cascadeSessionStats = {
            runs: 0,
            diagnosticsSurfaced: 0,
            coldSnapshotTouches: 0,
        };
        this._fixedThisTurn.clear();
        this._reportedThisTurn.clear();
        this._telemetrySessionId = `lens-${Date.now().toString(36)}-${randomBytes(4).toString("hex")}`;
        this._hasStableSessionId = false;
        this._telemetryModel = "unknown";
        this._turnIndex = 0;
        this._writeIndex = 0;
        this._projectSeq = 0;
        this._turnStartProjectSeq = 0;
        this._fileSeq.clear();
        this._gitGuardHasBlockers = false;
        this._gitGuardSummary = "";
        this._readGuard = null;
        this._pendingDeferredFormatFiles.clear();
        this._lspReadWarmState.clear();
        this._pendingInlineBlockers.clear();
        this._actionableWarningsThisTurn.clear();
        this._codeQualityWarningsThisTurn.clear();
    }
    get sessionStartedAt() {
        return this._sessionStartedAt;
    }
    get cascadeSessionStats() {
        return this._cascadeSessionStats;
    }
    recordCascadeRun(diagnosticsSurfaced, coldSnapshotTouches) {
        this._cascadeSessionStats.runs += 1;
        this._cascadeSessionStats.diagnosticsSurfaced += diagnosticsSurfaced;
        this._cascadeSessionStats.coldSnapshotTouches += coldSnapshotTouches;
    }
    updateGitGuardStatus(hasBlockers, output) {
        this._gitGuardHasBlockers = hasBlockers;
        if (!hasBlockers) {
            this._gitGuardSummary = "";
            return;
        }
        const firstLine = output
            .split("\n")
            .map((line) => line.trim())
            .find((line) => line.length > 0);
        this._gitGuardSummary = (firstLine ?? "Unresolved blockers detected").slice(0, 160);
    }
    get gitGuardHasBlockers() {
        return this._gitGuardHasBlockers;
    }
    get gitGuardSummary() {
        return this._gitGuardSummary;
    }
    beginTurn() {
        this._cascadeRuns = [];
        this._pendingInlineBlockers.clear();
        this._actionableWarningsThisTurn.clear();
        this._codeQualityWarningsThisTurn.clear();
        this._turnStartProjectSeq = this._projectSeq;
        this._turnIndex += 1;
        this._writeIndex = 0;
        this._reportedThisTurn.clear();
    }
    get reportedThisTurn() {
        return this._reportedThisTurn;
    }
    nextWriteIndex() {
        this._writeIndex += 1;
        return this._writeIndex;
    }
    peekWriteIndex() {
        return this._writeIndex;
    }
    setTelemetryIdentity(identity) {
        if (identity.sessionId && identity.sessionId.trim()) {
            this._telemetrySessionId = identity.sessionId.trim();
        }
        const model = identity.model?.trim();
        const provider = identity.provider?.trim();
        if (model && provider) {
            this._telemetryModel = `${provider}/${model}`;
        }
        else if (model) {
            this._telemetryModel = model;
        }
        else if (provider) {
            this._telemetryModel = provider;
        }
    }
    get telemetrySessionId() {
        return this._telemetrySessionId;
    }
    /**
     * Pin the session identity to pi's STABLE session id and record why this
     * session started (#190). Called AFTER {@link resetForSession} (which assigns
     * a fresh random id), so the stable id — when pi provides one via
     * `ctx.sessionManager.getSessionId()` — wins and survives a quit→resume.
     */
    setSessionLifecycle(args) {
        if (args.sessionId && args.sessionId.trim()) {
            this._telemetrySessionId = args.sessionId.trim();
            this._hasStableSessionId = true;
        }
        this._lifecycleReason = args.reason;
    }
    /** Why the current session started: new | resume | fork | reload | startup. */
    get sessionLifecycleReason() {
        return this._lifecycleReason;
    }
    /** True once a stable pi session id has been pinned (vs the random fallback). */
    get hasStableSessionId() {
        return this._hasStableSessionId;
    }
    get telemetryModel() {
        return this._telemetryModel;
    }
    get turnIndex() {
        return this._turnIndex;
    }
    get projectSeq() {
        return this._projectSeq;
    }
    get turnStartProjectSeq() {
        return this._turnStartProjectSeq;
    }
    seedProjectSequence(projectSeq, fileSeqByPath) {
        this._projectSeq = Math.max(0, Math.floor(projectSeq));
        this._turnStartProjectSeq = this._projectSeq;
        this._fileSeq.clear();
        for (const [filePath, seq] of fileSeqByPath ?? []) {
            this._fileSeq.set(normalizeMapKey(path.resolve(filePath)), Math.max(0, seq));
        }
    }
    bumpFileSeq(filePath) {
        const key = normalizeMapKey(path.resolve(filePath));
        this._projectSeq += 1;
        const fileSeq = (this._fileSeq.get(key) ?? 0) + 1;
        this._fileSeq.set(key, fileSeq);
        return { projectSeq: this._projectSeq, fileSeq };
    }
    getFileSeq(filePath) {
        return this._fileSeq.get(normalizeMapKey(path.resolve(filePath))) ?? 0;
    }
    getFileSeqEntries() {
        return [...this._fileSeq.entries()];
    }
    get sessionGeneration() {
        return this._sessionGeneration;
    }
    isCurrentSession(generation) {
        return this._sessionGeneration === generation;
    }
    markStartupScanInFlight(name, generation) {
        this._startupScansInFlight.set(name, generation);
    }
    clearStartupScanInFlight(name, generation) {
        const owner = this._startupScansInFlight.get(name);
        if (owner === generation) {
            this._startupScansInFlight.delete(name);
        }
    }
    isStartupScanInFlight(name) {
        return this._startupScansInFlight.has(name);
    }
    formatPipelineCrashNotice(filePath, err) {
        const key = path.resolve(filePath);
        const count = (this._pipelineCrashCounts.get(key) ?? 0) + 1;
        this._pipelineCrashCounts.set(key, count);
        const message = err instanceof Error ? err.message : String(err);
        const shortMessage = message.split("\n")[0].slice(0, 220);
        const shouldSurface = count <= RUNTIME_CONFIG.crashNotice.alwaysShowFirstN ||
            count % RUNTIME_CONFIG.crashNotice.showEveryNth === 0;
        if (!shouldSurface)
            return "";
        return [
            "⚠️ pi-lens pipeline crashed while analyzing this write.",
            `File: ${path.basename(filePath)} | crash count this session: ${count}`,
            `Error: ${shortMessage}`,
            "Recovery: LSP service was reset. If this repeats, rerun with --no-lsp and report the file + stack.",
        ].join("\n");
    }
    getCrashEntries() {
        return Array.from(this._pipelineCrashCounts.entries());
    }
    get projectRoot() {
        return this._projectRoot;
    }
    set projectRoot(value) {
        this._projectRoot = normalizeMapKey(value);
    }
    get errorDebtBaseline() {
        return this._errorDebtBaseline;
    }
    set errorDebtBaseline(value) {
        this._errorDebtBaseline = value;
    }
    get cachedExports() {
        return this._cachedExports;
    }
    appendCascadeRun(run) {
        this._cascadeRuns.push(run);
    }
    consumeCascadeRuns() {
        const runs = this._cascadeRuns;
        this._cascadeRuns = [];
        return runs;
    }
    recordInlineBlockers(filePath, summary) {
        this._pendingInlineBlockers.set(path.resolve(filePath), {
            filePath,
            summary,
        });
    }
    clearInlineBlockers(filePath) {
        this._pendingInlineBlockers.delete(path.resolve(filePath));
    }
    consumeInlineBlockers() {
        const entries = [...this._pendingInlineBlockers.values()];
        this._pendingInlineBlockers.clear();
        return entries;
    }
    recordActionableWarnings(warnings) {
        for (const warning of warnings) {
            this._actionableWarningsThisTurn.set(warning.id, warning);
        }
    }
    peekActionableWarnings() {
        return [...this._actionableWarningsThisTurn.values()];
    }
    clearActionableWarnings() {
        this._actionableWarningsThisTurn.clear();
    }
    recordCodeQualityWarnings(warnings) {
        for (const warning of warnings) {
            this._codeQualityWarningsThisTurn.set(warning.id, warning);
        }
    }
    peekCodeQualityWarnings() {
        return [...this._codeQualityWarningsThisTurn.values()];
    }
    clearCodeQualityWarnings() {
        this._codeQualityWarningsThisTurn.clear();
    }
    get complexityBaselines() {
        return this._complexityBaselines;
    }
    get fixedThisTurn() {
        return this._fixedThisTurn;
    }
    get projectRulesScan() {
        return this._projectRulesScan;
    }
    set projectRulesScan(value) {
        this._projectRulesScan = value;
    }
    get readGuard() {
        this._readGuard ??= new ReadGuard(this._telemetrySessionId);
        return this._readGuard;
    }
    deferFormat(filePath, cwd, toolName, turnStateCwd) {
        const key = path.resolve(filePath);
        const now = Date.now();
        const existing = this._pendingDeferredFormatFiles.get(key);
        if (existing) {
            existing.lastTouchedAt = now;
            existing.cwd = cwd;
            existing.turnStateCwd = turnStateCwd;
            existing.toolNames.add(toolName);
            return;
        }
        this._pendingDeferredFormatFiles.set(key, {
            filePath: key,
            cwd,
            turnStateCwd,
            firstTouchedAt: now,
            lastTouchedAt: now,
            toolNames: new Set([toolName]),
        });
    }
    get pendingDeferredFormatCount() {
        return this._pendingDeferredFormatFiles.size;
    }
    consumeDeferredFormatFiles() {
        const records = [...this._pendingDeferredFormatFiles.values()];
        this._pendingDeferredFormatFiles.clear();
        return records;
    }
    shouldWarmLspOnRead(filePath, maxAgeMs = 120_000) {
        const state = this._lspReadWarmState.get(path.resolve(filePath));
        if (!state)
            return true;
        if (state.status === "warming")
            return false;
        return Date.now() - state.ts > maxAgeMs;
    }
    markLspReadWarmStarted(filePath) {
        this._lspReadWarmState.set(path.resolve(filePath), {
            status: "warming",
            ts: Date.now(),
        });
    }
    markLspReadWarmCompleted(filePath) {
        this._lspReadWarmState.set(path.resolve(filePath), {
            status: "ready",
            ts: Date.now(),
        });
    }
    clearLspReadWarmState(filePath) {
        this._lspReadWarmState.delete(path.resolve(filePath));
    }
}
