//! `agy-voice`: local CPU-pinned Rust voice TUI (Silero VAD + Whisper.cpp +
//! Kokoro-82M) delegating directly to Antigravity CLI over `agy acp`.

mod acp;
mod audio;
mod models;
mod pi;
mod sherpa;
mod speech;
mod stt;
mod tui;

use acp::{AcpClient, AcpEvent};
use anyhow::{Context, Result};
use audio::{
    CAPTURE_SAMPLE_RATE, MicCapture, SampleRing, VAD_WINDOW_SAMPLES, frame_rms,
    play_pcm_interruptible,
};
use clap::{Parser, ValueEnum};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use models::{resolve_models, setup_models};
use pi::PiClient;
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use sherpa::{KokoroTts, SileroVad, VadOptions};
use speech::{SentenceStream, looks_portuguese};
use std::io;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};
use stt::WhisperStt;
use tui::{AgentStatus, AppState, MicMode, ModalState, Role, RouterBackend};

#[derive(Clone, Copy, ValueEnum)]
enum CliMode {
    Vad,
    Ptt,
}

#[derive(Clone, Copy, ValueEnum)]
enum CliBackend {
    Agy,
    Pi,
}

#[derive(Parser)]
#[command(
    name = "agy-voice",
    version,
    about = "Local voice TUI for Antigravity CLI using Silero VAD, Whisper.cpp, and Kokoro-82M over agy acp"
)]
struct Cli {
    /// Download required local models (Silero VAD, Kokoro-82M int8, Whisper small-q5_1) and exit
    #[arg(long)]
    setup_models: bool,

    /// Initial agent backend to route prompts to (switchable live with `r`)
    #[arg(long, value_enum, default_value_t = CliBackend::Agy)]
    backend: CliBackend,

    /// Initial microphone trigger mode (hybrid: switchable anytime with `v` or `Space`)
    #[arg(long, value_enum, default_value_t = CliMode::Vad)]
    mode: CliMode,

    /// Keep VAD active while TTS speaks for hands-free barge-in (use headphones)
    #[arg(long)]
    duplex: bool,

    /// Silero VAD speech probability threshold (lower = faster/more sensitive pickup)
    #[arg(long, default_value_t = 0.30)]
    vad_threshold: f32,

    /// Milliseconds of pre-speech audio prepended before VAD triggers (prevents clipped starts)
    #[arg(long, default_value_t = 350)]
    vad_preroll_ms: u32,

    /// Milliseconds of silence required before VAD ends an utterance (allows mid-sentence pauses)
    #[arg(long, default_value_t = 2200)]
    vad_silence_ms: u32,

    /// Prompt interactively for tool permissions instead of auto-approving like agy's default config
    #[arg(long)]
    ask_permissions: bool,

    /// CPU thread cap shared by Whisper and Kokoro (keeps gaming FPS smooth, 0 VRAM)
    #[arg(long, default_value_t = 4)]
    threads: usize,

    /// Whisper language (`auto`, `pt`, `en`)
    #[arg(long, default_value = "auto")]
    lang: String,

    /// Kokoro speaker ID for English responses (3 = af_heart, 2 = af_bella, 7 = af_nova)
    #[arg(long, default_value_t = 3)]
    speaker_en: i32,

    /// Kokoro speaker ID for Brazilian Portuguese responses (42 = pf_dora, 43 = pm_alex)
    #[arg(long, default_value_t = 42)]
    speaker_pt: i32,

    /// TTS playback speed multiplier (0.5 - 2.0)
    #[arg(long, default_value_t = 1.0)]
    speed: f32,

    /// Disable TTS audio playback (STT + TUI only)
    #[arg(long)]
    no_tts: bool,

    /// Max spoken characters per turn before summarizing to screen (0 = unlimited)
    #[arg(long, default_value_t = 800)]
    max_spoken_chars: usize,

    /// Antigravity model slug via ACP (defaults to Gemini 4 Neon Medium)
    #[arg(long, default_value = "gemini-4-neon-medium")]
    model: String,

    /// Reasoning effort / thinking level via ACP (`low`, `medium`, `high`, `xhigh`)
    #[arg(long, default_value = "medium")]
    effort: String,

    /// Workspace directory passed to `agy acp` (defaults to current directory)
    #[arg(long)]
    cwd: Option<PathBuf>,

    /// Explicit path to a Whisper GGML model file
    #[arg(long)]
    whisper_model: Option<PathBuf>,

    /// Explicit directory containing Kokoro ONNX files
    #[arg(long)]
    kokoro_dir: Option<PathBuf>,

