#!/usr/bin/env python3
"""Exercise CLI routing against an isolated HTTP runtime; no apps or simulators."""
import http.server
import json
import pathlib
import subprocess
import sys
import threading
import time
import urllib.parse

cli = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/loupe').resolve())
screen = {'size': {'width': 400, 'height': 800}, 'scale': 2}
identity = {'launchID': 'cli-contract', 'startedAt': '2026-01-01T00:00:00Z',
            'platform': 'macOS', 'bundleIdentifier': 'fixture.app', 'processIdentifier': 1}
requests = []
ax_status = 200
status_delay = 0
snapshot_delay = 0
wait_snapshot = {
    'id': 'wait-snapshot', 'capturedAt': '2026-01-01T00:00:00Z',
    'screen': screen, 'rootRefs': ['wait-node'],
    'nodes': {
        'wait-node': {
            'ref': 'wait-node', 'kind': 'view', 'typeName': 'FixtureView',
            'testID': 'wait.node', 'isVisible': True, 'isEnabled': True,
            'isInteractive': False, 'children': []
        }
    }
}


class Runtime(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        requests.append(('GET', self.path))
        url = urllib.parse.urlsplit(self.path)
        status, body = 500, {'error': 'snapshot_unavailable'}
        if url.path == '/status':
            time.sleep(status_delay)
            status, body = 200, {'identity': identity, 'retainedLogCount': 0}
        elif url.path == '/snapshot':
            time.sleep(snapshot_delay)
            status, body = 200, wait_snapshot
        elif url.path == '/observation':
            status, body = 200, {'fixture': 'compact'}
        elif url.path == '/accessibility':
            node = {'ref': 'ax-native', 'sourceRef': 'native-owner', 'role': 'button',
                    'label': 'Open', 'testID': 'native.button', 'traits': [],
                    'isVisible': True, 'isEnabled': True, 'isInteractive': True, 'children': []}
            status, body = ax_status, {'snapshotID': 'ax', 'screen': screen,
                                       'rootRefs': [node['ref']], 'nodes': {node['ref']: node}}
        elif url.path == '/accessibility/action-observation':
            frame = {'x': 10, 'y': 10, 'width': 100, 'height': 40}
            node = {'ref': 'ax-native', 'sourceRef': 'native-owner', 'role': 'button',
                    'label': 'Open', 'testID': 'native.button', 'traits': [], 'frame': frame,
                    'isVisible': True, 'isEnabled': True, 'isInteractive': True, 'children': [],
                    'actions': [{'name': 'press'}]}
            snapshot = {'id': 'action', 'capturedAt': '2026-01-01T00:00:00Z',
                        'screen': screen, 'rootRefs': [], 'nodes': {}}
            tree = {'snapshotID': 'action', 'screen': screen,
                    'rootRefs': [node['ref']], 'nodes': {node['ref']: node}}
            status, body = 200, {'snapshot': snapshot, 'tree': tree}
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def do_POST(self):
        requests.append(('POST', self.path))
        # Simulate a transport failure after the server may have applied a write.
        self.close_connection = True


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Runtime)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
host = 'http://127.0.0.1:' + str(server.server_port)


def run(arguments):
    requests.clear()
    return subprocess.run([cli] + arguments + ['--host', host],
                          capture_output=True, text=True, timeout=15)


try:
    for command in [
        ['app', 'info'], ['ui', 'snapshot'], ['ui', 'report'],
        ['ui', 'set', '--test-id', 'target', 'alpha', '--number', '0.5'],
        ['ui', 'set-many', '--refs', 'n1', 'alpha', '--number', '0.5'],
        ['debug', 'defaults', 'set', 'example.key', '--bool', 'true'],
        ['ui', 'appearance', 'dark'],
    ]:
        result = run(command + ['--bundle-id', 'other.app'])
        assert result.returncode != 0 and 'bundle mismatch' in result.stderr, (command, result.stderr)
        assert requests == [('GET', '/status')], (command, requests)

    result = run(['ui', 'compact'])
    assert result.returncode == 0 and json.loads(result.stdout)['fixture'] == 'compact', result.stderr
    assert requests == [('GET', '/observation')], requests

    result = run(['ui', 'tree', '--accessibility', '--include-hidden'])
    assert result.returncode == 0 and 'native.button' in result.stdout, result.stderr
    assert requests == [('GET', '/accessibility?includeHidden=true')], requests

    result = run(['ui', 'query', '--tree', 'accessibility', '--test-id', 'native.button'])
    assert result.returncode == 0 and len(json.loads(result.stdout)) == 1, result.stderr
    assert requests == [('GET', '/accessibility')], requests

    result = run(['ui', 'accessibility', '--include-hidden'])
    assert result.returncode == 0 and 'ax-native' in json.loads(result.stdout)['nodes'], result.stderr
    assert requests == [('GET', '/accessibility?includeHidden=true')], requests

    result = run(['ui', 'query', '--tree', 'accessibility', '--test-id', 'never', '--wait', '--timeout', '0.3'])
    assert result.returncode != 0 and 'timed out' in result.stderr, result.stderr

    snapshot_delay = 3.2
    result = run(['act', 'wait', 'visible', '--test-id', 'wait.node', '--timeout', '5'])
    assert result.returncode == 0 and 'wait-node' in result.stdout, result.stderr
    assert requests == [('GET', '/snapshot')], requests

    snapshot_delay = 0.8
    started = time.monotonic()
    result = run(['act', 'wait', 'visible', '--test-id', 'wait.node', '--timeout', '0.3'])
    assert result.returncode != 0 and 'timed out' in result.stderr, result.stderr
    assert time.monotonic() - started < 0.7, 'wait exceeded its overall timeout'
    assert requests == [('GET', '/snapshot')], requests
    snapshot_delay = 0

    result = run(['act', 'targets', '--search', 'native.button'])
    assert result.returncode == 0 and '#1' in result.stdout, result.stderr
    assert requests == [('GET', '/status'), ('GET', '/accessibility/action-observation')], requests

    result = run(['debug', 'defaults', 'set', 'example.key', '--bool', 'true'])
    assert result.returncode != 0 and 'may already have run' in result.stderr, result.stderr
    assert any(method == 'POST' for method, _ in requests), requests

    ax_status = 503
    result = run(['ui', 'tree', '--accessibility'])
    assert result.returncode != 0 and 'HTTP 503' in result.stderr, result.stderr
    assert requests == [('GET', '/accessibility')], requests
    status_delay = 0.8
    started = time.monotonic()
    result = run(['act', 'targets', '--bundle-id', 'fixture.app', '--timeout', '0.05'])
    assert result.returncode != 0 and 'timed out' in result.stderr, result.stderr
    assert time.monotonic() - started < 0.6, 'runtime selection ignored --timeout'
    assert requests == [('GET', '/status')], requests
    print('CLI contract checks passed: runtime identity, live accessibility, action capture, timeout, and error propagation')
finally:
    server.shutdown()
    server.server_close()
    thread.join()
