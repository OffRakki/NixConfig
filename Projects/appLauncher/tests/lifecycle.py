#!/usr/bin/env python3
"""Rust CLI contract using ONLY fake qs/helper processes and a private registry.
Usage: python3 tests/lifecycle.py /absolute/path/to/unwrapped/app-launcher
"""
import concurrent.futures
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

BINARY = str(Path(sys.argv[1]).resolve())
CONTEXT = {"address": "0x123", "pid": 123, "class": "fixture", "host": "dummy.example"}
STUB = '''
import fcntl,json,os,pathlib,signal,sys,time
root = pathlib.Path(os.environ["XDG_RUNTIME_DIR"])
args = sys.argv[1:]
def update(fn):
 with open(root / "fixture.lock", "w") as lock:
  fcntl.flock(lock, fcntl.LOCK_EX)
  state = json.loads((root / "fixture.json").read_text())
  result = fn(state)
  (root / "fixture.json").write_text(json.dumps(state))
  return result
if args[0] == "list":
 if os.environ.get("CASE") == "bad_registry": print("untrusted registry diagnostic"); sys.exit(0)
 rows = update(lambda s: s["live"] + (s["dead"] if "--show-dead" in args else []))
 print(json.dumps(rows) if rows else "No running instances.")
elif args[0] == "kill":
 def kill(s):
  rows = [r for r in s["live"] if r["pid"] == int(args[-1])]
  s["live"] = [r for r in s["live"] if r not in rows]
  s["dead"] += rows
 update(kill)
elif args[0] == "ipc":
 def ipc(s):
  s["ipc"].append(args)
  return any(r["pid"] == int(args[2]) for r in s["live"])
 success = update(ipc)
 if os.environ.get("CASE") == "ipc_timeout": success = False
 if os.environ.get("CASE") == "ipc_echo": print(json.dumps(args[3:])); sys.exit(7)
 sys.exit(0 if success else 1)
else:
 assert args[0] == "-p" and args[2] == "-n", args
 if os.environ.get("CASE") == "start_failure": sys.exit(9)
 def start(s):
  s["starts"] += 1
  pid = 40000 + s["starts"] if "-d" in args else os.getpid()
  row = dict(config_path=str(pathlib.Path(args[1]) / "shell.qml"), id="fixture-" + str(s["starts"]), shell_id="app-launcher", pid=pid)
  s["live"].append(row)
  s["hidden"].append(os.environ.get("APP_LAUNCHER_HIDDEN"))
  return row
 row = update(start)
 if "-d" not in args:
  def finish(sig, frame):
   def remove(s): s["live"] = [r for r in s["live"] if r["id"] != row["id"]]
   update(remove)
   sys.exit(0)
  signal.signal(signal.SIGTERM, finish)
  signal.signal(signal.SIGINT, finish)
  while True: time.sleep(.02)
'''

