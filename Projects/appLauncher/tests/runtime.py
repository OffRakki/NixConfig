#!/usr/bin/env python3
"""Opt-in installed-stack checks in a PRIVATE headless Sway, never the live session.
Usage: python3 tests/runtime.py /absolute/path/to/sway /absolute/path/to/clip-notify
Requires qs, wl-copy, wl-paste, cliphist, wtype, jq, flock, and Python on PATH.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

PROJECT = Path(__file__).resolve().parent.parent
SWAY, NOTIFIER = map(lambda s: str(Path(s).resolve()), sys.argv[1:3])
HELPER = str(Path(sys.argv[3]).resolve()) if len(sys.argv) > 3 else None
if HELPER:
    # A packaged PATH-prefixing wrapper would bypass fake rbw. Only an explicit
    # unwrapped ELF is safe for this opt-in installed clipboard integration.
    with open(HELPER, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "use the unwrapped test helper binary"


def wait(predicate, description, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(description)


with tempfile.TemporaryDirectory(prefix="password-isolated-runtime-") as tmp:
    root = Path(tmp)
    root.chmod(0o700)
    tools = root / "bin"
    tools.mkdir()
    # Deliberately do not inherit displays, bus, compositor/input sockets, HOME,
    # XDG locations or clipboard contents. No uinput/ydotool process is launched.
    env = dict(PATH=str(tools) + ":" + os.environ["PATH"], HOME=str(root), LANG="C.UTF-8", LC_ALL="C.UTF-8",
               XDG_RUNTIME_DIR=str(root), XDG_CONFIG_HOME=str(root / "config"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
               DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(root / "no-session-bus"),
               WLR_BACKENDS="headless", WLR_RENDERER="pixman", QT_QPA_PLATFORM="wayland")
    notifier_log = root / "notifications"
    notify = tools / "notify-send"
    notify.write_text("#!" + sys.executable + "\nimport json,sys\nwith open(" + repr(str(notifier_log)) + ", 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n")
    notify.chmod(0o700)
    helper = tools / "fixture-helper"
    helper.write_text("#!" + sys.executable + '''
import json,sys,time,os,pathlib
mode = pathlib.Path(os.environ["FIXTURE_CONTROL"]).read_text()
if sys.argv[1] == "context": print(json.dumps({"address":"0x123","pid":123,"class":"fixture","host":""}))
elif sys.argv[1] == "list":
 time.sleep(.6 if mode == "slow" else .2)
 entries = [] if mode == "empty" else [{"id":"aaaaaaaa-1111-2222-3333-444444444444","name":"fixture-login","username":"fixture-user","folder":"fixture-folder","entry_type":"login"}]
 print(json.dumps({"status":"error","code":"command_failed"} if mode == "error" else {"status":"listed","entries":entries}))
else:
 assert json.loads(sys.stdin.readline())["pid"] == 123
 time.sleep(.1)
 print(json.dumps({"status":"filled" if sys.argv[-1] == "fill" else "copied"}))
''')
    helper.chmod(0o700)
    env["APP_LAUNCHER_PASSWORD_HELPER"] = str(helper)
    control = root / "helper-control"
    control.write_text("normal")
    env["FIXTURE_CONTROL"] = str(control)
    config = root / "sway.conf"
    config.write_text("output * resolution 1280x720\nseat seat0 fallback true\n")
    children = []
    sway_log = open(root / "sway.log", "w")
    compositor = subprocess.Popen([SWAY, "-c", str(config)], env=env, stdout=sway_log, stderr=sway_log)
    children.append(compositor)

    def run(args, **kwargs):
        if str(args[0]) == "wl-copy":
            return subprocess.run(list(map(str, args)), env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, **kwargs)
        return subprocess.run(list(map(str, args)), env=env, check=True, capture_output=True, timeout=15, **kwargs)

    def launcher(*args):
        return run([PROJECT / "launch", *args])

    def instances():
        output = run(["qs", "list", "--all", "--json"]).stdout
        try:
            return [] if output.strip() in [b"", b"No running instances."] else json.loads(output)
        except json.JSONDecodeError:
            raise AssertionError("private qs list output: " + repr(output))

    def shells():
        return [p for p in instances() if p["shell_id"] == "app-launcher"]

    def launch_pid():
        rows = shells()
        assert len(rows) == 1, "not exactly one launcher"
        return rows[0]["pid"]

    try:
        wait(lambda: any(p.is_socket() for p in root.glob("wayland-*")), "private compositor unavailable")
        env["WAYLAND_DISPLAY"] = next(p.name for p in root.glob("wayland-*") if p.is_socket())
        # Create a virtual keyboard on this private compositor only (no keys).
        run(["wtype", "-s", "1"])
        # Installed clipboard stack, isolated socket and disposable history DB.
        db = root / "history.db"
        history = subprocess.Popen(["wl-paste", "--type", "text", "--watch", "cliphist", "-db-path", str(db), "store"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        notifications = subprocess.Popen(["wl-paste", "--watch", NOTIFIER], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        children.extend([history, notifications])
        time.sleep(0.25)
        ordinary = b"ordinary disposable fixture"
        run(["wl-copy", "--type", "text/plain"], input=ordinary)
        wait(lambda: db.exists() and ordinary in run(["cliphist", "-db-path", db, "list"]).stdout, "ordinary text missing from isolated history")
        wait(lambda: notifier_log.exists() and ordinary.decode() in notifier_log.read_text(), "ordinary preview missing")
        for fake in [b"FAKE-password\\n -option\nsecond line\n", b"987654"]:
            previous = len(notifier_log.read_text().splitlines())
            run(["wl-copy", "--sensitive", "--type", "text/secret"], input=fake)
            wait(lambda: len(notifier_log.read_text().splitlines()) > previous, "sensitive notification missing")
            assert run(["wl-paste", "--no-newline", "--type", "text/secret"]).stdout == fake
            assert "Sensitive clipboard content hidden" in notifier_log.read_text().splitlines()[-1]
            assert fake.decode().splitlines()[0] not in notifier_log.read_text()
            assert fake.splitlines()[0] not in run(["cliphist", "-db-path", db, "list"]).stdout
        run(["wl-copy", "--type", "text/plain"], input=b"ordinary fixture after sensitive")
        wait(lambda: b"ordinary fixture after sensitive" in run(["cliphist", "-db-path", db, "list"]).stdout, "ordinary clipboard did not recover")
        if HELPER:
            rbw = tools / "rbw"
            rbw.write_text("#!" + sys.executable + '''
import json,sys
id = "aaaaaaaa-1111-2222-3333-444444444444"
assert sys.argv[1:] == ["get", "--raw", id]
print(json.dumps({"id":id,"data":{"username":"fixture","password":"FAKE-helper\\\\n -option\\nsecond line\\n","totp":None,"uris":None}}))
''')
            rbw.chmod(0o700)
            result = run([HELPER, "act", "aaaaaaaa-1111-2222-3333-444444444444", "password"], input=b'{"address":"","pid":0,"class":"","host":""}\n')
            assert json.loads(result.stdout) == {"status":"copied"}
            assert run(["wl-paste", "--no-newline", "--type", "text/secret"]).stdout == b"FAKE-helper\\n -option\nsecond line\n"
            assert b"FAKE-helper" not in run(["cliphist", "-db-path", db, "list"]).stdout
        print("PASS: installed sensitive clipboard: exact bytes, fully hidden notification, absent from disposable cliphist; ordinary text before/after stores and previews")

        # Exercise the actual component's generation and busy-state logic using
        # fixture-only IPC in a separate test shell (no production debug API).
        session_dir = root / "session-test"
        session_dir.mkdir()
        shutil.copy(PROJECT / "PasswordSession.qml", session_dir)
        (session_dir / "shell.qml").write_text('''//@ pragma ShellId fixture-password-session
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    property int completions: 0
    PasswordSession { id: session; onFinished: completions++ }
    IpcHandler {
        target: "fixture"
        function snapshot(): string { return JSON.stringify({active: session.active, busy: session.busy, acting: session.acting, count: session.entries.length, selected: !!session.selected, message: session.message, completions: completions}) }
        function open(): void { session.open('{"address":"0x123","pid":123,"class":"fixture","host":""}') }
        function close(): void { session.close() }
        function choose(): void { session.selected = session.entries[0] }
        function submit(index: int): void { session.submit(index) }
    }
}
''')
        run(["qs", "-p", session_dir, "-n", "-d"])
        session_pid = next(p["pid"] for p in instances() if p["shell_id"] == "fixture-password-session")
        def session_call(name, *args):
            return run(["qs", "ipc", "--pid", str(session_pid), "call", "fixture", name, *args]).stdout
        def snapshot():
            return json.loads(session_call("snapshot"))
        session_call("open")
        assert snapshot()["busy"]
        wait(lambda: not snapshot()["busy"], "session load did not finish")
        assert snapshot()["count"] == 1
        for index in range(5):
            session_call("choose")
            session_call("submit", str(index))
            session_call("submit", str(index))  # duplicate must be ignored
            wait(lambda: not snapshot()["busy"], "session action did not finish")
            assert snapshot()["completions"] == index + 1
        session_call("close")
        assert not snapshot()["active"] and snapshot()["count"] == 0
        control.write_text("slow")
        session_call("open")
        time.sleep(.1)
        session_call("close")
        control.write_text("empty")
        session_call("open")
        wait(lambda: not snapshot()["busy"], "empty session did not finish")
        time.sleep(.7)
        assert snapshot()["active"] and snapshot()["count"] == 0
        control.write_text("error")
        session_call("open")
        wait(lambda: not snapshot()["busy"], "error session did not finish")
        assert "Unlock cancelled" in snapshot()["message"]
        control.write_text("normal")
        unavailable = helper.with_suffix(".unavailable")
        helper.rename(unavailable)
        try:
            session_call("open")
            wait(lambda: not snapshot()["busy"], "missing helper left session permanently busy")
        finally:
            unavailable.rename(helper)
        run(["qs", "kill", "--pid", str(session_pid)])
        print("PASS: PasswordSession loads, five actions, duplicate-submit guard, close clears metadata, cancelled/late responses stay invalid, empty/error sessions")

        # Unrelated shell must survive every canonical lifecycle transition.
        unrelated = root / "unrelated"
        unrelated.mkdir()
        (unrelated / "shell.qml").write_text('//@ pragma ShellId fixture-unrelated\nimport Quickshell\nimport QtQuick\nShellRoot { Timer { interval: 1000; running: true; repeat: true } }\n')
        started = run(["qs", "-p", unrelated, "-n", "-d"])
        wait(lambda: any(p["shell_id"] == "fixture-unrelated" for p in instances()), "unrelated shell unavailable: " + repr(started.stdout) + repr(started.stderr))
        other_pid = next(p["pid"] for p in instances() if p["shell_id"] == "fixture-unrelated")
        launcher("--passwords")  # cold, hidden-until-ready
        pid = launch_pid()
        time.sleep(0.4)
        for args in [[], ["--passwords"], ["--passwords"], ["--hidden"], [], ["--passwords"]]:
            launcher(*args)
            assert launch_pid() == pid
        # Metadata must not enter app favorites/launch counts or persisted logs.
        time.sleep(0.4)
        state = root / "state" / "quickshell" / "appLauncher" / "launcher.json"
        if state.exists():
            assert "fixture-" not in state.read_text()
            assert "aaaaaaaa-" not in state.read_text()
        logs = run(["qs", "log", "--pid", str(pid)]).stdout.decode()
        for error in ["Unable to assign", "Binding loop", "Failed to load configuration", "ReferenceError", "TypeError"]:
            assert error not in logs, "QML runtime error: " + error
        assert "fixture-login" not in logs and "fixture-user" not in logs
        assert any(p["pid"] == other_pid for p in instances())
        launcher("--stop")
        assert not shells()
        assert any(p["pid"] == other_pid for p in instances())
        alternate = root / "source-tree" / "appLauncher"
        alternate.mkdir(parents=True)
        for name in ["shell.qml", "PasswordSession.qml"]:
            shutil.copy(PROJECT / name, alternate)
        env["QUICKSHELL_CONFIG_PATH"] = str(alternate)
        launcher("--passwords")
        alternate_pid = launch_pid()
        del env["QUICKSHELL_CONFIG_PATH"]
        launcher("--passwords")
        assert launch_pid() != alternate_pid, "outdated/source-path shell was reused"
        assert shells()[0]["config_path"] == str(PROJECT / "shell.qml")
        assert any(p["pid"] == other_pid for p in instances())
        launcher("--stop")
        foreground_log = open(root / "foreground.log", "w")
        foreground = subprocess.Popen([str(PROJECT / "launch"), "--passwords", "--path", str(PROJECT)], env=env, stdout=foreground_log, stderr=foreground_log)
        children.append(foreground)
        wait(lambda: len(shells()) == 1, "source-path password foreground did not start")
        assert foreground.poll() is None, "foreground returned prematurely"
        foreground.terminate()
        foreground.wait(timeout=5)
        wait(lambda: not shells(), "foreground termination left shell alive")
        foreground_log.close()
        print("PASS: cold password start, app/password/hidden repeated routing, foreground source path and shutdown, one unchanged PID, unrelated shell preserved, no metadata persistence/logging or QML runtime errors")

        # Existing theme test is safe ONLY because all its lifecycle commands and
        # restoration run inside this disposable runtime, not Lucky's session.
        installed = tools / "app-launcher"
        installed.write_text("#!/bin/sh\nexec " + str(PROJECT / "launch") + ' "$@"\n')
        installed.chmod(0o700)
        first, second = root / "first.json", root / "second.json"
        first.write_text(json.dumps({"primary":"#123456","primaryContainer":"#234567","surfaceText":"#345678"}))
        second.write_text(json.dumps({"primary":"#654321","primaryContainer":"#765432","surfaceText":"#876543"}))
        result = run(["bash", PROJECT / "test-theme", first, second])
        print(result.stdout.decode().strip())
        launcher("--stop")
        run(["qs", "kill", "--pid", str(other_pid)])
    finally:
        try:
            launcher("--stop")
        except (subprocess.SubprocessError, OSError):
            pass
        for child in reversed(children):
            if child.poll() is not None:
                continue
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        sway_log.close()
