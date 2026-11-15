//! Quickshell lifecycle owner. Password values stay in the separate helper.
use serde::Deserialize;
use serde_json::Value;
use std::env;
use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Component, Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::thread;
use std::time::Duration;

type Result<T> = std::result::Result<T, String>;
const PAUSE: Duration = Duration::from_millis(50);
static INTERRUPTED: AtomicI32 = AtomicI32::new(0);

#[derive(Clone, Copy, Debug, PartialEq)]
enum Mode {
    Toggle,
    Hidden,
    Stop,
    Foreground,
}

#[derive(Debug)]
struct Options {
    config: PathBuf,
    mode: Mode,
    passwords: bool,
    ipc: Option<Vec<OsString>>,
}

impl Options {
    fn parse(args: impl IntoIterator<Item = OsString>, config: PathBuf) -> Result<Self> {
        let mut options = Self {
            config,
            mode: Mode::Toggle,
            passwords: false,
            ipc: None,
        };
        let mut args = args.into_iter();
        while let Some(arg) = args.next() {
            match arg.to_str() {
                Some("--passwords") => options.passwords = true,
                Some("--foreground") => options.mode = Mode::Foreground,
                Some("--hidden") => options.mode = Mode::Hidden,
                Some("--stop") => options.mode = Mode::Stop,
                Some("--path") => {
                    options.config = fs::canonicalize(args.next().ok_or("--path requires a directory")?)
                        .map_err(|_| "configuration directory not found")?;
                    if !options.config.join("shell.qml").is_file() {
                        return Err("shell.qml not found".into());
                    }
                    options.mode = Mode::Foreground;
                }
                Some("ipc") => {
                    options.ipc = Some(args.collect());
                    break;
                }
                _ => return Err("usage: app-launcher [--passwords] [--foreground | --hidden | --stop | --path PATH | ipc ARGS...]".into()),
            }
        }
        Ok(options)
    }
}

#[derive(Debug, Deserialize)]
struct Instance {
    config_path: PathBuf,
    id: String,
    shell_id: String,
    pid: u32,
}

impl Instance {
    fn matches(&self, config: &Path) -> bool {
        self.shell_id == "app-launcher"
            || self.config_path == config.join("shell.qml")
            || self.config_path.ends_with("appLauncher/shell.qml")
    }
}

fn qs() -> Command {
    Command::new("qs")
}

fn instances(config: &Path, dead: bool) -> Result<Vec<Instance>> {
    let mut command = qs();
    command.args(["list", "--all", "--json"]);
    if dead {
        command.arg("--show-dead");
    }
    let output = command
        .stderr(Stdio::null())
        .output()
        .map_err(|_| "could not run qs list")?;
    if !output.status.success() {
        return Err("qs list failed".into());
    }
    let rows = parse_instances(&output.stdout)?;
    Ok(rows.into_iter().filter(|row| row.matches(config)).collect())
}

fn parse_instances(output: &[u8]) -> Result<Vec<Instance>> {
    if output.trim_ascii() == b"No running instances." {
        return Ok(Vec::new());
    }
    let rows: Vec<Instance> =
        serde_json::from_slice(output).map_err(|_| "invalid qs instance registry")?;
    if rows
        .iter()
        .any(|row| row.pid == 0 || row.pid > i32::MAX as u32)
    {
        return Err("invalid qs instance PID".into());
    }
    Ok(rows)
}

fn single_current<'a>(rows: &'a [Instance], config: &Path) -> Option<&'a Instance> {
    match rows {
        [row] if row.config_path == config.join("shell.qml") => Some(row),
        _ => None,
    }
}

// Only individual registry names may be joined beneath the runtime directories.
fn safe_component(value: &str) -> bool {
    let mut parts = Path::new(value).components();
    matches!(parts.next(), Some(Component::Normal(_))) && parts.next().is_none()
}

fn remove(path: &Path, directory: bool) -> Result<()> {
    let result = if directory {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    };
    match result {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err("could not clean stale qs registry".into()),
    }
}

fn cleanup(config: &Path, runtime: &Path) -> Result<()> {
    for _ in 0..40 {
        let rows = instances(config, false)?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let _ = qs()
                .args(["kill", "--pid", &row.pid.to_string()])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
        thread::sleep(PAUSE);
    }
    if !instances(config, false)?.is_empty() {
        return Err("failed to stop every existing instance".into());
    }
    let registry = runtime.join("quickshell");
    for row in instances(config, true)? {
        if !safe_component(&row.id) || (!row.shell_id.is_empty() && !safe_component(&row.shell_id))
        {
            return Err("invalid qs registry path".into());
        }
        remove(&registry.join("by-id").join(&row.id), true)?;
        if !row.shell_id.is_empty() {
            let shell = registry.join("by-shell").join(&row.shell_id);
            remove(&shell.join(&row.id), false)?;
            let _ = fs::remove_dir(shell); // A nonempty directory belongs to other instances.
        }
    }
    for directory in ["by-pid", "by-path"] {
        let entries = match fs::read_dir(registry.join(directory)) {
            Ok(entries) => entries,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(_) => return Err("could not read qs registry".into()),
        };
        for entry in entries {
            let path = entry
                .map_err(|_| "could not read qs registry entry")?
                .path();
            if path.is_symlink() && !path.exists() {
                remove(&path, false)?;
            }
        }
    }
    Ok(())
}

