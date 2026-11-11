"""Synthetic-only CLI checks. All external helpers are replaced before execution."""
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1]).resolve()
bash = shutil.which('bash')
assert bash
with tempfile.TemporaryDirectory(prefix='clip-notify-smoke-') as directory:
    root = Path(directory)
    stubs = root / 'bin'
    stubs.mkdir()
    temporary = root / 'tmp'
    temporary.mkdir()
    capture = root / 'notification'
    call_log = root / 'calls'
    helpers = {
        'wl-paste': '[[ "$*" == "-l" ]] || exit 90\nprintf "%s\\n" "$TEST_MIMES"\n',
        'notify-send': 'printf "%s\\0" "$@" > "$TEST_CAPTURE"\n',
        'du': '[[ "$1" == "-h" && -f "$2" ]] || exit 90\nprintf "4.0K\\t%s\\n" "$2"\n',
        'file': '[[ "$1" == "-b" && -f "$2" ]] || exit 90\nprintf "synthetic <binary> & data, second, third\\n"\n',
    }
    for name, body in helpers.items():
        path = stubs / name
        path.write_text(f'#!{bash}\nset -euo pipefail\n'
                        'printf "%s\\n" "${0##*/}" >> "$TEST_CALLS"\n'
                        '[[ "${TEST_FAIL:-}" != "${0##*/}" ]] || exit 7\n' + body)
        path.chmod(0o700)
    env = dict(os.environ, PATH=f'{stubs}:{os.environ["PATH"]}', TMPDIR=str(temporary),
               TEST_CAPTURE=str(capture), TEST_CALLS=str(call_log))
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'TEST_FAIL'):
        env.pop(key, None)

    def run(data=b'', mimes='text/plain', state='data', fail=''):
        capture.unlink(missing_ok=True)
        call_log.unlink(missing_ok=True)
        result = subprocess.run([str(binary)], input=data, capture_output=True, timeout=15,
                                env=dict(env, TEST_MIMES=mimes, CLIPBOARD_STATE=state, TEST_FAIL=fail))
        notification = capture.read_bytes().split(b'\0')[:-1] if capture.exists() else None
        invoked = call_log.read_text().splitlines() if call_log.exists() else []
        assert not list(temporary.iterdir()), 'temporary file leaked'
        assert not result.stdout, 'unexpected stdout'
        return result, notification, invoked

    def preview(data, expected, **kwargs):
        result, args, calls = run(data, **kwargs)
        assert result.returncode == 0 and not result.stderr, result.stderr
        assert args == [b'-i', b'edit-copy', b'-t', b'2000', b'--', b'Copied to Clipboard:', expected.encode()], args
        return calls

    preview(b'', '')
    preview(b'hello\n\n', 'hello')
    preview(b'-n', '-n')
    preview(b'a\0b', 'ab')
    preview(b'<b>hello</b> & data', '&lt;b&gt;hello&lt;/b&gt; &amp; data')
    preview('Olá 中🙂'.encode(), 'Olá 中🙂', mimes='text/plain;charset=utf-8')
    preview(b'a\nb\nc\nd\ne', 'a\nb\nc\nd\ne')
    preview(b'a\nb\nc\nd\ne\nf\n', 'a\nb\nc\n[[ 2 more lines... ]]\nf')
    preview(b'x' * 1_000_000, 'x' * 4096 + '\n[Preview truncated]')
    preview(('🙂' * 5000).encode(), '🙂' * 4096 + '\n[Preview truncated]')
    preview(b'x' * (16 * 1024 * 1024 + 1), 'Clipboard content too large to preview (over 16 MiB)')
    binary_calls = preview(b'\x00\xff', '[[ 4.0K synthetic &lt;binary&gt; &amp; data, second ]]', mimes='application/octet-stream')
    assert binary_calls == ['wl-paste', 'du', 'file', 'notify-send']
    # Synthetic markers only. Sensitive payloads must never reach args or stderr,
    # nor require MIME queries, UTF-8 decoding, or temporary files.
    sensitive = b'SYNTHETIC_PRIVATE_MARKER\xff'
    assert preview(sensitive, 'Sensitive clipboard content hidden', state='sensitive') == ['notify-send']
    assert preview(sensitive, 'Sensitive clipboard content hidden', mimes='image/png\ntext/secret') == ['wl-paste', 'notify-send']
    result, args, calls = run(b'ignored', state='nil')
    assert result.returncode == 0 and args is None and not calls
    for helper, mimes in [('wl-paste', 'text/plain'), ('du', 'application/octet-stream'), ('file', 'application/octet-stream')]:
        result, args, calls = run(b'data', mimes=mimes, fail=helper)
        assert result.returncode != 0 and args is None, helper
    result, args, calls = run(b'data', fail='notify-send')
    assert result.returncode == 7 and args is None
    result, args, calls = run(b'\xff')
    assert result.returncode != 0 and args is None
    assert b'\xff' not in result.stderr
    # Independent, deterministic reference for ordinary UTF-8 previews.
    rng = random.Random(42)
    for _ in range(80):
        text = ''.join(rng.choices('abcáβ中🙂\n\r\t<> &\\', k=rng.randrange(300))).rstrip('\n')
        lines = text.split('\n')
        raw = text if len(lines) <= 5 else '\n'.join(lines[:3] + [f'[[ {len(lines) - 4} more lines... ]]', lines[-1]])
        expected = ''.join('�' if ord(ch) < 32 and ch not in '\n\t' else ch for ch in raw)
        expected = expected.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        preview(text.encode(), expected)
print('PASS: synthetic CLI previews, privacy, escaping, size limits, failures, and 80 generated cases')
