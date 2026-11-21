use serde_json::Value;
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::time::Duration;

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";

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

#[derive(Clone, Debug, PartialEq)]
struct BiliContext {
    session_id: String,
    pct: f64,
    blocks: u64,
    is_usage: bool,
}

fn parse_bili_loopback_addr(cloud_code_url: &str) -> Option<String> {
    let rest = cloud_code_url
        .trim()
        .strip_prefix("http://")
        .or_else(|| cloud_code_url.trim().strip_prefix("https://"))?;
    let host_port = rest.split('/').next()?;
    let (host, port) = if let Some(stripped) = host_port.strip_prefix('[') {
        let (h, p) = stripped.split_once("]:")?;
        (h, p)
    } else {
        host_port.rsplit_once(':')?
    };
    if !matches!(host, "127.0.0.1" | "localhost" | "::1") {
        return None;
    }
    let port_num: u16 = port.parse().ok()?;
    Some(format!("{host}:{port_num}"))
}

fn decode_http_body(raw: &[u8]) -> Option<String> {
    let sep = raw.windows(4).position(|w| w == b"\r\n\r\n")?;
    let headers = std::str::from_utf8(&raw[..sep]).ok()?;
    let body = &raw[sep + 4..];
    let is_chunked = headers.lines().any(|line| {
        let lower = line.to_ascii_lowercase();
        lower.starts_with("transfer-encoding:") && lower.contains("chunked")
    });
    if !is_chunked {
        return std::str::from_utf8(body).ok().map(ToString::to_string);
    }
    let mut out = Vec::with_capacity(body.len());
    let mut cursor = body;
    while !cursor.is_empty() {
        let crlf = cursor.windows(2).position(|w| w == b"\r\n")?;
        let size_line = std::str::from_utf8(&cursor[..crlf]).ok()?.trim();
        let size_hex = size_line.split(';').next()?.trim();
        let size = usize::from_str_radix(size_hex, 16).ok()?;
        cursor = &cursor[crlf + 2..];
        if size == 0 {
            break;
        }
        if cursor.len() < size {
            return None;
        }
        out.extend_from_slice(&cursor[..size]);
        cursor = cursor.get(size + 2..).unwrap_or(&[]);
    }
    String::from_utf8(out).ok()
}

fn select_bili_context(stats: &Value, session_id: Option<&str>) -> Option<BiliContext> {
    let sessions = stats.get("sessions")?.as_array()?;
    let extract = |s: &Value| -> Option<BiliContext> {
        let id = s.get("id").and_then(Value::as_str).unwrap_or("default");
        let tokens = s.get("contextTokens")?.as_f64()?;
        let window = s.get("contextWindow")?.as_f64()?;
        if window <= 0.0 || tokens < 0.0 {
            return None;
        }
        let blocks = s.get("blocks").and_then(Value::as_u64).unwrap_or(0);
        let is_usage = s.get("contextTokensSource").and_then(Value::as_str) == Some("usage");
        Some(BiliContext {
            session_id: id.to_string(),
            pct: ((tokens / window) * 100.0).clamp(0.0, 100.0),
            blocks,
            is_usage,
        })
    };

    if let Some(sid) = session_id.filter(|s| !s.trim().is_empty())
        && let Some(found) = sessions
            .iter()
            .find(|s| s.get("id").and_then(Value::as_str) == Some(sid))
            .and_then(extract)
    {
        return Some(found);
    }

    sessions
        .iter()
        .filter(|s| {
            s.get("contextWindow")
                .and_then(Value::as_f64)
                .unwrap_or(0.0)
                > 0.0
        })
        .max_by(|a, b| {
            let ta = a.get("lastSeen").and_then(Value::as_str).unwrap_or("");
            let tb = b.get("lastSeen").and_then(Value::as_str).unwrap_or("");
            ta.cmp(tb)
        })
        .and_then(extract)
}

