//! Metadata-only UI boundary. Child output and errors are never forwarded.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::os::unix::net::UnixDatagram;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

type Result<T> = std::result::Result<T, &'static str>;
const MAX: usize = 8 * 1024 * 1024;
const FIELD_MAX: usize = 64 * 1024;
const DEADLINE: Duration = Duration::from_secs(90);
static CANCELLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
extern "C" fn cancel(_: libc::c_int) {
    CANCELLED.store(true, std::sync::atomic::Ordering::Relaxed);
}

// Nonblocking pipes bound both time and memory, including blocked stdin writers.
fn nonblock(fd: i32) -> Result<()> {
    // SAFETY: fcntl operates on an owned, live pipe descriptor.
    if unsafe { libc::fcntl(fd, libc::F_SETFL, libc::O_NONBLOCK) } < 0 {
        return Err("process_failed");
    }
    Ok(())
}
fn run(
    program: &str,
    args: &[&str],
    input: &[u8],
    timeout: Duration,
    limit: usize,
) -> Result<Vec<u8>> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::piped())
        // wl-copy's clipboard owner inherits stdout after its parent exits.
        // Do not wait for EOF from that intentionally long-lived owner.
        .stdout(if program == "wl-copy" {
            Stdio::null()
        } else {
            Stdio::piped()
        })
        .stderr(Stdio::null())
        .process_group(0);
    // SAFETY: only async-signal-safe syscalls run between fork and exec. Kill direct
    // children if the UI terminates this helper; no secret sink survives cancellation.
    unsafe {
        command.pre_exec(|| {
            let parent = libc::getppid();
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL) < 0
                || libc::getppid() != parent
                || parent == 1
            {
                return Err(std::io::Error::other("parent unavailable"));
            }
            Ok(())
        });
    }
    let mut child = command.spawn().map_err(|_| "tool_unavailable")?;
    let result = (|| {
        let stdin_pipe = child.stdin.take().ok_or("process_failed")?;
        let mut stdout = child.stdout.take();
        nonblock(stdin_pipe.as_raw_fd())?;
        if let Some(pipe) = &stdout {
            nonblock(pipe.as_raw_fd())?;
        }
        let mut stdin = Some(stdin_pipe);
        let mut offset = 0;
        let start = Instant::now();
        let mut output = Vec::new();
        let mut eof = stdout.is_none();
        loop {
            if CANCELLED.load(std::sync::atomic::Ordering::Relaxed) {
                return Err("cancelled");
            }
            if start.elapsed() > timeout {
                return Err("timed_out");
            }
            if offset == input.len() {
                stdin = None;
            }
            // Dropping the actual owned handle is necessary to deliver EOF.
            if let Some(writer) = stdin.as_mut() {
                match writer.write(&input[offset..]) {
                    Ok(0) => return Err("process_failed"),
                    Ok(n) => offset += n,
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                    Err(_) => return Err("process_failed"),
                }
            }
            let mut buffer = [0; 8192];
            while let Some(stdout) = stdout.as_mut() {
                match stdout.read(&mut buffer) {
                    Ok(0) => {
                        eof = true;
                        break;
                    }
                    Ok(n) => {
                        if output.len() + n > limit {
                            return Err("output_too_large");
                        }
                        output.extend_from_slice(&buffer[..n]);
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(_) => return Err("process_failed"),
                }
            }
            if let Some(status) = child.try_wait().map_err(|_| "process_failed")? {
                if !status.success() {
                    return Err("command_failed");
                }
                if eof {
                    return Ok(output);
                }
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    })();
    if result.is_err() {
        // SAFETY: this child owns the process group created above.
        unsafe {
            libc::kill(-(child.id() as i32), libc::SIGKILL);
        }
        let _ = child.wait();
    }
    result
}
fn command(program: &str, args: &[&str]) -> Result<Vec<u8>> {
    run(program, args, &[], DEADLINE, MAX)
}
fn parse(bytes: &[u8]) -> Result<Value> {
    serde_json::from_slice(bytes).map_err(|_| "invalid_schema")
}
fn uuid(id: &str) -> bool {
    id.len() == 36
        && id.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
}
fn text(value: &Value, key: &str) -> Result<String> {
    match &value[key] {
        Value::Null => Ok(String::new()),
        Value::String(s) if s.len() <= FIELD_MAX => Ok(s.clone()),
        _ => Err("invalid_schema"),
    }
}
#[derive(Serialize)]
struct Entry {
    id: String,
    name: String,
    username: String,
    folder: String,
    entry_type: &'static str,
}
fn entries(bytes: &[u8]) -> Result<Vec<Entry>> {
    let raw = parse(bytes)?;
    let rows = raw.as_array().ok_or("invalid_schema")?;
    if rows.len() > 10000 {
        return Err("output_too_large");
    }
    let mut output = Vec::new();
    let mut ids = std::collections::HashSet::new();
    for row in rows {
        if row["type"] != "Login" {
            continue;
        }
        let id = text(row, "id")?;
        if !uuid(&id) || !ids.insert(id.clone()) {
            return Err("invalid_schema");
        }
        output.push(Entry {
            id,
            name: text(row, "name")?,
            username: text(row, "user")?,
            folder: text(row, "folder")?,
            entry_type: "login",
        });
    }
    Ok(output)
}
fn host(uri: &str) -> Option<String> {
    let uri = url::Url::parse(uri).ok()?;
    if !["http", "https"].contains(&uri.scheme()) {
        return None;
    }
    let host = uri.host_str()?.to_lowercase();
    Some(host.strip_prefix("www.").unwrap_or(&host).to_owned())
}
fn stored_uri(login: &Value, hint: &str) -> Result<String> {
    let empty = Vec::new();
    let uris = if login["uris"].is_null() {
        &empty
    } else {
        login["uris"].as_array().ok_or("invalid_schema")?
    };
    let valid: Vec<_> = uris
        .iter()
        .filter_map(|v| {
            let uri = v.as_str().or_else(|| v["uri"].as_str())?;
            (uri.len() <= FIELD_MAX && host(uri).is_some()).then_some(uri)
        })
        .collect();
    valid
        .iter()
        .find(|uri| host(uri).as_deref() == Some(hint))
        .or_else(|| valid.first())
        .map(|s| (*s).to_owned())
        .ok_or("missing_url")
}
#[derive(Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
struct Context {
    address: String,
    pid: u64,
    class: String,
    host: String,
}
fn window() -> Result<Context> {
    let value = parse(&run(
        "hyprctl",
        &["-j", "activewindow"],
        &[],
        Duration::from_secs(2),
        65536,
    )?)?;
    let address = text(&value, "address")?;
    let class = text(&value, "class")?;
    let pid = value["pid"].as_u64().ok_or("target_unavailable")?;
    focus_request(&address)?;
    if pid == 0 {
        return Err("target_unavailable");
    }
    Ok(Context {
        address,
        pid,
        class,
        host: String::new(),
    })
}
fn focus_request(address: &str) -> Result<String> {
    // A validated numeric address is the only interpolated Lua value.
    let hex = address.strip_prefix("0x").ok_or("target_unavailable")?;
    if hex.is_empty() || address.len() > 32 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("target_unavailable");
    }
    Ok(format!("hl.dsp.focus({{window=\"address:{address}\"}})"))
}
fn verify_window(current: &Context, target: &Context) -> Result<()> {
    if current.address != target.address
        || current.pid != target.pid
        || current.class != target.class
    {
        return Err("focus_changed");
    }
    Ok(())
}
fn same_window(target: &Context) -> Result<()> {
    verify_window(&window()?, target)
}
fn verify_target(clients: &Value, target: &Context) -> Result<()> {
    if !clients.as_array().ok_or("invalid_schema")?.iter().any(|c| {
        c["address"] == target.address && c["pid"] == target.pid && c["class"] == target.class
    }) {
        return Err("target_unavailable");
    }
    Ok(())
}
struct RuntimeDirectory(PathBuf);
impl Drop for RuntimeDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_file(self.0.join("host"));
        let _ = fs::remove_dir(&self.0);
    }
}
fn qute_host() -> Result<String> {
    let root = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").ok_or("context_unavailable")?);
    let metadata = fs::metadata(&root).map_err(|_| "context_unavailable")?;
    use std::os::unix::fs::MetadataExt;
    // SAFETY: geteuid has no preconditions.
    if metadata.uid() != unsafe { libc::geteuid() } || metadata.mode() & 0o077 != 0 {
        return Err("context_unavailable");
    }
    let mut random = [0u8; 16];
    File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut random))
        .map_err(|_| "context_unavailable")?;
    let token: String = random.iter().map(|b| format!("{b:02x}")).collect();
    let directory = RuntimeDirectory(root.join(format!("app-launcher-{token}")));
    fs::DirBuilder::new()
        .mode(0o700)
        .create(&directory.0)
        .map_err(|_| "context_unavailable")?;
    let path = directory.0.join("host");
    let socket = UnixDatagram::bind(&path).map_err(|_| "context_unavailable")?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
        .map_err(|_| "context_unavailable")?;
    socket
        .set_read_timeout(Some(Duration::from_secs(2)))
        .map_err(|_| "context_unavailable")?;
    let executable = std::env::current_exe().map_err(|_| "context_unavailable")?;
    let exe = executable.to_str().ok_or("context_unavailable")?;
    let path = path.to_str().ok_or("context_unavailable")?;
    // Qutebrowser parses this command, not a shell. Reject ambiguous command paths.
    if [exe, path].iter().any(|s| {
        !s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"/-_.".contains(&b))
    }) {
        return Err("context_unavailable");
    }
    let request = format!(":spawn --userscript {exe} qute-reply {path}");
    run(
        "qutebrowser",
        &["--nowindow", &request],
        &[],
        Duration::from_secs(2),
        1024,
    )?;
    let mut bytes = [0u8; 256];
    let n = socket.recv(&mut bytes).map_err(|_| "context_unavailable")?;
    let hint = std::str::from_utf8(&bytes[..n]).map_err(|_| "context_unavailable")?;
    if hint.is_empty() || host(&format!("https://{hint}")).as_deref() != Some(hint) {
        return Err("context_unavailable");
    }
    Ok(hint.to_owned())
}
fn context() -> Context {
    let mut context = window().unwrap_or_default();
    let class = context.class.to_lowercase();
    context.host = match class.as_str() {
        "vesktop"
        | "discord"
        | "discordcanary"
        | "discordptb"
        | "goofcord"
        | "dev.vencord.vesktop"
        | "com.discordapp.discord" => "discord.com".to_owned(),
        "steam" | "steamwebhelper" | "com.valvesoftware.steam" => "steampowered.com".to_owned(),
        "qutebrowser" | "org.qutebrowser.qutebrowser" => qute_host().unwrap_or_default(),
        _ => String::new(),
    };
    if same_window(&context).is_err() {
        return Context::default();
    }
    context
}
fn copy(value: &str, sensitive: bool) -> Result<()> {
    if value.is_empty() {
        return Err("missing_field");
    }
    let args: &[&str] = if sensitive {
        &["--sensitive", "--type", "text/secret"]
    } else {
        &["--type", "text/plain"]
    };
    run(
        "wl-copy",
        args,
        value.as_bytes(),
        Duration::from_secs(3),
        1024,
    )
    .map(|_| ())
}
// Read key *state* only, never input event streams. Existing input-group access
// is required. Any inaccessible device or query error fails closed.
fn released() -> Result<bool> {
    let devices = fs::read_dir("/dev/input").map_err(|_| "input_unavailable")?;
    let mut count = 0;
    for item in devices {
        let item = item.map_err(|_| "input_unavailable")?;
        if !item.file_name().to_string_lossy().starts_with("event") {
            continue;
        }
        let file = File::open(item.path()).map_err(|_| "input_unavailable")?;
        let mut bits = [0u8; 96];
        // EVIOCGKEY(96), Linux asm-generic ioctl ABI (supported package platforms).
        // SAFETY: writable buffer matches the size encoded in the ioctl request.
        if unsafe {
            libc::ioctl(
                file.as_raw_fd(),
                0x80604518 as libc::c_ulong,
                bits.as_mut_ptr(),
            )
        } < 0
        {
            return Err("input_unavailable");
        }
        count += 1;
        if !keys_released(&bits) {
            return Ok(false);
        }
    }
    if count == 0 {
        return Err("input_unavailable");
    }
    Ok(true)
}
fn keys_released(bits: &[u8; 96]) -> bool {
    ![28, 96, 29, 97, 42, 54, 56, 100, 125, 126]
        .iter()
        .any(|key| bits[key / 8] & (1 << (key % 8)) != 0)
}
fn plain_us() -> Result<()> {
    let devices = parse(&run(
        "hyprctl",
        &["-j", "devices"],
        &[],
        Duration::from_secs(2),
        65536,
    )?)?;
    verify_keymap(&devices)
}
fn verify_keymap(devices: &Value) -> Result<()> {
    let keyboards = devices["keyboards"].as_array().ok_or("input_unavailable")?;
    // ydotool emits US keycodes through its own device, not the physical keyboard.
    // Keep physical layouts untouched; only the emitting device must use plain US.
    let mut virtual_keyboards = keyboards
        .iter()
        .filter(|k| k["name"] == "ydotoold-virtual-device");
    let keyboard = virtual_keyboards.next().ok_or("unsupported_keymap")?;
    if virtual_keyboards.next().is_some()
        || keyboard["active_keymap"] != "English (US)"
        || keyboards
            .iter()
            .any(|k| k["capsLock"].as_bool() != Some(false))
    {
        return Err("unsupported_keymap");
    }
    Ok(())
}
fn wait_released(target: &Context) -> Result<()> {
    let start = Instant::now();
    loop {
        same_window(target)?;
        if released()? {
            return Ok(());
        }
        if start.elapsed() > Duration::from_secs(2) {
            return Err("keys_held");
        }
        std::thread::sleep(Duration::from_millis(30));
    }
}
fn typeable(s: &str) -> bool {
    !s.is_empty() && s.len() <= 1024 && s.bytes().all(|b| (32..=126).contains(&b))
}
fn type_text(s: &str) -> Result<()> {
    run(
        "ydotool",
        &[
            "type",
            "--file=-",
            "--escape=0",
            "--key-delay=5",
            "--key-hold=5",
        ],
        s.as_bytes(),
        Duration::from_secs(30),
        1024,
    )
    .map(|_| ())
}
// All stages use the same guards. After any emitted input, errors are partial.
fn fill_steps(
    username: &str,
    password: &str,
    mut guard: impl FnMut() -> Result<()>,
    mut type_value: impl FnMut(&str) -> Result<()>,
    mut tab: impl FnMut() -> Result<()>,
) -> Result<()> {
    guard()?;
    type_value(username).map_err(|_| "partial_fill")?;
    guard().map_err(|_| "partial_fill")?;
    tab().map_err(|_| "partial_fill")?;
    guard().map_err(|_| "partial_fill")?;
    type_value(password).map_err(|_| "partial_fill")
}
fn otp(id: &str) -> Result<String> {
    let bytes = command("rbw", &["code", id])?;
    let raw = std::str::from_utf8(&bytes).map_err(|_| "invalid_schema")?;
    let s = raw.strip_suffix('\n').unwrap_or(raw);
    if !(6..=10).contains(&s.len()) || !s.bytes().all(|b| b.is_ascii_digit()) {
        return Err("invalid_otp");
    }
    Ok(s.to_owned())
}
fn act(id: &str, action: &str, target: &Context) -> Result<Value> {
    if !uuid(id) || !["password", "username", "otp", "url", "fill"].contains(&action) {
        return Err("invalid_request");
    }
    let raw = parse(&command("rbw", &["get", "--raw", id])?)?;
    if raw["id"] != id {
        return Err("entry_changed");
    }
    // rbw 1.15 raw get uses an untagged data object, unlike its on-disk DB.
    let data = raw["data"].as_object().ok_or("not_login")?;
    if !["username", "password", "totp", "uris"]
        .iter()
        .all(|key| data.contains_key(*key))
    {
        return Err("not_login");
    }
    let login = Value::Object(data.clone());
    let username = text(&login, "username")?;
    let password = text(&login, "password")?;
    let has_otp = !text(&login, "totp")?.is_empty();
    match action {
        "password" => copy(&password, true)?,
        "username" => copy(&username, false)?,
        "otp" => {
            if !has_otp {
                return Err("missing_otp");
            }
            copy(&otp(id)?, true)?;
        }
        "url" => copy(&stored_uri(&login, &target.host)?, false)?,
        "fill" => {
            if !typeable(&username) || !typeable(&password) {
                return Err("unsupported_text");
            }
            if target.address.is_empty() || target.pid == 0 {
                return Err("target_unavailable");
            }
            // Restore only an extant identity; address reuse alone is not sufficient.
            let clients = parse(&run(
                "hyprctl",
                &["-j", "clients"],
                &[],
                Duration::from_secs(2),
                MAX,
            )?)?;
            verify_target(&clients, target)?;
            run(
                "hyprctl",
                &["dispatch", &focus_request(&target.address)?],
                &[],
                Duration::from_secs(2),
                1024,
            )
            .map_err(|_| "focus_failed")?;
            std::thread::sleep(Duration::from_millis(150));
            fill_steps(
                &username,
                &password,
                || {
                    plain_us()?;
                    wait_released(target)
                },
                type_text,
                || {
                    run(
                        "ydotool",
                        &["key", "15:1", "15:0"],
                        &[],
                        Duration::from_secs(2),
                        1024,
                    )
                    .map(|_| ())
                },
            )?;
            if has_otp && otp(id).and_then(|s| copy(&s, true)).is_err() {
                return Ok(json!({"status":"filled_otp_unavailable"}));
            }
            return Ok(json!({"status": if has_otp {"filled_otp_copied"} else {"filled"}}));
        }
        _ => return Err("invalid_request"),
    }
    Ok(json!({"status":"copied"}))
}
// Poll a direct descriptor rather than buffered stdin: partial requests cannot
// leave an action helper alive indefinitely. This transport never carries secrets.
fn request_line(fd: i32, timeout: Duration) -> Result<Vec<u8>> {
    let start = Instant::now();
    let mut bytes = Vec::new();
    loop {
        if CANCELLED.load(std::sync::atomic::Ordering::Relaxed) {
            return Err("cancelled");
        }
        if start.elapsed() >= timeout {
            return Err("timed_out");
        }
        let mut poll = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: initialized descriptor record, one element, bounded wait.
        let ready = unsafe { libc::poll(&mut poll, 1, 20) };
        if ready < 0 {
            if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err("invalid_request");
        }
        if ready == 0 {
            continue;
        }
        let mut chunk = [0u8; 1024];
        // SAFETY: valid writable buffer; this helper is the only stdin reader.
        let n = unsafe { libc::read(fd, chunk.as_mut_ptr().cast(), chunk.len()) };
        if n < 0 {
            return Err("invalid_request");
        }
        if n == 0 {
            return Ok(bytes);
        }
        let chunk = &chunk[..n as usize];
        let newline = chunk.iter().position(|b| *b == b'\n');
        bytes.extend_from_slice(&chunk[..newline.unwrap_or(chunk.len())]);
        if bytes.len() > 16384 {
            return Err("invalid_request");
        }
        if newline.is_some() {
            return Ok(bytes);
        }
    }
}
fn execute(args: &[String]) -> Result<Option<Value>> {
    match args.get(1).map(String::as_str) {
        Some("list") if args.len() == 2 => Ok(Some(
            json!({"status":"listed", "entries":entries(&command("rbw", &["list", "--raw"])?)?}),
        )),
        Some("context") if args.len() == 2 => Ok(Some(
            serde_json::to_value(context()).map_err(|_| "invalid_schema")?,
        )),
        Some("qute-reply") if args.len() == 3 => {
            let uri = std::env::var("QUTE_URL").map_err(|_| "context_unavailable")?;
            let hint = host(&uri).ok_or("context_unavailable")?;
            let socket = UnixDatagram::unbound().map_err(|_| "context_unavailable")?;
            socket
                .send_to(hint.as_bytes(), &args[2])
                .map_err(|_| "context_unavailable")?;
            Ok(None)
        }
        Some("act") if args.len() == 4 => {
            let bytes = request_line(libc::STDIN_FILENO, Duration::from_secs(2))?;
            let target: Context = serde_json::from_slice(&bytes).map_err(|_| "invalid_request")?;
            Ok(Some(act(&args[2], &args[3], &target)?))
        }
        _ => Err("invalid_request"),
    }
}
fn main() {
    // No core dumps of in-memory vault responses. Failure is fatal, not best effort.
    // SAFETY: valid prctl operation and initialized rlimit pointer.
    unsafe {
        libc::signal(libc::SIGTERM, cancel as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, cancel as *const () as libc::sighandler_t);
        let limit = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        if libc::prctl(libc::PR_SET_DUMPABLE, 0) < 0
            || libc::setrlimit(libc::RLIMIT_CORE, &limit) < 0
        {
            std::process::exit(1);
        }
    }
    let args: Vec<_> = std::env::args().collect();
    let result = execute(&args);
    // Userscript errors must not expose URLs in browser messages.
    if args.get(1).map(String::as_str) == Some("qute-reply") {
        return;
    }
    match result {
        Ok(Some(value)) => println!("{value}"),
        Ok(None) => {}
        Err(code) => {
            println!("{}", json!({"status":"error", "code":code}));
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn uuid_is_not_a_display_name() {
        assert!(uuid("aaaaaaaa-1111-2222-3333-444444444444"));
        assert!(!uuid("name/user"));
        assert!(!uuid("--password"));
    }
    #[test]
    fn lua_focus_uses_only_a_validated_numeric_address() {
        assert_eq!(
            focus_request("0x123aB").unwrap(),
            "hl.dsp.focus({window=\"address:0x123aB\"})"
        );
        for invalid in ["", "0x", "123", "0x12z", "0x1\"});bad()", "0x1\n"] {
            assert_eq!(focus_request(invalid), Err("target_unavailable"));
        }
        assert_eq!(
            focus_request(&format!("0x{}", "a".repeat(31))),
            Err("target_unavailable")
        );
    }
    #[test]
    fn metadata_is_allowlisted_and_duplicate_names_stay_distinct() {
        let fixture = br#"[{"id":"aaaaaaaa-1111-2222-3333-444444444444","name":"same/a","user":"a","type":"Login","password":"FAKE-SECRET"},{"id":"bbbbbbbb-1111-2222-3333-444444444444","name":"same/a","user":"a","type":"Login"},{"type":"Card","number":"FAKE-CARD"}]"#;
        let rows = entries(fixture).unwrap();
        assert_eq!(rows.len(), 2);
        assert_ne!(rows[0].id, rows[1].id);
        let encoded = serde_json::to_string(&rows).unwrap();
        assert!(!encoded.contains("FAKE"));
        assert!(!encoded.contains("password"));
    }
    #[test]
    fn uri_is_actual_stored_http_uri_with_exact_host_preference() {
        let login = json!({"uris":["javascript:bad", "https://first.example/path", {"uri":"https://www.discord.com/path?private=1"}]});
        assert_eq!(
            stored_uri(&login, "discord.com").unwrap(),
            "https://www.discord.com/path?private=1"
        );
        assert_eq!(
            stored_uri(&login, "unknown").unwrap(),
            "https://first.example/path"
        );
        assert_eq!(
            host("https://www.Example.com:444/a?q=x").unwrap(),
            "example.com"
        );
        assert_eq!(
            host("https://www2.example.com").unwrap(),
            "www2.example.com"
        );
        assert!(host("not a url").is_none());
    }
    #[test]
    fn unsafe_typing_values_fail_closed() {
        assert!(typeable(r#"-option \n \t \ !@#$%^&*() ' \""#));
        for s in ["", "a\nb", "a\tb", "x\0y", "café", "中", "🙂"] {
            assert!(!typeable(s));
        }
    }
    #[test]
    fn bad_schemas_fail_without_echoing_input() {
        assert!(entries(b"not json FAKE-SECRET").is_err());
        assert!(entries(br#"[{"type":"Login","id":"bad","name":"FAKE"}]"#).is_err());
    }
    #[test]
    fn fill_stages_guard_each_emission_and_never_submit() {
        use std::cell::RefCell;
        for failure in 0..=3 {
            let events = RefCell::new(Vec::new());
            let mut guards = 0;
            let result = fill_steps(
                "fixture-user",
                "fixture-password",
                || {
                    guards += 1;
                    events.borrow_mut().push("guard");
                    if guards == failure {
                        Err("focus_changed")
                    } else {
                        Ok(())
                    }
                },
                |value| {
                    events.borrow_mut().push(if value == "fixture-user" {
                        "username"
                    } else {
                        "password"
                    });
                    Ok(())
                },
                || {
                    events.borrow_mut().push("tab");
                    Ok(())
                },
            );
            match failure {
                0 => {
                    assert!(result.is_ok());
                    assert_eq!(
                        *events.borrow(),
                        ["guard", "username", "guard", "tab", "guard", "password"]
                    );
                }
                1 => {
                    assert_eq!(result, Err("focus_changed"));
                    assert_eq!(*events.borrow(), ["guard"]);
                }
                2 => {
                    assert_eq!(result, Err("partial_fill"));
                    assert_eq!(*events.borrow(), ["guard", "username", "guard"]);
                }
                3 => {
                    assert_eq!(result, Err("partial_fill"));
                    assert_eq!(
                        *events.borrow(),
                        ["guard", "username", "guard", "tab", "guard"]
                    );
                }
                _ => unreachable!(),
            }
        }
    }
    #[test]
    fn target_identity_and_input_guards_fail_closed() {
        let target = Context {
            address: "0x123".into(),
            pid: 123,
            class: "fixture".into(),
            host: String::new(),
        };
        assert!(verify_window(&target, &target).is_ok());
        for changed in [
            Context {
                address: "0x456".into(),
                ..target.clone()
            },
            Context {
                pid: 456,
                ..target.clone()
            },
            Context {
                class: "pinentry".into(),
                ..target.clone()
            },
        ] {
            assert_eq!(verify_window(&changed, &target), Err("focus_changed"));
            assert_eq!(
                verify_target(&json!([changed]), &target),
                Err("target_unavailable")
            );
        }
        assert_eq!(
            verify_target(&json!([]), &target),
            Err("target_unavailable")
        );
        assert!(verify_target(&json!([target.clone()]), &target).is_ok());
        let virtual_keyboard = json!({"name":"ydotoold-virtual-device","active_keymap":"English (US)","capsLock":false});
        let physical_keyboard =
            json!({"name":"physical","active_keymap":"English (US, alt. intl.)","capsLock":false});
        assert!(verify_keymap(&json!({"keyboards":[virtual_keyboard]})).is_ok());
        let valid = json!({"keyboards":[virtual_keyboard, physical_keyboard]});
        assert!(verify_keymap(&valid).is_ok());
        // Removing, duplicating or changing the emitting device must fail closed.
        for invalid in [
            json!({}),
            json!({"keyboards":[]}),
            json!({"keyboards":[physical_keyboard]}),
            json!({"keyboards":[virtual_keyboard, virtual_keyboard]}),
            json!({"keyboards":[{"name":"ydotoold-virtual-device","active_keymap":"English (US, intl.)","capsLock":false}]}),
            json!({"keyboards":[{"name":"ydotoold-virtual-device","active_keymap":"English (US)"}]}),
        ] {
            assert!(verify_keymap(&invalid).is_err());
        }
        for index in 0..2 {
            let mut locked = valid.clone();
            locked["keyboards"][index]["capsLock"] = json!(true);
            assert_eq!(verify_keymap(&locked), Err("unsupported_keymap"));
        }
        assert!(keys_released(&[0; 96]));
        for key in [28, 96, 29, 97, 42, 54, 56, 100, 125, 126] {
            let mut bits = [0; 96];
            bits[key / 8] |= 1 << (key % 8);
            assert!(!keys_released(&bits));
        }
    }
    #[test]
    fn partial_emission_errors_are_never_success() {
        for fail_tab in [false, true] {
            assert_eq!(
                fill_steps(
                    "user",
                    "password",
                    || Ok(()),
                    |_| if fail_tab {
                        Ok(())
                    } else {
                        Err("command_failed")
                    },
                    || Err("command_failed")
                ),
                Err("partial_fill")
            );
        }
    }
    #[test]
    fn request_transport_bounds_partial_lines_and_size() {
        use std::os::unix::net::UnixStream;
        let (read, mut write) = UnixStream::pair().unwrap();
        write.write_all(b"partial").unwrap();
        assert_eq!(
            request_line(read.as_raw_fd(), Duration::from_millis(30)),
            Err("timed_out")
        );
        write.write_all(b"complete\nignored").unwrap();
        assert_eq!(
            request_line(read.as_raw_fd(), Duration::from_secs(1)).unwrap(),
            b"complete"
        );
        let (read, mut write) = UnixStream::pair().unwrap();
        write.write_all(&vec![b'x'; 16385]).unwrap();
        assert_eq!(
            request_line(read.as_raw_fd(), Duration::from_secs(1)),
            Err("invalid_request")
        );
    }
    #[test]
    fn process_timeout_and_output_limit_are_bounded() {
        assert_eq!(
            run(
                "/bin/sh",
                &["-c", "sleep 2"],
                &[],
                Duration::from_millis(30),
                16
            ),
            Err("timed_out")
        );
        assert_eq!(
            run(
                "/bin/sh",
                &["-c", "printf '123456789'"],
                &[],
                Duration::from_secs(1),
                4
            ),
            Err("output_too_large")
        );
        assert_eq!(
            run(
                "/bin/sh",
                &["-c", "cat >/dev/null"],
                b"fixture\n\\n\n",
                Duration::from_secs(1),
                4
            ),
            Ok(Vec::new())
        );
    }
}
