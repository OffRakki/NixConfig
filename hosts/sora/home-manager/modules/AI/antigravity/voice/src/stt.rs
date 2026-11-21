//! Warm local `whisper-server` child process (CPU-pinned, thread-capped) with a
//! zero-dependency `TcpStream` HTTP/1.1 multipart `/inference` client.

use crate::audio::{CAPTURE_SAMPLE_RATE, encode_wav_i16};
use anyhow::{Context, Result, bail};
use serde::Deserialize;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const DEFAULT_PROMPT_GLOSSARY: &str = "Ciel, Lucky, NixConfig, NixOS, Home Manager, agy, Antigravity, jj, Jujutsu, Helix, Rust, Ratatui, Kokoro, Whisper, PipeWire, Hyprland, Quickshell.";

pub struct WhisperStt {
    child: Child,
    addr: SocketAddr,
}

#[derive(Deserialize)]
struct InferenceResponse {
    text: String,
}

impl WhisperStt {
    pub fn start(model_path: &Path, threads: usize, language: &str) -> Result<Self> {
        let port = pick_free_port()?;
        let addr: SocketAddr = format!("127.0.0.1:{port}").parse()?;

        let mut cmd = Command::new("whisper-server");
        cmd.args([
            "-m",
            model_path
                .to_str()
                .context("non-UTF-8 whisper model path")?,
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "-t",
            &threads.max(1).to_string(),
            "--no-gpu",
            "-l",
            language,
            "--prompt",
            DEFAULT_PROMPT_GLOSSARY,
            "--carry-initial-prompt",
            "-sns",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

        let mut child = cmd
            .spawn()
            .context("failed to spawn `whisper-server` (is whisper-cpp in PATH?)")?;

        // Wait up to 30 seconds for model load and HTTP listener bind.
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            if let Some(status) = child.try_wait()? {
                bail!("`whisper-server` exited early during startup ({status})");
            }
            if TcpStream::connect_timeout(&addr, Duration::from_millis(100)).is_ok() {
                break;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                bail!("timed out waiting for `whisper-server` to start on {addr}");
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        Ok(Self { child, addr })
    }

    /// Transcribes mono 16 kHz f32 PCM samples. Returns `Ok(None)` for silence
    /// or common Whisper non-speech artifacts.
    pub fn transcribe(&self, samples: &[f32]) -> Result<Option<String>> {
        if samples.len() < (CAPTURE_SAMPLE_RATE as usize / 5) {
            return Ok(None);
        }

        let wav = encode_wav_i16(samples, CAPTURE_SAMPLE_RATE);
        let boundary = "----agyvoiceboundary7MA4YWxkTrZu0gW";

        let mut body = Vec::with_capacity(wav.len() + 512);
        write!(
            body,
            "--{boundary}\r\n\
             Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n\
             Content-Type: audio/wav\r\n\r\n"
        )?;
        body.extend_from_slice(&wav);
        write!(
            body,
            "\r\n--{boundary}\r\n\
             Content-Disposition: form-data; name=\"response_format\"\r\n\r\n\
             json\r\n\
             --{boundary}\r\n\
             Content-Disposition: form-data; name=\"temperature\"\r\n\r\n\
             0.0\r\n\
             --{boundary}--\r\n"
        )?;

        let mut stream = TcpStream::connect_timeout(&self.addr, Duration::from_secs(5))
            .with_context(|| format!("failed connecting to whisper-server at {}", self.addr))?;
        stream.set_read_timeout(Some(Duration::from_secs(60)))?;
        stream.set_write_timeout(Some(Duration::from_secs(10)))?;

        let header = format!(
            "POST /inference HTTP/1.1\r\n\
             Host: {}\r\n\
             Content-Type: multipart/form-data; boundary={boundary}\r\n\
             Content-Length: {}\r\n\
             Connection: close\r\n\r\n",
            self.addr,
            body.len()
        );
        stream.write_all(header.as_bytes())?;
        stream.write_all(&body)?;
        stream.flush()?;

        let mut raw = Vec::new();
        stream.read_to_end(&mut raw)?;

        let body_bytes = extract_http_body(&raw)?;
        let parsed: InferenceResponse =
            serde_json::from_slice(body_bytes).context("invalid JSON from whisper-server")?;

        Ok(filter_transcript(&parsed.text))
    }
}

impl Drop for WhisperStt {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn pick_free_port() -> Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    Ok(listener.local_addr()?.port())
}

fn extract_http_body(raw: &[u8]) -> Result<&[u8]> {
    let sep = b"\r\n\r\n";
    let pos = raw
        .windows(sep.len())
        .position(|w| w == sep)
        .context("malformed HTTP response from whisper-server")?;
    let head = std::str::from_utf8(&raw[..pos]).unwrap_or("");
    let status_line = head.lines().next().unwrap_or("");
    if !status_line.contains(" 200 ") {
        bail!("whisper-server returned HTTP error: {status_line}");
    }
    Ok(&raw[pos + sep.len()..])
}

pub fn filter_transcript(text: &str) -> Option<String> {
    let cleaned = text.trim();
    if cleaned.is_empty() {
        return None;
    }
    let upper = cleaned.to_uppercase();
    if upper.contains("[BLANK_AUDIO]")
        || upper == "[SILENCE]"
        || upper == "(SILENCE)"
        || upper == "(MUSIC)"
        || upper == "[MUSIC]"
        || cleaned.chars().all(|c| !c.is_alphanumeric())
    {
        return None;
    }
    Some(cleaned.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filters_whisper_blank_artifacts() {
        assert_eq!(filter_transcript("  [BLANK_AUDIO] "), None);
        assert_eq!(filter_transcript("..."), None);
        assert_eq!(
            filter_transcript("  Hey Ciel, check NixConfig. "),
            Some("Hey Ciel, check NixConfig.".to_string())
        );
    }

    #[test]
    fn parses_http_body() {
        let resp = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"text\":\"hi\"}";
        assert_eq!(extract_http_body(resp).unwrap(), b"{\"text\":\"hi\"}");
    }
}
