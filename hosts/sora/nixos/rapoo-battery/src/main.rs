mod notify;

use std::{
    env, fs,
    fs::{File, OpenOptions},
    io::{self, Read, Write},
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt},
    path::{Path, PathBuf},
    process::ExitCode,
    thread,
    time::{Duration, Instant},
};

const DESCRIPTOR: &[u8] = &[
    0x05, 0x0c, 0x09, 0x01, 0xa1, 0x01, 0x05, 0x06, 0x09, 0x20, 0x15, 0x00, 0x25, 0x64, 0x75, 0x08,
    0x95, 0x01, 0x81, 0x02, 0xc0,
];

fn ready(file: &File, deadline: Instant) -> io::Result<bool> {
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Ok(false);
        }
        let mut fd = libc::pollfd {
            fd: file.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let timeout = remaining
            .as_millis()
            .saturating_add(1)
            .min(i32::MAX as u128) as i32;
        // SAFETY: fd points to one initialized pollfd, valid for this synchronous call.
        let result = unsafe { libc::poll(&mut fd, 1, timeout) };
        if result < 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(error);
        }
        if fd.revents & libc::POLLIN != 0 {
            return Ok(true);
        }
        if fd.revents & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL) != 0 {
            return Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "device disconnected",
            ));
        }
        if result == 0 {
            return Ok(false);
        }
    }
}

fn matches_device(uevent: &str, descriptor: &[u8]) -> bool {
    ["000024AE:0000185A", "000024AE:0000418A"]
        .iter()
        .any(|id| uevent.contains(id))
        && descriptor.windows(2).any(|p| p == [0x85, 0xba])
        && descriptor.windows(2).any(|p| p == [0x85, 0xbb])
}

fn find_device() -> io::Result<PathBuf> {
    for entry in fs::read_dir("/sys/class/hidraw")? {
        let entry = entry?;
        let device = entry.path().join("device");
        if let (Ok(uevent), Ok(descriptor)) = (
            fs::read_to_string(device.join("uevent")),
            fs::read(device.join("report_descriptor")),
        ) {
            if matches_device(&uevent, &descriptor) {
                return Ok(Path::new("/dev").join(entry.file_name()));
            }
        }
    }
    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "Rapoo VT9 Pro not found",
    ))
}

fn open(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(path)
}

// hidraw/UHID writes are single records: never split a short write into another event.
fn write_record(file: &mut File, bytes: &[u8]) -> io::Result<()> {
    loop {
        match file.write(bytes) {
            Ok(n) if n == bytes.len() => return Ok(()),
            Ok(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::WriteZero,
                    "short device write",
                ));
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error),
        }
    }
}

fn percentage(report: &[u8]) -> Option<u8> {
    match report {
        [0xbb, 0xb0, value, ..] if *value <= 100 => Some(*value),
        _ => None,
    }
}

fn query(device: Option<&Path>) -> io::Result<u8> {
    let path = device
        .map(Path::to_path_buf)
        .map(Ok)
        .unwrap_or_else(find_device)?;
    let mut file = open(&path)?;
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut report = [0; 64];
    loop {
        match file.read(&mut report) {
            Ok(0) => {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "hidraw closed",
                ));
            }
            Ok(_) if Instant::now() < deadline => (),
            Ok(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "hidraw drain timed out",
                ));
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }
    let mut request = [0; 32];
    request[..2].copy_from_slice(&[0xba, 0xb0]);
    write_record(&mut file, &request)?;
    while ready(&file, deadline)? {
        match file.read(&mut report) {
            Ok(0) => break,
            Ok(n) => {
                if let Some(value) = percentage(&report[..n]) {
                    return Ok(value);
                }
            }
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                ) => {}
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::TimedOut,
        "Rapoo VT9 Pro did not answer the battery query",
    ))
}

fn create_event() -> Vec<u8> {
    // linux/uhid.h: packed native-endian CREATE2, not a Rust struct's padded layout.
    let mut event = vec![0; 4 + 128 + 64 + 64];
    event[..4].copy_from_slice(&11_u32.to_ne_bytes());
    for (offset, value) in [
        (4, "Rapoo VT9 Pro"),
        (132, "rapoo-vt9pro"),
        (196, "24ae:185a"),
    ] {
        event[offset..offset + value.len()].copy_from_slice(value.as_bytes());
    }
    event.extend_from_slice(&(DESCRIPTOR.len() as u16).to_ne_bytes());
    event.extend_from_slice(&3_u16.to_ne_bytes());
    for value in [0x24ae_u32, 0x185a, 0x100, 0] {
        event.extend_from_slice(&value.to_ne_bytes());
    }
    event.extend_from_slice(DESCRIPTOR);
    event
}

fn report_reply(event: &[u8], value: u8) -> Option<Vec<u8>> {
    if event.len() < 8 || u32::from_ne_bytes(event[..4].try_into().ok()?) != 9 {
        return None;
    }
    let mut reply = 10_u32.to_ne_bytes().to_vec();
    reply.extend_from_slice(&event[4..8]);
    reply.extend_from_slice(&0_u16.to_ne_bytes());
    reply.extend_from_slice(&2_u16.to_ne_bytes());
    reply.extend_from_slice(&[0, value]);
    Some(reply)
}

