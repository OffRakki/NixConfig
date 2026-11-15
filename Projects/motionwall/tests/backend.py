"""Hermetic daemon/observer/renderer tests; no compositor or desktop changes."""
import concurrent.futures
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time

binary = str(Path(sys.argv[1]).resolve())


def wait_for(check, timeout=4):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.02)
    raise AssertionError("condition timed out")


with tempfile.TemporaryDirectory(prefix="motionwall-test-") as temporary:
    root = Path(temporary)
    (root / "hypr/test").mkdir(parents=True)
    bindir = root / "bin"
    bindir.mkdir()
    renderer = bindir / "gslapper"
    renderer.write_text(f"#!{sys.executable}\n" + r'''
import os, socket, sys
from pathlib import Path
args = sys.argv
assert args[-2] == '*'
p = Path(args[args.index('--ipc-socket')+1])
s = socket.socket(socket.AF_UNIX); s.bind(str(p)); s.listen()
state = 'playing'
while True:
    c, _ = s.accept()
    with c:
        command = c.recv(4096).decode().strip()
        if command == 'query' and (p.parent / 'fail-query').exists(): continue
        if command == 'pause' and not (p.parent / 'fail-ipc').exists(): state = 'paused'
        if command == 'resume': state = 'playing'
        answer = 'STATUS: '+state+' video '+args[-1] if command == 'query' else 'OK'
        c.sendall((answer+'\n').encode())
''')
    renderer.chmod(0o700)
    ffmpeg = bindir / "ffmpeg"
    ffmpeg.write_text(f"#!{sys.executable}\n" + r'''
import sys, time
from pathlib import Path
source = Path(sys.argv[sys.argv.index('-i')+1])
if source.name == 'slow.mp4':
    source.with_suffix('.started').touch()
    time.sleep(1.5)
Path(sys.argv[-1]).write_bytes(b'\xff\xd8\xffmock')
''')
    ffmpeg.chmod(0o700)
    for name in ("fast.mp4", "slow.mp4"):
        (root / name).write_bytes(b"mock video")

    monitor = {"name": "DP-1", "id": 7, "activeWorkspace": {"address": "visible"}, "specialWorkspace": {"address": ""}}
    snapshots = {"monitors": [monitor], "clients": []}
    event_clients = []
    stop = threading.Event()
    sockets = []

    def listen(name):
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(root / "hypr/test" / name))
        server.listen()
        server.settimeout(0.1)
        sockets.append(server)
        return server

    command_socket, event_socket = listen(".socket.sock"), listen(".socket2.sock")

    def command_server():
        while not stop.is_set():
            try:
                client, _ = command_socket.accept()
            except socket.timeout:
                continue
            with client:
                key = client.recv(1024).decode().removeprefix("j/")
                value = snapshots.get(key)
                try:
                    client.sendall(json.dumps(value).encode())
                except OSError:
                    pass  # Bounds checks may close a deliberately oversized response early.

    def events_server():
        while not stop.is_set():
            try:
                client, _ = event_socket.accept()
                event_clients.append(client)
            except socket.timeout:
                continue

    def invalidate():
        for client in event_clients[:]:
            try:
                client.sendall(b"fullscreen>>changed\n" * 20)
            except OSError:
                event_clients.remove(client)
                client.close()

    threads = [threading.Thread(target=fn, daemon=True) for fn in (command_server, events_server)]
    for thread in threads:
        thread.start()
    env = dict(os.environ, XDG_RUNTIME_DIR=temporary, HYPRLAND_INSTANCE_SIGNATURE="test", PATH=str(bindir) + ":" + os.environ["PATH"])
    log = (root / "events.log").open("w")
    daemon = subprocess.Popen([binary, "serve", str(root / "data")], env=env, stdout=log, stderr=log)

    def request(action, **values):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            client.connect(str(root / "motionwall/control.sock"))
            client.sendall((json.dumps(dict(action=action, **values)) + "\n").encode())
            return json.loads(client.makefile().readline())

    def status():
        return request("status")

    def full(value=True, monitor_id=7, workspace="visible"):
        snapshots["clients"] = [{"monitor": monitor_id, "workspace": {"address": workspace}, "mapped": True, "hidden": False, "fullscreen": 2 if value else 0}]
        invalidate()

    def paused(value):
        result = status()
        return result["playback"] and result["playback"]["state"].startswith("STATUS: " + ("paused" if value else "playing"))

    pool = concurrent.futures.ThreadPoolExecutor(1)
    try:
        wait_for(lambda: (root / "motionwall/control.sock").exists())
        wait_for(lambda: status()["policy"]["observer_error"] is None)
        assert request("play", output="*", path=str(root / "fast.mp4"))["ok"]
        pid = status()["playback"]["pid"]
        for _ in range(3):
            begin = time.monotonic()
            full()
            wait_for(lambda: paused(True))
            assert time.monotonic() - begin < 0.5, "ordinary transition exceeded 500ms"
            full(False)
            wait_for(lambda: paused(False))
        full(monitor_id=9)
        time.sleep(0.3)
        assert paused(False), "secondary fullscreen must be ignored"
        full(workspace="hidden")
        time.sleep(0.3)
        assert paused(False)
        request("control", output="*", command="pause")
        full(); wait_for(lambda: status()["policy"]["auto_paused"])
        request("control", output="*", command="resume")
        assert paused(True), "Resume must not override automatic pause"
        request("control", output="*", command="pause")
        full(False); wait_for(lambda: not status()["policy"]["auto_paused"])
        assert paused(True), "manual intent must survive fullscreen exit"
        request("control", output="*", command="resume")
        full(); wait_for(lambda: paused(True))
        snapshots["monitors"] = []
        invalidate(); wait_for(lambda: paused(False))
        snapshots["monitors"] = [monitor]
        invalidate(); wait_for(lambda: paused(True))
        request("configure", auto_pause=False)
        assert paused(False)
        request("configure", auto_pause=True)
        assert paused(True)
        snapshots["clients"] = {"malformed": True}
        invalidate(); wait_for(lambda: status()["policy"]["observer_error"] is not None)
        assert paused(False), "observer failure must fail open"
        full(); wait_for(lambda: paused(True))
        request("control", output="*", command="pause")
        snapshots["clients"] = "x" * (2 * 1024 * 1024 + 100)
        invalidate(); wait_for(lambda: status()["policy"]["observer_error"] is not None)
        assert paused(True) and not status()["policy"]["auto_paused"], "snapshot failure must preserve manual intent only"
        request("control", output="*", command="resume")
        assert paused(False)
        full(); wait_for(lambda: paused(True))
        for client in event_clients:
            client.shutdown(socket.SHUT_RDWR)
            client.close()
        event_clients.clear()
        wait_for(lambda: status()["policy"]["observer_error"] is not None)
        assert paused(False), "event disconnect must clear automatic pause"
        wait_for(lambda: status()["policy"]["observer_error"] is None)
        wait_for(lambda: paused(True))
        assert status()["playback"]["pid"] == pid, "policy and hotplug must not restart playback"
        full(False); wait_for(lambda: paused(False))
        future = pool.submit(request, "play", output="*", path=str(root / "slow.mp4"))
        wait_for(lambda: (root / "slow.started").exists())
        assert not request("preview", path=str(root / "fast.mp4"))["ok"], "media work must be bounded"
        begin = time.monotonic()
        full(); wait_for(lambda: paused(True))
        assert time.monotonic() - begin < 0.5, "FFmpeg must not block automatic controls"
        request("control", output="*", command="stop")
        assert not future.result()["ok"], "Stop must cancel an in-flight selection"
        assert status()["playback"] is None
        assert not Path(f"/proc/{pid}").exists(), "owned renderer leaked"
        assert request("play", output="*", path=str(root / "fast.mp4"))["ok"]
        assert paused(True), "replacement selection must inherit automatic pause"
        replacement = status()["playback"]["pid"]
        os.kill(replacement, 9)
        wait_for(lambda: status()["playback"] is None)
        assert not Path(f"/proc/{replacement}").exists(), "crashed renderer was not reaped"
        assert request("play", output="*", path=str(root / "fast.mp4"))["ok"]
        full(False); wait_for(lambda: paused(False))
        broken_pid = status()["playback"]["pid"]
        failure_marker = root / "motionwall/fail-ipc"
        failure_marker.touch()
        full(); wait_for(lambda: status()["playback"] is None)
        assert not Path(f"/proc/{broken_pid}").exists(), "failed IPC transition left a stranded renderer"
        failure_marker.unlink()
        assert request("play", output="*", path=str(root / "fast.mp4"))["ok"]
        query_pid = status()["playback"]["pid"]
        query_failure = root / "motionwall/fail-query"
        query_failure.touch()
        assert status()["playback"] is None, "failed health IPC must fall back without abandoning a live child"
        assert not Path(f"/proc/{query_pid}").exists()
        query_failure.unlink()
        assert request("play", output="*", path=str(root / "fast.mp4"))["ok"]
        final_pid = status()["playback"]["pid"]
        request("shutdown")
        daemon.wait(timeout=4)
        assert not (root / "motionwall/control.sock").exists()
        assert not Path(f"/proc/{final_pid}").exists(), "shutdown leaked its renderer"
        print("Backend shared ownership, fullscreen latency, precedence, reconnect, fail-open, worker isolation and cancellation passed")
    finally:
        if daemon.poll() is None:
            daemon.terminate()
            daemon.wait(timeout=5)
        pool.shutdown(wait=True)
        stop.set()
        for thread in threads:
            thread.join(timeout=2)
        for client in event_clients:
            client.close()
        for server in sockets:
            server.close()
        log.close()
