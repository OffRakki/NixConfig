use serde_json::Value;
use std::env;
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";

const SAKURA: Rgb = Rgb(242, 167, 198);
const PEACH: Rgb = Rgb(252, 201, 185);
const LAVENDER: Rgb = Rgb(199, 184, 245);
const SKY: Rgb = Rgb(159, 211, 242);

const TELEMETRY: &str = "◈  SAKURA CYBERDECK  ◈";

const ANIME_ART: &[&str] = &[
    "⠀⠀⠂⠈⣿⣷⣿⣿⣿⡅⡹⢿⠆⠙⠋⠉⠻⠿⣿⣿⣿⣿⣿⣿⣮⠻⣦⡙⢷⡑⠘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣌⠡⠌⠂⣙⠻⣛⠻⠷⠐⠈⠛⢱⣮⠁⠐⠀",
    "⠀⠂⠈⣿⡇⢿⢹⣿⣶⠐⠁⠀⣀⣠⣤⠄⠀⠀⠈⠙⠻⣿⣿⣿⣦⣵⣌⠻⣷⢝⠦⠚⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢟⣻⣿⣊⡃⠀⣙⠿⣿⣿⣿⣎⢮⡀⢮⣽⠁⠐",
    "⠂⠈⣿⣿⣧⡸⡎⡛⡩⠖⠀⣴⣿⣿⣿⠀⠀⠀⠀⠸⠇⠀⠙⢿⣿⣿⣿⣷⣌⢷⣑⢷⣄⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣫⠶⠛⠉⠀⠁⠀⠈⠈⠀⠠⠜⠻⣿⣆⢿⣼⣿⣿⠁",
    " ⠈⣿⣿⣿⣧⢧⣧⢻⣦⢀⣹⣿⣿⣿⣇⠀⠄⠀⠀⠀⡀⠀⠈⢻⣿⣿⣿⣿⣷⣝⢦⡹⠷⡙⢿⣿⣿⣿⣿⣿⣿⣿⣿⠈⠁⠀⠀⠀⠁⠀⠀⠀⠱⣶⣄⡀⠀⠈⠛⠜⣿⣿⣿⣿",
    "⠀⠊⢫⣿⣏⣿⡌⣼⣄⢫⡌⣿⣿⣿⣿⣿⣦⡈⠲⣄⣤⣤⡡⢀⣠⣿⣿⣿⣿⣿⣿⣷⣼⣍⢬⣦⡙⣿⣿⣿⣿⣿⣯⢁⡄⠀⡀⡀⠀⠄⢈⣠⢪⠀⣿⣿⣿⣦⠀⢉⢂⠹⡿⣿⣿",
    "⠀⠀⠄⢹⢃⢻⣟⠙⣿⣦⠱⢻⣿⣿⣿⣿⣿⣿⣷⣬⣍⣭⣥⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⡙⢿⣼⡿⣿⣿⣿⣿⣿⣷⣄⠘⣱⢦⣤⡴⡿⢈⣼⣿⣿⣿⣇⣴⣶⣮⣅⢻⣿⡏",
    "⠀⠀⠈⠹⣇⢡⢿⡆⠻⣿⣷⠀⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣍⡻⣿⣟⣻⣿⣿⣿⣿⣷⣦⣥⣬⣤⣴⣾⣿⣿⣿⣿⣷⣿⣿⣿⣿⣷⡜⠃",
    "⠀⠀⠀⢀⣘⠈⢂⠃⣧⡹⣿⣷⡄⠙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣮⣅⡙⢿⣟⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠋⡕⠂",
    "⠀⠀⠀⠀⠀⠀⠛⢷⣜⢷⡌⠻⣿⣿⣦⣝⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣹⣷⣦⣹⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠉⠃⠀",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Rgb(u8, u8, u8);

impl Rgb {
    fn from_hex(hex: &str) -> Option<Self> {
        let s = hex.trim().strip_prefix('#').unwrap_or(hex.trim());
        if s.len() != 6 {
            return None;
        }
        let r = u8::from_str_radix(&s[0..2], 16).ok()?;
        let g = u8::from_str_radix(&s[2..4], 16).ok()?;
        let b = u8::from_str_radix(&s[4..6], 16).ok()?;
        Some(Self(r, g, b))
    }

    fn fg(self) -> String {
        format!("\x1b[38;2;{};{};{}m", self.0, self.1, self.2)
    }

    fn bg(self) -> String {
        format!("\x1b[48;2;{};{};{}m", self.0, self.1, self.2)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Palette {
    panel: Rgb,
    panel_alt: Rgb,
    accent: Rgb,
    purple: Rgb,
    cyan: Rgb,
    green: Rgb,
    yellow: Rgb,
    orange: Rgb,
    red: Rgb,
    text: Rgb,
    muted: Rgb,
    dim: Rgb,
}

impl Default for Palette {
    // Catppuccin Mocha fallback when Noctalia has not rendered yet.
    fn default() -> Self {
        Self {
            panel: Rgb(49, 50, 68),
            panel_alt: Rgb(30, 30, 46),
            accent: Rgb(137, 180, 250),
            purple: Rgb(203, 166, 247),
            cyan: Rgb(148, 226, 213),
            green: Rgb(166, 227, 161),
            yellow: Rgb(249, 226, 175),
            orange: Rgb(250, 179, 135),
            red: Rgb(243, 139, 168),
            text: Rgb(205, 214, 244),
            muted: Rgb(166, 173, 200),
            dim: Rgb(108, 112, 134),
        }
    }
}

impl Palette {
    fn from_json(value: &Value) -> Self {
        let mut palette = Self::default();
        let vars = value.get("vars").unwrap_or(value);
        let pick = |key: &str, fallback: Rgb| -> Rgb {
            vars.get(key)
                .and_then(Value::as_str)
                .and_then(Rgb::from_hex)
                .unwrap_or(fallback)
        };
        palette.panel = pick("panel", palette.panel);
        palette.panel_alt = pick("panelAlt", palette.panel_alt);
        palette.accent = pick("accent", palette.accent);
        palette.purple = pick("purple", palette.purple);
        palette.cyan = pick("cyan", palette.cyan);
        palette.green = pick("green", palette.green);
        palette.yellow = pick("yellow", palette.yellow);
        palette.orange = pick("orange", palette.orange);
        palette.red = pick("red", palette.red);
        palette.text = pick("text", palette.text);
        palette.muted = pick("muted", palette.muted);
        palette.dim = pick("dim", palette.dim);
        palette
    }

    fn load() -> Self {
        let Some(path) = palette_path() else {
            return Self::default();
        };
        let Ok(raw) = fs::read_to_string(path) else {
            return Self::default();
        };
        serde_json::from_str::<Value>(&raw)
            .map(|v| Self::from_json(&v))
            .unwrap_or_default()
    }
}

fn palette_path() -> Option<PathBuf> {
    if let Ok(path) = env::var("AGY_PALETTE_PATH")
        && !path.trim().is_empty()
    {
        return Some(PathBuf::from(path));
    }
    if let Ok(xdg) = env::var("XDG_CONFIG_HOME")
        && !xdg.trim().is_empty()
    {
        return Some(PathBuf::from(xdg).join("antigravity/palette.json"));
    }
    env::var("HOME")
        .ok()
        .filter(|h| !h.trim().is_empty())
        .map(|h| PathBuf::from(h).join(".config/antigravity/palette.json"))
}

fn shorten_path(path: &str, home: Option<&str>) -> String {
    if path.is_empty() {
        return "~".to_string();
    }
    let normalized = match home {
        Some(h) if !h.is_empty() && path == h => "~".to_string(),
        Some(h) if !h.is_empty() && path.starts_with(&format!("{h}/")) => {
            format!("~{}", &path[h.len()..])
        }
        _ => path.to_string(),
    };
    let parts: Vec<&str> = normalized.split('/').filter(|p| !p.is_empty()).collect();
    if parts.len() <= 3 {
        return normalized;
    }
    if normalized.starts_with("~/") {
        format!("~/…/{}", parts[parts.len() - 2..].join("/"))
    } else {
        format!("…/{}", parts[parts.len() - 2..].join("/"))
    }
}

fn read_git_branch(dir: &Path) -> Option<String> {
    let mut current = Some(dir);
    while let Some(path) = current {
        let head = path.join(".git/HEAD");
        if let Ok(contents) = fs::read_to_string(&head) {
            let trimmed = contents.trim();
            if let Some(branch) = trimmed.strip_prefix("ref: refs/heads/") {
                return Some(branch.to_string());
            }
            if trimmed.len() >= 7 {
                return Some(trimmed[..7].to_string());
            }
        }
        current = path.parent();
    }
    None
}

fn format_effort(raw: &str) -> &'static str {
    match raw.to_ascii_lowercase().as_str() {
        "minimal" => "min",
        "low" => "low",
        "medium" => "med",
        "high" => "high",
        "xhigh" => "xhi",
        "max" => "max",
        _ => "",
    }
}

fn buddy_style(state: &str, palette: Palette) -> (&'static str, &'static str, Rgb) {
    match state {
        "working" => ("· •", "thinking", palette.accent),
        "tool_use" => ("◉ ◉", "working", palette.cyan),
        "reviewing" => ("⌕ ⌕", "reviewing", palette.purple),
        "initializing" => ("· ·", "starting", palette.muted),
        "authenticating" => ("◈ ◈", "auth", palette.yellow),
        "error" => ("× ×", "uh-oh", palette.red),
        _ => ("• •", "ready", palette.muted),
    }
}

fn render_progress_bar(pct: f64, width: usize) -> String {
    let clamped = pct.clamp(0.0, 100.0);
    let filled = ((clamped / 100.0) * width as f64).round() as usize;
    let filled = filled.min(width);
    format!("{}{}", "▓".repeat(filled), "░".repeat(width - filled))
}

fn lowest_quota_pct(value: &Value) -> Option<u64> {
    let obj = value.get("quota")?.as_object()?;
    let mut lowest: Option<f64> = None;
    for bucket in obj.values() {
        if bucket
            .get("disabled")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            continue;
        }
        if let Some(frac) = bucket.get("remaining_fraction").and_then(Value::as_f64) {
            let pct = (frac * 100.0).clamp(0.0, 100.0);
            lowest = Some(lowest.map_or(pct, |cur| cur.min(pct)));
        }
    }
    lowest.map(|v| v.round() as u64)
}

fn render_segment(text: &str, fg: Rgb, bg: Rgb) -> String {
    format!("{}{} {} {}", bg.bg(), fg.fg(), text, RESET)
}

fn render_statusline(payload: &Value, palette: Palette, home: Option<&str>) -> String {
    let cwd = payload
        .get("workspace")
        .and_then(|w| w.get("current_dir"))
        .and_then(Value::as_str)
        .or_else(|| payload.get("cwd").and_then(Value::as_str))
        .unwrap_or("");
    let short_dir = shorten_path(cwd, home);
    let terminal_width = payload
        .get("terminal_width")
        .and_then(Value::as_u64)
        .unwrap_or(120) as usize;

    let mut segments: Vec<String> = Vec::new();
    segments.push(render_segment(
        &format!("󰉋 {short_dir}"),
        palette.accent,
        palette.panel,
    ));

    if let Some(vcs_type) = payload
        .get("vcs")
        .and_then(|v| v.get("type"))
        .and_then(Value::as_str)
    {
        let vcs_label = match vcs_type {
            "git" => read_git_branch(Path::new(cwd))
                .map(|b| format!("󰘬 {b}"))
                .unwrap_or_else(|| "󰘬 git".to_string()),
            other => format!("󰘬 {other}"),
        };
        segments.push(render_segment(&vcs_label, palette.green, palette.panel_alt));
    }

    if let Some(model) = payload.get("model").filter(|v| v.is_object()) {
        let name = model
            .get("display_name")
            .and_then(Value::as_str)
            .or_else(|| model.get("id").and_then(Value::as_str))
            .unwrap_or("model");
        let effort = model
            .get("effort")
            .and_then(Value::as_str)
            .map(format_effort)
            .unwrap_or("");
        let label = if effort.is_empty() {
            format!("✦ {name}")
        } else {
            format!("✦ {name}  {effort}")
        };
        segments.push(render_segment(&label, palette.purple, palette.panel));
    }

    if let Some(ctx) = payload.get("context_window").filter(|v| v.is_object())
        && let Some(pct) = ctx.get("used_percentage").and_then(Value::as_f64)
    {
        let ctx_color = if pct >= 80.0 {
            palette.red
        } else if pct >= 50.0 {
            palette.yellow
        } else {
            palette.green
        };
        let label = if terminal_width >= 90 {
            format!("{} {:.0}%", render_progress_bar(pct, 6), pct)
        } else {
            format!("{:.0}%", pct)
        };
        segments.push(render_segment(&label, ctx_color, palette.panel_alt));
    }

    if let Some(quota) = lowest_quota_pct(payload) {
        let quota_color = if quota <= 15 {
            palette.red
        } else if quota <= 35 {
            palette.yellow
        } else {
            palette.cyan
        };
        segments.push(render_segment(
            &format!("◈ {quota}%"),
            quota_color,
            palette.panel,
        ));
    }

    if let Some(mode) = payload
        .get("cycle_mode")
        .and_then(Value::as_str)
        .filter(|m| !m.is_empty())
    {
        segments.push(render_segment(mode, palette.orange, palette.panel_alt));
    }

    if payload
        .get("sandbox")
        .and_then(|s| s.get("enabled"))
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        segments.push(render_segment("󰒃 sandbox", palette.cyan, palette.panel));
    }

    if let Some(subagents) = payload.get("subagents").and_then(Value::as_array) {
        let running = subagents
            .iter()
            .filter(|s| s.get("status").and_then(Value::as_str) == Some("running"))
            .count();
        if running > 0 {
            segments.push(render_segment(
                &format!("󰚩 {running}"),
                palette.accent,
                palette.panel_alt,
            ));
        }
    }

    if let Some(artifacts) = payload.get("artifact_count").and_then(Value::as_u64)
        && artifacts > 0
    {
        segments.push(render_segment(
            &format!("󰈙 {artifacts}"),
            palette.text,
            palette.panel,
        ));
    }

    let sep = format!("{}│{}", palette.dim.fg(), RESET);
    let line1 = segments.join(&sep);

    let state = payload
        .get("agent_state")
        .and_then(Value::as_str)
        .unwrap_or("idle");
    let (eyes, label, color) = buddy_style(state, palette);
    let agent_tag = payload
        .get("agent")
        .and_then(|a| a.get("name"))
        .and_then(Value::as_str)
        .filter(|n| !n.is_empty())
        .map(|n| format!(" {}[{n}]{}", DIM, RESET))
        .unwrap_or_default();

    let line2 = format!(
        "{}╭─ π ─╮ {}│ {eyes} │{} {BOLD}{label}{RESET}{agent_tag}",
        color.fg(),
        color.fg(),
        color.fg()
    );

    format!("{line1}\n{line2}")
}

