import * as fs from "node:fs";
import * as path from "node:path";
import { getProjectDataDir } from "./file-utils.js";
import { walkUpDirs } from "./path-utils.js";
export const LOCAL_SEMGREP_CONFIG_NAMES = [
    ".semgrep.yml",
    ".semgrep.yaml",
    "semgrep.yml",
    "semgrep.yaml",
];
export function findLocalSemgrepConfig(startDir) {
    for (const dir of walkUpDirs(startDir || process.cwd())) {
        for (const name of LOCAL_SEMGREP_CONFIG_NAMES) {
            const candidate = path.join(dir, name);
            if (fs.existsSync(candidate))
                return candidate;
        }
    }
    return undefined;
}
export function findPiLensSemgrepConfigPath(startDir) {
    // Check the configured data dir for the project first (respects PILENS_DATA_DIR)
    const dataCandidate = path.join(getProjectDataDir(startDir), "semgrep.json");
    if (fs.existsSync(dataCandidate))
        return dataCandidate;
    // Fall back to legacy walk-up search for backwards compatibility
    for (const dir of walkUpDirs(startDir || process.cwd())) {
        const candidate = path.join(dir, ".pi-lens", "semgrep.json");
        if (fs.existsSync(candidate))
            return candidate;
    }
    return undefined;
}
export function getPiLensSemgrepConfigPath(cwd) {
    return path.join(getProjectDataDir(path.resolve(cwd || process.cwd())), "semgrep.json");
}
export function loadPiLensSemgrepConfig(startDir) {
    const configPath = findPiLensSemgrepConfigPath(startDir);
    if (!configPath)
        return undefined;
    try {
        const parsed = JSON.parse(fs.readFileSync(configPath, "utf-8"));
        if (!parsed || typeof parsed !== "object")
            return undefined;
        const raw = parsed;
        return {
            enabled: typeof raw.enabled === "boolean" ? raw.enabled : undefined,
            config: typeof raw.config === "string" ? raw.config : undefined,
        };
    }
    catch {
        return undefined;
    }
}
export function savePiLensSemgrepConfig(cwd, config) {
    const configPath = getPiLensSemgrepConfigPath(cwd);
    fs.mkdirSync(path.dirname(configPath), { recursive: true });
    fs.writeFileSync(`${configPath}.tmp`, `${JSON.stringify(config, null, "\t")}\n`);
    fs.renameSync(`${configPath}.tmp`, configPath);
    return configPath;
}
export function removePiLensSemgrepConfig(cwd) {
    const configPath = getPiLensSemgrepConfigPath(cwd);
    if (!fs.existsSync(configPath))
        return false;
    fs.unlinkSync(configPath);
    return true;
}
function isRegistryOrAutoConfig(config) {
    return (config === "auto" || config.startsWith("p/") || config.startsWith("r/"));
}
export function normalizeSemgrepConfigArg(config, cwd) {
    if (!config)
        return undefined;
    const trimmed = config.trim();
    if (!trimmed)
        return undefined;
    if (isRegistryOrAutoConfig(trimmed))
        return trimmed;
    return path.isAbsolute(trimmed) ? trimmed : path.resolve(cwd, trimmed);
}
export function resolveSemgrepConfig(cwd, flags) {
    const localConfig = findLocalSemgrepConfig(cwd);
    const persisted = loadPiLensSemgrepConfig(cwd);
    const flagConfig = typeof flags?.config === "string" && flags.config.trim()
        ? flags.config.trim()
        : undefined;
    if (persisted?.enabled === false && !flags?.enabled) {
        return {
            enabled: false,
            source: "disabled",
            reason: "disabled in .pi-lens/semgrep.json",
        };
    }
    if (flags?.enabled) {
        const configArg = normalizeSemgrepConfigArg(flagConfig ?? localConfig, cwd);
        if (!configArg) {
            return {
                enabled: false,
                source: "disabled",
                reason: "--lens-semgrep was set but no Semgrep config was found; pass --lens-semgrep-config auto|p/<pack>|<path> or create .semgrep.yml",
            };
        }
        return {
            enabled: true,
            configArg,
            source: "flag",
        };
    }
    if (persisted?.enabled) {
        const configArg = normalizeSemgrepConfigArg(persisted.config ?? localConfig, cwd);
        if (!configArg) {
            return {
                enabled: false,
                source: "disabled",
                reason: "Semgrep is enabled in .pi-lens/semgrep.json but no config is set or discovered",
            };
        }
        return {
            enabled: true,
            configArg,
            source: "pi-lens",
        };
    }
    if (localConfig) {
        return {
            enabled: true,
            configArg: localConfig,
            source: "local",
        };
    }
    return {
        enabled: false,
        source: "disabled",
        reason: "no local semgrep config and semgrep not explicitly enabled",
    };
}
export function createStarterSemgrepConfig(cwd) {
    const configPath = path.join(path.resolve(cwd || process.cwd()), ".semgrep.yml");
    if (fs.existsSync(configPath))
        return configPath;
    const contents = `rules:
  - id: pi-lens.no-eval
    pattern: eval(...)
    message: Avoid eval; use a safer, explicit parser or allowlisted operation.
    languages: [javascript, typescript]
    severity: ERROR
    metadata:
      pi-lens:
        semantic: blocking
        defect_class: injection
        confidence: high
        fix: Replace eval with a constrained parser or an explicit allowlist.
`;
    fs.writeFileSync(configPath, contents);
    return configPath;
}
