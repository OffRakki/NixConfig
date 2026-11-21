//! Pi coding agent (`pi --mode rpc`) stdio NDJSON client, mapping Pi RPC events
//! onto the shared `AcpEvent` stream so `agy-voice` can route between `agy` and `pi`.

use crate::acp::{AcpEvent, PermissionOption, PermissionRequest, VOICE_SYSTEM_APPEND};
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Mutex, mpsc};
use std::thread;

pub struct PiClient {
    child: Mutex<Child>,
    stdin: Mutex<ChildStdin>,
}

impl PiClient {
    pub fn start(cwd: &Path, events_tx: mpsc::Sender<AcpEvent>) -> Result<Self> {
        let mut child = Command::new("pi")
            .args([
                "--mode",
                "rpc",
                "--append-system-prompt",
                VOICE_SYSTEM_APPEND,
            ])
            .current_dir(cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("failed to spawn `pi --mode rpc`")?;

        let mut stdin = child
            .stdin
            .take()
            .context("`pi --mode rpc` did not provide stdin")?;
        let stdout = child
            .stdout
            .take()
            .context("`pi --mode rpc` did not provide stdout")?;
        let mut reader = BufReader::new(stdout);

        // Request initial state so we know the active model label immediately.
        write_json_line(&mut stdin, &json!({ "type": "get_state" }))?;

        let mut line = String::new();
        let (model_label, context_window) = loop {
            line.clear();
            let n = reader.read_line(&mut line)?;
            if n == 0 {
                bail!("`pi --mode rpc` closed stdout before returning initial state");
            }
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(msg) = serde_json::from_str::<Value>(trimmed)
                && msg.get("type").and_then(Value::as_str) == Some("response")
                && msg.get("command").and_then(Value::as_str) == Some("get_state")
            {
                let label = msg
                    .pointer("/data/model/name")
                    .and_then(Value::as_str)
                    .or_else(|| msg.pointer("/data/model/id").and_then(Value::as_str))
                    .map(ToOwned::to_owned);
                let window = msg
                    .pointer("/data/model/contextWindow")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
                break (label, window);
            }
        };

        let _ = events_tx.send(AcpEvent::Ready {
            session_id: "pi-rpc".to_string(),
            model_label,
        });
        if context_window > 0 {
            let _ = events_tx.send(AcpEvent::Usage {
                used: 0,
                size: context_window,
            });
        }

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
                            Ok(msg) => handle_pi_event(&msg, context_window, &events_tx),
                            Err(e) => {
                                let _ = events_tx
                                    .send(AcpEvent::Error(format!("Pi RPC JSON error: {e}")));
                            }
                        }
                    }
                    Err(e) => {
                        let _ = events_tx.send(AcpEvent::Error(format!("Pi RPC read error: {e}")));
                        let _ = events_tx.send(AcpEvent::Disconnected);
                        break;
                    }
                }
            }
        });

        Ok(Self {
            child: Mutex::new(child),
            stdin: Mutex::new(stdin),
        })
    }

    pub fn send_prompt(&self, text: &str) -> Result<()> {
        let mut stdin = self.stdin.lock().unwrap();
        write_json_line(
            &mut stdin,
            &json!({
                "type": "prompt",
                "message": text
            }),
        )
    }

    pub fn cancel(&self) -> Result<()> {
        let mut stdin = self.stdin.lock().unwrap();
        write_json_line(&mut stdin, &json!({ "type": "abort" }))
    }

    pub fn reply_ui(&self, req_id: Value, option_id: Option<&str>) -> Result<()> {
        let payload = match option_id {
            Some("__confirm_yes__") => json!({
                "type": "extension_ui_response",
                "id": req_id,
                "confirmed": true
            }),
            Some("__confirm_no__") => json!({
                "type": "extension_ui_response",
                "id": req_id,
                "confirmed": false
            }),
            Some(val) => json!({
                "type": "extension_ui_response",
                "id": req_id,
                "value": val
            }),
            None => json!({
                "type": "extension_ui_response",
                "id": req_id,
                "cancelled": true
            }),
        };
        let mut stdin = self.stdin.lock().unwrap();
        write_json_line(&mut stdin, &payload)
    }
}

