#!/usr/bin/env python3
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
buddy_controller = root / "@apat183/pi-buddy/src/controller.ts"
powerbar_index = root / "@juanibiapina/pi-powerbar/src/powerbar/index.ts"
subagent_aliases = root / "pi-subagents/src/runs/background/runner-aliases.js"


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

text = powerbar_index.read_text()
text = replace_once(
    text,
    "\t\thideFooter(ctx);\n\t\trefresh();",
    "\t\thideFooter(ctx);\n"
    "\t\t// Keep startup ordering stable with other below-editor widgets on Pi 0.80.\n"
    "\t\tsetImmediate(refresh);",
)
powerbar_index.write_text(text)

# Pi 1.0 removed this unused legacy subpath; requiring it blocks every async child.
text = subagent_aliases.read_text()
text = replace_once(
    text,
    '    { specifier: "@earendil-works/pi-agent-core/node", '
    'pkg: "@earendil-works/pi-agent-core", subpath: "./node" },\n',
    "",
)
subagent_aliases.write_text(text)

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
