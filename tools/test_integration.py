#!/usr/bin/env python3
"""Exercise the packaged local demo using isolated ports and temporary progress state.
Build first: cd backend && mvn package
Run from any directory: python3 tools/test_integration.py
No API key or external AI calls are used. All child servers are stopped on exit.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def request(base, path, method='GET'):
    req = urllib.request.Request(base + path, method=method)
    with urllib.request.urlopen(req, timeout=100) as response:
        return json.load(response)


def wait_ready(base, path, processes, timeout=120):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if any(p.poll() is not None for p in processes):
            raise RuntimeError('A demo server exited during startup')
        try:
            return request(base, path)
        except (urllib.error.URLError, ConnectionError):
            time.sleep(0.5)
    raise TimeoutError(base + path)


def main():
    jar = ROOT / 'backend/target/wealth-tree-backend-0.1.0.jar'
    if not jar.exists():
        raise RuntimeError('Build backend first: cd backend && mvn package')
    ports = set()
    while len(ports) < 3:
        ports.add(free_port())
    bridge_port, backend_port, frontend_port = sorted(ports)
    bridge, backend, frontend = [f'http://127.0.0.1:{p}' for p in (bridge_port, backend_port, frontend_port)]
    java = str(Path(os.environ['JAVA_HOME']) / 'bin/java') if os.environ.get('JAVA_HOME') else 'java'
    processes = []
    with tempfile.TemporaryDirectory(prefix='wealth-tree-check-') as temporary:
        log_path = Path(temporary) / 'servers.log'
        with log_path.open('w+') as log:
            try:
                commands = [
                    [sys.executable, str(ROOT / 'backend/tools/kairos_server.py'), '--agent-dir',
                     str(ROOT / 'prediction-agent'), '--port', str(bridge_port)],
                    [java, '-jar', str(jar), f'--server.port={backend_port}',
                     f'--wealthtree.agent.url={bridge}', f'--wealthtree.state-file={temporary}/state.ser'],
                    [sys.executable, '-m', 'http.server', str(frontend_port), '--bind', '127.0.0.1',
                     '--directory', str(ROOT / 'projects-section')],
                ]
                for command in commands:
                    processes.append(subprocess.Popen(command, cwd=temporary,
                        env={**os.environ, 'HIP_API_KEY': ''}, stdout=log, stderr=log))
                wait_ready(bridge, '/health', processes)
                wait_ready(backend, '/api/users', processes)
                subprocess.run([sys.executable, str(ROOT / 'tools/check_demo.py'),
                    '--bridge', bridge, '--backend', backend, '--frontend', frontend], check=True)
                base = '/api/users/maya'
                original = request(backend, base + '/intake')
                mapping = request(backend, base + '/actions/mapping')['limit_eating_out']
                assert mapping['canCommit']
                for alias in ('limit_eating_out', 'act-limit-eating_out', 'start_buffer', 'income_protection_check'):
                    request(backend, base + '/actions/' + alias + '/commit', 'POST')
                progress = request(backend, base + '/progress')
                assert len(progress['actions']) == 3, 'Alias and canonical commitment duplicated'
                limit = next(a for a in progress['actions'] if a['actionId'] == 'act-limit-eating_out')
                assert limit['monthlyAmount'] == mapping['action']['monthlyAmount']
                try:
                    request(backend, base + '/actions/write_will/commit', 'POST')
                    raise AssertionError('Unsupported action was accepted')
                except urllib.error.HTTPError as error:
                    assert error.code == 404
                request(backend, base + '/advance-month?months=3', 'POST')
                progress = request(backend, base + '/progress')
                assert all(a['status'] == 'VERIFIED' for a in progress['actions']), progress
                changed = request(backend, base + '/intake')
                assert changed != original
                assert changed['has_buffer_plan'] and changed['disability_cover']
                kairos = request(backend, base + '/kairos?wait=120')
                scenarios = {s['id'] for s in kairos['engine']['scenarios']}
                assert 'buffer' not in scenarios and 'cover' not in scenarios, scenarios
                assert not request(backend, base + '/actions/mapping')['income_protection_check']['canCommit']
                dropped = request(backend, base + '/actions/limit_eating_out/drop', 'POST')
                assert next(a for a in dropped['actions'] if a['actionId'] == 'act-limit-eating_out')['status'] == 'DROPPED'
                request(backend, '/api/demo/reset', 'POST')
                assert request(backend, base + '/intake') == original
                assert not request(backend, base + '/progress')['actions']
                print('PASS: alias commit, deduplication, verification, scenario refresh, drop and reset')
            except Exception:
                log.flush()
                print(log_path.read_text()[-12000:], file=sys.stderr)
                raise
            finally:
                for process in processes:
                    process.terminate()
                for process in processes:
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    main()
