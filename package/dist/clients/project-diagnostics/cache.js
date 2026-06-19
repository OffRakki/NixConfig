import * as fs from "node:fs";
import * as path from "node:path";
import { getProjectDataDir } from "../file-utils.js";
export const PROJECT_DIAGNOSTICS_CACHE_VERSION = 1;
const SNAPSHOT_CACHE_FILE = "project-diagnostics.json";
const DELTA_CACHE_FILE = "project-diagnostics-delta.json";
function cachePath(cwd, fileName) {
    return path.join(getProjectDataDir(cwd), "cache", fileName);
}
export function loadProjectDiagnosticsSnapshot(cwd) {
    try {
        const parsed = JSON.parse(fs.readFileSync(cachePath(cwd, SNAPSHOT_CACHE_FILE), "utf-8"));
        if (!parsed || typeof parsed !== "object")
            return undefined;
        const snapshot = parsed;
        if (snapshot.version !== PROJECT_DIAGNOSTICS_CACHE_VERSION)
            return undefined;
        if (!Array.isArray(snapshot.diagnostics))
            return undefined;
        return snapshot;
    }
    catch {
        return undefined;
    }
}
export function saveProjectDiagnosticsSnapshot(cwd, snapshot) {
    const filePath = cachePath(cwd, SNAPSHOT_CACHE_FILE);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(snapshot, null, 2));
}
export function loadProjectDiagnosticsDeltaReport(cwd) {
    try {
        const parsed = JSON.parse(fs.readFileSync(cachePath(cwd, DELTA_CACHE_FILE), "utf-8"));
        if (!parsed || typeof parsed !== "object")
            return undefined;
        const report = parsed;
        if (report.version !== PROJECT_DIAGNOSTICS_CACHE_VERSION)
            return undefined;
        if (!Array.isArray(report.diagnostics))
            return undefined;
        return report;
    }
    catch {
        return undefined;
    }
}
export function writeProjectDiagnosticsDeltaReport(cwd, report) {
    const filePath = cachePath(cwd, DELTA_CACHE_FILE);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(report, null, 2));
}