    /// Explicit path to `silero_vad.onnx`
    #[arg(long)]
    vad_model: Option<PathBuf>,
}

enum AppEvent {
    MicRms(f32),
    VadSpeechStart,
    VadSpeechEnd,
    Transcribed(String),
    SttEmpty,
    SttError(String),
    TtsStarted,
    TtsFinished,
    TtsError(String),
    Backend(RouterBackend, AcpEvent),
}

struct BackendRouter {
    active: RouterBackend,
    agy: Option<AcpClient>,
    pi: Option<PiClient>,
    agy_model: String,
    pi_model: String,
    agy_usage: (u64, u64),
    pi_usage: (u64, u64),
    cwd: PathBuf,
    agy_model_arg: String,
    agy_effort_arg: String,
    skip_permissions: bool,
    app_tx: mpsc::Sender<AppEvent>,
}

impl BackendRouter {
    fn new(
        initial: RouterBackend,
        cwd: PathBuf,
        agy_model_arg: String,
        agy_effort_arg: String,
        skip_permissions: bool,
        app_tx: mpsc::Sender<AppEvent>,
    ) -> Result<Self> {
        let mut router = Self {
            active: initial,
            agy: None,
            pi: None,
            agy_model: agy_model_arg.clone(),
            pi_model: "pi rpc".to_string(),
            agy_usage: (0, 0),
            pi_usage: (0, 0),
            cwd,
            agy_model_arg,
            agy_effort_arg,
            skip_permissions,
            app_tx,
        };
        router.ensure_started(initial)?;
        Ok(router)
    }

    fn ensure_started(&mut self, target: RouterBackend) -> Result<()> {
        match target {
            RouterBackend::Agy if self.agy.is_none() => {
                let (tx, rx) = mpsc::channel::<AcpEvent>();
                let client = AcpClient::start(
                    &self.cwd,
                    Some(self.agy_model_arg.as_str()),
                    Some(self.agy_effort_arg.as_str()),
                    self.skip_permissions,
                    tx,
                )?;
                let app_tx = self.app_tx.clone();
                thread::spawn(move || {
                    while let Ok(ev) = rx.recv() {
                        if app_tx
                            .send(AppEvent::Backend(RouterBackend::Agy, ev))
                            .is_err()
                        {
                            break;
                        }
                    }
                });
                self.agy = Some(client);
            }
            RouterBackend::Pi if self.pi.is_none() => {
                let (tx, rx) = mpsc::channel::<AcpEvent>();
                let client = PiClient::start(&self.cwd, tx)?;
                let app_tx = self.app_tx.clone();
                thread::spawn(move || {
                    while let Ok(ev) = rx.recv() {
                        if app_tx
                            .send(AppEvent::Backend(RouterBackend::Pi, ev))
                            .is_err()
                        {
                            break;
                        }
                    }
                });
                self.pi = Some(client);
            }
            _ => {}
        }
        Ok(())
    }

    fn switch_to(&mut self, target: RouterBackend) -> Result<()> {
        self.ensure_started(target)?;
        self.active = target;
        Ok(())
    }

    fn active_model_label(&self) -> String {
        match self.active {
            RouterBackend::Agy => self.agy_model.clone(),
            RouterBackend::Pi => self.pi_model.clone(),
        }
    }

    fn active_usage(&self) -> (u64, u64) {
        match self.active {
            RouterBackend::Agy => self.agy_usage,
            RouterBackend::Pi => self.pi_usage,
        }
    }

    fn record_model(&mut self, backend: RouterBackend, model: String) {
        match backend {
            RouterBackend::Agy => self.agy_model = model,
            RouterBackend::Pi => self.pi_model = model,
        }
    }

    fn record_usage(&mut self, backend: RouterBackend, used: u64, size: u64) {
        match backend {
            RouterBackend::Agy => self.agy_usage = (used, size),
            RouterBackend::Pi => self.pi_usage = (used, size),
        }
    }

    fn send_prompt(&self, text: &str) -> Result<()> {
        match self.active {
            RouterBackend::Agy => self
                .agy
                .as_ref()
                .context("agy backend not connected")?
                .send_prompt(text),
            RouterBackend::Pi => self
                .pi
                .as_ref()
                .context("pi backend not connected")?
                .send_prompt(text),
        }
    }

