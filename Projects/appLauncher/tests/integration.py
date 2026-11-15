#!/usr/bin/env python3
"""Disposable fake processes only. Never runs real rbw/clipboard/input tools."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

BINARY = str(Path(sys.argv[1]).resolve())
ID = "aaaaaaaa-1111-2222-3333-444444444444"
OTHER = "bbbbbbbb-1111-2222-3333-444444444444"
CONTEXT = {"address": "0x123", "pid": 123, "class": "fixture", "host": "second.example"}
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, socket, subprocess, sys, time
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
id = "aaaaaaaa-1111-2222-3333-444444444444"
other = "bbbbbbbb-1111-2222-3333-444444444444"
password = "FAKE-only\\n\\t -option \" ' !@#$%^&*()\nsecond line\n"
mode = os.environ.get("CASE", "ok")
# A fixture leak in argv or env fails without ever echoing its contents.
assert all(password not in v and "987654" not in v for v in args)
assert all(password not in v and "987654" not in v for v in os.environ.values())
if name == "rbw":
    if mode == "cancel":
        print("untrusted fake backend secret diagnostic", file=sys.stderr)
        sys.exit(1)
    if mode == "oversize":
        sys.stdout.write("x" * (8 * 1024 * 1024 + 1)); sys.exit()
    if args == ["list", "--raw"]:
        print(json.dumps([{"id": id, "name": "same/name", "user": "person/example", "folder": "one", "type": "Login", "password": password, "notes": "PRIVATE-NOTE"}, {"id": other, "name": "same/name", "user": "person/example", "folder": "two", "type": "Login"}, {"id": "ignored", "type": "Card", "number": "PRIVATE-CARD"}]))
    elif args[:2] == ["get", "--raw"]:
        assert args[2] in [id, other]
        if mode == "malformed": print("not JSON"); sys.exit()
        data = {"username": "dummy-user", "password": password, "totp": "dummy-seed", "uris": [{"uri": "https://first.example/a"}, {"uri": "https://www.second.example/path"}]}
        if mode in ["destroyed", "changed_pid", "changed_class", "focus_changed", "bad_keymap"]: data["password"] = "dummy-ascii"
        if mode == "no_otp": data["totp"] = None
        if mode == "no_password": data["password"] = None
        if mode == "no_username": data["username"] = None
        if mode == "unicode": data["password"] = "dummy-café"
        if mode == "no_uri": data["uris"] = None
        if mode == "not_login": data = {"number": "PRIVATE-CARD"}
        print(json.dumps({"id": other if mode == "wrong_id" else args[2], "data": data, "notes": "PRIVATE-NOTE", "fields": [{"value": "PRIVATE-CUSTOM"}], "history": [{"password": "PRIVATE-HISTORY"}]}))
    elif args == ["code", id]:
        if mode == "otp_error": sys.exit(1)
        print("987654")
    else: sys.exit(22)
elif name == "wl-copy":
    value = sys.stdin.buffer.read()
    if args == ["--sensitive", "--type", "text/secret"]:
        assert value in [password.encode(), b"987654"]
    else:
        assert args == ["--type", "text/plain"]
        assert value in [b"dummy-user", b"https://www.second.example/path", b"https://first.example/a"]
    with open(os.environ["EVENTS"], "a") as output: output.write("copy-stdin-verified\n")
elif name == "hyprctl":
    c = {"address": "0x123", "pid": 123, "class": os.environ.get("CLASS", "fixture")}
    if args == ["-j", "activewindow"]:
        if mode == "focus_changed": c["class"] = "pinentry"
        print(json.dumps(c))
    elif args == ["-j", "clients"]:
        if mode == "changed_pid": c["pid"] = 999
        if mode == "changed_class": c["class"] = "other"
        print(json.dumps([] if mode == "destroyed" else [c]))
    elif args[:2] == ["dispatch", "focuswindow"]: print("ok")
    elif args == ["-j", "devices"]:
        print(json.dumps({"keyboards":[{"active_keymap":"other" if mode == "bad_keymap" else "English (US)","capsLock":False}]}))
    else: sys.exit(23)
elif name == "qutebrowser":
    assert args[0] == "--nowindow"
    command = args[1].removeprefix(":spawn --userscript ").split()
    env = os.environ.copy(); env["QUTE_URL"] = "https://www.example.com/private?query=not-forwarded"
    subprocess.run(command, env=env, check=True)
elif name == "ydotool":
    raise AssertionError("unexpected input: integration suite must not type")
else: sys.exit(24)
'''

with tempfile.TemporaryDirectory(prefix="app-launcher-fixtures-") as directory:
    root = Path(directory)
    root.chmod(0o700)
    tools = root / "bin"
    tools.mkdir()
    for name in ["rbw", "wl-copy", "hyprctl", "qutebrowser", "ydotool"]:
        path = tools / name
        path.write_text(STUB.replace("#!/usr/bin/env python3", "#!" + sys.executable, 1))
        path.chmod(0o700)
    events = root / "events"
    # No inherited Wayland or ydotool socket; every tool name resolves to a stub.
    env = {"PATH": str(tools), "XDG_RUNTIME_DIR": str(root), "EVENTS": str(events)}
    def invoke(args, case="ok", context=CONTEXT, class_name="fixture"):
        result = subprocess.run([BINARY, *args], input=json.dumps(context) + "\n", text=True, capture_output=True,
                                env=dict(env, CASE=case, CLASS=class_name), timeout=8)
        assert result.stderr == "", "helper emitted stderr"
        for forbidden in ["FAKE-only", "987654", "PRIVATE-", "dummy-seed", "untrusted fake"]:
            assert forbidden not in result.stdout, "helper leaked a fixture"
        return result.returncode, json.loads(result.stdout)
    code, value = invoke(["list"])
    assert code == 0 and value["status"] == "listed"
    assert len(value["entries"]) == 2
    assert {entry["id"] for entry in value["entries"]} == {ID, OTHER}
    assert all(set(entry) == {"id", "name", "username", "folder", "entry_type"} for entry in value["entries"])
    for action in ["password", "username", "otp", "url"]:
        code, value = invoke(["act", ID, action])
        assert code == 0 and value == {"status": "copied"}
    code, value = invoke(["act", OTHER, "username"])
    assert code == 0
    assert events.read_text().splitlines() == ["copy-stdin-verified"] * 5
    for case, action, expected in [
        ("cancel", "password", "command_failed"),
        ("malformed", "password", "invalid_schema"),
        ("wrong_id", "password", "entry_changed"),
        ("not_login", "password", "not_login"),
        ("no_password", "password", "missing_field"),
        ("no_username", "username", "missing_field"),
        ("no_password", "fill", "unsupported_text"),
        ("no_username", "fill", "unsupported_text"),
        ("no_otp", "otp", "missing_otp"),
        ("no_uri", "url", "missing_url"),
        ("otp_error", "otp", "command_failed"),
        ("unicode", "fill", "unsupported_text"),
        ("ok", "fill", "unsupported_text"),
        ("destroyed", "fill", "target_unavailable"),
        ("changed_pid", "fill", "target_unavailable"),
        ("changed_class", "fill", "target_unavailable"),
        ("focus_changed", "fill", "focus_changed"),
        ("bad_keymap", "fill", "unsupported_keymap"),
    ]:
        code, value = invoke(["act", ID, action], case)
        assert code != 0 and value == {"status": "error", "code": expected}, (case, action, value)
    code, value = invoke(["act", "display/name", "password"])
    assert code != 0 and value["code"] == "invalid_request"
    assert len(events.read_text().splitlines()) == 5, "failed action changed clipboard"
    code, value = invoke(["list"], "oversize")
    assert code != 0 and value["code"] == "output_too_large"
    for cls, hint in [("vesktop", "discord.com"), ("GoofCord", "discord.com"), ("discordcanary", "discord.com"), ("Steam", "steampowered.com"), ("firefox", ""), ("qutebrowser", "example.com")]:
        code, value = invoke(["context"], class_name=cls)
        assert code == 0 and value["host"] == hint, (cls, value)
        assert set(value) == {"address", "pid", "class", "host"}
    assert not list(root.glob("app-launcher-*")), "private context channel leaked"
print("integration: metadata allowlist, UUID actions, exact stdin, sanitized errors, no side effects on failure, context handoff passed")
