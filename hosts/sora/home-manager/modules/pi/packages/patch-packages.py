#!/usr/bin/env python3
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
