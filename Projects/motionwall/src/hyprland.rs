//! Bounded, coalescing Hyprland observer. Never controls the renderer itself.
use crate::{MAX_MESSAGE, Result};
use serde_json::Value;
use std::{
    env,
    io::{Read, Write},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Clone, Default, PartialEq, Debug)]
pub struct Observation {
    pub fullscreen: bool,
    pub error: Option<String>,
}

fn primary(monitors: &Value) -> Result<Option<&Value>> {
    Ok(monitors
        .as_array()
        .ok_or("invalid monitor snapshot")?
        .iter()
        .find(|m| m["name"] == "DP-1"))
}

// Workspace addresses support normal AND special workspaces without numeric IDs.
pub fn visible_fullscreen(monitors: &Value, clients: &Value) -> Result<bool> {
    let clients = clients.as_array().ok_or("invalid client snapshot")?;
    let Some(monitor) = primary(monitors)? else {
        return Ok(false);
    };
    let id = monitor["id"].as_i64().ok_or("monitor ID missing")?;
    let normal = monitor["activeWorkspace"]["address"]
        .as_str()
        .ok_or("active workspace address missing")?;
    let special = monitor["specialWorkspace"]["address"]
        .as_str()
        .ok_or("special workspace address missing")?;
    for client in clients {
        if client["monitor"].as_i64() != Some(id) {
            continue;
        }
        let workspace = client["workspace"]["address"]
            .as_str()
            .ok_or("client workspace address missing")?;
        if workspace.is_empty() || (workspace != normal && workspace != special) {
            continue;
        }
        let mapped = client["mapped"]
            .as_bool()
            .ok_or("client mapped flag missing")?;
        let hidden = client["hidden"]
            .as_bool()
            .ok_or("client hidden flag missing")?;
        let mode = client["fullscreen"]
            .as_u64()
            .ok_or("client fullscreen mode missing")?;
        // Installed Hyprland FullscreenTypes.hpp: NONE=0, MAXIMIZED=1, FULLSCREEN=2.
        // fullscreenClient is only the client request and must not decide this policy.
        if mapped && !hidden && mode == 2 {
            return Ok(true);
        }
    }
    Ok(false)
}

