#!/usr/local/bin/python3
"""
import_nodes.py - parse proxy links (vless/vmess/trojan/ss) into node dicts.

Usage: import_nodes.py '<links>' '<sub_id>'
  links: newline separated proxy URLs (also accepts a subscription body:
         plain links per line or base64-encoded blob)
  sub_id: subscription uuid, or 'manual'

Output: JSON array of node dicts on stdout. Each dict has:
  tag, protocol, address, port, network, security, sni, path, params (JSON), sub_id
Exits non-zero with error on stderr if nothing parsed.
"""
import sys
import json
import base64
import html
import urllib.parse


def b64decode(s):
    s = s.strip().replace('-', '+').replace('_', '/')
    return base64.b64decode(s + '=' * (-len(s) % 4)).decode('utf-8', 'replace')


def stream_settings(query, default_sni, default_host):
    """Build xray streamSettings from URL query params."""
    net = (query.get('type') or query.get('net') or ['tcp'])[0].lower()
    sec = (query.get('security') or ['none'])[0].lower()
    sni = query.get('sni', query.get('serverName', ['']))[0] or default_sni
    path = query.get('path', [''])[0]
    # Host header fallback: explicit ?host= wins, else the TLS SNI, else
    # the address. Fronted deployments route by vhost: the address domain
    # is often not a valid vhost while the SNI domain is (proven on-box:
    # xhttp nodes failed with Host=address, worked with Host=SNI).
    host = query.get('host', [''])[0] or sni or default_host

    ss = {'network': net}
    if net == 'ws':
        ws = {'path': urllib.parse.unquote(path) or '/'}
        if host:
            ws['headers'] = {'Host': host}
        ss['wsSettings'] = ws
    elif net == 'xhttp':
        xh = {'path': urllib.parse.unquote(path) or '/'}
        if host:
            xh['host'] = host
        mode = (query.get('mode') or query.get('xhttp_mode') or [''])[0]
        if mode:
            xh['mode'] = mode
        ss['xhttpSettings'] = xh
    elif net == 'grpc':
        ss['grpcSettings'] = {
            'serviceName': query.get('serviceName', [''])[0],
            'multiMode': (query.get('mode') or [''])[0] == 'multi',
        }

    if sec == 'tls':
        tls = {'serverName': sni or default_host}
        fp = (query.get('fp') or [''])[0]
        if fp:
            tls['fingerprint'] = fp
        ss['security'] = 'tls'
        ss['tlsSettings'] = tls
    elif sec == 'reality':
        ss['security'] = 'reality'
        ss['realitySettings'] = {
            'serverName': sni or default_host,
            'fingerprint': (query.get('fp') or ['chrome'])[0],
            'publicKey': (query.get('pbk') or [''])[0],
            'shortId': (query.get('sid') or [''])[0],
            'spiderX': (query.get('spx') or [''])[0],
        }
    return ss


def flat_stream_fields(query, ss):
    """Structured (form-editable) copies of the stream/credential settings."""
    # the effective ws/xhttp host: explicit ?host= wins, stream_settings falls
    # back to the server address - mirror that so both build paths agree
    host = (query.get('host') or [''])[0]
    ws = ss.get('wsSettings') or {}
    if (ws.get('headers') or {}).get('Host'):
        host = ws['headers']['Host']
    xh = ss.get('xhttpSettings') or {}
    if xh.get('host'):
        host = xh['host']
    return {
        'host': host,
        'fingerprint': (query.get('fp') or [''])[0],
        'allow_insecure': '1' if (query.get('allowInsecure') or query.get('insecure') or ['0'])[0] == '1' else '0',
        'public_key': (query.get('pbk') or [''])[0],
        'short_id': (query.get('sid') or [''])[0],
        'spider_x': (query.get('spx') or [''])[0],
    }


def parse_vless(u, query, sub_id):
    uuid = urllib.parse.unquote(u.username or '')
    host = u.hostname or ''
    port = u.port or 443
    name = urllib.parse.unquote(u.fragment or f'{host}:{port}')
    ss = stream_settings(query, '', host)
    flow = (query.get('flow') or [''])[0]
    user = {'id': uuid, 'encryption': 'none'}
    if flow:
        user['flow'] = flow
    outbound = {
        'protocol': 'vless',
        'settings': {'vnext': [{'address': host, 'port': port, 'users': [user]}]},
        'streamSettings': ss,
    }
    # grpc carries its service name in the path slot of the form
    path = (query.get('path') or [''])[0]
    if ss['network'] == 'grpc':
        path = (query.get('serviceName') or [''])[0]
    node = {
        'tag': name, 'protocol': 'vless', 'address': host, 'port': port,
        'network': ss['network'], 'security': ss.get('security', 'none'),
        'sni': (ss.get('tlsSettings') or ss.get('realitySettings') or {}).get('serverName', ''),
        'path': path,
        'user_id': uuid, 'flow': flow,
        'params': json.dumps(outbound), 'sub_id': sub_id,
    }
    node.update(flat_stream_fields(query, ss))
    return node


