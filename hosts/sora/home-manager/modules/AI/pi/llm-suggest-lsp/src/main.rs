//! Local LSP bridge for Pi's file-backed suggested edits; no model or network calls.
use percent_encoding::percent_decode_str;
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::io::{self, BufRead, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

const POLL: Duration = Duration::from_secs(1);
const MAX_MESSAGE: usize = 16 * 1024 * 1024;

// Match realpath even when the final file does not exist yet.
fn realpath(path: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("/"))
            .join(path)
    };
    fn resolve(path: &Path, links: &mut usize) -> PathBuf {
        let mut result = PathBuf::new();
        for component in path.components() {
            match component {
                Component::ParentDir => {
                    result.pop();
                }
                Component::CurDir => {}
                other => {
                    result.push(other.as_os_str());
                    if *links < 40 {
                        if let Ok(target) = fs::read_link(&result) {
                            *links += 1;
                            result.pop();
                            let target = if target.is_absolute() {
                                target
                            } else {
                                result.join(target)
                            };
                            result = resolve(&target, links);
                        }
                    }
                }
            }
        }
        result
    }
    resolve(&absolute, &mut 0)
}

fn uri_to_path(uri: &str) -> Option<PathBuf> {
    let (scheme, rest) = uri.split_once(':')?;
    if !scheme.eq_ignore_ascii_case("file") {
        return None;
    }
    let rest = rest.split(['?', '#']).next()?;
    let path = if let Some(authority) = rest.strip_prefix("//") {
        authority
            .find('/')
            .map(|index| &authority[index..])
            .unwrap_or("")
    } else {
        rest
    };
    Some(realpath(Path::new(
        percent_decode_str(path).decode_utf8_lossy().as_ref(),
    )))
}

fn integer(value: &Value, default: i64) -> i64 {
    match value {
        Value::Number(n) => n
            .as_i64()
            .or_else(|| n.as_f64().map(|n| n as i64))
            .unwrap_or(default),
        Value::String(s) => s.trim().parse().unwrap_or(default),
        Value::Bool(b) => i64::from(*b),
        _ => default,
    }
}

fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
        Value::Number(n) => n.as_f64() != Some(0.0),
    }
}

fn display(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Null => "None".into(),
        Value::Bool(true) => "True".into(),
        Value::Bool(false) => "False".into(),
        _ => value.to_string(),
    }
}

fn range(item: &Value) -> Value {
    let r = &item["range"];
    let sl = integer(&r["start"]["line"], 0);
    let sc = integer(&r["start"]["character"], 0);
    let el = integer(&r["end"]["line"], sl);
    let ec = integer(&r["end"]["character"], sc);
    if truthy(&item["wholeLine"]) || (sc == 0 && ec == 0 && el <= sl) {
        json!({"start":{"line":sl,"character":0},"end":{"line":sl.saturating_add(1).max(el),"character":0}})
    } else {
        json!({"start":{"line":sl,"character":sc},"end":{"line":el,"character":ec}})
    }
}

fn position(value: &Value) -> (i64, i64) {
    (integer(&value["line"], 0), integer(&value["character"], 0))
}

fn matches(request: &Value, action: &Value) -> bool {
    if !truthy(request) {
        return true;
    }
    let start = position(&request["start"]);
    let end = position(&request["end"]);
    let a = position(&action["start"]);
    let b = position(&action["end"]);
    if start == end {
        a <= start && start < b
    } else {
        start < b && a < end
    }
}

fn diagnostic(item: &Value) -> Value {
    let message = item
        .get("message")
        .map(display)
        .unwrap_or_else(|| "LLM suggested edit".into());
    json!({"range":range(item),"severity":integer(&item["severity"],3),"source":"llm-suggest","message":message,"data":{"id":item["id"]}})
}

struct Server {
    file: PathBuf,
    state_dir: PathBuf,
    open: BTreeSet<String>,
    mtime: Option<SystemTime>,
    shutdown: bool,
}

