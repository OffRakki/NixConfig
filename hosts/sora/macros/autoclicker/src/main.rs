use std::{
    env, io,
    os::unix::net::UnixDatagram,
    process::{Command, ExitCode},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};

// Native Linux input_event ABI used by the pinned ydotoold, one event per datagram.
fn event(kind: u16, code: u16, value: i32) -> Vec<u8> {
    let mut bytes = vec![0; std::mem::size_of::<libc::timeval>()];
    bytes.extend_from_slice(&kind.to_ne_bytes());
    bytes.extend_from_slice(&code.to_ne_bytes());
    bytes.extend_from_slice(&value.to_ne_bytes());
    bytes
}

struct Mouse(UnixDatagram);
impl Mouse {
    fn connect() -> io::Result<Self> {
        let socket = UnixDatagram::unbound()?;
        socket.set_write_timeout(Some(Duration::from_millis(100)))?;
        socket.connect(
            env::var_os("YDOTOOL_SOCKET").unwrap_or_else(|| "/run/ydotoold/socket".into()),
        )?;
        Ok(Self(socket))
    }
    fn button(&self, down: bool) -> io::Result<()> {
        for packet in [event(1, 0x110, i32::from(down)), event(0, 0, 0)] {
            if self.0.send(&packet)? != packet.len() {
                return Err(io::Error::new(
                    io::ErrorKind::WriteZero,
                    "short input datagram",
                ));
            }
        }
        Ok(())
    }
}
impl Drop for Mouse {
    fn drop(&mut self) {
        let _ = self.button(false);
    }
}

fn click_loop() -> io::Result<()> {
    let stop = Arc::new(AtomicBool::new(false));
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(signal, Arc::clone(&stop))?;
    }
    let mouse = Mouse::connect()?;
    // Match ydotool's default 25ms down/up delays plus the old script's 1ms pause.
    // Sleep relative to each event: no catch-up bursts after scheduler stalls.
    while !stop.load(Ordering::Relaxed) {
        mouse.button(true)?;
        thread::sleep(Duration::from_millis(25));
        mouse.button(false)?;
        thread::sleep(Duration::from_millis(26));
    }
    Ok(())
}

fn toggle() -> io::Result<()> {
    let state = Command::new("systemctl")
        .args([
            "--user",
            "show",
            "--property=ActiveState",
            "--value",
            "autoclicker.service",
        ])
        .output()?;
    if !state.status.success() {
        return Err(io::Error::other("could not read autoclicker service state"));
    }
    let action = match state.stdout.trim_ascii() {
        b"active" | b"activating" | b"reloading" | b"deactivating" => "stop",
        b"inactive" | b"failed" => "start",
        _ => return Err(io::Error::other("unexpected autoclicker service state")),
    };
    if !Command::new("systemctl")
        .args(["--user", action, "autoclicker.service"])
        .status()?
        .success()
    {
        return Err(io::Error::other("could not toggle autoclicker service"));
    }
    // Notification failure must never prevent stopping the click loop.
    let _ = Command::new("notify-send")
        .args([
            "-t",
            "1000",
            "Autoclicker",
            if action == "start" {
                "Enabled"
            } else {
                "Disabled"
            },
        ])
        .status();
    Ok(())
}

fn run() -> io::Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    match args.as_slice() {
        [arg] if arg == "run" => click_loop(),
        [arg] if arg == "release" => Mouse::connect()?.button(false),
        [arg] if arg == "toggle" => toggle(),
        [arg] if arg == "--help" || arg == "-h" => {
            println!("Usage: autoclicker run|toggle|release");
            Ok(())
        }
        _ => Err(io::Error::other(
            "expected run, toggle, or release; see --help",
        )),
    }
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("autoclicker: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_input_layout() {
        let bytes = event(1, 0x110, 1);
        assert_eq!(bytes.len(), std::mem::size_of::<libc::input_event>());
        let offset = std::mem::size_of::<libc::timeval>();
        assert!(bytes[..offset].iter().all(|byte| *byte == 0));
        assert_eq!(&bytes[offset..offset + 2], &1_u16.to_ne_bytes());
        assert_eq!(&bytes[offset + 2..offset + 4], &0x110_u16.to_ne_bytes());
        assert_eq!(&bytes[offset + 4..], &1_i32.to_ne_bytes());
    }
}
