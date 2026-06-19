import * as fs from "node:fs";
import * as path from "node:path";
import { isTestMode } from "./env-utils.js";
import { getGlobalPiLensDir } from "./file-utils.js";
const LATENCY_LOG_DIR = getGlobalPiLensDir();
const LATENCY_LOG_FILE = path.join(LATENCY_LOG_DIR, "latency.log");
try {
    if (!fs.existsSync(LATENCY_LOG_DIR)) {
        fs.mkdirSync(LATENCY_LOG_DIR, { recursive: true });
    }
}
catch { }
export function logLatency(entry) {
    if (isTestMode()) {
        return;
    }
    const line = `${JSON.stringify({ ts: new Date().toISOString(), ...entry })}\n`;
    try {
        fs.appendFileSync(LATENCY_LOG_FILE, line);
    }
    catch { }
}
export function getLatencyLogPath() {
    return LATENCY_LOG_FILE;
}
export function readLatencyLog(limit = 100) {
    try {
        const content = fs.readFileSync(LATENCY_LOG_FILE, "utf-8");
        const lines = content.trim().split(/\r?\n/).filter(Boolean);
        return lines
            .slice(-limit)
            .map((line) => JSON.parse(line))
            .reverse();
    }
    catch {
        return [];
    }
}
export function clearLatencyLog() {
    try {
        fs.writeFileSync(LATENCY_LOG_FILE, "");
    }
    catch { }
}
