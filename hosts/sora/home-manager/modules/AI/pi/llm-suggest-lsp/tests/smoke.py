"""Synthetic stdio contract tests; never touches the real suggestion state or editor."""
import json
import os
from pathlib import Path
import queue
import random
import subprocess
import sys
import tempfile
import threading
import time


def frame(message):
    body = json.dumps(message, ensure_ascii=False).encode()
    return f'Content-Length: {len(body)}\r\n\r\n'.encode() + body


class Client:
    def __init__(self, binary, state, file, override=True):
        env = dict(os.environ, HOME=str(state), XDG_STATE_HOME=str(state))
        env.pop('LLM_SUGGEST_FILE', None)
        if override:
            env['LLM_SUGGEST_FILE'] = str(file)
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS'):
            env.pop(key, None)
        self.serial = 0
        self.messages = queue.Queue()
        self.notifications = []
        self.stderr = tempfile.TemporaryFile()
        self.process = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.stderr, env=env, cwd=state)
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        try:
            while True:
                headers = {}
                while True:
                    line = self.process.stdout.readline()
                    if not line:
                        raise EOFError('unexpected LSP EOF')
                    if line == b'\r\n':
                        break
                    key, value = line.decode().split(':', 1)
                    headers[key.lower()] = value.strip()
                body = self.process.stdout.read(int(headers['content-length']))
                self.messages.put(json.loads(body))
        except Exception as error:
            self.messages.put(error)

    def get(self):
        message = self.messages.get(timeout=5)
        if isinstance(message, Exception):
            raise message
        return message

    def send(self, method, params=None, request=False):
        message = {'jsonrpc': '2.0', 'method': method, 'params': params or {}}
        if request:
            self.serial += 1
            message['id'] = self.serial
        self.process.stdin.write(frame(message))
        self.process.stdin.flush()

    def request(self, method, params=None):
        self.send(method, params, request=True)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            message = self.get()
            if message.get('id') == self.serial:
                assert 'error' not in message, message
                return message['result']
            self.notifications.append(message)
        raise AssertionError('request timed out')

    def diagnostics(self, uri, expected):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            for i, message in enumerate(self.notifications):
                if (message.get('method') == 'textDocument/publishDiagnostics'
                    and message['params'] == {'uri': uri, 'diagnostics': expected}):
                    self.notifications.pop(i)
                    return
            self.notifications.append(self.get())
        raise AssertionError('diagnostics timed out')

    def close(self, eof=False):
        try:
            if not eof:
                assert self.request('shutdown') is None
                self.send('exit')
            self.process.stdin.close()
            status = self.process.wait(timeout=5)
            self.stderr.seek(0)
            assert status == 0, self.stderr.read().decode(errors='replace')
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.process.stdin.close()
            self.process.stdout.close()
            self.reader.join(timeout=2)
            self.stderr.close()


def matches(request, action):
    def pos(p):
        return p['line'], p['character']
    a, b = pos(request['start']), pos(request['end'])
    x, y = pos(action['start']), pos(action['end'])
    return x <= a < y if a == b else a < y and x < b


