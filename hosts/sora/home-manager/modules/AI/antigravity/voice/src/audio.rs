//! PipeWire raw PCM audio capture (`pw-cat --record`) and playback
//! (`pw-cat --playback`), plus in-memory 16-bit WAV encoding for `whisper-server`.

use anyhow::{Context, Result};
use std::collections::VecDeque;
use std::io::{Read, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

pub const CAPTURE_SAMPLE_RATE: u32 = 16_000;
pub const VAD_WINDOW_SAMPLES: usize = 512;

/// Continuous 16 kHz mono f32 PipeWire microphone reader.
pub struct MicCapture {
    child: Child,
    stdout: ChildStdout,
    raw_buf: Vec<u8>,
}

impl MicCapture {
    pub fn start() -> Result<Self> {
        let mut child = Command::new("pw-cat")
            .args([
                "--record",
                "--raw",
                "--format=f32",
                "--rate=16000",
                "--channels=1",
                "--latency=32ms",
                "-",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("failed to spawn `pw-cat --record`")?;

        let stdout = child
            .stdout
            .take()
            .context("`pw-cat --record` did not provide stdout")?;
        Ok(Self {
            child,
            stdout,
            raw_buf: vec![0u8; VAD_WINDOW_SAMPLES * 4],
        })
    }

    /// Reads exactly `buf.len()` f32 mono samples (little-endian).
    pub fn read_frame(&mut self, buf: &mut [f32]) -> Result<()> {
        let need = buf.len() * 4;
        if self.raw_buf.len() != need {
            self.raw_buf.resize(need, 0);
        }
        self.stdout
            .read_exact(&mut self.raw_buf)
            .context("PipeWire mic stream closed")?;
        for (dst, chunk) in buf.iter_mut().zip(self.raw_buf.chunks_exact(4)) {
            *dst = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        }
        Ok(())
    }
}

/// Sample-indexed rolling history used to prepend exact pre-roll audio right
/// before a Silero VAD segment's `start` sample without overlap or clipping.
pub struct SampleRing {
    buf: VecDeque<f32>,
    capacity: usize,
    total_written: usize,
}

impl SampleRing {
    pub fn new(capacity: usize) -> Self {
        Self {
            buf: VecDeque::with_capacity(capacity),
            capacity,
            total_written: 0,
        }
    }

    pub fn push_slice(&mut self, samples: &[f32]) {
        self.buf.extend(samples.iter().copied());
        self.total_written += samples.len();
        if self.buf.len() > self.capacity {
            let overflow = self.buf.len() - self.capacity;
            self.buf.drain(..overflow);
        }
    }

    pub fn clear(&mut self) {
        self.buf.clear();
        self.total_written = 0;
    }

    /// Returns up to `pre_roll` samples immediately preceding `seg_start`
    /// (`[seg_start - pre_roll .. seg_start)`), clamped to retained history.
    pub fn preroll_before(&self, seg_start: usize, pre_roll: usize) -> Vec<f32> {
        if pre_roll == 0 || self.buf.is_empty() {
            return Vec::new();
        }
        let oldest = self.total_written.saturating_sub(self.buf.len());
        let end = seg_start.min(self.total_written);
        let start = end.saturating_sub(pre_roll).max(oldest);
        if start >= end {
            return Vec::new();
        }
        let rel_start = start - oldest;
        let rel_end = end - oldest;
        self.buf.range(rel_start..rel_end).copied().collect()
    }
}

impl Drop for MicCapture {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Computes normalized RMS energy in `[0.0, 1.0]` for the UI level meter.
pub fn frame_rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum_sq: f32 = samples.iter().map(|s| s * s).sum();
    (sum_sq / samples.len() as f32).sqrt().min(1.0)
}

/// Plays mono f32 PCM samples through PipeWire, aborting early if `cancel` flips.
pub fn play_pcm_interruptible(
    samples: &[f32],
    sample_rate: u32,
    cancel: &Arc<AtomicBool>,
) -> Result<()> {
    if samples.is_empty() || cancel.load(Ordering::Relaxed) {
        return Ok(());
    }

    let rate_arg = format!("--rate={sample_rate}");
    let mut child = Command::new("pw-cat")
        .args([
            "--playback",
            "--raw",
            "--format=f32",
            &rate_arg,
            "--channels=1",
            "--latency=64ms",
            "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("failed to spawn `pw-cat --playback`")?;

    let mut stdin: ChildStdin = child
        .stdin
        .take()
        .context("`pw-cat --playback` did not provide stdin")?;

    // Write in ~40ms chunks so cancel takes effect nearly instantaneously.
    let chunk_samples = (sample_rate as usize / 25).max(512);
    let mut bytes = Vec::with_capacity(chunk_samples * 4);
    for chunk in samples.chunks(chunk_samples) {
        if cancel.load(Ordering::Relaxed) {
            drop(stdin);
            let _ = child.kill();
            let _ = child.wait();
            return Ok(());
        }
        bytes.clear();
        for &s in chunk {
            bytes.extend_from_slice(&s.to_le_bytes());
        }
        if stdin.write_all(&bytes).is_err() {
            break;
        }
    }
    drop(stdin);

    // Poll child exit briefly so cancel can still cut buffered playback tail.
    loop {
        if cancel.load(Ordering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            return Ok(());
        }
        match child.try_wait()? {
            Some(_) => return Ok(()),
            None => std::thread::sleep(std::time::Duration::from_millis(20)),
        }
    }
}

/// Encodes mono f32 PCM in `[-1, 1]` to a standard 16-bit PCM WAV byte buffer.
pub fn encode_wav_i16(samples: &[f32], sample_rate: u32) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data_len as usize);

    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes()); // PCM chunk size
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM format
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&(sample_rate * 2).to_le_bytes()); // byte rate
    out.extend_from_slice(&2u16.to_le_bytes()); // block align
    out.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());

    for &s in samples {
        let clamped = s.clamp(-1.0, 1.0);
        let v = (clamped * i16::MAX as f32).round() as i16;
        out.extend_from_slice(&v.to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wav_header_is_valid() {
        let wav = encode_wav_i16(&[0.0, 0.5, -0.5, 1.0], 16_000);
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(wav.len(), 44 + 8);
    }

    #[test]
    fn sample_ring_extracts_exact_preroll_without_overlap() {
        let mut ring = SampleRing::new(10);
        ring.push_slice(&[0.0, 1.0, 2.0, 3.0, 4.0, 5.0]);
        assert_eq!(ring.preroll_before(5, 3), vec![2.0, 3.0, 4.0]);
        assert_eq!(ring.preroll_before(2, 5), vec![0.0, 1.0]);

        // After wrap-around (oldest index becomes 6, total_written = 16)
        ring.push_slice(&[6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0]);
        assert_eq!(ring.preroll_before(12, 4), vec![8.0, 9.0, 10.0, 11.0]);
        assert_eq!(ring.preroll_before(8, 5), vec![6.0, 7.0]);
    }
}
