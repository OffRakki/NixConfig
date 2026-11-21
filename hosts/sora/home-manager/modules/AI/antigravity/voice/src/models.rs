//! Model path discovery and first-run download helper for Silero VAD,
//! Kokoro-82M int8 multi-lang TTS, and Whisper GGML STT.

use crate::sherpa::KokoroPaths;
use anyhow::{Context, Result, bail};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const SILERO_VAD_URL: &str =
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx";
const KOKORO_URL: &str = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2";
const KOKORO_DIR_NAME: &str = "kokoro-multi-lang-v1_0";
const KOKORO_INT8_DIR_NAME: &str = "kokoro-int8-multi-lang-v1_0";
const WHISPER_DEFAULT_NAME: &str = "ggml-small-q5_1.bin";
const WHISPER_DEFAULT_URL: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin";

#[derive(Clone, Debug)]
pub struct ModelBundle {
    pub vad_model: PathBuf,
    pub whisper_model: PathBuf,
    pub kokoro: KokoroPaths,
}

pub fn data_root() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg).join("agy-voice").join("models");
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join(".local")
        .join("share")
        .join("agy-voice")
        .join("models")
}

fn whisper_shared_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join(".local")
        .join("share")
        .join("whisper-cpp")
}

fn find_kokoro_in(dir: &Path) -> Option<KokoroPaths> {
    let model = [dir.join("model.onnx"), dir.join("model.int8.onnx")]
        .into_iter()
        .find(|p| p.is_file())?;
    let voices = dir.join("voices.bin");
    let tokens = dir.join("tokens.txt");
    let data_dir = dir.join("espeak-ng-data");
    if !voices.is_file() || !tokens.is_file() || !data_dir.is_dir() {
        return None;
    }
    let lexicon = [
        dir.join("lexicon-us-en.txt"),
        dir.join("lexicon-gb-en.txt"),
        dir.join("lexicon.txt"),
    ]
    .into_iter()
    .find(|p| p.is_file());

    Some(KokoroPaths {
        model,
        voices,
        tokens,
        data_dir,
        lexicon,
    })
}

fn find_whisper_model(explicit: Option<&Path>, root: &Path) -> Option<PathBuf> {
    if let Some(p) = explicit {
        return p.is_file().then(|| p.to_path_buf());
    }
    let shared = whisper_shared_dir();
    let candidates = [
        root.join(WHISPER_DEFAULT_NAME),
        shared.join("ggml-small-q5_1.bin"),
        shared.join("ggml-large-v3-turbo-q5_0.bin"),
        shared.join("ggml-small.bin"),
        shared.join("ggml-base.bin"),
    ];
    candidates.into_iter().find(|p| p.is_file())
}

pub fn resolve_models(
    whisper_override: Option<&Path>,
    kokoro_override: Option<&Path>,
    vad_override: Option<&Path>,
) -> Result<ModelBundle> {
    let root = data_root();

    let vad_model = vad_override
        .map(Path::to_path_buf)
        .unwrap_or_else(|| root.join("silero_vad.onnx"));
    if !vad_model.is_file() {
        bail!(
            "Silero VAD model missing at {} (run `agy-voice --setup-models`)",
            vad_model.display()
        );
    }

    let whisper_model = find_whisper_model(whisper_override, &root).with_context(|| {
        format!(
            "Whisper GGML model missing in {} or {} (run `agy-voice --setup-models`)",
            root.display(),
            whisper_shared_dir().display()
        )
    })?;

    let kokoro = match kokoro_override {
        Some(dir) => find_kokoro_in(dir).with_context(|| {
            format!(
                "Kokoro TTS model files missing under {} (run `agy-voice --setup-models`)",
                dir.display()
            )
        })?,
        None => find_kokoro_in(&root.join(KOKORO_DIR_NAME))
            .or_else(|| find_kokoro_in(&root.join(KOKORO_INT8_DIR_NAME)))
            .with_context(|| {
                format!(
                    "Kokoro TTS model files missing under {} (run `agy-voice --setup-models`)",
                    root.join(KOKORO_DIR_NAME).display()
                )
            })?,
    };

    Ok(ModelBundle {
        vad_model,
        whisper_model,
        kokoro,
    })
}

fn download_file(url: &str, dest: &Path) -> Result<()> {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = dest.with_extension("part");
    eprintln!("Downloading {url} -> {}", dest.display());
    let status = Command::new("curl")
        .args(["-fL", "--progress-bar", "-o"])
        .arg(&tmp)
        .arg(url)
        .status()
        .context("failed to execute curl")?;
    if !status.success() {
        let _ = fs::remove_file(&tmp);
        bail!("curl failed downloading {url} (exit {status})");
    }
    fs::rename(&tmp, dest)?;
    Ok(())
}

pub fn setup_models(whisper_override: Option<&Path>) -> Result<ModelBundle> {
    let root = data_root();
    fs::create_dir_all(&root)?;

    let vad_path = root.join("silero_vad.onnx");
    if !vad_path.is_file() {
        download_file(SILERO_VAD_URL, &vad_path)?;
    } else {
        eprintln!("Silero VAD already present: {}", vad_path.display());
    }

    let kokoro_dir = root.join(KOKORO_DIR_NAME);
    if find_kokoro_in(&kokoro_dir).is_none() {
        let archive = root.join(format!("{KOKORO_DIR_NAME}.tar.bz2"));
        download_file(KOKORO_URL, &archive)?;
        eprintln!("Extracting Kokoro TTS -> {}", root.display());
        let status = Command::new("tar")
            .args(["-xjf"])
            .arg(&archive)
            .arg("-C")
            .arg(&root)
            .status()
            .context("failed to execute tar")?;
        let _ = fs::remove_file(&archive);
        if !status.success() {
            bail!("tar failed extracting Kokoro archive (exit {status})");
        }
    } else {
        eprintln!("Kokoro TTS already present: {}", kokoro_dir.display());
    }

    if find_whisper_model(whisper_override, &root).is_none() {
        let whisper_path = root.join(WHISPER_DEFAULT_NAME);
        download_file(WHISPER_DEFAULT_URL, &whisper_path)?;
    } else {
        eprintln!("Whisper model already present.");
    }

    resolve_models(whisper_override, None, None)
}
