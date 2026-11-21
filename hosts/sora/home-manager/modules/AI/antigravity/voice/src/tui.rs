//! Ratatui terminal UI for `agy-voice`: status header, scrollable transcript,
//! tool badges, live audio level gauge, text input, and interactive modal picker.

use crate::acp::PermissionRequest;
use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Gauge, List, ListItem, Paragraph, Wrap};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MicMode {
    Vad,
    Ptt,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RouterBackend {
    Agy,
    Pi,
}

impl RouterBackend {
    pub fn label(self) -> &'static str {
        match self {
            Self::Agy => "AGY",
            Self::Pi => "PI",
        }
    }

    pub fn other(self) -> Self {
        match self {
            Self::Agy => Self::Pi,
            Self::Pi => Self::Agy,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentStatus {
    Starting,
    Listening,
    HearingSpeech,
    RecordingPtt,
    Transcribing,
    Thinking,
    Speaking,
    Muted,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    User,
    Assistant,
    Tool,
    System,
}

#[derive(Clone, Debug)]
pub struct TranscriptEntry {
    pub role: Role,
    pub text: String,
    pub tool_id: Option<String>,
}

pub struct ModalState {
    pub request: PermissionRequest,
    pub selected: usize,
}

pub struct AppState {
    pub status: AgentStatus,
    pub router: RouterBackend,
    pub mic_mode: MicMode,
    pub muted: bool,
    pub ptt_active: bool,
    pub duplex: bool,
    pub rms: f32,
    pub session_title: String,
    pub model_label: String,
    pub tokens_used: u64,
    pub tokens_limit: u64,
    pub entries: Vec<TranscriptEntry>,
    pub streaming_assistant: Option<usize>,
    pub scroll_from_bottom: u16,
    pub typing: bool,
    pub input_buf: String,
    pub modal: Option<ModalState>,
    pub notice: Option<String>,
}

impl AppState {
    pub fn new(router: RouterBackend, mic_mode: MicMode, duplex: bool) -> Self {
        Self {
            status: AgentStatus::Starting,
            router,
            mic_mode,
            muted: false,
            ptt_active: false,
            duplex,
            rms: 0.0,
            session_title: "Antigravity Voice".to_string(),
            model_label: match router {
                RouterBackend::Agy => "agy acp".to_string(),
                RouterBackend::Pi => "pi rpc".to_string(),
            },
            tokens_used: 0,
            tokens_limit: 0,
            entries: Vec::new(),
            streaming_assistant: None,
            scroll_from_bottom: 0,
            typing: false,
            input_buf: String::new(),
            modal: None,
            notice: None,
        }
    }

    pub fn push_entry(&mut self, role: Role, text: impl Into<String>) {
        self.streaming_assistant = None;
        self.entries.push(TranscriptEntry {
            role,
            text: text.into(),
            tool_id: None,
        });
        self.scroll_from_bottom = 0;
    }

    pub fn append_assistant_delta(&mut self, delta: &str) {
        if let Some(idx) = self.streaming_assistant
            && let Some(entry) = self.entries.get_mut(idx)
        {
            entry.text.push_str(delta);
            self.scroll_from_bottom = 0;
            return;
        }
        self.entries.push(TranscriptEntry {
            role: Role::Assistant,
            text: delta.to_string(),
            tool_id: None,
        });
        self.streaming_assistant = Some(self.entries.len() - 1);
        self.scroll_from_bottom = 0;
    }

    pub fn upsert_tool_call(&mut self, id: String, title: String, status: String) {
        let text = format!("{title} [{status}]");
        if !id.is_empty()
            && let Some(existing) = self
                .entries
                .iter_mut()
                .rev()
                .find(|e| e.role == Role::Tool && e.tool_id.as_deref() == Some(id.as_str()))
        {
            existing.text = text;
            return;
        }
        self.streaming_assistant = None;
        self.entries.push(TranscriptEntry {
            role: Role::Tool,
            text,
            tool_id: (!id.is_empty()).then_some(id),
        });
        self.scroll_from_bottom = 0;
    }
}

pub fn render(frame: &mut Frame<'_>, state: &AppState) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // header
            Constraint::Min(5),    // transcript
            Constraint::Length(3), // input + level bar
            Constraint::Length(1), // help footer
        ])
        .split(area);

    render_header(frame, chunks[0], state);
    render_transcript(frame, chunks[1], state);
    render_input_and_meter(frame, chunks[2], state);
    render_footer(frame, chunks[3], state);

    if let Some(modal) = &state.modal {
        render_modal(frame, area, modal);
    }
}

fn render_header(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let (badge, badge_color) = match state.status {
        AgentStatus::Starting => ("◌ STARTING", Color::Yellow),
        AgentStatus::Listening => ("● LISTENING", Color::Green),
        AgentStatus::HearingSpeech => ("◉ SPEECH", Color::LightMagenta),
        AgentStatus::RecordingPtt => ("● PTT REC", Color::Red),
        AgentStatus::Transcribing => ("◌ STT", Color::Cyan),
        AgentStatus::Thinking => ("✦ THINKING", Color::Magenta),
        AgentStatus::Speaking => ("▶ SPEAKING", Color::LightCyan),
        AgentStatus::Muted => ("✕ MUTED", Color::DarkGray),
    };

    let mode_tag = match state.mic_mode {
        MicMode::Vad => {
            if state.duplex {
                "VAD+DUPLEX"
            } else {
                "VAD"
            }
        }
        MicMode::Ptt => "PTT",
    };

    let usage = if state.tokens_limit > 0 {
        format!(
            "{}k/{}k",
            state.tokens_used / 1000,
            state.tokens_limit / 1000
        )
    } else {
        "—".to_string()
    };

    let router_color = match state.router {
        RouterBackend::Agy => Color::Cyan,
        RouterBackend::Pi => Color::LightGreen,
    };

    let line = Line::from(vec![
        Span::styled(
            format!(" {badge} "),
            Style::default()
                .fg(badge_color)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("│ "),
        Span::styled(
            format!("[{}]", state.router.label()),
            Style::default()
                .fg(router_color)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(" │ "),
        Span::styled(mode_tag, Style::default().fg(Color::Yellow)),
        Span::raw(" │ "),
        Span::styled(&state.model_label, Style::default().fg(Color::Cyan)),
        Span::raw(" │ "),
        Span::styled(usage, Style::default().fg(Color::DarkGray)),
        Span::raw(" │ "),
        Span::styled(&state.session_title, Style::default().fg(Color::White)),
    ]);

    let block = Block::default()
        .borders(Borders::ALL)
        .title(" agy-voice ")
        .border_style(Style::default().fg(badge_color));
    frame.render_widget(Paragraph::new(line).block(block), area);
}

fn render_transcript(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let mut lines: Vec<Line<'_>> = Vec::new();
    for entry in &state.entries {
        let (prefix, style) = match entry.role {
            Role::User => (
                "Lucky: ",
                Style::default()
                    .fg(Color::LightBlue)
                    .add_modifier(Modifier::BOLD),
            ),
            Role::Assistant => (
                "Ciel: ",
                Style::default()
                    .fg(Color::LightMagenta)
                    .add_modifier(Modifier::BOLD),
            ),
            Role::Tool => ("  ⚙ ", Style::default().fg(Color::Yellow)),
            Role::System => ("  • ", Style::default().fg(Color::DarkGray)),
        };

        let mut entry_lines = entry.text.lines();
        if let Some(first) = entry_lines.next() {
            lines.push(Line::from(vec![
                Span::styled(prefix, style),
                Span::raw(first.to_string()),
            ]));
            for cont in entry_lines {
                lines.push(Line::from(vec![
                    Span::raw(" ".repeat(prefix.chars().count())),
                    Span::raw(cont.to_string()),
                ]));
            }
        }
        if matches!(entry.role, Role::User | Role::Assistant) {
            lines.push(Line::raw(""));
        }
    }

    if lines.is_empty() {
        lines.push(Line::styled(
            "Speak naturally (VAD) or press `i` to type. Press `Space` for push-to-talk.",
            Style::default().fg(Color::DarkGray),
        ));
    }

    let inner_height = area.height.saturating_sub(2) as usize;
    let inner_width = area.width.saturating_sub(2).max(1) as usize;
    let estimated_rows: usize = lines
        .iter()
        .map(|l| l.width().max(1).div_ceil(inner_width))
        .sum();
    let max_scroll = estimated_rows.saturating_sub(inner_height) as u16;
    let scroll_y = max_scroll.saturating_sub(state.scroll_from_bottom.min(max_scroll));

    let block = Block::default()
        .borders(Borders::ALL)
        .title(" Conversation ");
    let paragraph = Paragraph::new(lines)
        .block(block)
        .wrap(Wrap { trim: false })
        .scroll((scroll_y, 0));
    frame.render_widget(paragraph, area);
}

fn render_input_and_meter(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let row = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Min(20), Constraint::Length(22)])
        .split(area);

    let (title, content, border_color) = if state.typing {
        (
            " Prompt (Enter to send, Esc to exit) ",
            format!("{}_", state.input_buf),
            Color::LightCyan,
        )
    } else if let Some(notice) = &state.notice {
        (" Status ", notice.clone(), Color::Yellow)
    } else {
        (
            " Prompt (press `i` to type) ",
            String::new(),
            Color::DarkGray,
        )
    };

    let input = Paragraph::new(content).block(
        Block::default()
            .borders(Borders::ALL)
            .title(title)
            .border_style(Style::default().fg(border_color)),
    );
    frame.render_widget(input, row[0]);

    let ratio = ((state.rms * 4.0).min(1.0) as f64).clamp(0.0, 1.0);
    let gauge_color = if state.muted {
        Color::DarkGray
    } else if ratio > 0.35 {
        Color::LightMagenta
    } else {
        Color::Green
    };
    let gauge = Gauge::default()
        .block(Block::default().borders(Borders::ALL).title(" Mic "))
        .gauge_style(Style::default().fg(gauge_color))
        .ratio(if state.muted { 0.0 } else { ratio })
        .label(if state.muted {
            "MUTED".to_string()
        } else {
            format!("{:.0}%", ratio * 100.0)
        });
    frame.render_widget(gauge, row[1]);
}

fn render_footer(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let hint = if state.modal.is_some() {
        " ↑/↓ select · Enter confirm · 1-9 quick pick · Esc cancel "
    } else if state.typing {
        " Enter send · Esc normal mode · Ctrl+C quit "
    } else {
        " Space PTT · m mute · v VAD/PTT · d duplex · r router(agy/pi) · s stop TTS · i type · Esc cancel · q quit "
    };
    let footer = Paragraph::new(hint)
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    frame.render_widget(footer, area);
}

fn render_modal(frame: &mut Frame<'_>, area: Rect, modal: &ModalState) {
    let width = area.width.min(72);
    let height = (modal.request.options.len() as u16 + 7).min(area.height.saturating_sub(2));
    let popup = Rect {
        x: area.x + (area.width.saturating_sub(width)) / 2,
        y: area.y + (area.height.saturating_sub(height)) / 2,
        width,
        height,
    };

    frame.render_widget(Clear, popup);

    let block = Block::default()
        .borders(Borders::ALL)
        .title(format!(" {} ", modal.request.kind))
        .border_style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        );
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    let sections = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(2)])
        .split(inner);

    let mut header_text = modal.request.title.clone();
    if let Some(detail) = &modal.request.detail {
        let short: String = detail.chars().take(120).collect();
        header_text.push('\n');
        header_text.push_str(&short);
    }
    frame.render_widget(
        Paragraph::new(header_text).wrap(Wrap { trim: true }),
        sections[0],
    );

    let items: Vec<ListItem<'_>> = modal
        .request
        .options
        .iter()
        .enumerate()
        .map(|(idx, opt)| {
            let marker = if idx == modal.selected { "▸" } else { " " };
            let style = if idx == modal.selected {
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Yellow)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            ListItem::new(format!(" {marker} [{}] {}", idx + 1, opt.name)).style(style)
        })
        .collect();

    frame.render_widget(List::new(items), sections[1]);
}
