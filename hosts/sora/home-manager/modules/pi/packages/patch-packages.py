#!/usr/bin/env python3
import sys
from pathlib import Path

root = Path(sys.argv[1])
lens = root / "pi-lens/dist/clients/file-utils.js"
powerline = root / "pi-powerline-footer"
segments = powerline / "segments.ts"
types = powerline / "types.ts"
presets = powerline / "presets.ts"


def replace_once(text: str, old: str, new: str) -> str:
    return text.replace(old, new, 1) if old in text else text


if lens.exists():
    text = lens.read_text()
    if '"Onedrive"' not in text:
        text = replace_once(
            text,
            '    "vendors",\n',
            '    "vendors",\n    "Onedrive", // FUSE mount (rclone)\n',
        )
    lens.write_text(text)

if segments.exists():
    text = segments.read_text()
    text = text.replace("cost.toFixed(2)", "cost.toFixed(4)")
    text = text.replace(
        "return renderCustomSegment(id, ctx);",
        "return renderCustomSegment(id as `custom:${string}`, ctx);",
    )
    text = text.replace(
        "const segment = SEGMENTS[id];",
        "const segment = SEGMENTS[id as BuiltinStatusLineSegmentId];",
    )
    if "formatContextTokens" not in text:
        text = replace_once(
            text,
            "function formatDuration(ms: number): string {",
            """function formatContextTokens(n: number): string {
  if (n < 1000) return n.toString();
  if (n < 1000000) {
    const value = n / 1000;
    return `${Number.isInteger(value) ? value.toFixed(0) : value.toFixed(1)}k`;
  }
  const value = n / 1000000;
  return `${Number.isInteger(value) ? value.toFixed(0) : value.toFixed(1)}M`;
}

function formatDuration(ms: number): string {""",
        )

    text = text.replace(
        "    const text = `${pct.toFixed(1)}%/${formatTokens(window)}${autoIcon}`;",
        "    const used = Math.round((pct / 100) * window);\n"
        "    const text = `${formatContextTokens(used)}/${formatContextTokens(window)}${autoIcon}`;",
    )
    if "codexLimitsSegment" not in text:
        text = text.replace(
            'import { hostname as osHostname } from "node:os";',
            'import { readFileSync, statSync } from "node:fs";\n'
            'import { hostname as osHostname } from "node:os";',
        )
        marker = (
            "// ═══════════════════════════════════════════════════════════════════════════\n"
            "// Segment Implementations"
        )
        helper = """
type CodexLimitWindow = { usedPercent?: number; resetsAt?: number | null; windowDurationMins?: number | null };
type CodexRateLimitCache = {
  weekly?: CodexLimitWindow | null;
  rateLimits?: { primary?: CodexLimitWindow | null; secondary?: CodexLimitWindow | null } | null;
  rateLimitsByLimitId?: Record<string, { primary?: CodexLimitWindow | null; secondary?: CodexLimitWindow | null } | null> | null;
};

function normalizeCodexTimestamp(value: number | null | undefined): number | null {
  if (!Number.isFinite(value ?? NaN)) return null;
  return (value as number) < 100000000000 ? (value as number) * 1000 : (value as number);
}

function readCodexRateLimitCache(): CodexRateLimitCache | null {
  const home = process.env.HOME || process.env.USERPROFILE;
  if (!home) return null;

  const files = [
    home + "/.cache/codex-rate-limits.json",
    home + "/.codex/rate-limits.json",
    home + "/.codex/rate_limits.json",
  ];

  for (const file of files) {
    try {
      const stat = statSync(file);
      if (Date.now() - stat.mtimeMs > 15 * 60 * 1000) continue;
      return JSON.parse(readFileSync(file, "utf8")) as CodexRateLimitCache;
    } catch {
      // Missing or malformed cache: hide the segment. The footer render path must stay cheap.
    }
  }

  return null;
}

function findCodexWindow(cache: CodexRateLimitCache, minutes: number): CodexLimitWindow | null {
  const candidates: Array<CodexLimitWindow | null | undefined> = [
    cache.weekly,
    cache.rateLimits?.primary,
    cache.rateLimits?.secondary,
  ];

  for (const limits of Object.values(cache.rateLimitsByLimitId ?? {})) {
    candidates.push(limits?.primary, limits?.secondary);
  }

  return candidates.find((window) => window?.windowDurationMins === minutes && Number.isFinite(window.usedPercent ?? NaN)) ?? null;
}

function formatCodexWindow(label: string, window: CodexLimitWindow | null): string | null {
  if (!window || !Number.isFinite(window.usedPercent ?? NaN)) return null;

  const used = Math.max(0, Math.min(999, window.usedPercent as number));
  const resetAt = normalizeCodexTimestamp(window.resetsAt);
  const reset = resetAt && resetAt > Date.now() ? "/" + formatDuration(resetAt - Date.now()) : "";
  return label + used.toFixed(0) + "%" + reset;
}
"""
        text = text.replace(marker, helper + "\n" + marker)
        codex_segment = """
const codexLimitsSegment: StatusLineSegment = {
  id: "codex_limits",
  render(ctx) {
    if (ctx.model?.id && !ctx.model.id.startsWith("gpt")) {
      return { content: "", visible: false };
    }

    const cache = readCodexRateLimitCache();
    if (!cache) return { content: "", visible: false };

    const weekly = findCodexWindow(cache, 10080) ?? cache.weekly ?? null;
    const content = formatCodexWindow("7d ", weekly);
    if (!content) return { content: "", visible: false };

    return { content: color(ctx, "quota", "codex " + content), visible: true };
  },
};

"""
        text = replace_once(
            text,
            "const contextPctSegment: StatusLineSegment = {",
            codex_segment + "const contextPctSegment: StatusLineSegment = {",
        )
        text = replace_once(
            text,
            "  cost: costSegment,\n",
            "  cost: costSegment,\n  codex_limits: codexLimitsSegment,\n",
        )
    segments.write_text(text)

if types.exists():
    text = types.read_text()
    text = text.replace(
        '  | "cost"\n  | "codex_limits"\n  | "tokens"',
        '  | "cost"\n  | "tokens"',
    )
    if '| "quota"' not in text:
        text = text.replace('  | "tokens"\n', '  | "tokens"\n  | "quota"\n')
    if '  | "codex_limits"\n  | "context_pct"' not in text:
        text = text.replace(
            '  | "cost"\n  | "context_pct"',
            '  | "cost"\n  | "codex_limits"\n  | "context_pct"',
        )
    types.write_text(text)

if presets.exists():
    text = presets.read_text()
    if 'quota: "warning"' not in text:
        text = text.replace(
            '  cost: "warning",\n',
            '  cost: "warning",\n  quota: "warning",\n',
        )
    if '"codex_limits"' not in text:
        text = text.replace(
            '"cache_write", "cost", "context_pct"',
            '"cache_write", "cost", "codex_limits", "context_pct"',
        )
    text = text.replace(
        '"token_out", "token_rate", "cache_read"',
        '"token_out", "cache_read"',
    )
    presets.write_text(text)
