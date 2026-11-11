//! Clipboard copy notifications. Behavioral reference: misterio77/nix-config (MIT).
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_INPUT: usize = 16 * 1024 * 1024;
const MAX_PREVIEW_CHARS: usize = 4096;
const HIDDEN: &str = "Sensitive clipboard content hidden";
const TOO_LARGE: &str = "Clipboard content too large to preview (over 16 MiB)";

fn shell_text(bytes: &[u8]) -> io::Result<String> {
    // Match command substitution for ordinary UTF-8 text, not echo's options.
    let bytes: Vec<_> = bytes.iter().copied().filter(|byte| *byte != 0).collect();
    let text = String::from_utf8(bytes)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "text is not valid UTF-8"))?;
    Ok(text.trim_end_matches('\n').to_owned())
}

fn escaped_preview(text: &str) -> String {
    let mut output = String::new();
    let mut chars = text.chars();
    for ch in chars.by_ref().take(MAX_PREVIEW_CHARS) {
        match ch {
            '&' => output.push_str("&amp;"),
            '<' => output.push_str("&lt;"),
            '>' => output.push_str("&gt;"),
            // Keep newline/tab, but avoid injecting other terminal/control bytes.
            ch if ch.is_control() && ch != '\n' && ch != '\t' => output.push('�'),
            ch => output.push(ch),
        }
    }
    if chars.next().is_some() {
        output.push_str("\n[Preview truncated]");
    }
    output
}

fn text_preview(text: &str) -> String {
    let lines = text.split('\n').count();
    if lines <= 5 {
        return escaped_preview(text);
    }
    let first = text.split('\n').take(3).collect::<Vec<_>>().join("\n");
    let last = text.rsplit('\n').next().unwrap_or_default();
    escaped_preview(&format!(
        "{first}\n[[ {} more lines... ]]\n{last}",
        lines - 4
    ))
}

fn has_mime(mimes: &str, expected: &str) -> bool {
    mimes
        .lines()
        .any(|mime| mime.split(';').next().unwrap_or_default().trim() == expected)
}

fn read_bounded(reader: &mut impl Read, limit: usize) -> io::Result<Option<Vec<u8>>> {
    let mut bytes = Vec::new();
    reader
        .by_ref()
        .take(limit as u64 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > limit {
        // Drain without storing the remainder so wl-paste does not get a broken pipe.
        io::copy(reader, &mut io::sink())?;
        return Ok(None);
    }
    Ok(Some(bytes))
}

fn output(command: &mut Command) -> io::Result<String> {
    let result = command.output()?;
    if !result.status.success() {
        return Err(io::Error::other("clipboard helper failed"));
    }
    shell_text(&result.stdout)
}

struct Temporary(PathBuf);
impl Temporary {
    fn create() -> io::Result<(Self, File)> {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(io::Error::other)?
            .as_nanos();
        for attempt in 0..32 {
            let path = env::temp_dir().join(format!(
                "clip-notify-{}-{nonce}-{attempt}",
                std::process::id()
            ));
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&path)
            {
                Ok(file) => return Ok((Self(path), file)),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "could not create private temporary file",
        ))
    }
}
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn binary_preview(bytes: &[u8]) -> io::Result<String> {
    // Keep allocated-size and libmagic description behavior for binary data.
    let (temporary, mut file) = Temporary::create()?;
    file.write_all(bytes)?;
    drop(file);
    let size_output = output(Command::new("du").arg("-h").arg(&temporary.0))?;
    let size = size_output
        .split_whitespace()
        .next()
        .ok_or_else(|| io::Error::other("missing size"))?;
    let description = output(Command::new("file").arg("-b").arg(&temporary.0))?;
    let metadata = description.split(',').take(2).collect::<Vec<_>>().join(",");
    Ok(escaped_preview(&format!("[[ {size} {metadata} ]]")))
}

