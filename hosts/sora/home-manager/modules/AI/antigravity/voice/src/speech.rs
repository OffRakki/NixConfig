//! Natural markdown-to-speech normalizer and dynamic sentence chunker so Kokoro
//! TTS speaks smoothly without reading raw symbols, paths, flags, or tables.

/// Converts markdown text into natural, spoken-friendly prose.
pub fn sanitize_for_speech(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_fence = false;

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("```") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence || trimmed.is_empty() {
            continue;
        }
        // Skip markdown tables and horizontal rules completely.
        if is_table_or_rule(trimmed) {
            continue;
        }

        // Strip heading markers and list prefixes.
        let mut s = trimmed.trim_start_matches('#').trim_start();
        for prefix in ["- ", "* ", "+ ", "> ", "• ", "▸ ", "⚙ "] {
            if let Some(rest) = s.strip_prefix(prefix) {
                s = rest;
                break;
            }
        }
        // Strip numbered list prefix like "1. " or "2) ".
        s = strip_numbered_list_prefix(s);

        let unlinked = strip_markdown_links(s);
        let inline_cleaned = normalize_inline_code(&unlinked);
        let tokens_cleaned = normalize_tokens(&inline_cleaned);

        if !tokens_cleaned.is_empty() {
            if !out.is_empty() {
                if !out.ends_with(['.', '!', '?', ':', ',', ' ']) {
                    out.push_str(". ");
                } else if !out.ends_with(' ') {
                    out.push(' ');
                }
            }
            out.push_str(&tokens_cleaned);
        }
    }

    collapse_whitespace(&out)
}

fn is_table_or_rule(trimmed: &str) -> bool {
    if trimmed.starts_with('|') && trimmed.ends_with('|') {
        return true;
    }
    if trimmed.len() >= 3
        && trimmed
            .chars()
            .all(|c| matches!(c, '-' | '=' | '_' | '*' | '─' | '━' | ' '))
    {
        return true;
    }
    false
}

fn strip_numbered_list_prefix(s: &str) -> &str {
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
    }
    if i > 0 && i + 1 < bytes.len() && matches!(bytes[i], b'.' | b')') && bytes[i + 1] == b' ' {
        return s[i + 2..].trim_start();
    }
    s
}

fn strip_markdown_links(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let bytes = input.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i] == b'['
            && let Some(close_bracket) = input[i + 1..].find(']')
        {
            let label_start = i + 1;
            let label_end = label_start + close_bracket;
            let after_bracket = label_end + 1;
            if after_bracket < bytes.len()
                && bytes[after_bracket] == b'('
                && let Some(close_paren) = input[after_bracket + 1..].find(')')
            {
                out.push_str(&input[label_start..label_end]);
                i = after_bracket + 1 + close_paren + 1;
                continue;
            }
        }
        if let Some(ch) = input[i..].chars().next() {
            out.push(ch);
            i += ch.len_utf8();
        } else {
            break;
        }
    }
    out
}

/// Handles inline `` `code` `` spans so short identifiers are spoken naturally
/// while long CLI invocations, paths, or code expressions are skipped cleanly.
fn normalize_inline_code(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;

    while let Some(start) = rest.find('`') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        let Some(end) = after.find('`') else {
            out.push_str(after);
            return out;
        };
        let code = after[..end].trim();
        rest = &after[end + 1..];

        if code.is_empty() {
            continue;
        }
        // Skip long commands or expressions with code syntax.
        if code.len() > 28
            || code.contains("::")
            || code.contains("&&")
            || code.contains("||")
            || code.contains("=>")
            || code.contains('{')
            || code.contains('}')
            || code.contains('(')
            || code.contains(')')
        {
            continue;
        }
        // Shorten file paths inside backticks to just their basename.
        if code.contains('/') {
            if let Some(base) = code.rsplit('/').find(|seg| !seg.is_empty()) {
                out.push_str(base);
            }
            continue;
        }
        out.push_str(code);
    }
    out.push_str(rest);
    out
}

fn normalize_tokens(input: &str) -> String {
    let mut words: Vec<String> = Vec::new();
    for raw_tok in input.split_whitespace() {
        // Skip bare URLs and file URIs.
        if raw_tok.starts_with("http://")
            || raw_tok.starts_with("https://")
            || raw_tok.starts_with("file://")
        {
            continue;
        }

        // Preserve trailing sentence punctuation before normalizing the core token.
        let (core, trail) = split_trailing_punct(raw_tok);
        let core = core.trim_matches(|c: char| {
            matches!(
                c,
                '*' | '_' | '~' | '`' | '"' | '\'' | '(' | ')' | '[' | ']' | '<' | '>' | '|'
            )
        });
        if core.is_empty() {
            continue;
        }

        // Skip raw hex commit hashes / UUIDs.
        if is_hex_hash_or_uuid(core) {
            continue;
        }

        // Shorten absolute or deep relative paths to basename.
        let core = if core.contains('/') {
            let trimmed = core.trim_end_matches('/');
            if trimmed.starts_with('/')
                || trimmed.starts_with("~/")
                || trimmed.matches('/').count() >= 2
            {
                trimmed.rsplit('/').next().unwrap_or(trimmed)
            } else {
                trimmed
            }
        } else {
            core
        };

        // Strip CLI flag leading dashes (`--setup-models` -> `setup models`).
        let core = core.trim_start_matches('-');
        if core.is_empty() {
            continue;
        }

        // Em-dash / en-dash -> natural pause comma.
        if matches!(core, "—" | "–") {
            if let Some(last) = words.last_mut()
                && !last.ends_with([',', '.', '!', '?', ':'])
            {
                last.push(',');
            }
            continue;
        }

        let humanized = humanize_word(core);
        if humanized.is_empty() {
            continue;
        }

        if trail.is_empty() {
            words.push(humanized);
        } else {
            words.push(format!("{humanized}{trail}"));
        }
    }

    words.join(" ")
}

