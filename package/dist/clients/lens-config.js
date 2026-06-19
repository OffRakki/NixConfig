import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
export function getPiLensGlobalConfigPath(homeDir = os.homedir()) {
    const override = process.env.PI_LENS_CONFIG_PATH;
    if (override)
        return path.resolve(override);
    return path.join(homeDir, ".pi-lens", "config.json");
}
export function loadPiLensGlobalConfig(configPath = getPiLensGlobalConfigPath()) {
    try {
        const parsed = JSON.parse(fs.readFileSync(configPath, "utf-8"));
        if (!parsed || typeof parsed !== "object")
            return undefined;
        const raw = parsed;
        const dispatchRaw = raw.dispatch;
        const dispatch = dispatchRaw && typeof dispatchRaw === "object"
            ? dispatchRaw
            : undefined;
        const widgetRaw = raw.widget;
        const widget = widgetRaw && typeof widgetRaw === "object"
            ? widgetRaw
            : undefined;
        const formatRaw = raw.format;
        const format = formatRaw && typeof formatRaw === "object"
            ? formatRaw
            : undefined;
        const actionableWarningsRaw = raw.actionableWarnings;
        const actionableWarnings = actionableWarningsRaw && typeof actionableWarningsRaw === "object"
            ? actionableWarningsRaw
            : undefined;
        const actionableWarningsAutoFixRaw = actionableWarnings?.autoFix;
        const actionableWarningsAutoFix = actionableWarningsAutoFixRaw &&
            typeof actionableWarningsAutoFixRaw === "object"
            ? actionableWarningsAutoFixRaw
            : undefined;
        const contextInjectionRaw = raw.contextInjection;
        const contextInjection = contextInjectionRaw && typeof contextInjectionRaw === "object"
            ? contextInjectionRaw
            : undefined;
        const formatMode = format?.mode === "immediate" || format?.mode === "deferred"
            ? format.mode
            : undefined;
        return {
            dispatch: dispatch
                ? {
                    runnerTimeoutFloorMs: typeof dispatch.runnerTimeoutFloorMs === "number" &&
                        Number.isFinite(dispatch.runnerTimeoutFloorMs) &&
                        dispatch.runnerTimeoutFloorMs > 0
                        ? dispatch.runnerTimeoutFloorMs
                        : undefined,
                }
                : undefined,
            widget: widget
                ? {
                    visible: typeof widget.visible === "boolean" ? widget.visible : undefined,
                }
                : undefined,
            format: format
                ? {
                    enabled: typeof format.enabled === "boolean" ? format.enabled : undefined,
                    mode: formatMode,
                }
                : undefined,
            actionableWarnings: actionableWarnings
                ? {
                    enabled: typeof actionableWarnings.enabled === "boolean"
                        ? actionableWarnings.enabled
                        : undefined,
                    includeLspCodeActions: typeof actionableWarnings.includeLspCodeActions === "boolean"
                        ? actionableWarnings.includeLspCodeActions
                        : undefined,
                    deltaOnly: typeof actionableWarnings.deltaOnly === "boolean"
                        ? actionableWarnings.deltaOnly
                        : undefined,
                    autoFix: actionableWarningsAutoFix
                        ? {
                            enabled: typeof actionableWarningsAutoFix.enabled === "boolean"
                                ? actionableWarningsAutoFix.enabled
                                : undefined,
                        }
                        : undefined,
                }
                : undefined,
            contextInjection: contextInjection
                ? {
                    enabled: typeof contextInjection.enabled === "boolean"
                        ? contextInjection.enabled
                        : undefined,
                }
                : undefined,
        };
    }
    catch {
        return undefined;
    }
}
export function getGlobalWidgetDefaultVisible(configPath) {
    return loadPiLensGlobalConfig(configPath)?.widget?.visible !== false;
}
export function getGlobalAutoformatEnabled(configPath) {
    return loadPiLensGlobalConfig(configPath)?.format?.enabled !== false;
}
export function getGlobalImmediateFormatDefault(configPath) {
    return loadPiLensGlobalConfig(configPath)?.format?.mode === "immediate";
}
export function getGlobalContextInjectionEnabled(configPath) {
    return (loadPiLensGlobalConfig(configPath)?.contextInjection?.enabled !== false);
}
export function resolvePiLensFlag(name, value, config) {
    if (value)
        return value;
    if (name === "no-autoformat") {
        return config?.format?.enabled === false;
    }
    if (name === "immediate-format") {
        return config?.format?.mode === "immediate";
    }
    if (name === "lens-actionable-warnings") {
        return config?.actionableWarnings?.enabled === true;
    }
    if (name === "lens-actionable-warning-actions") {
        return config?.actionableWarnings?.includeLspCodeActions === true;
    }
    if (name === "lens-actionable-warning-autofix") {
        return config?.actionableWarnings?.autoFix?.enabled === true;
    }
    if (name === "lens-actionable-warning-all") {
        return config?.actionableWarnings?.deltaOnly === false;
    }
    if (name === "no-lens-context") {
        return config?.contextInjection?.enabled === false;
    }
    return value;
}