def parse_vmess(link, sub_id):
    try:
        data = json.loads(b64decode(link[8:]))
    except Exception as e:
        raise ValueError(f'bad vmess link: {e}')
    host = data.get('add', '')
    port = int(data.get('port', 443))
    name = data.get('ps') or f'{host}:{port}'
    net = (data.get('net') or 'tcp').lower()
    tls = str(data.get('tls', '')).lower() in ('tls', '1', 'true')
    query = {
        'type': [net],
        'security': ['tls' if tls else 'none'],
        'sni': [data.get('sni') or data.get('host') or ''],
        'path': [data.get('path') or ''],
        'host': [data.get('host') or ''],
    }
    ss = stream_settings(query, '', host)
    outbound = {
        'protocol': 'vmess',
        'settings': {'vnext': [{'address': host, 'port': port, 'users': [{
            'id': data.get('id', ''), 'alterId': int(data.get('aid') or 0),
            'security': data.get('scy') or 'auto',
        }]}]},
        'streamSettings': ss,
    }
    return {
        'tag': name, 'protocol': 'vmess', 'address': host, 'port': port,
        'network': net, 'security': 'tls' if tls else 'none',
        'sni': data.get('sni') or '', 'path': data.get('path') or '',
        'user_id': data.get('id', ''), 'alter_id': str(data.get('aid') or 0),
        'vmess_cipher': data.get('scy') or 'auto',
        'host': ((ss.get('wsSettings') or {}).get('headers') or {}).get('Host') or data.get('host') or '',
        'allow_insecure': '1' if str(data.get('allowInsecure', '')).lower() in ('1', 'true') else '0',
        'params': json.dumps(outbound), 'sub_id': sub_id,
    }


def parse_trojan(u, query, sub_id):
    pwd = urllib.parse.unquote(u.username or '')
    host = u.hostname or ''
    port = u.port or 443
    name = urllib.parse.unquote(u.fragment or f'{host}:{port}')
    q = dict(query)
    q.setdefault('security', ['tls'])
    ss = stream_settings(q, '', host)
    outbound = {
        'protocol': 'trojan',
        'settings': {'servers': [{'address': host, 'port': port, 'password': pwd}]},
        'streamSettings': ss,
    }
    node = {
        'tag': name, 'protocol': 'trojan', 'address': host, 'port': port,
        'network': ss['network'], 'security': ss.get('security', 'tls'),
        'sni': (ss.get('tlsSettings') or {}).get('serverName', ''),
        'path': (query.get('path') or [''])[0],
        'password': pwd,
        'params': json.dumps(outbound), 'sub_id': sub_id,
    }
    node.update(flat_stream_fields(query, ss))
    return node


def parse_ss(u, sub_id):
    # ss://BASE64(method:password)@host:port#name  or  ss://BASE64(method:password@host:port)#name
    host, port, method, pwd, name = u.hostname, u.port, '', '', ''
    userinfo = u.username or ''
    try:
        decoded = b64decode(userinfo)
        if '@' in decoded and not host:
            # whole thing was encoded
            creds, _, hp = decoded.rpartition('@')
            method, _, pwd = creds.partition(':')
            host, _, p = hp.partition(':')
            port = int(p or 8388)
        else:
            method, _, pwd = decoded.partition(':')
    except Exception:
        pass
    if not host:
        raise ValueError('bad ss link')
    name = urllib.parse.unquote(u.fragment or f'{host}:{port}')
    outbound = {
        'protocol': 'shadowsocks',
        'settings': {'servers': [{
            'address': host, 'port': port, 'method': method,
            'password': pwd, 'uot': True,
        }]},
    }
    return {
        'tag': name, 'protocol': 'shadowsocks', 'address': host, 'port': port,
        'network': 'tcp', 'security': 'none', 'sni': '', 'path': '',
        'password': pwd, 'ss_method': method,
        'params': json.dumps(outbound), 'sub_id': sub_id,
    }


def parse_link(link, sub_id):
    # The quick-import path passes links through PHP/configd, which
    # HTML-escapes '&' to '&amp;'; parse_qs would then see keys like
    # 'amp;security' and drop every param after the first. Undo the
    # escaping here so both import paths parse identically (the
    # subscription path pipes via stdin and never sees it).
    link = html.unescape(link.strip())
    if not link:
        return None
    scheme = link.split('://', 1)[0].lower()
    if scheme == 'vmess':
        return parse_vmess(link, sub_id)
    u = urllib.parse.urlparse(link)
    query = urllib.parse.parse_qs(u.query)
    if scheme == 'vless':
        return parse_vless(u, query, sub_id)
    if scheme == 'trojan':
        return parse_trojan(u, query, sub_id)
    if scheme == 'ss':
        return parse_ss(u, sub_id)
    raise ValueError(f'unsupported scheme: {scheme}')


def main():
    if len(sys.argv) < 3:
        print('usage: import_nodes.py <links|/dev/stdin> <sub_id>', file=sys.stderr)
        sys.exit(2)
    blob = sys.argv[1]
    sub_id = sys.argv[2]
    # allow reading subscription body from a file or stdin pipe
    if blob == '/dev/stdin':
        blob = sys.stdin.read()
    elif '\n' not in blob and '://' not in blob:
        try:
            with open(blob) as f:
                blob = f.read()
        except OSError:
            pass
    # subscription bodies may be base64-encoded
    lines = [l for l in blob.splitlines() if l.strip()]
    if len(lines) == 1 and '://' not in lines[0]:
        try:
            blob = b64decode(lines[0])
            lines = [l for l in blob.splitlines() if l.strip()]
        except Exception:
            pass
    nodes, errors = [], []
    for line in lines:
        line = line.strip()
        if not line or '://' not in line:
            continue
        try:
            n = parse_link(line, sub_id)
            if n:
                nodes.append(n)
        except Exception as e:
            errors.append(f'{line[:40]}: {e}')
    if not nodes:
        print('no nodes parsed' + (f'; errors: {errors}' if errors else ''), file=sys.stderr)
        sys.exit(1)
    print(json.dumps(nodes, ensure_ascii=False))


if __name__ == '__main__':
    main()