impl Server {
    fn read(&self) -> Vec<Value> {
        fs::read(&self.file)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Vec<Value>>(&bytes).ok())
            .unwrap_or_default()
    }

    fn suggestions(&self, path: &Path) -> Vec<Value> {
        let path = realpath(path);
        self.read()
            .into_iter()
            .filter(|item| {
                let file = item.get("file").map(display).unwrap_or_default();
                realpath(Path::new(&file)) == path
            })
            .collect()
    }

    fn publish(&self, uri: &str, output: &mut impl Write) -> io::Result<()> {
        if let Some(path) = uri_to_path(uri) {
            let diagnostics: Vec<_> = self.suggestions(&path).iter().map(diagnostic).collect();
            eprintln!(
                "llm-suggest-lsp: publishing {} diagnostic(s) for {}",
                diagnostics.len(),
                path.display()
            );
            send(
                output,
                &json!({"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":uri,"diagnostics":diagnostics}}),
            )?;
        }
        Ok(())
    }

    fn actions(&self, params: &Value) -> Vec<Value> {
        let Some(uri) = params["textDocument"]["uri"].as_str() else {
            return vec![];
        };
        let Some(path) = uri_to_path(uri) else {
            return vec![];
        };
        let ids: Vec<_> = params["context"]["diagnostics"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|d| &d["data"]["id"])
            .filter(|id| !id.is_null())
            .collect();
        self.suggestions(&path).iter().filter_map(|item| {
            let replacement = item["replacement"].as_str()?;
            if !ids.is_empty() && !ids.contains(&&item["id"]) { return None; }
            let r = range(item);
            if !matches(&params["range"], &r) { return None; }
            let title = [&item["title"], &item["message"]].into_iter().find(|v| truthy(v)).map(display).unwrap_or_else(|| "Apply LLM suggested edit".into());
            let mut action = json!({"title":format!("LLM: {title}"),"kind":"quickfix","isPreferred":false,"diagnostics":[diagnostic(item)],"edit":{"changes":{uri:[{"range":r,"newText":replacement}]}}});
            if !item["id"].is_null() {
                action["command"] = json!({"title":"Clear LLM suggestion","command":"llm-suggest.clearSuggestion","arguments":[item["id"]]});
            }
            Some(action)
        }).collect()
    }

    fn clear(&self, id: &Value, output: &mut impl Write) -> io::Result<()> {
        let before = self.read();
        let after: Vec<_> = before.iter().filter(|item| item["id"] != *id).collect();
        if after.len() != before.len() {
            // Preserve the existing shared-file contract, including its non-atomic writes.
            fs::create_dir_all(&self.state_dir)?;
            let mut file = fs::File::create(&self.file)?;
            serde_json::to_writer_pretty(&mut file, &after)?;
            file.write_all(b"\n")?;
            for uri in &self.open {
                self.publish(uri, output)?;
            }
        }
        Ok(())
    }

    fn handle(&mut self, msg: &Value, output: &mut impl Write) -> io::Result<bool> {
        let params = &msg["params"];
        let id = &msg["id"];
        let uri = params["textDocument"]["uri"].as_str();
        let result = match msg["method"].as_str().unwrap_or("") {
            "exit" => return Ok(false),
            "initialize" => Some(
                json!({"capabilities":{"textDocumentSync":1,"codeActionProvider":{"codeActionKinds":["quickfix"]},"executeCommandProvider":{"commands":["llm-suggest.clearSuggestion"]}},"serverInfo":{"name":"llm-suggest-lsp","version":"0.1.0"}}),
            ),
            "shutdown" => {
                self.shutdown = true;
                Some(Value::Null)
            }
            "textDocument/codeAction" => Some(json!(self.actions(params))),
            "workspace/executeCommand" => {
                if params["command"] == "llm-suggest.clearSuggestion" {
                    if let Some(id) = params["arguments"].as_array().and_then(|a| a.first()) {
                        self.clear(id, output)?;
                    }
                }
                Some(Value::Null)
            }
            "textDocument/didOpen" => {
                if let Some(uri) = uri {
                    self.open.insert(uri.into());
                    self.publish(uri, output)?;
                }
                None
            }
            "textDocument/didChange" => {
                if let Some(uri) = uri {
                    self.publish(uri, output)?;
                }
                None
            }
            "textDocument/didClose" => {
                if let Some(uri) = uri {
                    self.open.remove(uri);
                    send(
                        output,
                        &json!({"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":uri,"diagnostics":[]}}),
                    )?;
                }
                None
            }
            "initialized" => {
                for uri in &self.open {
                    self.publish(uri, output)?;
                }
                None
            }
            _ => {
                if id.is_null() {
                    None
                } else {
                    Some(Value::Null)
                }
            }
        };
        if let Some(result) = result {
            send(output, &json!({"jsonrpc":"2.0","id":id,"result":result}))?;
        }
        Ok(true)
    }

    fn poll(&mut self, output: &mut impl Write) -> io::Result<()> {
        let current = fs::metadata(&self.file)
            .ok()
            .and_then(|meta| meta.modified().ok());
        if current != self.mtime {
            self.mtime = current;
            for uri in &self.open {
                self.publish(uri, output)?;
            }
        }
        Ok(())
    }
}