fn sanitize_title(input: &str) -> String {
    input
        .chars()
        .filter(|c| !c.is_control())
        .collect::<String>()
        .trim()
        .to_string()
}

fn render_title(payload: &Value) -> String {
    let cwd = payload
        .get("workspace")
        .and_then(|w| w.get("project_dir"))
        .and_then(Value::as_str)
        .or_else(|| payload.get("cwd").and_then(Value::as_str))
        .unwrap_or("");
    let folder = Path::new(cwd)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("agy");
    let state = payload
        .get("agent_state")
        .and_then(Value::as_str)
        .unwrap_or("idle");
    let label = match state {
        "working" => Some("thinking"),
        "tool_use" => Some("working"),
        "reviewing" => Some("reviewing"),
        "initializing" => Some("starting"),
        "authenticating" => Some("auth"),
        "error" => Some("error"),
        _ => None,
    };
    let raw = match label {
        Some(status) => format!("agy — {folder} [{status}]"),
        None => format!("agy — {folder}"),
    };
    sanitize_title(&raw)
}

fn lerp_u8(a: u8, b: u8, t: f64) -> u8 {
    (f64::from(a) + (f64::from(b) - f64::from(a)) * t).round() as u8
}

fn gradient_line(text: &str, from: Rgb, to: Rgb, bold: bool) -> String {
    let chars: Vec<char> = text.chars().collect();
    let span = chars.len().saturating_sub(1).max(1) as f64;
    let prefix = if bold { BOLD } else { "" };
    let mut out = String::with_capacity(text.len() * 8);
    for (idx, ch) in chars.iter().enumerate() {
        if ch.is_whitespace() || *ch == '\u{2800}' {
            out.push(*ch);
            continue;
        }
        let t = idx as f64 / span;
        let color = Rgb(
            lerp_u8(from.0, to.0, t),
            lerp_u8(from.1, to.1, t),
            lerp_u8(from.2, to.2, t),
        );
        out.push_str(prefix);
        out.push_str(&color.fg());
        out.push(*ch);
        out.push_str(RESET);
    }
    out
}

