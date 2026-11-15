//! Noctalia owns the UI and palette; this process owns every renderer child.
use fs2::FileExt;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, HashSet},
    env, fs,
    fs::{File, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    os::unix::{
        fs::{DirBuilderExt, FileTypeExt, MetadataExt, OpenOptionsExt},
        net::{UnixListener, UnixStream},
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant, UNIX_EPOCH},
};
use walkdir::WalkDir;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const MAX_MESSAGE: u64 = 2 * 1024 * 1024;

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Scan {
        root: PathBuf,
    },
    Preview {
        path: PathBuf,
        #[serde(default)]
        thumbnail: bool,
    },
    Play {
        output: String,
        path: PathBuf,
        #[serde(default)]
        scale: Scale,
        #[serde(default = "default_fps")]
        fps: u32,
    },
    Control {
        output: String,
        command: Control,
    },
    Status {},
    Shutdown {},
}
#[derive(Default, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Scale {
    #[default]
    Fill,
    Stretch,
    Original,
    Fit,
}
impl Scale {
    fn option(&self) -> &'static str {
        match self {
            Self::Fill => "fill",
            Self::Stretch => "stretch",
            Self::Original => "original",
            Self::Fit => "panscan=1.0",
        }
    }
}
#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum Control {
    Pause,
    Resume,
    Stop,
}
fn default_fps() -> u32 {
    30
}
fn digest(value: impl AsRef<[u8]>) -> String {
    format!("{:x}", Sha256::digest(value))
}
fn error(message: impl std::fmt::Display) -> Value {
    json!({"ok":false,"error":message.to_string()})
}
fn emit(value: Value) {
    println!("{value}");
    let _ = io::stdout().flush();
}