fn split_trailing_punct(tok: &str) -> (&str, &str) {
    let mut end = tok.len();
    for (idx, ch) in tok.char_indices().rev() {
        if matches!(ch, '.' | ',' | '!' | '?' | ':' | ';') {
            end = idx;
        } else {
            break;
        }
    }
    (&tok[..end], &tok[end..])
}

fn is_hex_hash_or_uuid(s: &str) -> bool {
    let clean = s.replace('-', "");
    if clean.len() < 7 {
        return false;
    }
    let all_hex = clean.chars().all(|c| c.is_ascii_hexdigit());
    let has_digit = clean.chars().any(|c| c.is_ascii_digit());
    let has_alpha = clean.chars().any(|c| c.is_ascii_alphabetic());
    all_hex && has_digit && has_alpha
}

fn humanize_word(word: &str) -> String {
    // Expand common acronyms so Kokoro pronounces them naturally.
    let expanded = match word {
        "NixOS" | "nixos" => return "Nix O S".to_string(),
        "TUI" => return "T U I".to_string(),
        "CLI" => return "C L I".to_string(),
        "VAD" => return "V A D".to_string(),
        "TTS" => return "T T S".to_string(),
        "STT" => return "S T T".to_string(),
        "ACP" => return "A C P".to_string(),
        "API" => return "A P I".to_string(),
        "CPU" => return "C P U".to_string(),
        "GPU" => return "G P U".to_string(),
        "VRAM" => return "V RAM".to_string(),
        "SSH" => return "S S H".to_string(),
        "URL" => return "U R L".to_string(),
        "PT-BR" | "pt-br" => return "Portuguese".to_string(),
        "JSON-RPC" => return "JSON R P C".to_string(),
        "jj" => return "J J".to_string(),
        "agy" => return "aggy".to_string(),
        _ => word,
    };

    // Replace underscores and hyphens with spaces (`agy-voice` -> `agy voice`).
    let spaced = expanded.replace(['_', '-'], " ");
    // Filter out non-speech symbols (emojis, box drawing, math symbols).
    let filtered: String = spaced
        .chars()
        .filter(|c| c.is_alphanumeric() || matches!(c, ' ' | '.' | '\'' | ',' | '!' | '?'))
        .collect();
    collapse_whitespace(&filtered)
}

