"""Real binary, fake datagram receiver and fake systemctl/notify-send only."""
import json
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

BINARY = sys.argv[1]
EVENT = struct.Struct("@llHHi")

with tempfile.TemporaryDirectory(prefix="autoclicker-test-") as directory:
    root = Path(directory)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sock.bind(str(root / "input.sock"))
    sock.settimeout(2)
    env = dict(os.environ, YDOTOOL_SOCKET=str(root / "input.sock"))
    for stop_signal in [signal.SIGTERM, signal.SIGINT]:
        process = subprocess.Popen([BINARY, "run"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        packets = []
        down_times = []
        try:
            # Observe five complete clicks, then stop during the sixth button-down.
            while len(down_times) < 6:
                packet = sock.recv(4096)
                assert len(packet) == EVENT.size, packet
                event = EVENT.unpack(packet)
                assert event[:2] == (0, 0), event
                packets.append(event[2:])
                if event[2:] == (1, 0x110, 1):
                    down_times.append(time.monotonic())
            process.send_signal(stop_signal)
            # Drain shutdown packets, including the RAII release after the loop.
            while True:
                try:
                    packets.append(EVENT.unpack(sock.recv(4096))[2:])
                except socket.timeout:
                    break
            stdout, stderr = process.communicate(timeout=2)
            assert process.returncode == 0, (process.returncode, stderr)
            assert not stdout and not stderr
            assert all(gap >= 0.045 for gap in [b - a for a, b in zip(down_times, down_times[1:])]), down_times
            assert packets[-2:] == [(1, 0x110, 0), (0, 0, 0)], packets
            down = False
            for index, packet in enumerate(packets):
                if index % 2 == 1:
                    assert packet == (0, 0, 0), packets
                else:
                    assert packet in [(1, 0x110, 0), (1, 0x110, 1)], packets
                    if packet[-1] == 1:
                        assert not down, packets
                    down = bool(packet[-1])
            assert not down
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    release = subprocess.Popen([BINARY, "release"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert EVENT.unpack(sock.recv(4096))[2:] == (1, 0x110, 0)
    assert EVENT.unpack(sock.recv(4096))[2:] == (0, 0, 0)
    # Drop repeats release as a fallback; drain it too.
    assert EVENT.unpack(sock.recv(4096))[2:] == (1, 0x110, 0)
    assert EVENT.unpack(sock.recv(4096))[2:] == (0, 0, 0)
    assert release.wait(timeout=2) == 0
    sock.close()
    assert subprocess.run([BINARY, "run"], env=env, capture_output=True, timeout=2).returncode != 0

    stub = "#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([Path(sys.argv[0]).name, *sys.argv[1:]]) + "\\n")
if Path(sys.argv[0]).name == "systemctl":
    if "show" in sys.argv:
        print(os.environ["TEST_STATE"])
        sys.exit(int(os.environ.get("SHOW_FAILURE", "0")))
    sys.exit(int(os.environ.get("ACTION_FAILURE", "0")))
sys.exit(1)  # Failed notification must not break a successful toggle.
'''
    for name in ["systemctl", "notify-send"]:
        path = root / name
        path.write_text(stub)
        path.chmod(0o700)
    log = root / "calls.jsonl"
    for state, action in [("active", "stop"), ("activating", "stop"), ("deactivating", "stop"), ("reloading", "stop"), ("inactive", "start"), ("failed", "start")]:
        log.write_text("")
        test_env = dict(env, PATH=str(root), CALL_LOG=str(log), TEST_STATE=state)
        result = subprocess.run([BINARY, "toggle"], env=test_env, capture_output=True, timeout=2)
        assert result.returncode == 0, result.stderr
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert calls[0] == ["systemctl", "--user", "show", "--property=ActiveState", "--value", "autoclicker.service"]
        assert calls[1] == ["systemctl", "--user", action, "autoclicker.service"], calls
        assert calls[2][-1] == ("Enabled" if action == "start" else "Disabled"), calls
    for overrides in [{"SHOW_FAILURE": "1"}, {"ACTION_FAILURE": "1"}, {"TEST_STATE": "unknown"}]:
        log.write_text("")
        result = subprocess.run([BINARY, "toggle"], env=dict(test_env, **overrides), capture_output=True, timeout=2)
        assert result.returncode != 0
        assert "notify-send" not in log.read_text()
    for args in [[], ["nonsense"], ["run", "extra"]]:
        assert subprocess.run([BINARY, *args], env=env, capture_output=True, timeout=2).returncode != 0
    assert subprocess.run([BINARY, "--help"], env=env, capture_output=True, timeout=2).returncode == 0
print("PASS: fake input wire format/cadence, SIGTERM/SIGINT release, missing socket, stubbed toggle/error paths")
