#!/usr/bin/env python3
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
buddy_controller = root / "@apat183/pi-buddy/src/controller.ts"


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"Expected exactly one patch target, found {count}: {old!r}")
    return text.replace(old, new, 1)


text = buddy_controller.read_text()
text = replace_once(
    text,
    "\t\tthis.applyAll(ctx);\n\t\tctx.ui.setTitle(",
    "\t\t// Pi 0.80 misplaces widgets registered synchronously during session_start.\n"
    "\t\tsetImmediate(() => this.applyAll(ctx));\n\t\tctx.ui.setTitle(",
)
buddy_controller.write_text(text)

# Suppress only the informational startup banner; keep actionable warnings.
failover_index = root / "pi-multi-account/index.ts"
text = failover_index.read_text()
text = replace_once(
    text,
    '\t\tctx.ui.notify(\n'
    '\t\t\tsubagentChild\n'
    '\t\t\t\t? `pi-multi-account v${VERSION} loaded in passive pi-subagents child mode. Model routing remains owned by the parent runner.`\n'
    '\t\t\t\t: `pi-multi-account v${VERSION} loaded (${config.enabled ? "enabled" : "disabled"}). ${rotation.length} account(s) in rotation. Config: ${CONFIG_PATH}`,\n'
    '\t\t\t"info",\n'
    '\t\t);\n',
    "",
)
text = replace_once(
    text,
    '\t\t\t} else if (!seamlessResume) {\n'
    '\t\t\t\tctx.ui?.notify?.(\n'
    '\t\t\t\t\t`pi-multi-account v${VERSION}: seamless in-place resume (pi.continueAgent) is not available on this Pi build — automatic recovery resumes from the preserved task context in a fresh turn. Temporary errors keep the same provider/model; confirmed quota limits retain failover. This is the expected fallback, not an error.`,\n'
    '\t\t\t\t\t"info",\n'
    '\t\t\t\t);\n',
    "",
)
failover_index.write_text(text)

# Mail's approval bindings pin this configuration path. Do not merge ambient HOME,
# project or environment-selected browser settings into the mail process. Normal Pi
# keeps upstream discovery when this explicit wrapper-only mode is absent.
browser_policy = root / "pi-agent-browser-native/dist/extensions/agent-browser/lib/config-policy.js"
text = browser_policy.read_text()
text = replace_once(
    text,
    '    const env = options.env ?? process.env;\n'
    '    const paths = getAgentBrowserConfigPaths({ cwd: options.cwd, env });\n',
    '    const env = options.env ?? process.env;\n'
    '    const pinned = env.PI_AGENT_BROWSER_PINNED_CONFIG;\n'
    '    if (pinned !== undefined) {\n'
    '        if (!pinned.startsWith("/nix/store/")) throw new Error("Pinned browser config must be Nix-owned");\n'
    '        const errors = [], warnings = [];\n'
    '        const layer = readConfigLayerSync(pinned, "override", errors, warnings);\n'
    '        if (!layer || errors.length) throw new Error("Invalid pinned browser configuration");\n'
    '        return buildAgentBrowserConfigState({ env: {}, errors, warnings, layers: [layer],\n'
    '            paths: { global: pinned, project: pinned, override: pinned },\n'
    '            mergedConfig: layer.config, projectConfigIncluded: false });\n'
    '    }\n'
    '    const paths = getAgentBrowserConfigPaths({ cwd: options.cwd, env });\n',
)
browser_policy.write_text(text)

# The native CLI has its own config/env discovery, independent of the extension.
# Mail starts from a pinned empty native config and drops inherited launch/proxy
# settings. Internal, explicitly approved CLI/session overrides still compose.
browser_environment = root / "pi-agent-browser-native/dist/extensions/agent-browser/lib/process-environment.js"
text = browser_environment.read_text()
text = replace_once(
    text,
    '    const isolatedConfig = isolatedAgentBrowserEnvironment.getStore();\n',
    '    const isolatedConfig = isolatedAgentBrowserEnvironment.getStore();\n'
    '    if (baseEnv.PI_AGENT_BROWSER_PINNED_CONFIG !== undefined) {\n'
    '        const nativeConfig = baseEnv.PI_AGENT_BROWSER_NATIVE_CONFIG;\n'
    '        if (!nativeConfig?.startsWith("/nix/store/")) throw new Error("Native browser config must be Nix-owned");\n'
    '        return {\n'
    '            ...Object.fromEntries(Object.entries(baseEnv).filter(([name]) =>\n'
    '                !name.toUpperCase().startsWith("AGENT_BROWSER_") && !PROXY_ENV_NAMES.has(name.toUpperCase()))),\n'
    '            AGENT_BROWSER_CONFIG: nativeConfig,\n'
    '            ...agentBrowserProcessEnvironment.getStore(),\n'
    '            ...(isolatedConfig !== undefined ? { AGENT_BROWSER_CONFIG: isolatedConfig } : {}),\n'
    '        };\n'
    '    }\n',
)
browser_environment.write_text(text)

# Pi 1.0 supplies TypeBox; use its host alias instead of a private runtime copy.
orchestrator = root / "@groeponline/pi-agent-orchestrator"
manifest_path = orchestrator / "package.json"
manifest = json.loads(manifest_path.read_text())
del manifest["dependencies"]["@sinclair/typebox"]
manifest["peerDependencies"]["typebox"] = "*"
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
for source in [*orchestrator.rglob("*.js"), *orchestrator.rglob("*.ts")]:
    text = source.read_text()
    source.write_text(text.replace('"@sinclair/typebox"', '"typebox"'))