fn input_event(value: u8) -> Vec<u8> {
    let mut event = 12_u32.to_ne_bytes().to_vec();
    event.extend_from_slice(&1_u16.to_ne_bytes());
    event.push(value);
    event
}

fn daemon(device: Option<&Path>, uhid: &Path) -> io::Result<()> {
    let mut value = loop {
        match query(device) {
            Ok(value) => break value,
            Err(error) => {
                eprintln!("rapoo-battery: {error}; retrying in 5s");
                thread::sleep(Duration::from_secs(5));
            }
        }
    };
    let mut file = open(uhid)?;
    write_record(&mut file, &create_event())?;
    // Closing /dev/uhid (including on SIGTERM) destroys the virtual device in the kernel.
    let mut next_query = Instant::now() + Duration::from_secs(1);
    loop {
        if ready(&file, next_query)? {
            let mut event = [0; 4380];
            match file.read(&mut event) {
                Ok(0) => return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "UHID closed")),
                Ok(n) => {
                    if let Some(reply) = report_reply(&event[..n], value) {
                        write_record(&mut file, &reply)?;
                    }
                }
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                    ) => {}
                Err(e) => return Err(e),
            }
        }
        if Instant::now() >= next_query {
            match query(device) {
                Ok(new_value) => {
                    value = new_value;
                    write_record(&mut file, &input_event(value))?;
                    next_query = Instant::now() + Duration::from_secs(60);
                }
                Err(error) => {
                    eprintln!("rapoo-battery: {error}; retrying in 5s");
                    next_query = Instant::now() + Duration::from_secs(5);
                }
            }
        }
    }
}

fn run() -> io::Result<()> {
    let mut device = None;
    let mut uhid = PathBuf::from("/dev/uhid");
    let mut is_daemon = false;
    let mut is_notify = false;
    let mut power_supply = None;
    let mut args = env::args_os().skip(1);
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("--daemon") => is_daemon = true,
            Some("--notify") => is_notify = true,
            Some("--power-supply") => {
                power_supply =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        io::Error::other("--power-supply needs a path")
                    })?))
            }
            Some("--device") => {
                device = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| io::Error::other("--device needs a path"))?,
                ))
            }
            Some("--uhid") => {
                uhid = PathBuf::from(
                    args.next()
                        .ok_or_else(|| io::Error::other("--uhid needs a path"))?,
                )
            }
            Some("--help" | "-h") => {
                println!(
                    "Usage: rapoo-battery [--daemon] [--device PATH] [--uhid PATH]\n       rapoo-battery --notify [--power-supply PATH]"
                );
                return Ok(());
            }
            _ => return Err(io::Error::other("unknown argument; see --help")),
        }
    }
    if is_notify {
        if is_daemon || device.is_some() || uhid != Path::new("/dev/uhid") {
            return Err(io::Error::other("--notify cannot query HID devices"));
        }
        notify::run(
            power_supply
                .as_deref()
                .unwrap_or(Path::new("/sys/class/power_supply")),
        )
    } else if power_supply.is_some() {
        Err(io::Error::other("--power-supply requires --notify"))
    } else if is_daemon {
        daemon(device.as_deref(), &uhid)
    } else {
        println!("{}%", query(device.as_deref())?);
        Ok(())
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("rapoo-battery: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn report_validation() {
        assert_eq!(percentage(&[0xbb, 0xb0, 0]), Some(0));
        assert_eq!(percentage(&[0xbb, 0xb0, 100, 0]), Some(100));
        for bytes in [&[0xbb, 0xb0][..], &[0xba, 0xb0, 40], &[0xbb, 0xb0, 101]] {
            assert_eq!(percentage(bytes), None);
        }
    }
    #[test]
    fn receiver_filter() {
        for id in ["000024AE:0000185A", "000024AE:0000418A"] {
            assert!(matches_device(id, &[0x85, 0xba, 0x85, 0xbb]));
            assert!(!matches_device(id, &[0x85, 0xba]));
        }
        assert!(!matches_device(
            "00000000:0000185A",
            &[0x85, 0xba, 0x85, 0xbb]
        ));
    }
    #[test]
    fn uhid_wire_layout() {
        let event = create_event();
        assert_eq!(event.len(), 280 + DESCRIPTOR.len());
        assert_eq!(&event[4..18], b"Rapoo VT9 Pro\0");
        assert_eq!(&event[260..262], &(DESCRIPTOR.len() as u16).to_ne_bytes());
        assert_eq!(&event[264..268], &0x24ae_u32.to_ne_bytes());
        assert_eq!(&event[280..], DESCRIPTOR);
        let mut request = 9_u32.to_ne_bytes().to_vec();
        request.extend_from_slice(&123_u32.to_ne_bytes());
        let reply = report_reply(&request, 42).unwrap();
        assert_eq!(&reply[4..8], &123_u32.to_ne_bytes());
        assert_eq!(&reply[8..], &[0, 0, 2, 0, 0, 42]);
        assert!(report_reply(&[9], 42).is_none());
        assert_eq!(input_event(99).len(), 7);
    }
}