    fn cancel(&self) -> Result<()> {
        match self.active {
            RouterBackend::Agy => {
                if let Some(c) = &self.agy {
                    c.cancel()?;
                }
            }
            RouterBackend::Pi => {
                if let Some(c) = &self.pi {
                    c.cancel()?;
                }
            }
        }
        Ok(())
    }

    fn reply_modal(&self, rpc_id: serde_json::Value, option_id: Option<&str>) -> Result<()> {
        match self.active {
            RouterBackend::Agy => self
                .agy
                .as_ref()
                .context("agy backend not connected")?
                .reply_permission(rpc_id, option_id),
            RouterBackend::Pi => self
                .pi
                .as_ref()
                .context("pi backend not connected")?
                .reply_ui(rpc_id, option_id),
        }
    }
}

enum TtsCommand {
    Speak(String),
    Shutdown,
}

struct MicControl {
    mode: Mutex<MicMode>,
    muted: AtomicBool,
    ptt_active: AtomicBool,
    is_speaking: AtomicBool,
    duplex: AtomicBool,
    shutdown: AtomicBool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.setup_models {
        let bundle = setup_models(cli.whisper_model.as_deref())?;
        println!("Models ready:");
        println!("  VAD:     {}", bundle.vad_model.display());
        println!("  Whisper: {}", bundle.whisper_model.display());
        println!("  Kokoro:  {}", bundle.kokoro.model.display());
        return Ok(());
    }

    let bundle = match resolve_models(
        cli.whisper_model.as_deref(),
        cli.kokoro_dir.as_deref(),
        cli.vad_model.as_deref(),
    ) {
        Ok(b) => b,
        Err(err) => {
            eprintln!("{err}");
            eprintln!("Tip: run `agy-voice --setup-models` once to fetch the local models.");
            return Err(err);
        }
    };

    let cwd = match cli.cwd {
        Some(p) => p,
        None => std::env::current_dir().context("failed to read current directory")?,
    };

    // Load local engines before entering raw terminal mode so startup errors stay readable.
    eprintln!("Loading Silero VAD...");
    let vad_opts = VadOptions {
        threshold: cli.vad_threshold.clamp(0.05, 0.95),
        min_silence_duration: (cli.vad_silence_ms.clamp(250, 5000) as f32) / 1000.0,
        ..VadOptions::default()
    };
    let vad = SileroVad::new(&bundle.vad_model, &vad_opts)?;

    eprintln!(
        "Starting warm whisper-server (CPU, {} threads)...",
        cli.threads
    );
    let stt = Arc::new(WhisperStt::start(
        &bundle.whisper_model,
        cli.threads,
        &cli.lang,
    )?);

    let tts_engine = if cli.no_tts {
        None
    } else {
        eprintln!("Loading Kokoro-82M TTS (CPU, {} threads)...", cli.threads);
        Some(KokoroTts::new(&bundle.kokoro, cli.threads as i32, "en")?)
    };

    let (app_tx, app_rx) = mpsc::channel::<AppEvent>();
    let initial_backend = match cli.backend {
        CliBackend::Agy => RouterBackend::Agy,
        CliBackend::Pi => RouterBackend::Pi,
    };

    match initial_backend {
        RouterBackend::Agy => eprintln!(
            "Connecting to `agy acp` ({}, effort={})...",
            cli.model, cli.effort
        ),
        RouterBackend::Pi => eprintln!("Connecting to `pi --mode rpc`..."),
    }
    let mut router = BackendRouter::new(
        initial_backend,
        cwd,
        cli.model.clone(),
        cli.effort.clone(),
        !cli.ask_permissions,
        app_tx.clone(),
    )?;

    let initial_mode = match cli.mode {
        CliMode::Vad => MicMode::Vad,
        CliMode::Ptt => MicMode::Ptt,
    };

    let mic_ctrl = Arc::new(MicControl {
        mode: Mutex::new(initial_mode),
        muted: AtomicBool::new(false),
        ptt_active: AtomicBool::new(false),
        is_speaking: AtomicBool::new(false),
        duplex: AtomicBool::new(cli.duplex),
        shutdown: AtomicBool::new(false),
    });

    // TTS worker thread
    let tts_cancel = Arc::new(AtomicBool::new(false));
    let (tts_tx, tts_rx) = mpsc::channel::<TtsCommand>();
    let tts_handle = spawn_tts_worker(
        tts_engine,
        bundle.kokoro.clone(),
        cli.threads as i32,
        tts_rx,
        Arc::clone(&tts_cancel),
        Arc::clone(&mic_ctrl),
        app_tx.clone(),
        cli.speaker_en,
        cli.speaker_pt,
        cli.speed,
    );