fn notify(preview: &str) -> io::Result<ExitCode> {
    let status = Command::new("notify-send")
        .args([
            "-i",
            "edit-copy",
            "-t",
            "2000",
            "--",
            "Copied to Clipboard:",
            preview,
        ])
        .status()?;
    Ok(ExitCode::from(status.code().unwrap_or(1) as u8))
}

fn run() -> io::Result<ExitCode> {
    let state = env::var("CLIPBOARD_STATE").unwrap_or_default();
    if state == "nil" {
        return Ok(ExitCode::SUCCESS);
    }
    let mut input = io::stdin().lock();
    if state == "sensitive" {
        io::copy(&mut input, &mut io::sink())?;
        return notify(HIDDEN);
    }
    let mimes = output(Command::new("wl-paste").arg("-l"))?;
    if has_mime(&mimes, "text/secret") {
        io::copy(&mut input, &mut io::sink())?;
        return notify(HIDDEN);
    }
    let preview = match read_bounded(&mut input, MAX_INPUT)? {
        None => TOO_LARGE.to_owned(),
        Some(bytes) if has_mime(&mimes, "text/plain") => text_preview(&shell_text(&bytes)?),
        Some(bytes) => binary_preview(&bytes)?,
    };
    notify(&preview)
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            // Never print clipboard data or helper stderr.
            eprintln!("clip-notify: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn substitution_removes_nuls_and_trailing_newlines() {
        assert_eq!(shell_text(b"a\0b\n\n").unwrap(), "ab");
        assert_eq!(shell_text(b"\n\n").unwrap(), "");
        assert!(shell_text(&[0xff]).is_err());
    }

    #[test]
    fn line_preview_threshold() {
        assert_eq!(text_preview("a\nb\nc\nd\ne"), "a\nb\nc\nd\ne");
        assert_eq!(
            text_preview("a\nb\nc\nd\ne\nf"),
            "a\nb\nc\n[[ 2 more lines... ]]\nf"
        );
        assert_eq!(text_preview(""), "");
        assert_eq!(text_preview("-n"), "-n");
    }

    #[test]
    fn markup_and_control_characters_are_not_interpreted() {
        assert_eq!(
            text_preview("<b>text</b> & data"),
            "&lt;b&gt;text&lt;/b&gt; &amp; data"
        );
        assert_eq!(escaped_preview("\r\u{1b}\t\n"), "��\t\n");
    }

    #[test]
    fn truncation_is_unicode_safe_and_bounds_escaped_arguments() {
        assert_eq!(
            escaped_preview(&"中".repeat(MAX_PREVIEW_CHARS)),
            "中".repeat(MAX_PREVIEW_CHARS)
        );
        assert!(
            escaped_preview(&"🙂".repeat(MAX_PREVIEW_CHARS + 1)).ends_with("[Preview truncated]")
        );
        assert!(escaped_preview(&"&".repeat(1_000_000)).len() < 25_000);
    }

    #[test]
    fn input_limit_drains_and_handles_exact_boundary() {
        let mut oversized = &b"abcdef"[..];
        assert!(read_bounded(&mut oversized, 3).unwrap().is_none());
        assert!(oversized.is_empty());
        assert_eq!(read_bounded(&mut &b"abc"[..], 3).unwrap().unwrap(), b"abc");
    }

    #[test]
    fn mime_matching_is_exact_and_supports_parameters() {
        assert!(has_mime(
            "image/png\ntext/plain;charset=utf-8\n",
            "text/plain"
        ));
        assert!(has_mime("text/secret", "text/secret"));
        assert!(!has_mime("application/x-text/plain", "text/plain"));
    }

    #[test]
    fn temporary_file_is_private_and_removed() {
        use std::os::unix::fs::PermissionsExt;
        let (temporary, file) = Temporary::create().unwrap();
        let path = temporary.0.clone();
        assert_eq!(file.metadata().unwrap().permissions().mode() & 0o777, 0o600);
        drop(file);
        drop(temporary);
        assert!(!path.exists());
    }
}