fn bili_cache_dir() -> Option<PathBuf> {
    env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|d| !d.trim().is_empty())
        .map(PathBuf::from)
        .or_else(|| Some(env::temp_dir()))
}

fn bili_cache_file(dir: &Path, session_id: &str) -> PathBuf {
    let safe: String = session_id
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .take(64)
        .collect();
    dir.join(format!("agy-statusline-bili-{safe}.json"))
}

fn stabilize_bili_context(ctx: BiliContext, cache_dir: Option<&Path>) -> BiliContext {
    let Some(dir) = cache_dir else {
        return ctx;
    };
    let path = bili_cache_file(dir, &ctx.session_id);
    if ctx.is_usage {
        let payload = format!("{{\"pct\":{:.6}}}", ctx.pct);
        let _ = fs::write(&path, payload);
        return ctx;
    }
    if let Ok(raw) = fs::read_to_string(&path)
        && let Ok(parsed) = serde_json::from_str::<Value>(&raw)
        && let Some(cached_pct) = parsed.get("pct").and_then(Value::as_f64)
        && cached_pct.is_finite()
    {
        return BiliContext {
            pct: cached_pct.clamp(0.0, 100.0),
            ..ctx
        };
    }
    ctx
}

fn fetch_bili_context(payload: &Value) -> Option<BiliContext> {
    let url = env::var("CLOUD_CODE_URL").ok()?;
    let host_port = parse_bili_loopback_addr(&url)?;
    let addr: SocketAddr = host_port
        .to_socket_addrs()
        .ok()?
        .find(|a| a.ip().is_loopback())?;
    let mut stream = TcpStream::connect_timeout(&addr, Duration::from_millis(80)).ok()?;
    let _ = stream.set_write_timeout(Some(Duration::from_millis(80)));
    let _ = stream.set_read_timeout(Some(Duration::from_millis(120)));
    let req =
        format!("GET /__bili/stats HTTP/1.1\r\nHost: {host_port}\r\nConnection: close\r\n\r\n");
    stream.write_all(req.as_bytes()).ok()?;
    let mut raw = Vec::with_capacity(4096);
    stream.read_to_end(&mut raw).ok()?;
    let body = decode_http_body(&raw)?;
    let stats: Value = serde_json::from_str(&body).ok()?;
    let sid = payload
        .get("session_id")
        .and_then(Value::as_str)
        .or_else(|| payload.get("conversation_id").and_then(Value::as_str));
    let ctx = select_bili_context(&stats, sid)?;
    let cache_dir = bili_cache_dir();
    Some(stabilize_bili_context(ctx, cache_dir.as_deref()))
}

fn render_segment(text: &str, fg: Rgb, bg: Rgb) -> String {
    format!("{}{} {} {}", bg.bg(), fg.fg(), text, RESET)
}