    // STT worker thread
    let (stt_tx, stt_rx) = mpsc::channel::<Vec<f32>>();
    let stt_handle = spawn_stt_worker(Arc::clone(&stt), stt_rx, app_tx.clone());

    // Audio capture + Silero VAD thread
    let preroll_samples = ((cli.vad_preroll_ms as usize) * CAPTURE_SAMPLE_RATE as usize) / 1000;
    let mic_handle = spawn_mic_worker(
        vad,
        Arc::clone(&mic_ctrl),
        Arc::clone(&tts_cancel),
        preroll_samples,
        stt_tx.clone(),
        app_tx.clone(),
    );

    // Install panic hook so terminal always restores cleanly.
    let prev_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen);
        prev_hook(info);
    }));

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    terminal.clear()?;

    let mut state = AppState::new(initial_backend, initial_mode, cli.duplex);
    let mut sentences = SentenceStream::new(cli.max_spoken_chars);
    let mut turn_active = false;
    let mut active_tools: std::collections::HashSet<String> = std::collections::HashSet::new();

    let run_result = (|| -> Result<()> {
        loop {
            // Drain all pending background events before redraw.
            while let Ok(ev) = app_rx.try_recv() {
                match ev {
                    AppEvent::MicRms(rms) => {
                        state.rms = rms;
                    }
                    AppEvent::VadSpeechStart => {
                        if !turn_active {
                            state.status = AgentStatus::HearingSpeech;
                        }
                    }
                    AppEvent::VadSpeechEnd => {
                        if !turn_active {
                            state.status = AgentStatus::Transcribing;
                        }
                    }
                    AppEvent::Transcribed(text) => {
                        state.notice = None;
                        if turn_active {
                            state.push_entry(
                                Role::System,
                                format!("Queued skipped while agent busy: {text}"),
                            );
                        } else {
                            submit_prompt(
                                &text,
                                &router,
                                &mut state,
                                &mut sentences,
                                &tts_cancel,
                                &mut turn_active,
                            );
                        }
                    }
                    AppEvent::SttEmpty => {
                        if !turn_active {
                            state.status = idle_status(&state);
                        }
                    }
                    AppEvent::SttError(e) => {
                        state.notice = Some(format!("STT error: {e}"));
                        if !turn_active {
                            state.status = idle_status(&state);
                        }
                    }
                    AppEvent::TtsStarted => {
                        state.status = AgentStatus::Speaking;
                    }
                    AppEvent::TtsFinished => {
                        if !turn_active {
                            state.status = idle_status(&state);
                        }
                    }
                    AppEvent::TtsError(e) => {
                        state.notice = Some(format!("TTS error: {e}"));
                    }
                    AppEvent::Backend(source, acp_ev) => match acp_ev {
                        AcpEvent::Ready {
                            session_id,
                            model_label,
                        } => {
                            if let Some(m) = model_label {
                                router.record_model(source, m.clone());
                                if source == state.router {
                                    state.model_label = m;
                                }
                            }
                            if source == state.router {
                                state.status = idle_status(&state);
                            }
                            state.push_entry(
                                Role::System,
                                format!("Connected to {} (session {session_id})", source.label()),
                            );
                        }
                        AcpEvent::TextDelta(delta) => {
                            if source != state.router {
                                continue;
                            }
                            state.append_assistant_delta(&delta);
                            // Stay quiet while tools are actively executing; speak clean
                            // conversational responses once tool work settles.
                            if active_tools.is_empty() {
                                for sentence in sentences.push_delta(&delta) {
                                    let _ = tts_tx.send(TtsCommand::Speak(sentence));
                                }
                            }
                        }
                        AcpEvent::Thinking => {
                            if source == state.router
                                && !mic_ctrl.is_speaking.load(Ordering::Relaxed)
                            {
                                state.status = AgentStatus::Thinking;
                            }
                        }
                        AcpEvent::ToolCall { id, title, status } => {
                            if source != state.router {
                                continue;
                            }
                            let is_done = matches!(
                                status.as_str(),
                                "completed" | "done" | "failed" | "error" | "cancelled"
                            );
                            if !id.is_empty() {
                                if is_done {
                                    active_tools.remove(&id);
                                } else {
                                    // Clear half-buffered pre-tool chatter so Ciel stays
                                    // quiet while running commands/edits.
                                    sentences.clear();
                                    active_tools.insert(id.clone());
                                }
                            }
                            state.upsert_tool_call(id, title, status);
                        }
                        AcpEvent::Usage { used, size } => {
                            router.record_usage(source, used, size);
                            if source == state.router {
                                state.tokens_used = used;
                                state.tokens_limit = size;
                            }
                        }
                        AcpEvent::Title(title) => {
                            if source == state.router {
                                state.session_title = title;
                            }
                        }
                        AcpEvent::PermissionRequest(req) => {
                            if source != state.router {
                                continue;
                            }
                            let spoken = format!("Selection requested: {}", req.title);
                            let _ = tts_tx.send(TtsCommand::Speak(spoken));
                            state.modal = Some(ModalState {
                                request: req,
                                selected: 0,
                            });
                        }
                        AcpEvent::TurnComplete { stop_reason, error } => {
                            if source != state.router {
                                continue;
                            }
                            turn_active = false;
                            active_tools.clear();
                            state.streaming_assistant = None;
                            for tail in sentences.flush() {
                                let _ = tts_tx.send(TtsCommand::Speak(tail));
                            }
                            if let Some(err) = error {
                                state.push_entry(Role::System, format!("Error: {err}"));
                            } else if stop_reason == "cancelled" {
                                state.push_entry(Role::System, "Turn cancelled.");
                            }
                            if !mic_ctrl.is_speaking.load(Ordering::Relaxed) {
                                state.status = idle_status(&state);
                            }
                        }
                        AcpEvent::Error(e) => {
                            state.notice = Some(format!("[{}] {e}", source.label()));
                        }
                        AcpEvent::Disconnected => {
                            state.push_entry(
                                Role::System,
                                format!("{} backend disconnected.", source.label()),
                            );
                            if source == state.router {
                                turn_active = false;
                                state.status = AgentStatus::Muted;
                            }
                        }
                    },
                }
            }

            terminal.draw(|f| tui::render(f, &state))?;

            if event::poll(Duration::from_millis(33))?
                && let Event::Key(key) = event::read()?
                && key.kind == KeyEventKind::Press
                && handle_key(
                    key,
                    &mut state,
                    &mic_ctrl,
                    &mut router,
                    &mut sentences,
                    &tts_cancel,
                    &mut turn_active,
                )
            {
                break;
            }
        }
        Ok(())
    })();

    // Clean teardown
    mic_ctrl.shutdown.store(true, Ordering::Relaxed);
    tts_cancel.store(true, Ordering::Relaxed);
    let _ = tts_tx.send(TtsCommand::Shutdown);
    drop(stt_tx);

    let _ = disable_raw_mode();
    let _ = execute!(terminal.backend_mut(), LeaveAlternateScreen);
    let _ = terminal.show_cursor();

    let _ = mic_handle.join();
    let _ = stt_handle.join();
    let _ = tts_handle.join();

    run_result
}

