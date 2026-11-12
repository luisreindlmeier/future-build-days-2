#!/usr/bin/env python3
"""Read-only smoke check for the local three-component demo (standard library only)."""
import argparse
import json
import sys
import time
import urllib.request


def get(url, timeout=100):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.load(response)


def check(args):
    health = get(args.bridge + '/health')
    assert health['ok'], health
    print(f"Bridge: engine {health['engine_version']}; key configured: {health['live_ai']}")
    for user in ('lena', 'alex', 'maya', 'max'):
        base = args.backend + '/api/users/' + user
        deadline = time.monotonic() + args.timeout
        while True:
            result = get(base + '/prediction')
            if result['status'] == 'READY':
                break
            if time.monotonic() >= deadline:
                raise RuntimeError(f"{user}: {result['status']}: {result.get('error')}")
            time.sleep(1)
        kairos = get(base + '/kairos')
        assert all(k in kairos for k in ('intake', 'engine', 'prediction_agent', 'action_agent')), user
        assert kairos['intake']['wealth_total'] == result['intake']['wealth_total'], user
        mappings = get(base + '/actions/mapping')
        assert mappings['limit_eating_out']['backendActionId'] == 'act-limit-eating_out', user
        assert not mappings['write_will']['canCommit'], user
        for mapping in mappings.values():
            if mapping['canCommit']:
                assert mapping['action']['id'] == mapping['backendActionId'], user
        print(f"{user}: READY; prediction={result['prediction']['source']}; "
              f"actions={result['actions']['source']}; FinPulse and mappings OK")
    with urllib.request.urlopen(args.frontend + '/index.html', timeout=10) as response:
        assert response.status == 200
    print('Projects page: HTTP 200 (browser AI needs a separate manual check)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', default='http://localhost:8080')
    parser.add_argument('--bridge', default='http://localhost:8090')
    parser.add_argument('--frontend', default='http://localhost:5500')
    parser.add_argument('--timeout', type=float, default=120, help='seconds to wait per customer')
    try:
        check(parser.parse_args())
    except Exception as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
