"""Synthetic power supplies and notify-send only; no hardware or desktop access."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

BINARY = sys.argv[1]

with tempfile.TemporaryDirectory(prefix="rapoo-notify-test-") as directory:
    root = Path(directory)
    supplies = root / "power_supply"
    supplies.mkdir()
    home = root / "home"
    home.mkdir()
    state_home = root / "state"
    state = state_home / "rapoo-battery-watcher/last-threshold"
    log = root / "notifications.jsonl"
    helpers = root / "bin"
    helpers.mkdir()
    stub = helpers / "notify-send"
    stub.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
with open(os.environ["NOTIFY_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(int(os.environ.get("NOTIFY_FAILURE", "0")))
''')
    stub.chmod(0o755)
    env = {"HOME": str(home), "XDG_STATE_HOME": str(state_home),
           "PATH": str(helpers), "NOTIFY_LOG": str(log)}

    def calls():
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def run(ok=True, overrides=None, args=None):
        log.unlink(missing_ok=True)
        result = subprocess.run(
            [BINARY, "--notify", "--power-supply", str(supplies), *(args or [])],
            env=env | (overrides or {}), capture_output=True, timeout=3,
        )
        assert (result.returncode == 0) == ok, result.stderr
        return calls()

    def expected(value, threshold):
        critical = threshold <= 5
        return ["--app-name=Rapoo Battery",
                "--urgency=" + ("critical" if critical else "normal"),
                "--icon=" + ("battery-empty-symbolic" if critical else "battery-caution-symbolic"),
                "Rapoo VT9 Pro battery low",
                f"{value}% remaining (reached {threshold}% warning)"]

    # Missing/disconnected or unrelated supplies never create state or notify.
    assert run() == [] and not state_home.exists()
    unrelated = supplies / "BAT0"
    unrelated.mkdir()
    (unrelated / "capacity").write_text("1\n")
    assert run() == [] and not state_home.exists()
    battery = supplies / "hid-24ae:185a-battery-001"
    battery.mkdir()
    capacity = battery / "capacity"
    assert run() == [] and not state_home.exists()

    # Exact thresholds, suppression, recharge reset, and jumps across all thresholds.
    for value, threshold in [(50, None), (11, None), (10, 10), (9, None),
                             (6, None), (5, 5), (2, None), (1, 1), (0, None)]:
        capacity.write_text(f"{value}\n")
        assert run() == ([] if threshold is None else [expected(value, threshold)])
    assert state.read_text() == "1\n"
    capacity.write_text("100\n")
    assert run() == [] and state.read_text() == "101\n"
    capacity.write_text("0\n")
    assert run() == [expected(0, t) for t in [10, 5, 1]]
    assert state.read_text() == "1\n"
    assert run() == []

    # Failed notifications do not consume warnings; the next invocation retries.
    state.unlink()
    capacity.write_text("5\n")
    assert run(overrides={"NOTIFY_FAILURE": "1"}) == [expected(5, t) for t in [10, 5]]
    assert not state.exists()
    assert run() == [expected(5, t) for t in [10, 5]]
    assert state.read_text() == "5\n"
    state.unlink()
    assert run(overrides={"PATH": str(root / "missing-helper")}) == []
    assert not state.exists()

    # Mixed success matches the original shell's per-threshold acknowledgement.
    stub.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
with open(os.environ["NOTIFY_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(1 if "reached 10%" in sys.argv[-1] else 0)
''')
    assert run() == [expected(5, t) for t in [10, 5]]
    assert state.read_text() == "5\n"
    assert run() == []

    # Invalid input/state fails closed without publishing or overwriting state.
    for value in ["", "garbage", "-1", "101", "9999999999999999999"]:
        capacity.write_text(value)
        assert run(ok=False) == [] and state.read_text() == "5\n"
    capacity.write_text("5\n")
    for value in ["", "broken", "-1", "102"]:
        state.write_text(value)
        assert run(ok=False) == [] and state.read_text() == value
    capacity.write_text("11\n")
    assert run() == [] and state.read_text() == "101\n"
    state.unlink()

    # HOME fallback, including empty XDG_STATE_HOME, uses the existing state path.
    fallback = home / ".local/state/rapoo-battery-watcher/last-threshold"
    capacity.write_text("50\n")
    assert run(overrides={"XDG_STATE_HOME": ""}) == []
    assert fallback.read_text() == "101\n" and not state.exists()
    without_xdg = env.copy()
    del without_xdg["XDG_STATE_HOME"]
    assert subprocess.run([BINARY, "--notify", "--power-supply", str(supplies)],
                          env=without_xdg, capture_output=True, timeout=3).returncode == 0
    assert fallback.read_text() == "101\n"

    # The first lexical matching supply wins, like Bash glob order.
    second = supplies / "hid-24ae:185a-battery-002"
    second.mkdir()
    (second / "capacity").write_text("0\n")
    assert run() == [] and state.read_text() == "101\n"
    capacity.unlink()
    assert run() == [] and state.read_text() == "101\n"

    # Misconfigured state paths and incompatible modes fail, without real hardware.
    state_home.rename(root / "old-state")
    state_home.write_text("not a directory")
    capacity.write_text("50\n")
    assert run(ok=False) == []
    for args in [["--daemon"], ["--device", "/unused"], ["--power-supply"]]:
        assert run(ok=False, args=args) == []
    result = subprocess.run([BINARY, "--power-supply", str(supplies)],
                            env=env, capture_output=True, timeout=3)
    assert result.returncode != 0

print("PASS: notification thresholds, exact argv, suppression/reset, retries, state paths, malformed input, missing devices, CLI isolation")