def check(binary, state, file, override):
    document = state / 'synthetic space # 中.rs'
    document.write_text('synthetic\n')
    alias = state / 'alias.rs'
    alias.symlink_to(document)
    uri = document.as_uri()
    r = {'start': {'line': 2, 'character': 0}, 'end': {'line': 3, 'character': 0}}
    item = {'id': 'first', 'file': str(document), 'message': 'Olá 中🙂',
            'replacement': 'new\n', 'wholeLine': True,
            'range': {'start': {'line': 2, 'character': 5}, 'end': {'line': 2, 'character': 8}}}
    diag = {'range': r, 'severity': 3, 'source': 'llm-suggest',
            'message': item['message'], 'data': {'id': 'first'}}
    action = {'title': 'LLM: Olá 中🙂', 'kind': 'quickfix', 'isPreferred': False,
              'diagnostics': [diag], 'edit': {'changes': {uri: [{'range': r, 'newText': 'new\n'}]}},
              'command': {'title': 'Clear LLM suggestion', 'command': 'llm-suggest.clearSuggestion',
                          'arguments': ['first']}}
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps([item]))
    client = Client(binary, state, file, override)
    try:
        initialized = client.request('initialize')
        assert initialized == {'capabilities': {'textDocumentSync': 1,
            'codeActionProvider': {'codeActionKinds': ['quickfix']},
            'executeCommandProvider': {'commands': ['llm-suggest.clearSuggestion']}},
            'serverInfo': {'name': 'llm-suggest-lsp', 'version': '0.1.0'}}
        client.send('initialized')
        base = {'textDocument': {'uri': uri}}
        client.send('textDocument/didOpen', base)
        client.diagnostics(uri, [diag])
        assert client.request('textDocument/codeAction', base) == [action]
        rng = random.Random(42)
        ranges = [{'start': {'line': n, 'character': 0}, 'end': {'line': n, 'character': 0}} for n in range(6)]
        for _ in range(60):
            a, b = sorted(rng.sample(range(8), 2))
            ranges.append({'start': {'line': a, 'character': 1}, 'end': {'line': b, 'character': 1}})
        for requested in ranges:
            assert client.request('textDocument/codeAction', dict(base, range=requested)) == ([action] if matches(requested, r) else [])
        for id, expected in [('first', [action]), ('missing', [])]:
            context = {'diagnostics': [{'data': {'id': id}}]}
            assert client.request('textDocument/codeAction', dict(base, context=context)) == expected
        alias_action = json.loads(json.dumps(action))
        alias_action['edit']['changes'] = {alias.as_uri(): action['edit']['changes'][uri]}
        assert client.request('textDocument/codeAction', {'textDocument': {'uri': alias.as_uri()}}) == [alias_action]
        assert client.request('textDocument/codeAction', {'textDocument': {'uri': 'untitled:test'}}) == []
        client.send('textDocument/didChange', base)
        client.diagnostics(uri, [diag])
        assert client.request('workspace/executeCommand', {'command': 'llm-suggest.clearSuggestion', 'arguments': ['first']}) is None
        assert json.loads(file.read_text()) == []
        client.diagnostics(uri, [])
        client.notifications.clear()
        old_mtime = file.stat().st_mtime_ns
        file.write_text(json.dumps([item]))
        now = max(time.time_ns(), old_mtime + 1000)
        os.utime(file, ns=(now, now))
        client.diagnostics(uri, [diag])  # Poll-only update, no editor notification.
        for payload in ('{broken', '{}'):
            file.write_text(payload)
            assert client.request('textDocument/codeAction', base) == []
        file.unlink()
        assert client.request('textDocument/codeAction', base) == []
        client.diagnostics(uri, [])
        client.send('textDocument/didClose', base)
        client.diagnostics(uri, [])
        assert client.request('synthetic/unknown') is None
        client.process.stdin.write(b'Content-Length: 1\r\n\r\n{')
        body = b'{"jsonrpc":"2.0","id":"split","method":"unknown"}'
        packet = f'content-length: {len(body)}\r\nContent-Type: application/vscode-jsonrpc\r\n\r\n'.encode() + body
        for part in (packet[:5], packet[5:17], packet[17:]):
            client.process.stdin.write(part)
            client.process.stdin.flush()
        while True:
            message = client.get()
            if message.get('id') == 'split':
                assert message['result'] is None
                break
    finally:
        client.close()


binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='llm-suggest-smoke-') as directory:
    state = Path(directory)
    for override, name in [(True, 'override'), (False, 'default')]:
        home = state / name
        home.mkdir()
        file = home / ('custom.json' if override else 'llm-suggest/suggestions.json')
        check(binary, home, file, override)
    client = Client(binary, state, state / 'missing.json')
    assert client.request('initialize')['serverInfo']['name'] == 'llm-suggest-lsp'
    client.close(eof=True)
print('PASS: LSP stdio, diagnostics, actions/ranges, state paths, watcher, clearing, framing and clean shutdown')
