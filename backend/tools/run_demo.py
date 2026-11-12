#!/usr/bin/env python3
"""Run the connected local demo. Ctrl+C stops all three servers."""
import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--components', type=Path, required=True, help='folder containing prediction-agent and projects-section')
parser.add_argument('--api-port', type=int, default=8080)
parser.add_argument('--bridge-port', type=int, default=8091)
parser.add_argument('--web-port', type=int, default=5500)
args = parser.parse_args()
components = args.components.resolve()
java = str(Path(os.environ['JAVA_HOME']) / 'bin/java') if os.environ.get('JAVA_HOME') else 'java'
jar = ROOT / 'target/wealth-tree-backend-0.1.0.jar'
if not jar.exists() or not shutil.which('node'):
    parser.error('Build the backend jar first (mvn package) and install Node.js.')
for directory in ('prediction-agent', 'projects-section'):
    if not (components / directory).is_dir():
        parser.error('Missing component: ' + directory)
run = ROOT / 'data/run'
run.mkdir(parents=True, exist_ok=True)
commands = [
    ('bridge', [sys.executable, '-u', str(ROOT / 'tools/kairos_server.py'),
       '--agent-dir', str(components / 'prediction-agent'), '--projects-dir', str(components / 'projects-section'),
       '--env-file', str(ROOT / '.env'), '--port', str(args.bridge_port)]),
    ('backend', [java, '-jar', str(jar), f'--server.port={args.api_port}', '--server.address=127.0.0.1',
       f'--wealthtree.agent.url=http://localhost:{args.bridge_port}']),
    ('projects', [sys.executable, '-u', str(ROOT / 'tools/serve_projects.py'),
       '--directory', str(components / 'projects-section'), '--port', str(args.web_port)]),
]
processes = []

def stop(signum, frame):
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, stop)
try:
    # Fail before starting anything if a requested port is already occupied.
    import socket
    for port in (args.api_port, args.bridge_port, args.web_port):
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)   # closing connections are fine; a live server is not
            sock.bind(('127.0.0.1', port))
    for name, command in commands:
        with (run / (name + '.log')).open('a') as log:
            p = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        (run / (name + '.pid')).write_text(str(p.pid))
        processes.append(p)
    print(f'Open http://localhost:{args.web_port}/index.html?customer=http://localhost:{args.api_port}/api/users/maya/kairos', flush=True)
    print(f'One API key: {ROOT / ".env"}; logs: {run}', flush=True)
    while all(p.poll() is None for p in processes):
        time.sleep(0.5)
    raise RuntimeError('A service exited. Inspect data/run/*.log.')
except KeyboardInterrupt:
    pass
finally:
    for p in processes:
        p.terminate()
    for p in processes:
        try:
            p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
