//! Antigravity Agent Client Protocol (`agy acp`) stdio JSON-RPC client.

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::thread;

pub const VOICE_SYSTEM_APPEND: &str = "Live voice session (agy-voice): your replies are shown in the terminal and spoken aloud by local TTS. Keep spoken prose concise, natural, and conversational. Put code, file paths, CLI commands, diffs, and tables in markdown for the screen without spelling out raw flags, paths, URLs, or commit hashes in prose. Stay quiet while tools execute instead of narrating every step; speak only meaningful updates or the final answer.";

#[derive(Clone, Debug)]
pub struct PermissionOption {
    pub option_id: String,
    pub name: String,
}

#[derive(Clone, Debug)]
pub struct PermissionRequest {
    pub rpc_id: Value,
    pub title: String,
    pub kind: String,
    pub detail: Option<String>,
    pub options: Vec<PermissionOption>,
}

#[derive(Clone, Debug)]
pub enum AcpEvent {
    Ready {
        session_id: String,
        model_label: Option<String>,
    },
    TextDelta(String),
    Thinking,
    ToolCall {
        id: String,
        title: String,
        status: String,
    },
    Usage {
        used: u64,
        size: u64,
    },
    Title(String),
    PermissionRequest(PermissionRequest),
    TurnComplete {
        stop_reason: String,
        error: Option<String>,
    },
    Error(String),
    Disconnected,
}

pub struct AcpClient {
    child: Mutex<Child>,
    stdin: Mutex<ChildStdin>,
    session_id: String,
    next_id: AtomicU64,
    active_prompt_id: Arc<Mutex<Option<u64>>>,
}

impl AcpClient {
    pub fn start(
        cwd: &Path,
        model_override: Option<&str>,
        effort_override: Option<&str>,
        skip_permissions: bool,
        events_tx: mpsc::Sender<AcpEvent>,
    ) -> Result<Self> {
        let mut cmd = Command::new("agy");
        cmd.arg("acp");
        if skip_permissions {
            cmd.arg("--dangerously-skip-permissions");
        }
        let mut child = cmd
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("failed to spawn `agy acp`")?;

        let mut stdin = child
            .stdin
            .take()
            .context("`agy acp` did not provide stdin")?;
        let stdout = child
            .stdout
            .take()
            .context("`agy acp` did not provide stdout")?;
        let mut reader = BufReader::new(stdout);

        // 1. JSON-RPC initialize
        write_json_line(
            &mut stdin,
            &json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": 1,
                    "clientCapabilities": {},
                    "clientInfo": {
                        "name": "agy-voice",
                        "version": env!("CARGO_PKG_VERSION")
                    }
                }
            }),
        )?;
        let init_resp = read_response_for_id(&mut reader, 1)?;
        if let Some(err) = init_resp.get("error") {
            bail!("`agy acp` initialize error: {err}");
        }

        // 2. JSON-RPC session/new
        let cwd_str = cwd.to_str().context("non-UTF-8 workspace path")?;
        write_json_line(
            &mut stdin,
            &json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "session/new",
                "params": {
                    "cwd": cwd_str,
                    "mcpServers": [],
                    "_meta": {
                        "antigravity": {
                            "systemPrompt": {
                                "append": VOICE_SYSTEM_APPEND
                            }
                        }
                    }
                }
            }),
        )?;
        let new_resp = read_response_for_id(&mut reader, 2)?;
        if let Some(err) = new_resp.get("error") {
            bail!("`agy acp` session/new error: {err}");
        }
        let result = new_resp
            .get("result")
            .context("missing `result` in session/new response")?;
        let session_id = result
            .get("sessionId")
            .and_then(Value::as_str)
            .context("missing `sessionId` in session/new response")?
            .to_string();

        let mut model_label = result
            .pointer("/models/currentModelId")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned);

        let mut next_id = 3u64;

        // 3. Optional model override
        if let Some(model_id) = model_override {
            let id = next_id;
            next_id += 1;
            write_json_line(
                &mut stdin,
                &json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "method": "session/set_model",
                    "params": {
                        "sessionId": session_id,
                        "modelId": model_id
                    }
                }),
            )?;
            let resp = read_response_for_id(&mut reader, id)?;
            if resp.get("error").is_none() {
                model_label = Some(model_id.to_string());
            }
        }

        // 4. Optional reasoning effort (`thought_level`) override
        if let Some(effort) = effort_override {
            let id = next_id;
            next_id += 1;
            write_json_line(
                &mut stdin,
                &json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "method": "session/set_config_option",
                    "params": {
                        "sessionId": session_id,
                        "configId": "thought_level",
                        "value": effort
                    }
                }),
            )?;
            let _ = read_response_for_id(&mut reader, id)?;
        }

        let _ = events_tx.send(AcpEvent::Ready {
            session_id: session_id.clone(),
            model_label,
        });

        let active_prompt_id = Arc::new(Mutex::new(None));
        let active_prompt_reader = Arc::clone(&active_prompt_id);

        thread::spawn(move || {
            let mut line = String::new();
            loop {
                line.clear();
                match reader.read_line(&mut line) {
                    Ok(0) => {
                        let _ = events_tx.send(AcpEvent::Disconnected);
                        break;
                    }
                    Ok(_) => {
                        let trimmed = line.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        match serde_json::from_str::<Value>(trimmed) {
                            Ok(msg) => {
                                handle_incoming_message(&msg, &active_prompt_reader, &events_tx);
                            }
                            Err(e) => {
                                let _ = events_tx
                                    .send(AcpEvent::Error(format!("ACP JSON parse error: {e}")));
                            }
                        }
                    }
                    Err(e) => {
                        let _ = events_tx.send(AcpEvent::Error(format!("ACP read error: {e}")));
                        let _ = events_tx.send(AcpEvent::Disconnected);
                        break;
                    }
                }
            }
        });

        Ok(Self {
            child: Mutex::new(child),
            stdin: Mutex::new(stdin),
            session_id,
            next_id: AtomicU64::new(next_id),
            active_prompt_id,
        })
    }

    pub fn send_prompt(&self, text: &str) -> Result<()> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        {
            let mut active = self.active_prompt_id.lock().unwrap();
            *active = Some(id);
        }
        let payload = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": "session/prompt",
            "params": {
                "sessionId": self.session_id,
                "prompt": [
                    {
                        "type": "text",
                        "text": text
                    }
                ]
            }
        });
        let mut stdin = self.stdin.lock().unwrap();
        write_json_line(&mut stdin, &payload)
    }

    pub fn cancel(&self) -> Result<()> {
        let payload = json!({
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": {
                "sessionId": self.session_id
            }
        });
        let mut stdin = self.stdin.lock().unwrap();
        write_json_line(&mut stdin, &payload)
    }

    pub fn reply_permission(&self, rpc_id: Value, option_id: Option<&str>) -> Result<()> {
        let outcome = match option_id {
            Some(opt) => json!({ "outcome": "selected", "optionId": opt }),
            None => json!({ "outcome": "cancelled" }),
        };
        let payload = json!({
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {
                "outcome": outcome
            }
        });
        let mut stdin = self.stdin.lock().unwrap();
        write_json_line(&mut stdin, &payload)
    }
}

