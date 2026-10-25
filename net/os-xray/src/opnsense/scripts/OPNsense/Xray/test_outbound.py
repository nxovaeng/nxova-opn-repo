#!/usr/local/bin/python3
"""Probe the live xray default outbound path and report up/down + latency.

Runs curl through socks5h://127.0.0.1:10808 (the fixed tun2socks-in
inbound) against a 204 endpoint. The probe walks the live config:
traffic matching a user rule follows that rule's outbound, otherwise
it takes proxy-default (the active node). Always exits 0 and prints
one JSON object so the controller can pass it straight through.
"""
import json
import os
import subprocess

PROXY = 'socks5h://127.0.0.1:10808'
URL = 'https://www.google.com/generate_204'
TIMEOUT = 15


def find_curl():
    for p in ('/usr/local/bin/curl', '/usr/bin/curl'):
        if os.path.exists(p):
            return p
    return 'curl'


def main():
    try:
        r = subprocess.run(
            [find_curl(), '-s', '-o', '/dev/null', '-w', '%{http_code} %{time_total}',
             '--proxy', PROXY, '--max-time', str(TIMEOUT), URL],
            capture_output=True, text=True, timeout=TIMEOUT + 5)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(json.dumps({'ok': False, 'http_code': 0, 'ms': 0,
                          'error': f'探针执行失败：{e}'}))
        return
    parts = (r.stdout or '').strip().split()
    code, total = 0, 0.0
    if len(parts) >= 2:
        try:
            code = int(parts[0])
        except ValueError:
            code = 0
        try:
            total = float(parts[1])
        except ValueError:
            total = 0.0
    ms = round(total * 1000)
    if r.returncode == 0 and code in (200, 204):
        print(json.dumps({'ok': True, 'http_code': code, 'ms': ms, 'error': ''}))
        return
    if r.returncode == 7:
        detail = 'xray 未运行或 socks 入站未监听（连接被拒）'
    else:
        lines = (r.stderr or '').strip().splitlines()
        detail = lines[-1] if lines else f'HTTP {code}'
    print(json.dumps({'ok': False, 'http_code': code, 'ms': ms, 'error': detail}))


if __name__ == '__main__':
    main()