fn render_statusline(
    payload: &Value,
    palette: Palette,
    home: Option<&str>,
    bili: Option<&BiliContext>,
) -> String {
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

    let ctx_pct = bili.map(|b| b.pct).or_else(|| {
        payload
            .get("context_window")
            .filter(|v| v.is_object())
            .and_then(|ctx| ctx.get("used_percentage"))
            .and_then(Value::as_f64)
    });
    if let Some(pct) = ctx_pct {
        let ctx_color = if pct >= 80.0 {
            palette.red
        } else if pct >= 50.0 {
            palette.yellow
        } else {
            palette.green
        };
        let suffix = match bili.filter(|b| b.blocks > 0) {
            Some(b) => format!(" ({}b)", b.blocks),
            None => String::new(),
        };
        let label = if terminal_width >= 90 {
            format!("{} {:.0}%{suffix}", render_progress_bar(pct, 6), pct)
        } else {
            format!("{:.0}%{suffix}", pct)
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
    segments.join(&sep)
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
            let bili = fetch_bili_context(&payload);
            println!(
                "{}",
                render_statusline(&payload, palette, home.as_deref(), bili.as_ref())
            );
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
    fn renders_single_line_powerline_statusline() {
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
        let out = render_statusline(&payload, Palette::default(), Some("/home/rakki"), None);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains("~/Projects/NixConfig"));
        assert!(lines[0].contains("jj"));
        assert!(lines[0].contains("Gemini 4 Neon  high"));
        assert!(lines[0].contains("42%"));
        assert!(lines[0].contains("◈ 87%"));
        assert!(lines[0].contains("plan"));
        assert!(lines[0].contains("sandbox"));
        assert!(lines[0].contains("󰚩 1"));
        assert!(lines[0].contains("󰈙 2"));
        assert!(!out.contains("╭─ π ─╮"));
    }

    #[test]
    fn handles_empty_payload_cleanly() {
        let out = render_statusline(&json!({}), Palette::default(), Some("/home/rakki"), None);
        assert_eq!(out.lines().count(), 1);
        assert!(out.contains("~"));
    }

    #[test]
    fn parses_bili_stats_and_overrides_inflated_context_percentage() {
        assert_eq!(
            parse_bili_loopback_addr(
                "http://127.0.0.1:18787/bili/https://daily-cloudcode-pa.googleapis.com"
            ),
            Some("127.0.0.1:18787".to_string())
        );
        assert_eq!(
            parse_bili_loopback_addr("https://daily-cloudcode-pa.googleapis.com"),
            None
        );

        let chunked = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10\r\n{\"sessions\": []}\r\n0\r\n\r\n";
        assert_eq!(
            decode_http_body(chunked).as_deref(),
            Some("{\"sessions\": []}")
        );

        let stats = json!({
            "sessions": [
                {
                    "id": "old-sess",
                    "contextTokens": 500000,
                    "contextWindow": 1000000,
                    "contextTokensSource": "usage",
                    "blocks": 0,
                    "lastSeen": "2026-11-21T10:00:00.000Z"
                },
                {
                    "id": "cur-sess",
                    "contextTokens": 62145,
                    "contextWindow": 1048576,
                    "contextTokensSource": "usage",
                    "blocks": 2,
                    "lastSeen": "2026-11-21T13:49:07.528Z"
                }
            ]
        });
        let bili = select_bili_context(&stats, Some("cur-sess")).expect("matching session");
        assert_eq!(bili.blocks, 2);
        assert!(bili.is_usage);
        assert!((bili.pct - 5.926).abs() < 0.01);

        let cache_dir = env::temp_dir().join(format!("agy-sl-test-{}", std::process::id()));
        let _ = fs::create_dir_all(&cache_dir);
        let usage = stabilize_bili_context(bili, Some(&cache_dir));
        assert!((usage.pct - 5.926).abs() < 0.01);

        let estimate_flicker = BiliContext {
            session_id: "cur-sess".to_string(),
            pct: 20.0,
            blocks: 2,
            is_usage: false,
        };
        let held = stabilize_bili_context(estimate_flicker, Some(&cache_dir));
        assert!((held.pct - 5.926).abs() < 0.01);

        let fresh_estimate = BiliContext {
            session_id: "brand-new-sess".to_string(),
            pct: 12.0,
            blocks: 0,
            is_usage: false,
        };
        let turn1 = stabilize_bili_context(fresh_estimate, Some(&cache_dir));
        assert!((turn1.pct - 12.0).abs() < 0.01);
        let _ = fs::remove_dir_all(&cache_dir);

        let payload = json!({
            "cwd": "/home/rakki/Projects/NixConfig",
            "context_window": { "used_percentage": 36.0 },
            "terminal_width": 120
        });
        let out = render_statusline(
            &payload,
            Palette::default(),
            Some("/home/rakki"),
            Some(&held),
        );
        assert!(out.contains("6% (2b)"));
        assert!(!out.contains("36%"));
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
