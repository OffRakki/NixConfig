//! Safe Rust wrappers over `libsherpa-onnx-c-api` (v1.13.8) for Silero VAD
//! and Kokoro-82M offline TTS.

use anyhow::{Context, Result, bail};
use std::ffi::{CString, c_char, c_void};
use std::path::Path;
use std::ptr;
use std::slice;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

#[repr(C)]
struct SherpaOnnxSileroVadModelConfig {
    model: *const c_char,
    threshold: f32,
    min_silence_duration: f32,
    min_speech_duration: f32,
    window_size: i32,
    max_speech_duration: f32,
}

#[repr(C)]
struct SherpaOnnxTenVadModelConfig {
    model: *const c_char,
    threshold: f32,
    min_silence_duration: f32,
    min_speech_duration: f32,
    window_size: i32,
    max_speech_duration: f32,
}

#[repr(C)]
struct SherpaOnnxVadModelConfig {
    silero_vad: SherpaOnnxSileroVadModelConfig,
    sample_rate: i32,
    num_threads: i32,
    provider: *const c_char,
    debug: i32,
    ten_vad: SherpaOnnxTenVadModelConfig,
}

#[repr(C)]
struct SherpaOnnxSpeechSegment {
    start: i32,
    samples: *mut f32,
    n: i32,
}

#[repr(C)]
struct SherpaOnnxVoiceActivityDetector {
    _private: [u8; 0],
}