fn collapse_whitespace(input: &str) -> String {
    input.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Dynamic sentence chunker with per-turn spoken budget so Kokoro speaks in
/// smooth, natural phrases instead of choppy line-by-line or character-by-character output.
pub struct SentenceStream {
    pending: String,
    in_fence: bool,
    spoken_chars: usize,
    max_spoken_chars: usize,
    truncated_notified: bool,
}

impl Default for SentenceStream {
    fn default() -> Self {
        Self::new(800)
    }
}

impl SentenceStream {
    pub fn new(max_spoken_chars: usize) -> Self {
        Self {
            pending: String::new(),
            in_fence: false,
            spoken_chars: 0,
            max_spoken_chars,
            truncated_notified: false,
        }
    }

    pub fn push_delta(&mut self, delta: &str) -> Vec<String> {
        self.pending.push_str(delta);
        self.drain_ready(false)
    }

    pub fn flush(&mut self) -> Vec<String> {
        self.drain_ready(true)
    }

    pub fn clear(&mut self) {
        self.pending.clear();
        self.in_fence = false;
        self.spoken_chars = 0;
        self.truncated_notified = false;
    }

    fn emit_chunk(&mut self, raw: &str, out: &mut Vec<String>) {
        if self.max_spoken_chars > 0 && self.spoken_chars >= self.max_spoken_chars {
            if !self.truncated_notified {
                self.truncated_notified = true;
                out.push("Check the screen for the rest of the details.".to_string());
            }
            return;
        }
        let cleaned = sanitize_for_speech(raw);
        if cleaned.is_empty() {
            return;
        }
        self.spoken_chars += cleaned.len();
        out.push(cleaned);
    }

    fn drain_ready(&mut self, force: bool) -> Vec<String> {
        let mut out = Vec::new();

        // Track code fences line by line, buffering prose across single newlines
        // and flushing on paragraph breaks (`\n\n`) or natural sentence ends.
        let mut prose_buf = String::new();

        while let Some(nl) = self.pending.find('\n') {
            let line = self.pending[..nl].to_string();
            self.pending.drain(..=nl);

            let trimmed = line.trim();
            if trimmed.starts_with("```") {
                if !prose_buf.is_empty() {
                    self.emit_chunk(&prose_buf, &mut out);
                    prose_buf.clear();
                }
                self.in_fence = !self.in_fence;
                continue;
            }
            if self.in_fence || is_table_or_rule(trimmed) {
                continue;
            }
            if trimmed.is_empty() {
                if !prose_buf.is_empty() {
                    self.emit_chunk(&prose_buf, &mut out);
                    prose_buf.clear();
                }
                continue;
            }

            if !prose_buf.is_empty() {
                prose_buf.push('\n');
            }
            prose_buf.push_str(trimmed);

            // Emit when accumulated prose reaches a comfortable natural chunk.
            if prose_buf.len() >= 80 && prose_buf.ends_with(['.', '!', '?']) {
                self.emit_chunk(&prose_buf, &mut out);
                prose_buf.clear();
            }
        }

        if !prose_buf.is_empty() {
            // Put incomplete prose back in front of remaining pending text.
            if !self.pending.is_empty() {
                prose_buf.push(' ');
                prose_buf.push_str(&self.pending);
            }
            self.pending = prose_buf;
        }

        // Mid-paragraph sentence streaming for snappy first-sentence latency.
        if !self.in_fence && !self.pending.trim_start().starts_with("```") {
            while let Some(idx) = find_sentence_boundary(&self.pending) {
                let chunk = self.pending[..idx].to_string();
                self.pending.drain(..idx);
                self.emit_chunk(&chunk, &mut out);
            }
        }

        if force {
            if !self.in_fence && !self.pending.trim().is_empty() {
                let tail = std::mem::take(&mut self.pending);
                self.emit_chunk(&tail, &mut out);
            }
            self.pending.clear();
            self.in_fence = false;
        }

        out
    }
}

fn find_sentence_boundary(s: &str) -> Option<usize> {
    let chars: Vec<(usize, char)> = s.char_indices().collect();
    for w in chars.windows(2) {
        let (idx1, c1) = w[0];
        let (idx2, c2) = w[1];
        if matches!(c1, '.' | '!' | '?') && c2.is_whitespace() && idx1 >= 36 {
            return Some(idx2 + c2.len_utf8());
        }
    }
    None
}

/// Lightweight heuristic to pick Portuguese vs English speaker ID when
/// auto-switching in Kokoro multi-lang.
pub fn looks_portuguese(text: &str) -> bool {
    let lower = text.to_lowercase();
    let pt_chars = lower
        .chars()
        .filter(|c| {
            matches!(
                c,
                'ã' | 'õ' | 'ç' | 'á' | 'é' | 'í' | 'ó' | 'ú' | 'â' | 'ê' | 'ô'
            )
        })
        .count();
    if pt_chars >= 2 {
        return true;
    }
    let markers = [
        " não ",
        " para ",
        " você ",
        " está ",
        " com ",
        " isso ",
        " também ",
        " porque ",
        " então ",
    ];
    let padded = format!(" {lower} ");
    markers.iter().filter(|m| padded.contains(**m)).count() >= 2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_links_code_tables_hashes_and_urls() {
        let input = "\
Check [default.nix](file:///a/b.nix) in commit 70e3dda5 with `cargo clippy --locked --all-targets -- -D warnings` at https://example.com.
| Col | Val |
| --- | --- |
| a | b |
```rust
fn main() {}
```
Done!";
        let got = sanitize_for_speech(input);
        assert!(got.contains("Check default.nix"));
        assert!(!got.contains("file://"));
        assert!(!got.contains("https://"));
        assert!(!got.contains("70e3dda5"));
        assert!(!got.contains("cargo clippy"));
        assert!(!got.contains("Col"));
        assert!(!got.contains("fn main"));
        assert!(got.contains("Done!"));
    }

    #[test]
    fn humanizes_acronyms_and_flags() {
        let got = sanitize_for_speech("Updated NixOS TUI with `--vad-preroll-ms` on CPU.");
        assert!(got.contains("Nix O S"));
        assert!(got.contains("T U I"));
        assert!(got.contains("vad preroll ms"));
        assert!(got.contains("C P U"));
    }

    #[test]
    fn streams_sentences_and_caps_verbosity() {
        let mut st = SentenceStream::new(60);
        let first = st.push_delta("Ciel checked the NixOS build and everything compiled cleanly. ");
        assert_eq!(
            first,
            vec!["Ciel checked the Nix O S build and everything compiled cleanly."]
        );
        let second =
            st.push_delta("Here is a second very long sentence that exceeds the spoken budget. ");
        assert_eq!(
            second,
            vec!["Check the screen for the rest of the details."]
        );
    }

    #[test]
    fn detects_portuguese() {
        assert!(looks_portuguese("Você não precisa reiniciar agora."));
        assert!(!looks_portuguese("Ciel updated default.nix cleanly."));
    }
}