fn idle_status(state: &AppState) -> AgentStatus {
    if state.muted {
        AgentStatus::Muted
    } else if state.ptt_active {
        AgentStatus::RecordingPtt
    } else {
        AgentStatus::Listening
    }
}

fn submit_prompt(
    text: &str,
    router: &BackendRouter,
    state: &mut AppState,
    sentences: &mut SentenceStream,
    tts_cancel: &Arc<AtomicBool>,
    turn_active: &mut bool,
) {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return;
    }
    tts_cancel.store(false, Ordering::Relaxed);
    sentences.clear();
    state.push_entry(Role::User, trimmed);
    state.status = AgentStatus::Thinking;
    *turn_active = true;
    if let Err(e) = router.send_prompt(trimmed) {
        *turn_active = false;
        state.push_entry(Role::System, format!("Failed to send prompt: {e}"));
        state.status = idle_status(state);
    }
}

/// Returns `true` when the user requests exiting the app.
fn handle_key(
    key: KeyEvent,
    state: &mut AppState,
    mic_ctrl: &Arc<MicControl>,
    router: &mut BackendRouter,
    sentences: &mut SentenceStream,
    tts_cancel: &Arc<AtomicBool>,
    turn_active: &mut bool,
) -> bool {
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        return true;
    }

    // 1. Modal dialog takes priority over everything else.
    if let Some(modal) = &mut state.modal {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                if modal.selected > 0 {
                    modal.selected -= 1;
                }
            }
            KeyCode::Down | KeyCode::Char('j') => {
                if modal.selected + 1 < modal.request.options.len() {
                    modal.selected += 1;
                }
            }
            KeyCode::Enter => {
                if let Some(m) = state.modal.take() {
                    let chosen = m.request.options.get(m.selected);
                    let opt_id = chosen.map(|o| o.option_id.as_str());
                    let label = chosen.map(|o| o.name.as_str()).unwrap_or("cancelled");
                    let _ = router.reply_modal(m.request.rpc_id, opt_id);
                    state.push_entry(Role::System, format!("Selected: {label}"));
                }
            }
            KeyCode::Char(c) if ('1'..='9').contains(&c) => {
                let idx = (c as usize) - ('1' as usize);
                if idx < modal.request.options.len()
                    && let Some(m) = state.modal.take()
                {
                    let opt = &m.request.options[idx];
                    let _ = router.reply_modal(m.request.rpc_id, Some(&opt.option_id));
                    state.push_entry(Role::System, format!("Selected: {}", opt.name));
                }
            }
            KeyCode::Esc => {
                if let Some(m) = state.modal.take() {
                    let _ = router.reply_modal(m.request.rpc_id, None);
                    state.push_entry(Role::System, "Selection cancelled.");
                }
            }
            _ => {}
        }
        return false;
    }

    // 2. Typing mode
    if state.typing {
        match key.code {
            KeyCode::Esc => {
                state.typing = false;
            }
            KeyCode::Enter => {
                let prompt = std::mem::take(&mut state.input_buf);
                state.typing = false;
                if !prompt.trim().is_empty() && !*turn_active {
                    submit_prompt(&prompt, router, state, sentences, tts_cancel, turn_active);
                }
            }
            KeyCode::Backspace => {
                state.input_buf.pop();
            }
            KeyCode::Char(c) => {
                state.input_buf.push(c);
            }
            _ => {}
        }
        return false;
    }

    // 3. Normal voice-control mode
    match key.code {
        KeyCode::Char('q') => return true,
        KeyCode::Char('i') => {
            state.typing = true;
        }
        KeyCode::Char('m') => {
            state.muted = !state.muted;
            mic_ctrl.muted.store(state.muted, Ordering::Relaxed);
            if !*turn_active && !mic_ctrl.is_speaking.load(Ordering::Relaxed) {
                state.status = idle_status(state);
            }
        }
        KeyCode::Char('d') => {
            state.duplex = !state.duplex;
            mic_ctrl.duplex.store(state.duplex, Ordering::Relaxed);
            state.notice = Some(if state.duplex {
                "Duplex barge-in ON (use headphones)".to_string()
            } else {
                "Duplex barge-in OFF (echo-safe)".to_string()
            });
        }
        KeyCode::Char('r') => {
            if *turn_active {
                state.notice = Some(
                    "Finish or Esc-cancel the active turn before switching router".to_string(),
                );
            } else {
                let target = state.router.other();
                match router.switch_to(target) {
                    Ok(()) => {
                        state.router = target;
                        state.model_label = router.active_model_label();
                        let (used, size) = router.active_usage();
                        state.tokens_used = used;
                        state.tokens_limit = size;
                        state.notice = Some(format!("Routing prompts to [{}]", target.label()));
                        state.push_entry(
                            Role::System,
                            format!("Switched router -> [{}]", target.label()),
                        );
                    }
                    Err(e) => {
                        state.notice = Some(format!("Failed to start [{}]: {e}", target.label()));
                    }
                }
            }
        }
        KeyCode::Char('v') => {
            state.mic_mode = match state.mic_mode {
                MicMode::Vad => MicMode::Ptt,
                MicMode::Ptt => MicMode::Vad,
            };
            state.ptt_active = false;
            mic_ctrl.ptt_active.store(false, Ordering::Relaxed);
            *mic_ctrl.mode.lock().unwrap() = state.mic_mode;
            state.notice = Some(match state.mic_mode {
                MicMode::Vad => "Switched to hands-free Silero VAD mode".to_string(),
                MicMode::Ptt => {
                    "Switched to Push-to-Talk mode (press Space to start/stop)".to_string()
                }
            });
            if !*turn_active && !mic_ctrl.is_speaking.load(Ordering::Relaxed) {
                state.status = idle_status(state);
            }
        }
        KeyCode::Char(' ') => {
            // Cut TTS immediately and toggle Push-to-Talk capture (works even in hybrid VAD mode).
            tts_cancel.store(true, Ordering::Relaxed);
            state.ptt_active = !state.ptt_active;
            mic_ctrl
                .ptt_active
                .store(state.ptt_active, Ordering::Relaxed);
            if state.ptt_active {
                state.muted = false;
                mic_ctrl.muted.store(false, Ordering::Relaxed);
                state.status = AgentStatus::RecordingPtt;
            } else if !*turn_active {
                state.status = AgentStatus::Transcribing;
            }
        }
        KeyCode::Char('s') => {
            tts_cancel.store(true, Ordering::Relaxed);
            sentences.clear();
            if !*turn_active {
                state.status = idle_status(state);
            }
        }
        KeyCode::Esc => {
            tts_cancel.store(true, Ordering::Relaxed);
            sentences.clear();
            if *turn_active {
                let _ = router.cancel();
            }
            if state.ptt_active {
                state.ptt_active = false;
                mic_ctrl.ptt_active.store(false, Ordering::Relaxed);
            }
            state.status = idle_status(state);
        }
        KeyCode::Up | KeyCode::Char('k') => {
            state.scroll_from_bottom = state.scroll_from_bottom.saturating_add(2);
        }
        KeyCode::Down | KeyCode::Char('j') => {
            state.scroll_from_bottom = state.scroll_from_bottom.saturating_sub(2);
        }
        KeyCode::PageUp => {
            state.scroll_from_bottom = state.scroll_from_bottom.saturating_add(12);
        }
        KeyCode::PageDown => {
            state.scroll_from_bottom = state.scroll_from_bottom.saturating_sub(12);
        }
        _ => {}
    }
    false
}

