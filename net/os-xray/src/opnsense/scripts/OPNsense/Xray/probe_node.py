#!/usr/local/bin/python3
"""Probe one node as a single egress: egress IP + download speed.

A temporary xray config is built with a socks inbound on a loopback port
and that node as the ONLY outbound. Both probes share this one temp
config (and one temp xray process, terminated afterwards):
  - egress IP: curl via socks5h to the selected probe endpoint
    (default Cloudflare trace, which answers ip= and loc= from the
    egress network, so ip/loc are the node's exit identity, not the
    gateway's; plain-IP endpoints return just the IP, no loc).
  - download speed: curl via socks5h to
    https://speed.cloudflare.com/__down?bytes=10000000 (10 MB),
    report speed_download as Mbps. A timeout with partial bytes still
    yields a usable average speed.
The temp xray is terminated and the temp dir removed in all cases.
This is an on-demand, single-node probe (no bulk probing, so no
rate-limit concern on the echo/speed endpoints).

Usage: probe_node.py '<json node fields>' [endpoint-key]
  endpoint-key: cloudflare (default), ifconfig, ipify, ipsb, ipinfo,
    checkip, icanhazip.
Output: one JSON object {ok, ip, loc, trace_ms, speed_mbps, error}.
Always exits 0 so the controller can pass it straight through.
Error handling: the probe URL's final HTTP status must be 2xx
(redirects are followed) and the parsed IP must be a valid IPv4 or
IPv6 address, so an error page (e.g. a 403 HTML body) is reported
as a failure instead of surfacing as a bogus egress IP.
"""
import ipaddress
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_config import (  # noqa: E402
    XRAY_ASSET_DIR,
    XRAY_BIN,
    build_outbound_from_fields,
    structured_ready,
)

# endpoint key -> (url, parser): 'trace' parses ip=/loc= lines,
# 'plain' takes the body itself as the IP (no loc), 'json' parses an
# ip.sb-style geoip object (ip + country_code as loc).
PROBE_ENDPOINTS = {
    'cloudflare': ('https://www.cloudflare.com/cdn-cgi/trace', 'trace'),
    'ifconfig': ('https://ifconfig.me', 'plain'),
    'ipify': ('https://api.ipify.org', 'plain'),
    'ipsb': ('https://api.ip.sb/geoip', 'json'),
    'ipinfo': ('https://ipinfo.io/json', 'json'),
    'checkip': ('https://checkip.amazonaws.com', 'plain'),
    'icanhazip': ('https://icanhazip.com', 'plain'),
}
SPEED_URL = 'https://speed.cloudflare.com/__down?bytes=10000000'
TRACE_TIMEOUT = 10
SPEED_TIMEOUT = 15
START_TIMEOUT = 10


def find_curl():
    for p in ('/usr/local/bin/curl', '/usr/bin/curl'):
        if os.path.exists(p):
            return p
    return 'curl'


def free_port():
    s = socket.socket()
    try:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]
    finally:
        s.close()


def parse_trace(text):
    """Return (ip, loc) from a cdn-cgi/trace body, '' when absent."""
    ip, loc = '', ''
    for line in (text or '').splitlines():
        if line.startswith('ip='):
            ip = line[3:].strip()
        elif line.startswith('loc='):
            loc = line[4:].strip()
    return ip, loc


def is_ip(s):
    try:
        ipaddress.ip_address((s or '').strip())
        return True
    except ValueError:
        return False


def parse_probe_body(kind, body):
    """Return (ip, loc, error); error is '' on success.

    Every body is validated: an error page (e.g. a 403 HTML body)
    must never surface as an egress IP.
    """
    if kind == 'plain':
        stripped = (body or '').strip()
        token = stripped.split()[0] if stripped else ''
        if not token:
            return '', '', '端点返回为空'
        if not is_ip(token):
            return '', '', '端点返回内容不是 IP'
        return token, '', ''
    if kind == 'json':
        try:
            data = json.loads(body or '')
        except ValueError:
            return '', '', '端点返回内容不是 JSON'
        if not isinstance(data, dict):
            return '', '', '端点返回内容不是 JSON 对象'
        ip = str(data.get('ip') or '')
        loc = str(data.get('country_code') or data.get('country') or '')
        if not ip:
            return '', '', 'JSON 中未找到 ip'
        if not is_ip(ip):
            return '', '', 'JSON 中的 ip 格式无效'
        return ip, loc, ''
    ip, loc = parse_trace(body)
    if not ip:
        return '', '', 'trace 中未找到 ip'
    if not is_ip(ip):
        return '', '', 'trace 中的 ip 格式无效'
    return ip, loc, ''