fn clip_center(line: &str, max_cols: usize) -> String {
    let chars: Vec<char> = line.chars().collect();
    if chars.len() <= max_cols {
        return line.to_string();
    }
    let start = (chars.len() - max_cols) / 2;
    chars[start..start + max_cols].iter().collect()
}

fn render_banner(columns: usize) -> String {
    if columns < 40 {
        return String::new();
    }
    let mut lines = Vec::with_capacity(ANIME_ART.len() + 2);
    for row in ANIME_ART {
        let clipped = clip_center(row, columns);
        let pad = columns.saturating_sub(clipped.chars().count()) / 2;
        lines.push(format!(
            "{}{}",
            " ".repeat(pad),
            gradient_line(&clipped, SAKURA, SKY, false)
        ));
    }
    let tel_clipped = clip_center(TELEMETRY, columns);
    let tel_pad = columns.saturating_sub(tel_clipped.chars().count()) / 2;
    lines.push(String::new());
    lines.push(format!(
        "{}{}",
        " ".repeat(tel_pad),
        gradient_line(&tel_clipped, PEACH, LAVENDER, true)
    ));
    lines.join("\n")
}

fn read_stdin_json() -> Value {
    let mut buf = String::new();
    if io::stdin().read_to_string(&mut buf).is_err() || buf.trim().is_empty() {
        return Value::Object(serde_json::Map::new());
    }
    serde_json::from_str(&buf).unwrap_or_else(|_| Value::Object(serde_json::Map::new()))
}