fn send(output: &mut impl Write, payload: &Value) -> io::Result<()> {
    let body = serde_json::to_vec(payload)?;
    write!(output, "Content-Length: {}\r\n\r\n", body.len())?;
    output.write_all(&body)?;
    output.flush()
}

fn read_message(input: &mut impl BufRead) -> io::Result<Option<Value>> {
    loop {
        let mut length = 0;
        let mut headers_size = 0;
        loop {
            let mut line = String::new();
            // Bound individual header allocations as well as complete frames.
            let read = input.by_ref().take(8193).read_line(&mut line)?;
            if read == 0 {
                return Ok(None);
            }
            headers_size += read;
            if headers_size > 8192 {
                return Err(io::Error::other("LSP headers too large"));
            }
            if line == "\r\n" || line == "\n" {
                break;
            }
            if let Some((name, value)) = line.split_once(':') {
                if name.eq_ignore_ascii_case("content-length") {
                    length = value.trim().parse().unwrap_or(0);
                }
            }
        }
        if length > MAX_MESSAGE {
            return Err(io::Error::other("LSP frame exceeds 16 MiB"));
        }
        let mut body = vec![0; length];
        input.read_exact(&mut body)?;
        if let Ok(value) = serde_json::from_slice(&body) {
            return Ok(Some(value));
        }
    }
}

fn main() -> io::Result<()> {
    let state_home = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    let state_dir = state_home.join("llm-suggest");
    let file = env::var_os("LLM_SUGGEST_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| state_dir.join("suggestions.json"));
    let mut server = Server {
        file,
        state_dir,
        open: BTreeSet::new(),
        mtime: None,
        shutdown: false,
    };
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut input = io::stdin().lock();
        loop {
            match read_message(&mut input) {
                Ok(Some(message)) => {
                    if sender.send(message).is_err() {
                        break;
                    }
                }
                Ok(None) => break,
                Err(error) => {
                    eprintln!("llm-suggest-lsp: {error}");
                    break;
                }
            }
        }
    });
    let mut output = io::stdout().lock();
    let mut next_poll = Instant::now();
    loop {
        if !server.shutdown && Instant::now() >= next_poll {
            server.poll(&mut output)?;
            next_poll = Instant::now() + POLL;
        }
        match receiver.recv_timeout(
            next_poll
                .saturating_duration_since(Instant::now())
                .max(Duration::from_millis(1)),
        ) {
            Ok(message) => {
                if !server.handle(&message, &mut output)? {
                    break;
                }
            }
            Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if server.shutdown {
            next_poll = Instant::now() + POLL;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn whole_lines_and_cursor_boundaries() {
        let r = range(
            &json!({"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}}}),
        );
        assert_eq!(
            r,
            json!({"start":{"line":3,"character":0},"end":{"line":4,"character":0}})
        );
        assert!(matches(&json!({"start":{"line":3},"end":{"line":3}}), &r));
        assert!(!matches(&json!({"start":{"line":4},"end":{"line":4}}), &r));
    }
    #[test]
    fn numeric_defaults_and_framing() {
        assert_eq!(integer(&json!(" 12 "), 0), 12);
        assert_eq!(integer(&json!("bad"), 3), 3);
        let mut bytes = vec![];
        send(&mut bytes, &json!({"hello":"Olá 中🙂"})).unwrap();
        assert_eq!(
            read_message(&mut io::Cursor::new(bytes)).unwrap(),
            Some(json!({"hello":"Olá 中🙂"}))
        );
        assert!(read_message(&mut io::Cursor::new(b"Content-Length: 999999999\r\n\r\n")).is_err());
    }
    #[test]
    fn uri_decoding_and_missing_paths() {
        assert_eq!(
            uri_to_path("file:///tmp/a%20b%23c.rs"),
            Some(PathBuf::from("/tmp/a b#c.rs"))
        );
        assert!(uri_to_path("untitled:test").is_none());
        assert_eq!(
            realpath(Path::new("/tmp/not-here/../new.rs")),
            PathBuf::from("/tmp/new.rs")
        );
    }
}
