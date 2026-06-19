import * as fs from "node:fs";
import * as path from "node:path";
import { isTestMode } from "./env-utils.js";
import { getGlobalPiLensDir } from "./file-utils.js";
const CASCADE_LOG_DIR = getGlobalPiLensDir();
const CASCADE_LOG_FILE = path.join(CASCADE_LOG_DIR, "cascade.log");
try {
    if (!fs.existsSync(CASCADE_LOG_DIR)) {
        fs.mkdirSync(CASCADE_LOG_DIR, { recursive: true });
    }
}
catch { }
export function logCascade(entry) {
    if (isTestMode()) {
        return;
    }
    const line = `${JSON.stringify({ ts: new Date().toISOString(), ...entry })}\n`;
    try {
        fs.appendFileSync(CASCADE_LOG_FILE, line);
    }
    catch { }
}
export function getCascadeLogPath() {
    return CASCADE_LOG_FILE;
}