fn spawn_mic_worker(
    mut vad: SileroVad,
    ctrl: Arc<MicControl>,
    tts_cancel: Arc<AtomicBool>,
    preroll_samples: usize,
    stt_tx: mpsc::Sender<Vec<f32>>,
    app_tx: mpsc::Sender<AppEvent>,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut capture = match MicCapture::start() {
            Ok(c) => c,
            Err(e) => {
                let _ = app_tx.send(AppEvent::SttError(format!("Mic capture failed: {e}")));
                return;
            }
        };

        let mut frame = vec![0.0f32; VAD_WINDOW_SAMPLES];
        // Retain up to 30 seconds of sample-indexed history so `seg.start` always
        // maps cleanly even for long utterances.
        let mut history = SampleRing::new(CAPTURE_SAMPLE_RATE as usize * 30);
        let mut ptt_buf: Vec<f32> = Vec::new();
        let mut was_ptt = false;
        let mut was_speech = false;
        let mut was_speaking = false;
        let mut echo_guard_until = Instant::now();

        while !ctrl.shutdown.load(Ordering::Relaxed) {
            if capture.read_frame(&mut frame).is_err() {
                break;
            }

            let rms = frame_rms(&frame);
            let _ = app_tx.send(AppEvent::MicRms(rms));

            if ctrl.muted.load(Ordering::Relaxed) {
                if was_speech {
                    vad.reset();
                    history.clear();
                    was_speech = false;
                }
                ptt_buf.clear();
                was_ptt = false;
                continue;
            }

            let ptt_now = ctrl.ptt_active.load(Ordering::Relaxed);
            if ptt_now {
                if !was_ptt {
                    ptt_buf.clear();
                    vad.reset();
                    history.clear();
                    was_speech = false;
                    was_ptt = true;
                }
                ptt_buf.extend_from_slice(&frame);
                continue;
            } else if was_ptt {
                was_ptt = false;
                if !ptt_buf.is_empty() {
                    let utterance = std::mem::take(&mut ptt_buf);
                    let _ = stt_tx.send(utterance);
                }
                continue;
            }

            let mode = *ctrl.mode.lock().unwrap();
            if mode != MicMode::Vad {
                continue;
            }

            let speaking = ctrl.is_speaking.load(Ordering::Relaxed);
            let duplex = ctrl.duplex.load(Ordering::Relaxed);

            if speaking && !duplex {
                if !was_speaking {
                    vad.reset();
                    history.clear();
                    was_speech = false;
                    was_speaking = true;
                }
                continue;
            } else if was_speaking {
                was_speaking = false;
                echo_guard_until = Instant::now() + Duration::from_millis(280);
                vad.reset();
                history.clear();
                continue;
            }

            if Instant::now() < echo_guard_until {
                continue;
            }

            history.push_slice(&frame);
            vad.accept_waveform(&frame);
            let in_speech = vad.is_speech_detected();
            if in_speech && !was_speech {
                was_speech = true;
                if speaking && duplex {
                    // Cut TTS directly from the audio thread with zero UI-loop hop.
                    tts_cancel.store(true, Ordering::Relaxed);
                }
                let _ = app_tx.send(AppEvent::VadSpeechStart);
            }

            let segments = vad.pop_segments();
            if !segments.is_empty() {
                was_speech = false;
                let _ = app_tx.send(AppEvent::VadSpeechEnd);
                for seg in segments {
                    let mut full = history.preroll_before(seg.start, preroll_samples);
                    full.extend_from_slice(&seg.samples);
                    let _ = stt_tx.send(full);
                }
            }
        }
    })
}