impl Drop for AcpClient {
    fn drop(&mut self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

fn write_json_line(stdin: &mut ChildStdin, val: &Value) -> Result<()> {
    let serialized = serde_json::to_string(val)?;
    stdin.write_all(serialized.as_bytes())?;
    stdin.write_all(b"\n")?;
    stdin.flush()?;
    Ok(())
}

fn read_response_for_id(
    reader: &mut BufReader<std::process::ChildStdout>,
    id: u64,
) -> Result<Value> {
    let mut line = String::new();
    loop {
        line.clear();
        let n = reader.read_line(&mut line)?;
        if n == 0 {
            bail!("`agy acp` closed stdout before replying to request id {id}");
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let msg: Value = serde_json::from_str(trimmed)
            .with_context(|| format!("invalid JSON during ACP handshake: {trimmed}"))?;
        if msg.get("id").and_then(Value::as_u64) == Some(id) {
            return Ok(msg);
        }
    }
}

fn handle_incoming_message(
    msg: &Value,
    active_prompt_id: &Arc<Mutex<Option<u64>>>,
    tx: &mpsc::Sender<AcpEvent>,
) {
    // 1. Server-initiated request or notification (`method` field present)
    if let Some(method) = msg.get("method").and_then(Value::as_str) {
        match method {
            "session/update" => {
                if let Some(update) = msg.pointer("/params/update") {
                    parse_session_update(update, tx);
                }
            }
            "session/request_permission" => {
                if let Some(req) = parse_permission_request(msg) {
                    let _ = tx.send(AcpEvent::PermissionRequest(req));
                }
            }
            _ => {}
        }
        return;
    }

    // 2. Response to our active `session/prompt` request
    if let Some(resp_id) = msg.get("id").and_then(Value::as_u64) {
        let is_prompt = {
            let mut active = active_prompt_id.lock().unwrap();
            if *active == Some(resp_id) {
                *active = None;
                true
            } else {
                false
            }
        };
        if is_prompt {
            if let Some(err) = msg.get("error") {
                let err_msg = err
                    .get("message")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
                    .unwrap_or_else(|| err.to_string());
                let _ = tx.send(AcpEvent::TurnComplete {
                    stop_reason: "error".to_string(),
                    error: Some(err_msg),
                });
            } else {
                let stop_reason = msg
                    .pointer("/result/stopReason")
                    .and_then(Value::as_str)
                    .unwrap_or("end_turn")
                    .to_string();
                let _ = tx.send(AcpEvent::TurnComplete {
                    stop_reason,
                    error: None,
                });
            }
        }
    }
}

fn parse_session_update(update: &Value, tx: &mpsc::Sender<AcpEvent>) {
    let Some(kind) = update.get("sessionUpdate").and_then(Value::as_str) else {
        return;
    };
    match kind {
        "agent_message_chunk" => {
            if let Some(text) = update.pointer("/content/text").and_then(Value::as_str)
                && !text.is_empty()
            {
                let _ = tx.send(AcpEvent::TextDelta(text.to_string()));
            }
        }
        "agent_thought_chunk" => {
            let _ = tx.send(AcpEvent::Thinking);
        }
        "tool_call" | "tool_call_update" => {
            let id = update
                .get("toolCallId")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let title = update
                .get("title")
                .and_then(Value::as_str)
                .or_else(|| update.get("kind").and_then(Value::as_str))
                .unwrap_or("tool")
                .to_string();
            let status = update
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("running")
                .to_string();
            let _ = tx.send(AcpEvent::ToolCall { id, title, status });
        }
        "usage_update" => {
            let used = update.get("used").and_then(Value::as_u64).unwrap_or(0);
            let size = update.get("size").and_then(Value::as_u64).unwrap_or(0);
            let _ = tx.send(AcpEvent::Usage { used, size });
        }
        "session_info_update" => {
            if let Some(title) = update.get("title").and_then(Value::as_str) {
                let _ = tx.send(AcpEvent::Title(title.to_string()));
            }
        }
        _ => {}
    }
}

fn parse_permission_request(msg: &Value) -> Option<PermissionRequest> {
    let rpc_id = msg.get("id")?.clone();
    let params = msg.get("params")?;
    let tool_call = params.get("toolCall");
    let title = tool_call
        .and_then(|t| t.get("title"))
        .and_then(Value::as_str)
        .unwrap_or("Permission requested")
        .to_string();
    let kind = tool_call
        .and_then(|t| t.get("kind"))
        .and_then(Value::as_str)
        .unwrap_or("tool")
        .to_string();
    let detail = tool_call
        .and_then(|t| t.get("rawInput"))
        .map(|v| v.to_string());

    let mut options = Vec::new();
    if let Some(arr) = params.get("options").and_then(Value::as_array) {
        for item in arr {
            let option_id = item
                .get("optionId")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let name = item
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or(&option_id)
                .to_string();
            if !option_id.is_empty() {
                options.push(PermissionOption { option_id, name });
            }
        }
    }

    Some(PermissionRequest {
        rpc_id,
        title,
        kind,
        detail,
        options,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_agent_message_chunk() {
        let (tx, rx) = mpsc::channel();
        let active = Arc::new(Mutex::new(Some(3)));
        let msg = json!({
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": {
                "sessionId": "abc",
                "update": {
                    "sessionUpdate": "agent_message_chunk",
                    "content": { "type": "text", "text": "pong" }
                }
            }
        });
        handle_incoming_message(&msg, &active, &tx);
        match rx.try_recv().unwrap() {
            AcpEvent::TextDelta(t) => assert_eq!(t, "pong"),
            other => panic!("unexpected event: {other:?}"),
        }
    }

    #[test]
    fn parses_permission_request_options() {
        let msg = json!({
            "jsonrpc": "2.0",
            "id": 9,
            "method": "session/request_permission",
            "params": {
                "toolCall": { "title": "Run cargo test", "kind": "execute" },
                "options": [
                    { "optionId": "allow_once", "name": "Allow once", "kind": "allow_once" },
                    { "optionId": "reject_once", "name": "Reject", "kind": "reject_once" }
                ]
            }
        });
        let req = parse_permission_request(&msg).unwrap();
        assert_eq!(req.title, "Run cargo test");
        assert_eq!(req.options.len(), 2);
        assert_eq!(req.options[0].option_id, "allow_once");
    }
}