fn private_dir(path: &Path, uid: u32) -> Result<()> {
    match fs::DirBuilder::new().mode(0o700).create(path) {
        Ok(()) => (),
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => (),
        Err(e) => return Err(e.into()),
    }
    let meta = fs::symlink_metadata(path)?;
    if !meta.is_dir() || meta.uid() != uid || meta.mode() & 0o077 != 0 {
        return Err(format!("{} must be a real owner-only directory", path.display()).into());
    }
    Ok(())
}
fn runtime_dir() -> Result<PathBuf> {
    let root = PathBuf::from(env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR is unset")?);
    let meta = fs::symlink_metadata(&root)?;
    if !meta.is_dir() || meta.mode() & 0o077 != 0 {
        return Err("XDG_RUNTIME_DIR is not private".into());
    }
    let path = root.join("motionwall");
    private_dir(&path, meta.uid())?;
    Ok(path)
}
fn kind(path: &Path) -> Option<&'static str> {
    match path.extension()?.to_str()?.to_ascii_lowercase().as_str() {
        "jpg" | "jpeg" | "png" | "webp" | "bmp" => Some("image"),
        "mp4" | "mkv" | "webm" | "mov" | "avi" | "m4v" | "gif" => Some("video"),
        _ => None,
    }
}
fn media_path(path: &Path) -> Result<PathBuf> {
    let path = fs::canonicalize(path)?;
    let text = path.to_str().ok_or("media path is not UTF-8")?;
    // gSlapper's line-oriented IPC has a 512-byte status response.
    if text.contains(['\n', '\r', '\0']) || text.len() > 450 {
        return Err("media path contains a control character or exceeds 450 bytes".into());
    }
    if !path.is_file() || kind(&path).is_none() {
        return Err("unsupported media file".into());
    }
    Ok(path)
}
fn scan(root: &Path) -> Result<Value> {
    if !root.is_dir() {
        return Err(format!("not a readable directory: {}", root.display()).into());
    }
    let mut entries = Vec::new();
    let mut warnings = Vec::new();
    let mut seen = HashSet::new();
    for entry in WalkDir::new(root)
        .follow_links(true)
        .max_depth(32)
        .sort_by_file_name()
        .into_iter()
        .take(20_001)
        .enumerate()
    {
        if entry.0 == 20_000 {
            warnings
                .push("Scan limited to 20,000 filesystem entries; use a smaller folder.".into());
            break;
        }
        let entry = match entry.1 {
            Ok(e) => e,
            Err(e) => {
                if warnings.len() < 20 {
                    warnings.push(e.to_string());
                }
                continue;
            }
        };
        if !entry.file_type().is_file() || kind(entry.path()).is_none() {
            continue;
        }
        match media_path(entry.path()) {
            Ok(path) if seen.insert(path.clone()) => {
                entries.push(json!({"path":path,"name":entry.file_name().to_string_lossy(),"kind":kind(&path)}));
                if entries.len() >= 512 {
                    warnings
                        .push("Library limited to 512 media files; use a smaller folder.".into());
                    break;
                }
            }
            Ok(_) => (),
            Err(e) => {
                if warnings.len() < 20 {
                    warnings.push(e.to_string());
                }
            }
        }
    }
    entries.sort_by_key(|e| e["name"].as_str().unwrap_or("").to_lowercase());
    Ok(json!({"ok":true,"entries":entries,"warnings":warnings}))
}
fn cache_key(path: &Path) -> Result<String> {
    let meta = fs::metadata(path)?;
    Ok(digest(format!(
        "v1:{}:{}:{}:{}:{}",
        path.display(),
        meta.len(),
        meta.modified()?.duration_since(UNIX_EPOCH)?.as_nanos(),
        meta.dev(),
        meta.ino()
    )))
}
fn jpeg_valid(path: &Path) -> bool {
    let mut header = [0; 3];
    File::open(path)
        .and_then(|mut f| f.read_exact(&mut header))
        .is_ok()
        && header == [0xff, 0xd8, 0xff]
}
fn read_excerpt(path: &Path) -> String {
    let mut text = String::new();
    if let Ok(f) = File::open(path) {
        let _ = f.take(8192).read_to_string(&mut text);
    }
    text
}
fn preview(path: &Path, cache: &Path, quit: &AtomicBool, thumbnail: bool) -> Result<PathBuf> {
    if !thumbnail && kind(path) == Some("image") {
        return Ok(path.to_path_buf());
    }
    // Picker images must never decode the multi-megapixel original on the UI thread.
    // Keep these separate from the larger video still used for wallpaper colors.
    let key = format!(
        "{}{}",
        if thumbnail { "thumb-" } else { "" },
        cache_key(path)?
    );
    let filter = if thumbnail {
        "scale=420:230:force_original_aspect_ratio=decrease"
    } else {
        "scale=1280:720:force_original_aspect_ratio=decrease"
    };
    let filter = if kind(path) == Some("video") {
        format!("{filter},thumbnail=60")
    } else {
        filter.to_string()
    };
    let target = cache.join(format!("{key}.jpg"));
    if jpeg_valid(&target) {
        return Ok(target);
    }
    let temporary = cache.join(format!("{key}.tmp.jpg"));
    let log = cache.join(format!("{key}.stderr"));
    let result = (|| -> Result<()> {
        let stderr = File::create(&log)?;
        let mut child = Command::new("ffmpeg")
            .args([
                "-nostdin",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-threads",
                "2",
                "-filter_threads",
                "1",
                "-i",
            ])
            .arg(path)
            .args([
                "-an",
                "-vf",
                &filter,
                "-frames:v",
                "1",
                "-q:v",
                "2",
                "-f",
                "image2",
            ])
            .arg(&temporary)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(stderr)
            .spawn()?;
        let deadline = Instant::now() + Duration::from_secs(20);
        loop {
            if let Some(status) = child.try_wait()? {
                if !status.success() || !jpeg_valid(&temporary) {
                    return Err(format!("FFmpeg preview failed: {}", read_excerpt(&log)).into());
                }
                break;
            }
            if quit.load(Ordering::Relaxed) || Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err("FFmpeg preview cancelled or timed out after 20 seconds".into());
            }
            thread::sleep(Duration::from_millis(20));
        }
        fs::rename(&temporary, &target)?;
        Ok(())
    })();
    let _ = fs::remove_file(&temporary);
    let _ = fs::remove_file(&log);
    result?;
    Ok(target)
}
fn line(stream: &mut UnixStream) -> Result<String> {
    let mut value = String::new();
    BufReader::new(stream)
        .take(MAX_MESSAGE + 1)
        .read_line(&mut value)?;
    if value.len() as u64 > MAX_MESSAGE || !value.ends_with('\n') {
        return Err("oversized or incomplete IPC response".into());
    }
    Ok(value.trim_end_matches(['\n', '\r']).into())
}
fn ipc(socket: &Path, command: &str) -> Result<String> {
    let mut stream = UnixStream::connect(socket)?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    writeln!(stream, "{command}")?;
    let response = line(&mut stream)?;
    if response.starts_with("ERROR") {
        return Err(response.into());
    }
    Ok(response)
}
struct Player {
    child: Child,
    socket: PathBuf,
    path: PathBuf,
    log: PathBuf,
}
impl Drop for Player {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = fs::remove_file(&self.socket);
    }
}
struct Server {
    players: BTreeMap<String, Player>,
    runtime: PathBuf,
    cache: PathBuf,
    quit: Arc<AtomicBool>,
}
impl Server {
    fn play(&mut self, output: String, path: PathBuf, scale: Scale, fps: u32) -> Result<Value> {
        if output.is_empty()
            || output.len() > 64
            || !output
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
        {
            return Err("invalid output connector".into());
        }
        if ![30, 60, 100].contains(&fps) {
            return Err("FPS must be 30, 60 or 100".into());
        }
        let path = media_path(&path)?;
        let image = preview(&path, &self.cache, &self.quit, false)?;
        if kind(&path) == Some("image") {
            self.players.remove(&output);
            return Ok(json!({"ok":true,"path":path,"preview":image,"kind":"image"}));
        }
        // Only replace a running wallpaper after the new source and preview validate.
        self.players.remove(&output);
        let socket = self
            .runtime
            .join(format!("{}.sock", &digest(&output)[..16]));
        let log = self.runtime.join(format!("{}.log", &digest(&output)[..16]));
        // The daemon holds the exclusive runtime lock and owns all sockets here.
        if socket.exists() {
            fs::remove_file(&socket)?;
        }
        let child = Command::new("gslapper")
            // Renderer visibility auto-pause can strand playback on this compositor.
            // Keep pause ownership explicit through the control socket instead.
            .args(["--no-save-state", "--fps-cap"])
            .arg(fps.to_string())
            .arg("--ipc-socket")
            .arg(&socket)
            .arg("--gst-options")
            .arg(format!("no-audio loop {}", scale.option()))
            .arg(&output)
            .arg(&path)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(File::create(&log)?)
            .spawn()?;
        let mut player = Player {
            child,
            socket,
            path: path.clone(),
            log,
        };
        let deadline = Instant::now() + Duration::from_secs(12);
        loop {
            if let Some(status) = player.child.try_wait()? {
                return Err(
                    format!("renderer exited ({status}): {}", read_excerpt(&player.log)).into(),
                );
            }
            if let Ok(status) = ipc(&player.socket, "query") {
                if status == format!("STATUS: playing video {}", path.display())
                    || status == format!("STATUS: paused video {}", path.display())
                {
                    break;
                }
            }
            if self.quit.load(Ordering::Relaxed) || Instant::now() >= deadline {
                return Err(format!(
                    "renderer readiness timed out: {}",
                    read_excerpt(&player.log)
                )
                .into());
            }
            thread::sleep(Duration::from_millis(40));
        }
        self.players.insert(output, player);
        Ok(json!({"ok":true,"path":path,"preview":image,"kind":"video"}))
    }
    fn handle(&mut self, request: Request) -> Result<Value> {
        match request {
            Request::Scan { root } => scan(&root),
            Request::Preview { path, thumbnail } => {
                let path = media_path(&path)?;
                Ok(json!({"ok":true,"preview":preview(&path,&self.cache,&self.quit,thumbnail)?}))
            }
            Request::Play {
                output,
                path,
                scale,
                fps,
            } => self.play(output, path, scale, fps),
            Request::Control { output, command } => {
                match command {
                    Control::Stop => {
                        self.players.remove(&output);
                    }
                    Control::Pause | Control::Resume => {
                        let player = self
                            .players
                            .get(&output)
                            .ok_or("no running wallpaper on this output")?;
                        let reply = ipc(
                            &player.socket,
                            if matches!(command, Control::Pause) {
                                "pause"
                            } else {
                                "resume"
                            },
                        )?;
                        if reply != "OK" {
                            return Err(format!("unexpected renderer response: {reply}").into());
                        }
                    }
                }
                Ok(json!({"ok":true}))
            }
            Request::Status {} => {
                let mut outputs = serde_json::Map::new();
                for (output, player) in &self.players {
                    let state =
                        ipc(&player.socket, "query").unwrap_or_else(|e| format!("ERROR: {e}"));
                    outputs.insert(output.clone(), json!({"path":player.path,"state":state}));
                }
                Ok(json!({"ok":true,"outputs":outputs}))
            }
            Request::Shutdown {} => {
                self.quit.store(true, Ordering::Relaxed);
                Ok(json!({"ok":true}))
            }
        }
    }
    fn reap(&mut self) {
        let dead: Vec<_> = self
            .players
            .iter_mut()
            .filter_map(|(output, player)| match player.child.try_wait() {
                Ok(None) => None,
                result => Some((
                    output.clone(),
                    format!(
                        "renderer stopped: {result:?}; {}",
                        read_excerpt(&player.log)
                    ),
                )),
            })
            .collect();
        for (output, message) in dead {
            self.players.remove(&output);
            emit(json!({"event":"stopped","output":output,"error":message}));
        }
    }
}
fn serve(data: &Path) -> Result<()> {
    let runtime = runtime_dir()?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(runtime.join("lock"))?;
    // Reload teardown and startup can overlap briefly. Never unlink a live daemon's socket.
    let deadline = Instant::now() + Duration::from_secs(2);
    while lock.try_lock_exclusive().is_err() {
        if Instant::now() >= deadline {
            return Err("another motionwall daemon is already running".into());
        }
        thread::sleep(Duration::from_millis(20));
    }
    fs::create_dir_all(data)?;
    let cache = data.join("previews");
    private_dir(&cache, fs::metadata(data)?.uid())?;
    let socket = runtime.join("control.sock");
    if let Ok(meta) = fs::symlink_metadata(&socket) {
        if !meta.file_type().is_socket() {
            return Err("control socket path is not a socket".into());
        }
        fs::remove_file(&socket)?;
    }
    let listener = UnixListener::bind(&socket)?;
    listener.set_nonblocking(true)?;
    let quit = Arc::new(AtomicBool::new(false));
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(signal, Arc::clone(&quit))?;
    }
    let mut server = Server {
        players: BTreeMap::new(),
        runtime,
        cache,
        quit: Arc::clone(&quit),
    };
    emit(json!({"event":"ready"}));
    while !quit.load(Ordering::Relaxed) {
        server.reap();
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_read_timeout(Some(Duration::from_secs(2)))?;
                stream.set_write_timeout(Some(Duration::from_secs(2)))?;
                let response = line(&mut stream)
                    .and_then(|s| Ok(serde_json::from_str::<Request>(&s)?))
                    .and_then(|r| server.handle(r))
                    .unwrap_or_else(error);
                let _ = writeln!(stream, "{response}");
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(20))
            }
            Err(e) => return Err(e.into()),
        }
    }
    drop(server); // Children die before releasing the daemon lock.
    fs::remove_file(socket)?;
    Ok(())
}
fn request(raw: &str) -> Result<Value> {
    let _: Request = serde_json::from_str(raw)?;
    let mut stream = UnixStream::connect(runtime_dir()?.join("control.sock"))?;
    stream.set_read_timeout(Some(Duration::from_secs(45)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    writeln!(stream, "{raw}")?;
    Ok(serde_json::from_str(&line(&mut stream)?)?)
}
fn main() {
    let args: Vec<_> = env::args().collect();
    let result = match args.get(1).map(String::as_str) {
        Some("serve") if args.len() == 3 => serve(Path::new(&args[2])).map(|()| None),
        Some("request") if args.len() == 3 => request(&args[2]).map(Some),
        _ => Err("usage: motionwall serve DATA_DIR | motionwall request JSON".into()),
    };
    match result {
        Ok(Some(value)) => {
            let ok = value["ok"].as_bool().unwrap_or(false);
            emit(value);
            if !ok {
                std::process::exit(1);
            }
        }
        Ok(None) => (),
        Err(e) => {
            emit(error(e));
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    fn temp(name: &str) -> PathBuf {
        let p = env::temp_dir().join(format!("motionwall-test-{name}-{}", std::process::id()));
        fs::create_dir_all(&p).unwrap();
        p
    }
    #[test]
    fn extensions_and_scaling() {
        assert_eq!(kind(Path::new("a.MP4")), Some("video"));
        assert_eq!(kind(Path::new("a.gif")), Some("video"));
        assert_eq!(kind(Path::new("a.txt")), None);
        assert_eq!(Scale::Fit.option(), "panscan=1.0");
    }
    #[test]
    fn scan_follows_symlinks_deduplicates_and_reports_loops() {
        let dir = temp("scan");
        fs::write(dir.join("video with ' quotes.MP4"), b"fake").unwrap();
        symlink(dir.join("video with ' quotes.MP4"), dir.join("alias.mp4")).unwrap();
        symlink(&dir, dir.join("loop")).unwrap();
        let result = scan(&dir).unwrap();
        assert_eq!(result["entries"].as_array().unwrap().len(), 1);
        assert!(!result["warnings"].as_array().unwrap().is_empty());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn cache_key_changes_with_source() {
        let dir = temp("cache");
        let path = dir.join("a.mp4");
        fs::write(&path, b"one").unwrap();
        let a = cache_key(&path).unwrap();
        fs::write(&path, b"another").unwrap();
        assert_ne!(a, cache_key(&path).unwrap());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn image_thumbnails_are_bounded_cached_and_do_not_replace_wallpaper_sources() {
        let dir = temp("thumbnail");
        let path = dir.join("source.png");
        assert!(
            Command::new("ffmpeg")
                .args([
                    "-nostdin",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=blue:s=1600x900",
                    "-frames:v",
                    "1"
                ])
                .arg(&path)
                .status()
                .unwrap()
                .success()
        );
        let quit = AtomicBool::new(false);
        assert_eq!(preview(&path, &dir, &quit, false).unwrap(), path);
        let thumb = preview(&path, &dir, &quit, true).unwrap();
        assert_ne!(thumb, path);
        assert!(jpeg_valid(&thumb));
        let dimensions = Command::new("ffprobe")
            .args([
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=width,height",
                "-of",
                "csv=p=0",
            ])
            .arg(&thumb)
            .output()
            .unwrap();
        assert!(dimensions.status.success());
        let values: Vec<u32> = String::from_utf8(dimensions.stdout)
            .unwrap()
            .trim()
            .split(',')
            .map(|n| n.parse().unwrap())
            .collect();
        assert!(values[0] <= 420 && values[1] <= 230);
        let modified = fs::metadata(&thumb).unwrap().modified().unwrap();
        assert_eq!(preview(&path, &dir, &quit, true).unwrap(), thumb);
        assert_eq!(fs::metadata(&thumb).unwrap().modified().unwrap(), modified);
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn rejects_ipc_injection_and_unknown_fields() {
        let dir = temp("paths");
        let path = dir.join("evil\nstop.mp4");
        fs::write(&path, b"fake").unwrap();
        assert!(media_path(&path).is_err());
        assert!(
            serde_json::from_str::<Request>(
                r#"{"action":"control","output":"DP-1","command":"change"}"#
            )
            .is_err()
        );
        assert!(serde_json::from_str::<Request>(r#"{"action":"status","extra":1}"#).is_err());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn unix_ipc_keeps_spaced_paths_intact() {
        let dir = temp("ipc");
        let path = dir.join("test.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let worker = thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            assert_eq!(line(&mut s).unwrap(), "query");
            writeln!(s, "STATUS: playing video /some/path with spaces.mp4").unwrap();
        });
        assert_eq!(
            ipc(&path, "query").unwrap(),
            "STATUS: playing video /some/path with spaces.mp4"
        );
        worker.join().unwrap();
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn incomplete_ipc_and_invalid_play_options_fail() {
        let (mut writer, mut reader) = UnixStream::pair().unwrap();
        writer.write_all(b"partial response").unwrap();
        writer.shutdown(std::net::Shutdown::Write).unwrap();
        assert!(line(&mut reader).is_err());
        let mut server = Server {
            players: BTreeMap::new(),
            runtime: PathBuf::new(),
            cache: PathBuf::new(),
            quit: Arc::new(AtomicBool::new(false)),
        };
        assert!(
            server
                .play("DP-1".into(), PathBuf::new(), Scale::Fill, 0)
                .is_err()
        );
        assert!(
            server
                .play("DP-1; stop".into(), PathBuf::new(), Scale::Fill, 30)
                .is_err()
        );
    }
    #[test]
    fn dropping_player_reaps_its_child_and_socket() {
        let dir = temp("player");
        let socket = dir.join("owned.sock");
        let _listener = UnixListener::bind(&socket).unwrap();
        let child = Command::new("sleep").arg("30").spawn().unwrap();
        let proc = PathBuf::from(format!("/proc/{}", child.id()));
        assert!(proc.exists());
        drop(Player {
            child,
            socket: socket.clone(),
            path: PathBuf::new(),
            log: PathBuf::new(),
        });
        assert!(!proc.exists());
        assert!(!socket.exists());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn private_directory_refuses_symlinks() {
        let dir = temp("private");
        let alias = dir.join("alias");
        symlink(&dir, &alias).unwrap();
        assert!(private_dir(&alias, fs::metadata(&dir).unwrap().uid()).is_err());
        fs::remove_dir_all(dir).unwrap();
    }
}