fn spawn_stt_worker(
    stt: Arc<WhisperStt>,
    rx: mpsc::Receiver<Vec<f32>>,
    app_tx: mpsc::Sender<AppEvent>,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        while let Ok(samples) = rx.recv() {
            match stt.transcribe(&samples) {
                Ok(Some(text)) => {
                    let _ = app_tx.send(AppEvent::Transcribed(text));
                }
                Ok(None) => {
                    let _ = app_tx.send(AppEvent::SttEmpty);
                }
                Err(e) => {
                    let _ = app_tx.send(AppEvent::SttError(e.to_string()));
                }
            }
        }
    })
}

#[allow(clippy::too_many_arguments)]
fn spawn_tts_worker(
    mut tts_en: Option<KokoroTts>,
    kokoro_paths: sherpa::KokoroPaths,
    tts_threads: i32,
    rx: mpsc::Receiver<TtsCommand>,
    cancel: Arc<AtomicBool>,
    mic_ctrl: Arc<MicControl>,
    app_tx: mpsc::Sender<AppEvent>,
    speaker_en: i32,
    speaker_pt: i32,
    speed: f32,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut tts_pt: Option<KokoroTts> = None;
        let mut next_cmd: Option<TtsCommand> = None;
        loop {
            let cmd = match next_cmd.take() {
                Some(c) => c,
                None => match rx.recv() {
                    Ok(c) => c,
                    Err(_) => break,
                },
            };

            match cmd {
                TtsCommand::Shutdown => break,
                TtsCommand::Speak(text) => {
                    if tts_en.is_none() {
                        continue;
                    }
                    if cancel.load(Ordering::Relaxed) {
                        while let Ok(queued) = rx.try_recv() {
                            if matches!(queued, TtsCommand::Shutdown) {
                                return;
                            }
                        }
                        cancel.store(false, Ordering::Relaxed);
                        continue;
                    }

                    mic_ctrl.is_speaking.store(true, Ordering::Relaxed);
                    let _ = app_tx.send(AppEvent::TtsStarted);

                    let is_pt = looks_portuguese(&text);
                    let (engine, sid) = if is_pt {
                        if tts_pt.is_none() {
                            match KokoroTts::new(&kokoro_paths, tts_threads, "pt-br") {
                                Ok(pt_engine) => tts_pt = Some(pt_engine),
                                Err(e) => {
                                    let _ = app_tx.send(AppEvent::TtsError(format!(
                                        "PT-BR TTS init failed: {e}"
                                    )));
                                }
                            }
                        }
                        if let Some(pt_engine) = tts_pt.as_mut() {
                            (pt_engine, speaker_pt)
                        } else {
                            (tts_en.as_mut().unwrap(), speaker_en)
                        }
                    } else {
                        (tts_en.as_mut().unwrap(), speaker_en)
                    };

                    match engine.generate(&text, sid, speed, &cancel) {
                        Ok(Some(samples)) if !samples.is_empty() => {
                            if let Err(e) =
                                play_pcm_interruptible(&samples, engine.sample_rate(), &cancel)
                            {
                                let _ = app_tx.send(AppEvent::TtsError(e.to_string()));
                            }
                        }
                        Ok(_) => {}
                        Err(e) => {
                            let _ = app_tx.send(AppEvent::TtsError(e.to_string()));
                        }
                    }

                    if cancel.load(Ordering::Relaxed) {
                        while let Ok(queued) = rx.try_recv() {
                            if matches!(queued, TtsCommand::Shutdown) {
                                mic_ctrl.is_speaking.store(false, Ordering::Relaxed);
                                return;
                            }
                        }
                        cancel.store(false, Ordering::Relaxed);
                        mic_ctrl.is_speaking.store(false, Ordering::Relaxed);
                        let _ = app_tx.send(AppEvent::TtsFinished);
                        continue;
                    }

                    match rx.try_recv() {
                        Ok(queued) => next_cmd = Some(queued),
                        Err(_) => {
                            mic_ctrl.is_speaking.store(false, Ordering::Relaxed);
                            let _ = app_tx.send(AppEvent::TtsFinished);
                        }
                    }
                }
            }
        }
    })
}