fn context() -> Result<String> {
    let helper = env::var_os("APP_LAUNCHER_PASSWORD_HELPER")
        .unwrap_or_else(|| "app-launcher-passwords".into());
    let output = Command::new(helper)
        .arg("context")
        .stderr(Stdio::null())
        .output()
        .map_err(
            |_| "password helper unavailable; build/install it or set APP_LAUNCHER_PASSWORD_HELPER",
        )?;
    if !output.status.success() {
        return Err("password context unavailable".into());
    }
    validate_context(&output.stdout)
}

fn validate_context(output: &[u8]) -> Result<String> {
    let value: Value = serde_json::from_slice(output).map_err(|_| "invalid password context")?;
    if !value.is_object() || value.get("address").is_none() || value.get("host").is_none() {
        return Err("invalid password context".into());
    }
    // Preserve the helper's metadata schema; never fetch list/action values here.
    Ok(value.to_string())
}

fn route(pid: u32, context: Option<&str>) -> bool {
    let mut command = qs();
    command.args(["ipc", "--pid", &pid.to_string(), "call", "launcher"]);
    match context {
        Some(value) => {
            command.args(["passwordMode", value]);
        }
        None => {
            command.arg("toggle");
        }
    }
    command
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
}

fn start_command(options: &Options) -> Command {
    let mut command = qs();
    command.arg("-p").arg(&options.config).arg("-n");
    if options.passwords || options.mode == Mode::Hidden {
        command.env("APP_LAUNCHER_HIDDEN", "1");
    }
    if options.mode != Mode::Foreground {
        command.arg("-d");
    }
    command
}

extern "C" fn interrupted(signal: libc::c_int) {
    INTERRUPTED.store(signal, Ordering::Relaxed);
}

fn install_signals() -> Result<()> {
    // SAFETY: zero is a valid initial sigaction, and the handler only stores an
    // atomic integer. No allocation, I/O or non-signal-safe work runs in it.
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = interrupted as *const () as usize;
        libc::sigemptyset(&mut action.sa_mask);
        for signal in [libc::SIGTERM, libc::SIGINT] {
            if libc::sigaction(signal, &action, std::ptr::null_mut()) != 0 {
                return Err("could not install foreground signal handler".into());
            }
        }
    }
    Ok(())
}

struct OwnedShell(Child);
impl Drop for OwnedShell {
    fn drop(&mut self) {
        if !matches!(self.0.try_wait(), Ok(None)) {
            return;
        }
        // SAFETY: this is an unreaped child owned by this process, so its PID
        // cannot be reused between try_wait and kill.
        unsafe {
            libc::kill(self.0.id() as i32, libc::SIGTERM);
        }
        for _ in 0..20 {
            if !matches!(self.0.try_wait(), Ok(None)) {
                return;
            }
            thread::sleep(PAUSE);
        }
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn exit_code(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(1))
}

fn run(options: Options) -> Result<i32> {
    if let Some(args) = &options.ipc {
        let rows = instances(&options.config, false)?;
        let row = rows.first().ok_or("no running instance")?;
        return Err(format!(
            "could not execute qs ipc: {}",
            qs().args(["ipc", "--pid", &row.pid.to_string()])
                .args(args)
                .exec()
        ));
    }
    // std's Unix file descriptors are CLOEXEC: the qs child never inherits the
    // flock, while the parent holds it throughout cleanup/start/IPC readiness.
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            // SAFETY: geteuid has no preconditions and does not mutate state.
            PathBuf::from(format!("/run/user/{}", unsafe { libc::geteuid() }))
        });
    let lock: File = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(runtime.join("app-launcher.lock"))
        .map_err(|_| "could not open launcher lock")?;
    lock.lock().map_err(|_| "could not lock launcher")?;
    let context = if options.passwords {
        Some(context()?)
    } else {
        None
    };
    let rows = instances(&options.config, false)?;
    if let Some(row) = single_current(&rows, &options.config) {
        if options.mode == Mode::Toggle && route(row.pid, context.as_deref()) {
            return Ok(0);
        }
        if options.mode == Mode::Hidden && !options.passwords {
            return Ok(0);
        }
    }
    cleanup(&options.config, &runtime)?;
    if options.mode == Mode::Stop {
        return Ok(0);
    }
    let mut command = start_command(&options);
    if !options.passwords {
        if options.mode == Mode::Foreground {
            return Err(format!("could not execute qs: {}", command.exec()));
        }
        return command
            .status()
            .map(exit_code)
            .map_err(|_| "could not start qs".into());
    }
    let mut foreground = if options.mode == Mode::Foreground {
        install_signals()?;
        Some(OwnedShell(
            command.spawn().map_err(|_| "could not start qs")?,
        ))
    } else {
        if !command
            .status()
            .map_err(|_| "could not start qs")?
            .success()
        {
            return Err("qs start failed".into());
        }
        None
    };
    for _ in 0..100 {
        let signal = INTERRUPTED.load(Ordering::Relaxed);
        if signal != 0 {
            return Ok(128 + signal);
        }
        if let Some(child) = &mut foreground
            && child
                .0
                .try_wait()
                .map_err(|_| "could not check qs status")?
                .is_some()
        {
            return Err("qs exited before password IPC became ready".into());
        }
        let rows = instances(&options.config, false)?;
        if let Some(row) = single_current(&rows, &options.config)
            && route(row.pid, context.as_deref())
        {
            drop(lock);
            if let Some(child) = &mut foreground {
                loop {
                    let signal = INTERRUPTED.load(Ordering::Relaxed);
                    if signal != 0 {
                        return Ok(128 + signal);
                    }
                    if let Some(status) = child.0.try_wait().map_err(|_| "could not wait for qs")? {
                        return Ok(exit_code(status));
                    }
                    thread::sleep(PAUSE);
                }
            }
            return Ok(0);
        }
        thread::sleep(PAUSE);
    }
    if foreground.is_none() {
        cleanup(&options.config, &runtime)?;
    }
    Err("password mode IPC did not become ready".into())
}