fn query(root: &Path, command: &str) -> Result<Value> {
    let mut stream = UnixStream::connect(root.join(".socket.sock"))?;
    stream.set_read_timeout(Some(Duration::from_millis(500)))?;
    stream.set_write_timeout(Some(Duration::from_millis(500)))?;
    stream.write_all(format!("j/{command}").as_bytes())?;
    let deadline = Instant::now() + Duration::from_millis(700);
    let mut bytes = Vec::new();
    let mut chunk = [0; 8192];
    loop {
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            break;
        }
        bytes.extend_from_slice(&chunk[..n]);
        if bytes.len() as u64 > MAX_MESSAGE || Instant::now() >= deadline {
            return Err("Hyprland snapshot exceeded bounds".into());
        }
    }
    Ok(serde_json::from_slice(&bytes)?)
}
fn snapshot(root: &Path) -> Result<bool> {
    for _ in 0..3 {
        let before = query(root, "monitors")?;
        let clients = query(root, "clients")?;
        let after = query(root, "monitors")?;
        // Focus-only fields may change; compare only the visibility identity.
        let identity = |m: Option<&Value>| {
            m.map(|m| {
                (
                    m["id"].clone(),
                    m["activeWorkspace"].clone(),
                    m["specialWorkspace"].clone(),
                )
            })
        };
        if identity(primary(&before)?) == identity(primary(&after)?) {
            return visible_fullscreen(&after, &clients);
        }
    }
    Err("Hyprland visibility changed during snapshots".into())
}
fn socket_root() -> Result<PathBuf> {
    let signature = env::var("HYPRLAND_INSTANCE_SIGNATURE")?;
    if signature.is_empty() || signature.contains('/') || signature == "." || signature == ".." {
        return Err("invalid Hyprland instance signature".into());
    }
    Ok(
        PathBuf::from(env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR unset")?)
            .join("hypr")
            .join(signature),
    )
}
pub fn start(quit: Arc<AtomicBool>) -> (Arc<Mutex<Observation>>, thread::JoinHandle<()>) {
    let state = Arc::new(Mutex::new(Observation {
        fullscreen: false,
        error: Some("Waiting for Hyprland observer".into()),
    }));
    let shared = Arc::clone(&state);
    let worker = thread::spawn(move || {
        while !quit.load(Ordering::Relaxed) {
            let result = (|| -> Result<()> {
                let root = socket_root()?;
                let mut events = UnixStream::connect(root.join(".socket2.sock"))?;
                events.set_read_timeout(Some(Duration::from_millis(50)))?;
                // Subscribe before the initial snapshot; events that race it stay queued.
                let mut refresh = Instant::now();
                let mut dirty = None;
                loop {
                    if quit.load(Ordering::Relaxed) {
                        return Ok(());
                    }
                    if Instant::now() >= refresh || dirty.is_some_and(|at| Instant::now() >= at) {
                        let fullscreen = snapshot(&root)?;
                        *shared.lock().unwrap_or_else(|e| e.into_inner()) = Observation {
                            fullscreen,
                            error: None,
                        };
                        refresh = Instant::now() + Duration::from_secs(10);
                        dirty = None;
                    }
                    let mut buffer = [0; 4096];
                    match events.read(&mut buffer) {
                        Ok(0) => return Err("Hyprland event socket disconnected".into()),
                        Ok(_) => {
                            dirty.get_or_insert(Instant::now() + Duration::from_millis(150));
                        }
                        Err(e)
                            if matches!(
                                e.kind(),
                                std::io::ErrorKind::WouldBlock
                                    | std::io::ErrorKind::TimedOut
                                    | std::io::ErrorKind::Interrupted
                            ) => {}
                        Err(e) => return Err(e.into()),
                    }
                }
            })();
            if let Err(e) = result {
                *shared.lock().unwrap_or_else(|e| e.into_inner()) = Observation {
                    fullscreen: false,
                    error: Some(e.to_string()),
                };
            }
            for _ in 0..10 {
                if quit.load(Ordering::Relaxed) {
                    break;
                }
                thread::sleep(Duration::from_millis(100));
            }
        }
    });
    (state, worker)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn monitors() -> Value {
        json!([{"name":"DP-1","id":7,"activeWorkspace":{"address":"1"},"specialWorkspace":{"address":"special:term"}},{"name":"HDMI-A-1","id":8,"activeWorkspace":{"address":"2"},"specialWorkspace":{"address":""}}])
    }
    fn client() -> Value {
        json!({"monitor":7,"workspace":{"address":"1"},"mapped":true,"hidden":false,"fullscreen":2,"fullscreenClient":0})
    }
    #[test]
    fn primary_visible_effective_fullscreen_only() {
        let m = monitors();
        let mut c = client();
        assert!(visible_fullscreen(&m, &json!([c])).unwrap());
        c["fullscreen"] = json!(1);
        c["fullscreenClient"] = json!(2);
        assert!(!visible_fullscreen(&m, &json!([c])).unwrap());
        c["fullscreen"] = json!(2);
        c["workspace"]["address"] = json!("hidden");
        assert!(!visible_fullscreen(&m, &json!([c])).unwrap());
        c["workspace"]["address"] = json!("special:term");
        assert!(visible_fullscreen(&m, &json!([c])).unwrap());
        c["hidden"] = json!(true);
        assert!(!visible_fullscreen(&m, &json!([c])).unwrap());
        c["hidden"] = json!(false);
        c["mapped"] = json!(false);
        assert!(!visible_fullscreen(&m, &json!([c])).unwrap());
        c = client();
        c["monitor"] = json!(8);
        c["workspace"]["address"] = json!("2");
        assert!(!visible_fullscreen(&m, &json!([c])).unwrap());
        assert!(!visible_fullscreen(&json!([]), &json!([client()])).unwrap());
        assert!(visible_fullscreen(&json!({}), &json!([])).is_err());
        assert!(visible_fullscreen(&m, &json!([{"monitor":7}])).is_err());
    }
}