#[repr(C)]
struct SherpaOnnxOfflineTtsVitsModelConfig {
    model: *const c_char,
    lexicon: *const c_char,
    tokens: *const c_char,
    data_dir: *const c_char,
    noise_scale: f32,
    noise_scale_w: f32,
    length_scale: f32,
    dict_dir: *const c_char,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsMatchaModelConfig {
    acoustic_model: *const c_char,
    vocoder: *const c_char,
    lexicon: *const c_char,
    tokens: *const c_char,
    data_dir: *const c_char,
    noise_scale: f32,
    length_scale: f32,
    dict_dir: *const c_char,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsKokoroModelConfig {
    model: *const c_char,
    voices: *const c_char,
    tokens: *const c_char,
    data_dir: *const c_char,
    length_scale: f32,
    dict_dir: *const c_char,
    lexicon: *const c_char,
    lang: *const c_char,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsKittenModelConfig {
    model: *const c_char,
    voices: *const c_char,
    tokens: *const c_char,
    data_dir: *const c_char,
    length_scale: f32,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsZipvoiceModelConfig {
    tokens: *const c_char,
    encoder: *const c_char,
    decoder: *const c_char,
    vocoder: *const c_char,
    data_dir: *const c_char,
    lexicon: *const c_char,
    feat_scale: f32,
    t_shift: f32,
    target_rms: f32,
    guidance_scale: f32,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsPocketModelConfig {
    lm_flow: *const c_char,
    lm_main: *const c_char,
    encoder: *const c_char,
    decoder: *const c_char,
    text_conditioner: *const c_char,
    vocab_json: *const c_char,
    token_scores_json: *const c_char,
    voice_embedding_cache_capacity: i32,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsSupertonicModelConfig {
    duration_predictor: *const c_char,
    text_encoder: *const c_char,
    vector_estimator: *const c_char,
    vocoder: *const c_char,
    tts_json: *const c_char,
    unicode_indexer: *const c_char,
    voice_style: *const c_char,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsModelConfig {
    vits: SherpaOnnxOfflineTtsVitsModelConfig,
    num_threads: i32,
    debug: i32,
    provider: *const c_char,
    matcha: SherpaOnnxOfflineTtsMatchaModelConfig,
    kokoro: SherpaOnnxOfflineTtsKokoroModelConfig,
    kitten: SherpaOnnxOfflineTtsKittenModelConfig,
    zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig,
    pocket: SherpaOnnxOfflineTtsPocketModelConfig,
    supertonic: SherpaOnnxOfflineTtsSupertonicModelConfig,
}

#[repr(C)]
struct SherpaOnnxOfflineTtsConfig {
    model: SherpaOnnxOfflineTtsModelConfig,
    rule_fsts: *const c_char,
    max_num_sentences: i32,
    rule_fars: *const c_char,
    silence_scale: f32,
}

#[repr(C)]
struct SherpaOnnxGeneratedAudio {
    samples: *const f32,
    n: i32,
    sample_rate: i32,
}

#[repr(C)]
struct SherpaOnnxOfflineTts {
    _private: [u8; 0],
}

#[repr(C)]
struct SherpaOnnxGenerationConfig {
    silence_scale: f32,
    speed: f32,
    sid: i32,
    reference_audio: *const f32,
    reference_audio_len: i32,
    reference_sample_rate: i32,
    reference_text: *const c_char,
    num_steps: i32,
    extra: *const c_char,
}

type ProgressCallbackWithArg =
    Option<unsafe extern "C" fn(samples: *const f32, n: i32, p: f32, arg: *mut c_void) -> i32>;

unsafe extern "C" {
    fn SherpaOnnxCreateVoiceActivityDetector(
        config: *const SherpaOnnxVadModelConfig,
        buffer_size_in_seconds: f32,
    ) -> *const SherpaOnnxVoiceActivityDetector;
    fn SherpaOnnxDestroyVoiceActivityDetector(p: *const SherpaOnnxVoiceActivityDetector);
    fn SherpaOnnxVoiceActivityDetectorAcceptWaveform(
        p: *const SherpaOnnxVoiceActivityDetector,
        samples: *const f32,
        n: i32,
    );
    fn SherpaOnnxVoiceActivityDetectorEmpty(p: *const SherpaOnnxVoiceActivityDetector) -> i32;
    fn SherpaOnnxVoiceActivityDetectorDetected(p: *const SherpaOnnxVoiceActivityDetector) -> i32;
    fn SherpaOnnxVoiceActivityDetectorPop(p: *const SherpaOnnxVoiceActivityDetector);
    fn SherpaOnnxVoiceActivityDetectorFront(
        p: *const SherpaOnnxVoiceActivityDetector,
    ) -> *const SherpaOnnxSpeechSegment;
    fn SherpaOnnxDestroySpeechSegment(p: *const SherpaOnnxSpeechSegment);
    fn SherpaOnnxVoiceActivityDetectorReset(p: *const SherpaOnnxVoiceActivityDetector);

    fn SherpaOnnxCreateOfflineTts(
        config: *const SherpaOnnxOfflineTtsConfig,
    ) -> *const SherpaOnnxOfflineTts;
    fn SherpaOnnxDestroyOfflineTts(tts: *const SherpaOnnxOfflineTts);
    fn SherpaOnnxOfflineTtsSampleRate(tts: *const SherpaOnnxOfflineTts) -> i32;
    fn SherpaOnnxOfflineTtsNumSpeakers(tts: *const SherpaOnnxOfflineTts) -> i32;
    fn SherpaOnnxOfflineTtsGenerateWithConfig(
        tts: *const SherpaOnnxOfflineTts,
        text: *const c_char,
        config: *const SherpaOnnxGenerationConfig,
        callback: ProgressCallbackWithArg,
        arg: *mut c_void,
    ) -> *const SherpaOnnxGeneratedAudio;
    fn SherpaOnnxDestroyOfflineTtsGeneratedAudio(p: *const SherpaOnnxGeneratedAudio);
}

fn path_to_cstring(path: &Path) -> Result<CString> {
    let s = path
        .to_str()
        .with_context(|| format!("non-UTF-8 path: {}", path.display()))?;
    CString::new(s).with_context(|| format!("path contains NUL byte: {}", path.display()))
}

/// CPU-pinned Silero VAD wrapper over `SherpaOnnxVoiceActivityDetector`.
pub struct SileroVad {
    ptr: *const SherpaOnnxVoiceActivityDetector,
}

// SAFETY: SileroVad owns an exclusive opaque sherpa-onnx handle and is only
// accessed via `&mut self` (single-owner thread confinement).
unsafe impl Send for SileroVad {}

pub struct VadOptions {
    pub threshold: f32,
    pub min_silence_duration: f32,
    pub min_speech_duration: f32,
    pub max_speech_duration: f32,
    pub sample_rate: i32,
    pub window_size: i32,
}

impl Default for VadOptions {
    fn default() -> Self {
        Self {
            threshold: 0.30,
            min_silence_duration: 2.2,
            min_speech_duration: 0.12,
            max_speech_duration: 60.0,
            sample_rate: 16_000,
            window_size: 512,
        }
    }
}

pub struct SpeechSegment {
    pub start: usize,
    pub samples: Vec<f32>,
}

impl SileroVad {
    pub fn new(model_path: &Path, opts: &VadOptions) -> Result<Self> {
        let model_c = path_to_cstring(model_path)?;
        let provider_c = CString::new("cpu")?;
        let empty_c = CString::new("")?;

        let cfg = SherpaOnnxVadModelConfig {
            silero_vad: SherpaOnnxSileroVadModelConfig {
                model: model_c.as_ptr(),
                threshold: opts.threshold,
                min_silence_duration: opts.min_silence_duration,
                min_speech_duration: opts.min_speech_duration,
                window_size: opts.window_size,
                max_speech_duration: opts.max_speech_duration,
            },
            sample_rate: opts.sample_rate,
            num_threads: 1,
            provider: provider_c.as_ptr(),
            debug: 0,
            ten_vad: SherpaOnnxTenVadModelConfig {
                model: empty_c.as_ptr(),
                threshold: 0.0,
                min_silence_duration: 0.0,
                min_speech_duration: 0.0,
                window_size: 0,
                max_speech_duration: 0.0,
            },
        };

        // SAFETY: `cfg` and its CString pointers remain valid for the duration
        // of `SherpaOnnxCreateVoiceActivityDetector`, which copies all strings.
        let ptr = unsafe { SherpaOnnxCreateVoiceActivityDetector(&cfg, 65.0) };
        if ptr.is_null() {
            bail!(
                "failed to initialize Silero VAD from {}",
                model_path.display()
            );
        }
        Ok(Self { ptr })
    }

    pub fn accept_waveform(&mut self, samples: &[f32]) {
        // SAFETY: `self.ptr` is a live handle and `samples` is a valid slice.
        unsafe {
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                self.ptr,
                samples.as_ptr(),
                samples.len() as i32,
            );
        }
    }

    pub fn is_speech_detected(&self) -> bool {
        // SAFETY: `self.ptr` is valid.
        unsafe { SherpaOnnxVoiceActivityDetectorDetected(self.ptr) != 0 }
    }

    pub fn reset(&mut self) {
        // SAFETY: `self.ptr` is valid.
        unsafe {
            SherpaOnnxVoiceActivityDetectorReset(self.ptr);
        }
    }

    /// Drains all completed speech segments currently queued in the VAD.
    pub fn pop_segments(&mut self) -> Vec<SpeechSegment> {
        let mut out = Vec::new();
        // SAFETY: Standard sherpa-onnx Front -> DestroySpeechSegment -> Pop protocol.
        unsafe {
            while SherpaOnnxVoiceActivityDetectorEmpty(self.ptr) == 0 {
                let seg = SherpaOnnxVoiceActivityDetectorFront(self.ptr);
                if !seg.is_null() {
                    let start = (*seg).start.max(0) as usize;
                    let n = (*seg).n.max(0) as usize;
                    if n > 0 && !(*seg).samples.is_null() {
                        out.push(SpeechSegment {
                            start,
                            samples: slice::from_raw_parts((*seg).samples, n).to_vec(),
                        });
                    }
                    SherpaOnnxDestroySpeechSegment(seg);
                }
                SherpaOnnxVoiceActivityDetectorPop(self.ptr);
            }
        }
        out
    }
}

impl Drop for SileroVad {
    fn drop(&mut self) {
        // SAFETY: `self.ptr` was returned by `SherpaOnnxCreateVoiceActivityDetector`.
        unsafe {
            SherpaOnnxDestroyVoiceActivityDetector(self.ptr);
        }
    }
}

/// Kokoro-82M model paths on disk.
#[derive(Clone, Debug)]
pub struct KokoroPaths {
    pub model: std::path::PathBuf,
    pub voices: std::path::PathBuf,
    pub tokens: std::path::PathBuf,
    pub data_dir: std::path::PathBuf,
    pub lexicon: Option<std::path::PathBuf>,
}

/// CPU-pinned Kokoro-82M offline TTS engine via `libsherpa-onnx-c-api`.
pub struct KokoroTts {
    ptr: *const SherpaOnnxOfflineTts,
    sample_rate: u32,
    num_speakers: i32,
}

// SAFETY: KokoroTts owns an exclusive opaque sherpa-onnx handle accessed only
// from its dedicated TTS worker thread.
unsafe impl Send for KokoroTts {}

struct CancelContext {
    cancel: Arc<AtomicBool>,
}

unsafe extern "C" fn tts_cancel_callback(
    _samples: *const f32,
    _n: i32,
    _p: f32,
    arg: *mut c_void,
) -> i32 {
    if arg.is_null() {
        return 1;
    }
    // SAFETY: `arg` points to a live `CancelContext` for the duration of
    // `SherpaOnnxOfflineTtsGenerateWithConfig`.
    let ctx = unsafe { &*(arg as *const CancelContext) };
    if ctx.cancel.load(Ordering::Relaxed) {
        0
    } else {
        1
    }
}

impl KokoroTts {
    pub fn new(paths: &KokoroPaths, num_threads: i32, lang: &str) -> Result<Self> {
        let model_c = path_to_cstring(&paths.model)?;
        let voices_c = path_to_cstring(&paths.voices)?;
        let tokens_c = path_to_cstring(&paths.tokens)?;
        let data_dir_c = path_to_cstring(&paths.data_dir)?;
        // Only apply the US English lexicon for English; other languages (e.g.
        // `pt-br`) rely on espeak-ng via `lang` so phonemes aren't mangled.
        let lexicon_c = match (&paths.lexicon, lang) {
            (Some(p), "" | "en" | "en-us") => path_to_cstring(p)?,
            _ => CString::new("")?,
        };
        let lang_c = CString::new(lang)?;
        let provider_c = CString::new("cpu")?;
        let empty_c = CString::new("")?;
        let null = ptr::null();

        let cfg = SherpaOnnxOfflineTtsConfig {
            model: SherpaOnnxOfflineTtsModelConfig {
                vits: SherpaOnnxOfflineTtsVitsModelConfig {
                    model: null,
                    lexicon: null,
                    tokens: null,
                    data_dir: null,
                    noise_scale: 0.0,
                    noise_scale_w: 0.0,
                    length_scale: 0.0,
                    dict_dir: null,
                },
                num_threads: num_threads.max(1),
                debug: 0,
                provider: provider_c.as_ptr(),
                matcha: SherpaOnnxOfflineTtsMatchaModelConfig {
                    acoustic_model: null,
                    vocoder: null,
                    lexicon: null,
                    tokens: null,
                    data_dir: null,
                    noise_scale: 0.0,
                    length_scale: 0.0,
                    dict_dir: null,
                },
                kokoro: SherpaOnnxOfflineTtsKokoroModelConfig {
                    model: model_c.as_ptr(),
                    voices: voices_c.as_ptr(),
                    tokens: tokens_c.as_ptr(),
                    data_dir: data_dir_c.as_ptr(),
                    length_scale: 1.0,
                    dict_dir: empty_c.as_ptr(),
                    lexicon: lexicon_c.as_ptr(),
                    lang: lang_c.as_ptr(),
                },
                kitten: SherpaOnnxOfflineTtsKittenModelConfig {
                    model: null,
                    voices: null,
                    tokens: null,
                    data_dir: null,
                    length_scale: 0.0,
                },
                zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig {
                    tokens: null,
                    encoder: null,
                    decoder: null,
                    vocoder: null,
                    data_dir: null,
                    lexicon: null,
                    feat_scale: 0.0,
                    t_shift: 0.0,
                    target_rms: 0.0,
                    guidance_scale: 0.0,
                },
                pocket: SherpaOnnxOfflineTtsPocketModelConfig {
                    lm_flow: null,
                    lm_main: null,
                    encoder: null,
                    decoder: null,
                    text_conditioner: null,
                    vocab_json: null,
                    token_scores_json: null,
                    voice_embedding_cache_capacity: 0,
                },
                supertonic: SherpaOnnxOfflineTtsSupertonicModelConfig {
                    duration_predictor: null,
                    text_encoder: null,
                    vector_estimator: null,
                    vocoder: null,
                    tts_json: null,
                    unicode_indexer: null,
                    voice_style: null,
                },
            },
            rule_fsts: empty_c.as_ptr(),
            max_num_sentences: 1,
            rule_fars: empty_c.as_ptr(),
            silence_scale: 0.2,
        };

        // SAFETY: `cfg` and all CStrings live across the constructor call.
        let ptr = unsafe { SherpaOnnxCreateOfflineTts(&cfg) };
        if ptr.is_null() {
            bail!(
                "failed to initialize Kokoro TTS from {}",
                paths.model.display()
            );
        }

        // SAFETY: `ptr` is non-null and initialized.
        let sample_rate = unsafe { SherpaOnnxOfflineTtsSampleRate(ptr) }.max(8000) as u32;
        let num_speakers = unsafe { SherpaOnnxOfflineTtsNumSpeakers(ptr) };

        Ok(Self {
            ptr,
            sample_rate,
            num_speakers,
        })
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Synthesizes mono f32 PCM samples at `self.sample_rate()`.
    /// Returns `Ok(None)` if canceled mid-generation.
    pub fn generate(
        &mut self,
        text: &str,
        speaker_id: i32,
        speed: f32,
        cancel: &Arc<AtomicBool>,
    ) -> Result<Option<Vec<f32>>> {
        if cancel.load(Ordering::Relaxed) {
            return Ok(None);
        }
        let clean = text.replace('\0', " ");
        let text_c = CString::new(clean)?;
        let sid = if self.num_speakers > 0 {
            speaker_id.clamp(0, self.num_speakers - 1)
        } else {
            0
        };

        let gen_cfg = SherpaOnnxGenerationConfig {
            silence_scale: 0.2,
            speed: speed.clamp(0.5, 2.0),
            sid,
            reference_audio: ptr::null(),
            reference_audio_len: 0,
            reference_sample_rate: 0,
            reference_text: ptr::null(),
            num_steps: 0,
            extra: ptr::null(),
        };

        let mut ctx = CancelContext {
            cancel: Arc::clone(cancel),
        };

        // SAFETY: `self.ptr` is live, `text_c` and `ctx` outlive the C call,
        // and the returned audio pointer is destroyed before returning.
        let audio = unsafe {
            SherpaOnnxOfflineTtsGenerateWithConfig(
                self.ptr,
                text_c.as_ptr(),
                &gen_cfg,
                Some(tts_cancel_callback),
                (&mut ctx as *mut CancelContext).cast::<c_void>(),
            )
        };

        if audio.is_null() {
            if cancel.load(Ordering::Relaxed) {
                return Ok(None);
            }
            return Ok(Some(Vec::new()));
        }

        let samples = unsafe {
            let n = (*audio).n.max(0) as usize;
            let buf = if n > 0 && !(*audio).samples.is_null() {
                slice::from_raw_parts((*audio).samples, n).to_vec()
            } else {
                Vec::new()
            };
            SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
            buf
        };

        if cancel.load(Ordering::Relaxed) {
            return Ok(None);
        }
        Ok(Some(samples))
    }
}

impl Drop for KokoroTts {
    fn drop(&mut self) {
        // SAFETY: `self.ptr` was returned by `SherpaOnnxCreateOfflineTts`.
        unsafe {
            SherpaOnnxDestroyOfflineTts(self.ptr);
        }
    }
}