fn main() {
    let config = env::var_os("QUICKSHELL_CONFIG_PATH")
        .map(PathBuf::from)
        .unwrap_or_default();
    let options = match Options::parse(env::args_os().skip(1), config) {
        Ok(options) => options,
        Err(error) => {
            eprintln!("app-launcher: {error}");
            std::process::exit(2);
        }
    };
    if options.config.as_os_str().is_empty() {
        eprintln!(
            "app-launcher: set QUICKSHELL_CONFIG_PATH or use the source-tree launch entrypoint"
        );
        std::process::exit(2);
    }
    match run(options) {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            eprintln!("app-launcher: {error}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn parse(args: &[&str]) -> Result<Options> {
        Options::parse(args.iter().map(OsString::from), "/fixture".into())
    }
    fn row(path: &str, shell: &str) -> Instance {
        Instance {
            config_path: path.into(),
            shell_id: shell.into(),
            id: "fixture".into(),
            pid: 123,
        }
    }
    #[test]
    fn cli_contract() {
        assert_eq!(parse(&[]).unwrap().mode, Mode::Toggle);
        let args = parse(&["--passwords", "--hidden", "--foreground"]).unwrap();
        assert!(args.passwords);
        assert_eq!(args.mode, Mode::Foreground);
        assert_eq!(
            parse(&["ipc", "call", "--anything"]).unwrap().ipc.unwrap(),
            ["call", "--anything"]
        );
        for args in [
            vec!["--path"],
            vec!["--wat"],
            vec!["--path", "/not/a/real/config"],
        ] {
            assert!(parse(&args).is_err());
        }
    }
    #[test]
    fn ownership_and_current_path() {
        let config = Path::new("/fixture");
        assert!(row("/different/shell.qml", "app-launcher").matches(config));
        assert!(row("/fixture/shell.qml", "legacy").matches(config));
        assert!(row("/old/appLauncher/shell.qml", "legacy").matches(config));
        assert!(!row("/other/shell.qml", "unrelated").matches(config));
        assert!(
            single_current(&[row("/old/appLauncher/shell.qml", "app-launcher")], config).is_none()
        );
        assert!(
            single_current(
                &[
                    row("/fixture/shell.qml", "app-launcher"),
                    row("/fixture/shell.qml", "app-launcher")
                ],
                config
            )
            .is_none()
        );
    }
    #[test]
    fn registry_and_context_validation() {
        assert!(
            parse_instances(b"No running instances.\n")
                .unwrap()
                .is_empty()
        );
        for bad in [
            b"".as_slice(),
            b"null",
            b"{}",
            b"not-json",
            br#"[{"pid":0,"id":"id","shell_id":"app-launcher","config_path":"/fixture"}]"#,
        ] {
            assert!(parse_instances(bad).is_err());
        }
        assert!(validate_context(br#"{"address":"0x123","host":"example.com"}"#).is_ok());
        for bad in [
            b"[]".as_slice(),
            b"{}",
            b"null",
            br#"{"host":"example.com"}"#,
        ] {
            assert!(validate_context(bad).is_err());
        }
        for bad in ["", ".", "..", "/tmp/id", "../id", "id/other"] {
            assert!(!safe_component(bad));
        }
        assert!(safe_component("fixture-id"));
    }
}