with tempfile.TemporaryDirectory(prefix="app-launcher-lifecycle-") as directory:
    root = Path(directory)
    root.chmod(0o700)
    tools = root / "bin"
    tools.mkdir()
    qs = tools / "qs"
    qs.write_text("#!" + sys.executable + "\n" + STUB)
    qs.chmod(0o700)
    helper = tools / "helper"
    helper.write_text("#!" + sys.executable + '\nimport json,os,sys\nassert sys.argv[1:] == ["context"]\nprint("bad context" if os.environ.get("CASE") == "bad_context" else ' + repr(json.dumps(CONTEXT)) + ')\n')
    helper.chmod(0o700)
    config = root / "config with spaces"
    config.mkdir()
    (config / "shell.qml").write_text("fixture")
    state_file = root / "fixture.json"
    unrelated = dict(config_path="/fixture/unrelated/shell.qml", id="unrelated", shell_id="unrelated", pid=12345)
    initial = dict(live=[unrelated], dead=[], ipc=[], starts=0, hidden=[])
    state_file.write_text(json.dumps(initial))
    env = dict(PATH=str(tools), HOME=str(root), XDG_RUNTIME_DIR=str(root),
               QUICKSHELL_CONFIG_PATH=str(config), APP_LAUNCHER_PASSWORD_HELPER=str(helper))

    def state():
        # Writers replace the contents under a private fixture lock.
        import fcntl
        with open(root / "fixture.lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return json.loads(state_file.read_text())

    def invoke(*args, case="ok", expected=0):
        result = subprocess.run([BINARY, *args], env=dict(env, CASE=case), capture_output=True, text=True, timeout=12)
        assert result.returncode == expected, (args, result.returncode, result.stderr)
        return result

    def wait(predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate(): return
            time.sleep(.02)
        raise AssertionError("fixture condition timed out")

    invoke("--stop")
    invoke("--hidden")
    assert state()["hidden"] == ["1"]
    invoke("--hidden")
    assert state()["starts"] == 1
    invoke()
    assert state()["ipc"][-1][-1] == "toggle"
    invoke("--passwords")
    assert json.loads(state()["ipc"][-1][-1]) == CONTEXT
    assert state()["starts"] == 1
    result = invoke("ipc", "call", "fixture", "arg with spaces", case="ipc_echo", expected=7)
    assert json.loads(result.stdout) == ["call", "fixture", "arg with spaces"]
    # Invalid helper/registry must not stop the current shell or echo diagnostics.
    for case in ["bad_context", "bad_registry"]:
        result = invoke("--passwords", case=case, expected=1)
        assert "untrusted" not in result.stderr and not result.stdout
        assert state()["starts"] == 1
    for args in [("--wat",), ("--path",), ("--path", str(root))]:
        invoke(*args, expected=2)
    invoke("--stop")
    assert state()["live"] == [unrelated]
    invoke("ipc", "call", "launcher", "theme", expected=1)
    invoke(case="start_failure", expected=9)
    # Concurrent starts share one flock and produce one daemon, even from cold.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda _: invoke("--hidden"), range(8)))
    assert state()["starts"] == 2 and len(state()["live"]) == 2
    invoke("--stop")
    # Legacy paths and duplicate owners must be replaced rather than reused.
    snapshot = state()
    snapshot["live"] += [
        dict(config_path="/old/appLauncher/shell.qml", id="old", shell_id="", pid=41001),
        dict(config_path="/other/shell.qml", id="duplicate", shell_id="app-launcher", pid=41002),
    ]
    state_file.write_text(json.dumps(snapshot))
    invoke("--hidden")
    assert len(state()["live"]) == 2 and state()["live"][0] == unrelated
    assert state()["live"][1]["config_path"] == str(config / "shell.qml")
    invoke("--stop")
    invoke("--passwords", case="ipc_timeout", expected=1)
    assert state()["live"] == [unrelated], "failed cold readiness orphaned a shell"
    # Dead registry entries are reclaimed; unrelated records and files survive.
    registry = root / "quickshell"
    for row in state()["dead"] + [unrelated]:
        (registry / "by-id" / row["id"]).mkdir(parents=True, exist_ok=True)
        if row["shell_id"]:
            shell = registry / "by-shell" / row["shell_id"]
            shell.mkdir(parents=True, exist_ok=True)
            (shell / row["id"]).symlink_to(registry / "by-id" / row["id"])
    for name in ["by-pid", "by-path"]:
        (registry / name).mkdir()
        (registry / name / "dangling").symlink_to(root / "absent")
        (registry / name / "unrelated").symlink_to(registry / "by-id" / "unrelated")
    invoke("--stop")
    assert list((registry / "by-id").iterdir()) == [registry / "by-id" / "unrelated"]
    assert (registry / "by-path" / "unrelated").exists()
    assert not (registry / "by-path" / "dangling").is_symlink()
    # Reject traversal before touching any attacker-controlled registry path.
    snapshot = state()
    original_dead = snapshot["dead"][:]
    snapshot["dead"].append(dict(config_path=str(config / "shell.qml"), id="../outside", shell_id="app-launcher", pid=41003))
    state_file.write_text(json.dumps(snapshot))
    marker = root / "outside" / "marker"
    marker.parent.mkdir()
    marker.write_text("keep")
    invoke("--stop", expected=1)
    assert marker.read_text() == "keep"
    snapshot["dead"] = original_dead
    state_file.write_text(json.dumps(snapshot))
    # Password foreground owns only its child, releases the lifecycle lock once
    # ready, forwards termination via Drop, and never kills the unrelated row.
    foreground = subprocess.Popen([BINARY, "--passwords", "--path", str(config)], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        wait(lambda: any(r["pid"] != 12345 for r in state()["live"]))
        wait(lambda: state()["ipc"][-1][-2] == "passwordMode")
        invoke("--hidden")  # fails by timeout if foreground retained its lock
        assert foreground.poll() is None
        foreground.send_signal(signal.SIGTERM)
        assert foreground.wait(timeout=5) == 143
        wait(lambda: state()["live"] == [unrelated])
    finally:
        if foreground.poll() is None:
            foreground.kill()
            foreground.wait()
        foreground.stderr.close()
    print("lifecycle: CLI, IPC/exit forwarding, validation, concurrent flock, stale cleanup, cold timeout cleanup, foreground ownership and signal handling passed")