def build_probe_config(nd):
    """Return (config dict, port) or (None, 0) when no outbound builds."""
    ob = None
    if structured_ready(nd):
        ob = build_outbound_from_fields(nd)
    if ob is None:
        try:
            ob = json.loads(nd.get('params') or '{}')
        except Exception:
            ob = None
        if not ob or not ob.get('protocol'):
            return None, 0
    ob['tag'] = 'probe-node'
    port = free_port()
    cfg = {
        'log': {'loglevel': 'warning'},
        'dns': {'servers': ['1.1.1.1']},
        'inbounds': [{
            'tag': 'probe-in',
            'port': port,
            'listen': '127.0.0.1',
            'protocol': 'socks',
            'settings': {'auth': 'noauth', 'udp': True},
        }],
        'outbounds': [ob],
    }
    return cfg, port


def wait_for_port(port, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.create_connection(('127.0.0.1', port), timeout=1)
            s.close()
            return True
        except OSError:
            time.sleep(0.2)
    return False


def run_curl(args, timeout):
    return subprocess.run(
        [find_curl()] + args,
        capture_output=True, text=True, timeout=timeout + 5)


def main():
    try:
        nd = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    except Exception:
        nd = {}
    endpoint_key = sys.argv[2] if len(sys.argv) > 2 else 'cloudflare'
    trace_url, trace_kind = PROBE_ENDPOINTS.get(
        endpoint_key, PROBE_ENDPOINTS['cloudflare'])
    cfg, port = build_probe_config(nd)
    if cfg is None:
        print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': 0,
                          'speed_mbps': None, 'error': '节点出站构建失败'}))
        return
    tmpdir = tempfile.mkdtemp(prefix='xray-probe-')
    proc = None
    try:
        cfg_path = os.path.join(tmpdir, 'config.json')
        with open(cfg_path, 'w') as f:
            json.dump(cfg, f)
        err_path = os.path.join(tmpdir, 'xray.err')
        env = dict(os.environ)
        env['XRAY_LOCATION_ASSET'] = XRAY_ASSET_DIR
        with open(err_path, 'wb') as errf:
            proc = subprocess.Popen(
                [XRAY_BIN, 'run', '-c', cfg_path],
                stdout=errf, stderr=subprocess.STDOUT, env=env)
        proxy = 'socks5h://127.0.0.1:%d' % port
        if not wait_for_port(port, START_TIMEOUT):
            tail = ''
            try:
                with open(err_path, 'rb') as f:
                    tail = f.read().decode('utf-8', 'replace')[-200:].strip()
            except OSError:
                pass
            print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': 0,
                              'speed_mbps': None,
                              'error': '临时 xray 未能启动' + ('：' + tail if tail else '')}))
            return
        try:
            r = run_curl(['-s', '-L', '-w', '\n%{http_code} %{time_total}',
                          '--proxy', proxy,
                          '--max-time', str(TRACE_TIMEOUT), trace_url],
                         TRACE_TIMEOUT)
        except (OSError, subprocess.TimeoutExpired):
            print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': 0,
                              'speed_mbps': None, 'error': '出口 IP 探测执行失败'}))
            return
        body, _, last = (r.stdout or '').rpartition('\n')
        code, total = '', ''
        parts = (last or '').strip().split()
        if len(parts) >= 2:
            code, total = parts[0], parts[1]
        try:
            trace_ms = round(float(total) * 1000)
        except ValueError:
            trace_ms = 0
        if r.returncode != 0:
            detail = (r.stderr or '').strip().splitlines()
            print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': trace_ms,
                              'speed_mbps': None,
                              'error': detail[-1] if detail else '出口 IP 探测执行失败'}))
            return
        if code and not code.startswith('2'):
            print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': trace_ms,
                              'speed_mbps': None,
                              'error': '探测端点返回 HTTP %s' % code}))
            return
        ip, loc, parse_err = parse_probe_body(trace_kind, body)
        if parse_err:
            print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': trace_ms,
                              'speed_mbps': None, 'error': parse_err}))
            return
        speed_mbps = None
        try:
            r = run_curl(['-s', '-o', '/dev/null', '-w', '%{speed_download}',
                          '--proxy', proxy, '--max-time', str(SPEED_TIMEOUT),
                          SPEED_URL], SPEED_TIMEOUT)
            try:
                bps = float((r.stdout or '').strip())
                if bps > 0:
                    speed_mbps = round(bps * 8 / 1e6, 1)
            except ValueError:
                speed_mbps = None
        except (OSError, subprocess.TimeoutExpired):
            speed_mbps = None
        print(json.dumps({'ok': True, 'ip': ip, 'loc': loc, 'trace_ms': trace_ms,
                          'speed_mbps': speed_mbps, 'error': ''}))
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(json.dumps({'ok': False, 'ip': '', 'loc': '', 'trace_ms': 0,
                          'speed_mbps': None, 'error': f'探针异常：{e}'}))
