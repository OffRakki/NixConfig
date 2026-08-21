#!/usr/bin/env python3
import sys
from pathlib import Path

root = Path(sys.argv[1])
buddy_controller = root / "@apat183/pi-buddy/src/controller.ts"
powerbar_index = root / "@juanibiapina/pi-powerbar/src/powerbar/index.ts"
lens = root / "pi-lens/dist/clients/file-utils.js"


def replace_once(text: str, old: str, new: str) -> str:
    return text.replace(old, new, 1) if old in text else text


if buddy_controller.exists():
    text = buddy_controller.read_text()
    text = replace_once(
        text,
        "\t\tthis.applyAll(ctx);",
        "\t\t// Pi 0.80 misplaces widgets registered synchronously during session_start.\n"
        "\t\tsetImmediate(() => this.applyAll(ctx));",
    )
    buddy_controller.write_text(text)

if powerbar_index.exists():
    text = powerbar_index.read_text()
    text = replace_once(
        text,
        "\t\thideFooter(ctx);\n\t\trefresh();",
        "\t\thideFooter(ctx);\n"
        "\t\t// Keep startup ordering stable with other below-editor widgets on Pi 0.80.\n"
        "\t\tsetImmediate(refresh);",
    )
    powerbar_index.write_text(text)

if lens.exists():
    text = lens.read_text()
    if '"Onedrive"' not in text:
        text = replace_once(
            text,
            '    "vendors",\n',
            '    "vendors",\n    "Onedrive", // FUSE mount (rclone)\n',
        )
    lens.write_text(text)
