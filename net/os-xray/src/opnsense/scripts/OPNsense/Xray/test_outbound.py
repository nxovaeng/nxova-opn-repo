#!/usr/local/bin/python3
"""Probe one site through the live xray path and report up/down + latency.

Runs curl (HEAD, so no page body is downloaded) through
socks5h://127.0.0.1:10808 (the fixed tun2socks-in inbound) against
the chosen site. The probe walks the live config: traffic matching
a user rule follows that rule's outbound, otherwise it takes the
default outbound (proxy-default = the active node). Always exits 0
and prints one JSON object so the controller can pass it straight
through.

Usage: test_outbound.py [site]
  site: google (default), github, youtube, aliyun, qq, youku.
  Any other value falls back to google.
"""
import json
import os
import subprocess
import sys

PROXY = 'socks5h://127.0.0.1:10808'
USER_AGENT = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/124.0 Safari/537.36')
TIMEOUT = 15

SITES = {
    'google': 'https://www.google.com/generate_204',
    'github': 'https://github.com',
    'youtube': 'https://www.youtube.com',
    'aliyun': 'https://www.aliyun.com',
    'qq': 'https://www.qq.com',
    'youku': 'https://www.youku.com',
}


def find_curl():
    for p in ('/usr/local/bin/curl', '/usr/bin/curl'):
        if os.path.exists(p):
            return p
    return 'curl'


def main():
    site = sys.argv[1] if len(sys.argv) > 1 else 'google'
    url = SITES.get(site, SITES['google'])
    try:
        r = subprocess.run(
            [find_curl(), '-s', '-I', '-o', '/dev/null',
             '-w', '%{http_code} %{time_total}',
             '-A', USER_AGENT,
             '--proxy', PROXY, '--max-time', str(TIMEOUT), url],
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
    if r.returncode == 0 and 200 <= code < 400:
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
