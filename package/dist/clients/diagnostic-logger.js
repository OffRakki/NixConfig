/**
 * Diagnostic Logger — append-only JSONL log for cross-session analytics
 *
 * Log file: ~/.pi-lens/logs/{date}.jsonl
 */
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { isTestMode } from "./env-utils.js";
function getLogDir() {
    const home = os.homedir();
    const logDir = path.join(home, ".pi-lens", "logs");
    if (!fs.existsSync(logDir)) {
        fs.mkdirSync(logDir, { recursive: true });
    }
    return logDir;
}
function getLogFile() {
    const date = new Date().toISOString().split("T")[0];
    return path.join(getLogDir(), `${date}.jsonl`);
}
// Module-level singleton — persists across all writes
let _logger = null;
export function getDiagnosticLogger() {
    if (!_logger) {
        _logger = createDiagnosticLogger();
    }
    return _logger;
}
export function createDiagnosticLogger() {
    const pending = [];
    let writing = false;
    const writePending = async () => {
        if (writing || pending.length === 0)
            return;
        writing = true;
        const toWrite = pending.splice(0, pending.length);
        const lines = toWrite.map((e) => JSON.stringify(e)).join("\n") + "\n";
        try {
            await fs.promises.appendFile(getLogFile(), lines);
        }
        catch (err) {
            // pi-lens-ignore: missing-error-propagation — fire-and-forget log write, must not throw
            console.error("Failed to write diagnostic log:", err);
        }
        writing = false;
    };
    return {
        log(entry) {
            if (isTestMode()) {
                return;
            }
            pending.push(entry);
            writePending(); // async, non-blocking
        },
        logCaught(d, context, shownInline = false) {
            this.log({
                timestamp: new Date().toISOString(),
                tool: d.tool || "unknown",
                ruleId: d.rule || d.id || "unknown",
                severity: d.severity || "warning",
                language: d.language || "unknown",
                filePath: d.filePath,
                line: d.line || 1,
                column: d.column || 1,
                message: d.message || "",
                caughtByPipeline: true,
                shownInline,
                autoFixed: false,
                shownToAgent: shownInline,
                agentFixed: false,
                unresolved: true,
                model: context.model,
                sessionId: context.sessionId,
                turnIndex: context.turnIndex,
                writeIndex: context.writeIndex,
            });
        },
        async flush() {
            // Drain any buffered entries, then wait for the write to finish.
            await writePending();
            while (writing) {
                await new Promise((resolve) => setTimeout(resolve, 10));
            }
        },
    };
}
