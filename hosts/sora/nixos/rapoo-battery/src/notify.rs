use std::{
    env, fs,
    io::{self, ErrorKind},
    path::{Path, PathBuf},
    process::Command,
};

fn capacity(root: &Path) -> io::Result<Option<u8>> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    let mut paths = Vec::new();
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with("hid-24ae:185a-battery-") {
            paths.push(entry.path().join("capacity"));
        }
    }
    paths.sort();
    // Match the shell watcher's first glob match; a disconnected device is a no-op.
    let Some(path) = paths.first() else {
        return Ok(None);
    };
    let Ok(value) = fs::read_to_string(path) else {
        return Ok(None);
    };
    let value: u8 = value
        .trim()
        .parse()
        .map_err(|_| io::Error::other("invalid battery capacity"))?;
    if value > 100 {
        return Err(io::Error::other("battery capacity exceeds 100"));
    }
    Ok(Some(value))
}

fn state_file() -> io::Result<PathBuf> {
    let base = env::var_os("XDG_STATE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .ok_or_else(|| io::Error::other("HOME or XDG_STATE_HOME must be set"))?;
    Ok(base.join("rapoo-battery-watcher/last-threshold"))
}

fn previous_threshold(path: &Path) -> io::Result<u8> {
    let value = match fs::read_to_string(path) {
        Ok(value) => value,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(101),
        Err(error) => return Err(error),
    };
    let value: u8 = value
        .trim()
        .parse()
        .map_err(|_| io::Error::other("invalid saved battery threshold"))?;
    if value > 101 {
        return Err(io::Error::other("saved battery threshold exceeds 101"));
    }
    Ok(value)
}

pub fn run(root: &Path) -> io::Result<()> {
    let Some(percentage) = capacity(root)? else {
        return Ok(());
    };
    let state = state_file()?;
    // state_file always appends a filename and its containing directory.
    fs::create_dir_all(state.parent().expect("state has a parent"))?;
    if percentage > 10 {
        return fs::write(state, "101\n");
    }
    let mut previous = previous_threshold(&state)?;
    for threshold in [10, 5, 1] {
        if percentage > threshold || previous <= threshold {
            continue;
        }
        let (urgency, icon) = if threshold <= 5 {
            ("critical", "battery-empty-symbolic")
        } else {
            ("normal", "battery-caution-symbolic")
        };
        let result = Command::new("notify-send")
            .args([
                "--app-name=Rapoo Battery",
                &format!("--urgency={urgency}"),
                &format!("--icon={icon}"),
                "Rapoo VT9 Pro battery low",
                &format!("{percentage}% remaining (reached {threshold}% warning)"),
            ])
            .status();
        match result {
            Ok(status) if status.success() => {
                previous = threshold;
                fs::write(&state, format!("{previous}\n"))?;
            }
            Ok(status) => eprintln!("rapoo-battery: notification failed: {status}"),
            Err(error) => eprintln!("rapoo-battery: notification failed: {error}"),
        }
    }
    Ok(())
}