impl Drop for PiClient {
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

fn handle_pi_event(msg: &Value, context_window: u64, tx: &mpsc::Sender<AcpEvent>) {
    let Some(ev_type) = msg.get("type").and_then(Value::as_str) else {
        return;
    };

    match ev_type {
        "message_update" => {
            if let Some(sub) = msg.get("assistantMessageEvent") {
                match sub.get("type").and_then(Value::as_str) {
                    Some("text_delta") => {
                        if let Some(delta) = sub.get("delta").and_then(Value::as_str)
                            && !delta.is_empty()
                        {
                            let _ = tx.send(AcpEvent::TextDelta(delta.to_string()));
                        }
                    }
                    Some("thinking_start" | "thinking_delta") => {
                        let _ = tx.send(AcpEvent::Thinking);
                    }
                    _ => {}
                }
            }
        }
        "tool_execution_start" => {
            let id = msg
                .get("toolCallId")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let title = msg
                .get("toolName")
                .and_then(Value::as_str)
                .unwrap_or("tool")
                .to_string();
            let _ = tx.send(AcpEvent::ToolCall {
                id,
                title,
                status: "running".to_string(),
            });
        }
        "tool_execution_end" => {
            let id = msg
                .get("toolCallId")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let title = msg
                .get("toolName")
                .and_then(Value::as_str)
                .unwrap_or("tool")
                .to_string();
            let is_err = msg.get("isError").and_then(Value::as_bool).unwrap_or(false);
            let _ = tx.send(AcpEvent::ToolCall {
                id,
                title,
                status: if is_err { "failed" } else { "completed" }.to_string(),
            });
        }
        "message_end" => {
            if let Some(used) = msg
                .pointer("/message/usage/totalTokens")
                .and_then(Value::as_u64)
                && used > 0
            {
                let _ = tx.send(AcpEvent::Usage {
                    used,
                    size: context_window,
                });
            }
        }
        "agent_end" => {
            let _ = tx.send(AcpEvent::TurnComplete {
                stop_reason: "end_turn".to_string(),
                error: None,
            });
        }
        "response" => {
            if msg.get("success").and_then(Value::as_bool) == Some(false) {
                let err = msg
                    .get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("Pi RPC command failed")
                    .to_string();
                let _ = tx.send(AcpEvent::Error(err));
            }
        }
        "extension_ui_request" => {
            if let Some(req) = parse_pi_ui_request(msg) {
                let _ = tx.send(AcpEvent::PermissionRequest(req));
            }
        }
        _ => {}
    }
}

fn parse_pi_ui_request(msg: &Value) -> Option<PermissionRequest> {
    let id = msg.get("id")?.clone();
    let method = msg.get("method").and_then(Value::as_str)?;
    match method {
        "select" => {
            let title = msg
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or("Select an option")
                .to_string();
            let mut options = Vec::new();
            if let Some(arr) = msg.get("options").and_then(Value::as_array) {
                for item in arr {
                    if let Some(s) = item.as_str() {
                        options.push(PermissionOption {
                            option_id: s.to_string(),
                            name: s.to_string(),
                        });
                    } else if let Some(val) = item.get("value").and_then(Value::as_str) {
                        let label = item.get("label").and_then(Value::as_str).unwrap_or(val);
                        options.push(PermissionOption {
                            option_id: val.to_string(),
                            name: label.to_string(),
                        });
                    }
                }
            }
            if options.is_empty() {
                return None;
            }
            Some(PermissionRequest {
                rpc_id: id,
                title,
                kind: "pi select".to_string(),
                detail: None,
                options,
            })
        }
        "confirm" => {
            let title = msg
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or("Confirm")
                .to_string();
            let detail = msg
                .get("message")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned);
            Some(PermissionRequest {
                rpc_id: id,
                title,
                kind: "pi confirm".to_string(),
                detail,
                options: vec![
                    PermissionOption {
                        option_id: "__confirm_yes__".to_string(),
                        name: "Yes".to_string(),
                    },
                    PermissionOption {
                        option_id: "__confirm_no__".to_string(),
                        name: "No".to_string(),
                    },
                ],
            })
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_pi_text_delta_and_agent_end() {
        let (tx, rx) = mpsc::channel();
        let delta_msg = json!({
            "type": "message_update",
            "assistantMessageEvent": {
                "type": "text_delta",
                "delta": "pong"
            }
        });
        handle_pi_event(&delta_msg, 200_000, &tx);
        match rx.try_recv().unwrap() {
            AcpEvent::TextDelta(t) => assert_eq!(t, "pong"),
            other => panic!("unexpected event: {other:?}"),
        }

        handle_pi_event(&json!({ "type": "agent_end" }), 200_000, &tx);
        match rx.try_recv().unwrap() {
            AcpEvent::TurnComplete { stop_reason, error } => {
                assert_eq!(stop_reason, "end_turn");
                assert!(error.is_none());
            }
            other => panic!("unexpected event: {other:?}"),
        }
    }

    #[test]
    fn parses_pi_select_ui_request() {
        let msg = json!({
            "type": "extension_ui_request",
            "id": "req-1",
            "method": "select",
            "title": "Favorite color?",
            "options": ["Red", "Blue", "Purple"]
        });
        let req = parse_pi_ui_request(&msg).unwrap();
        assert_eq!(req.title, "Favorite color?");
        assert_eq!(req.options.len(), 3);
        assert_eq!(req.options[2].option_id, "Purple");
    }
}