fn main() {
    let mode = env::args()
        .nth(1)
        .unwrap_or_else(|| "--statusline".to_string());
    match mode.as_str() {
        "--banner" => {
            let cols = env::var("COLUMNS")
                .ok()
                .and_then(|c| c.parse::<usize>().ok())
                .unwrap_or(132);
            let banner = render_banner(cols);
            if !banner.is_empty() {
                println!("{banner}\n");
            }
        }
        "--title" => {
            let payload = read_stdin_json();
            println!("{}", render_title(&payload));
        }
        _ => {
            let payload = read_stdin_json();
            let palette = Palette::load();
            let home = env::var("HOME").ok();
            println!("{}", render_statusline(&payload, palette, home.as_deref()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_noctalia_palette_and_falls_back_cleanly() {
        let p = Palette::from_json(&json!({
            "vars": {
                "accent": "#ff88cc",
                "green": "invalid",
                "red": "#f38ba8"
            }
        }));
        assert_eq!(p.accent, Rgb(0xff, 0x88, 0xcc));
        assert_eq!(p.green, Palette::default().green);
        assert_eq!(p.red, Rgb(0xf3, 0x8b, 0xa8));
    }

    #[test]
    fn renders_full_statusline_and_buddy() {
        let payload = json!({
            "cwd": "/home/rakki/Projects/NixConfig",
            "vcs": { "type": "jj" },
            "model": { "display_name": "Gemini 4 Neon", "effort": "high" },
            "context_window": { "used_percentage": 42.3 },
            "quota": {
                "gemini": { "remaining_fraction": 0.87, "disabled": false },
                "ignored": { "remaining_fraction": 0.1, "disabled": true }
            },
            "agent_state": "tool_use",
            "cycle_mode": "plan",
            "sandbox": { "enabled": true },
            "subagents": [
                { "name": "research", "status": "running" },
                { "name": "done-one", "status": "completed" }
            ],
            "artifact_count": 2,
            "terminal_width": 120
        });
        let out = render_statusline(&payload, Palette::default(), Some("/home/rakki"));
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("~/Projects/NixConfig"));
        assert!(lines[0].contains("jj"));
        assert!(lines[0].contains("Gemini 4 Neon  high"));
        assert!(lines[0].contains("42%"));
        assert!(lines[0].contains("◈ 87%"));
        assert!(lines[0].contains("plan"));
        assert!(lines[0].contains("sandbox"));
        assert!(lines[0].contains("󰚩 1"));
        assert!(lines[0].contains("󰈙 2"));
        assert!(lines[1].contains("◉ ◉"));
        assert!(lines[1].contains("working"));
    }

    #[test]
    fn handles_empty_payload_and_all_states() {
        let palette = Palette::default();
        let empty = render_statusline(&json!({}), palette, Some("/home/rakki"));
        assert!(empty.contains("ready"));
        for (state, expected_label) in [
            ("idle", "ready"),
            ("working", "thinking"),
            ("tool_use", "working"),
            ("reviewing", "reviewing"),
            ("initializing", "starting"),
            ("authenticating", "auth"),
            ("error", "uh-oh"),
        ] {
            let out = render_statusline(&json!({ "agent_state": state }), palette, None);
            assert!(out.contains(expected_label), "state={state} out={out}");
        }
    }

    #[test]
    fn renders_plain_title_without_ansi_or_controls() {
        let title = render_title(&json!({
            "workspace": { "project_dir": "/home/rakki/Projects/NixConfig" },
            "agent_state": "working"
        }));
        assert_eq!(title, "agy — NixConfig [thinking]");
        assert!(!title.contains('\x1b'));

        let idle_title = render_title(&json!({
            "cwd": "/home/rakki/Projects/NixConfig",
            "agent_state": "idle"
        }));
        assert_eq!(idle_title, "agy — NixConfig");
    }

    #[test]
    fn renders_sakura_banner_and_skips_narrow_terminals() {
        let banner = render_banner(100);
        assert!(banner.contains("SAKURA") || banner.contains("\x1b[38;2;"));
        assert_eq!(banner.lines().count(), ANIME_ART.len() + 2);
        assert!(render_banner(30).is_empty());
    }
}
