#!/usr/local/bin/python3
"""
generate_config.py - build /usr/local/etc/xray-os/config.json from the model.

Usage: generate_config.py [--preview]
  Reads /usr/local/etc/xray-os/model.json (dumped by the OPNsense template).
  --preview: print config JSON to stdout instead of writing + testing.
  Otherwise: write config.json, run `xray -test -c`, exit 0 on success.

Fixed infrastructure inbounds (always present):
  hev-socks-in  127.0.0.1:10808  socks (udp, sniffing http/tls/quic routeOnly)
  dns-in        127.0.0.1:10853  dokodemo-door -> 1.1.1.1:53
"""
import sys
import os
import json
import subprocess

CONF_DIR = '/usr/local/etc/xray-os'
MODEL_JSON = os.path.join(CONF_DIR, 'model.json')
CONFIG_JSON = os.path.join(CONF_DIR, 'config.json')
XRAY_BIN = '/usr/local/bin/xray'


def load_model():
    with open(MODEL_JSON) as f:
        return json.load(f)


def sniffing_obj():
    # object form (never the bool!) - see sniffing bool bug in old controller
    return {
        'enabled': True,
        'destOverride': ['http', 'tls', 'quic'],
        'routeOnly': True,
    }


def build_inbounds(model):
    inbounds = [
        {
            'tag': 'hev-socks-in',
            'protocol': 'socks',
            'listen': '127.0.0.1',
            'port': 10808,
            'settings': {'auth': 'noauth', 'udp': True},
            'sniffing': sniffing_obj(),
        },
        {
            'tag': 'dns-in',
            'protocol': 'dokodemo-door',
            'listen': '127.0.0.1',
            'port': 10853,
            'settings': {'address': '1.1.1.1', 'port': 53, 'networks': ['tcp', 'udp']},
        },
    ]
    for _uuid, ib in (model.get('inbounds') or {}).get('inbound', {}).items():
        if ib.get('enabled') != '1':
            continue
        entry = {
            'tag': ib.get('tag') or f'in-{ib.get("port")}x',
            'protocol': ib.get('protocol') or 'socks',
            'listen': ib.get('listen') or '127.0.0.1',
            'port': int(ib.get('port') or 0),
            'settings': {'udp': True},
            'sniffing': sniffing_obj() if ib.get('sniffing') == '1' else {'enabled': False},
        }
        if ib.get('username'):
            entry['settings'] = {
                'auth': 'password',
                'accounts': [{'user': ib['username'], 'pass': ib.get('password', '')}],
                'udp': True,
            }
        else:
            entry['settings']['auth'] = 'noauth'
        inbounds.append(entry)
    return inbounds


def build_stream(nd):
    """xray streamSettings from the node's structured stream fields."""
    net = (nd.get('network') or 'tcp').lower()
    sec = (nd.get('security') or 'none').lower()
    sni = nd.get('sni') or ''
    path = nd.get('path') or ''
    host = nd.get('host') or ''
    ss = {'network': net}
    if net == 'ws':
        ws = {'path': path or '/'}
        if host:
            ws['headers'] = {'Host': host}
        ss['wsSettings'] = ws
    elif net == 'xhttp':
        xh = {'path': path or '/'}
        if host:
            xh['host'] = host
        ss['xhttpSettings'] = xh
    elif net == 'grpc':
        ss['grpcSettings'] = {'serviceName': path, 'multiMode': False}
    if sec == 'tls':
        tls = {'serverName': sni}
        if nd.get('allow_insecure') == '1':
            tls['allowInsecure'] = True
        if nd.get('fingerprint'):
            tls['fingerprint'] = nd['fingerprint']
        ss['security'] = 'tls'
        ss['tlsSettings'] = tls
    elif sec == 'reality':
        ss['security'] = 'reality'
        ss['realitySettings'] = {
            'serverName': sni,
            'fingerprint': nd.get('fingerprint') or 'chrome',
            'publicKey': nd.get('public_key') or '',
            'shortId': nd.get('short_id') or '',
            'spiderX': nd.get('spider_x') or '',
        }
    return ss


def structured_ready(nd):
    """True when the node's credential field for its protocol is filled;
    then the structured fields are authoritative over the legacy params JSON."""
    proto = (nd.get('protocol') or '').lower()
    if proto in ('vless', 'vmess'):
        return bool(nd.get('user_id'))
    if proto in ('trojan', 'shadowsocks'):
        return bool(nd.get('password'))
    return False


def build_outbound_from_fields(nd):
    proto = (nd.get('protocol') or '').lower()
    addr = nd.get('address') or ''
    try:
        port = int(nd.get('port') or 0)
    except (TypeError, ValueError):
        port = 0
    if not proto or not addr or not port:
        return None
    ss = build_stream(nd)
    if proto == 'vless':
        user = {'id': nd.get('user_id') or '', 'encryption': 'none'}
        if nd.get('flow'):
            user['flow'] = nd['flow']
        return {'protocol': 'vless',
                'settings': {'vnext': [{'address': addr, 'port': port, 'users': [user]}]},
                'streamSettings': ss}
    if proto == 'vmess':
        try:
            alter = int(nd.get('alter_id') or 0)
        except (TypeError, ValueError):
            alter = 0
        user = {'id': nd.get('user_id') or '', 'alterId': alter,
                'security': nd.get('vmess_cipher') or 'auto'}
        return {'protocol': 'vmess',
                'settings': {'vnext': [{'address': addr, 'port': port, 'users': [user]}]},
                'streamSettings': ss}
    if proto == 'trojan':
        return {'protocol': 'trojan',
                'settings': {'servers': [{'address': addr, 'port': port,
                                          'password': nd.get('password') or ''}]},
                'streamSettings': ss}
    if proto == 'shadowsocks':
        return {'protocol': 'shadowsocks',
                'settings': {'servers': [{'address': addr, 'port': port,
                                          'method': nd.get('ss_method') or 'aes-256-gcm',
                                          'password': nd.get('password') or '',
                                          'uot': True}]}}
    return None


def build_outbounds(model):
    nodes = (model.get('nodes') or {}).get('node', {})
    active = (model.get('general') or {}).get('active_node', '')
    outbounds = []
    active_out = None
    seen_tags = set()
    for uuid, nd in nodes.items():
        if nd.get('enabled') != '1':
            continue
        ob = None
        if structured_ready(nd):
            ob = build_outbound_from_fields(nd)
        if ob is None:
            # legacy path: full outbound stored in params (imported nodes)
            try:
                ob = json.loads(nd.get('params') or '{}')
            except Exception:
                continue
            if not ob.get('protocol'):
                continue
        tag = nd.get('tag') or f'node-{uuid[:8]}'
        # dedupe tags
        base, i = tag, 2
        while tag in seen_tags:
            tag = f'{base}-{i}'
            i += 1
        seen_tags.add(tag)
        ob['tag'] = tag
        outbounds.append(ob)
        if uuid == active:
            active_out = dict(ob)
            active_out['tag'] = 'proxy-default'
    if active_out:
        outbounds.append(active_out)
    else:
        # no active node: proxy-default falls back to direct
        outbounds.append({'tag': 'proxy-default', 'protocol': 'freedom'})
    outbounds.append({'tag': 'direct', 'protocol': 'freedom'})
    outbounds.append({'tag': 'block', 'protocol': 'blackhole'})
    outbounds.append({'tag': 'dns-out', 'protocol': 'dns'})
    return outbounds


def build_routing(model):
    rules = []
    rules.append({
        'type': 'field',
        'inboundTag': ['dns-in'],
        'outboundTag': 'dns-out',
    })
    for _uuid, r in (model.get('rules') or {}).get('rule', {}).items():
        if r.get('enabled') != '1':
            continue
        values = [v.strip() for v in (r.get('values') or '').split(',') if v.strip()]
        if not values:
            continue
        entry = {
            'type': 'field',
            'outboundTag': r.get('outbound_tag') or 'proxy-default',
        }
        rtype = (r.get('type') or 'domain')
        if rtype == 'ip':
            entry['ip'] = values
        elif rtype == 'source':
            entry['source'] = values
        elif rtype == 'port':
            # xray port matcher is one string: "53,80,443" or ranges "1000-2000"
            entry['port'] = ','.join(values)
        else:
            entry['domain'] = values
        rules.append(entry)
    rules.append({
        'type': 'field',
        'network': 'tcp,udp',
        'outboundTag': 'proxy-default',
    })
    return {
        'domainStrategy': (model.get('general') or {}).get('domain_strategy') or 'AsIs',
        'rules': rules,
    }


def build_config(model):
    general = model.get('general') or {}
    dns_servers = [s.strip() for s in (general.get('dns_servers') or '').split(',') if s.strip()]
    return {
        'log': {'loglevel': general.get('log_level') or 'warning'},
        'dns': {
            'servers': dns_servers or ['tcp://1.1.1.1:53'],
            'queryStrategy': 'UseIP',
        },
        'inbounds': build_inbounds(model),
        'outbounds': build_outbounds(model),
        'routing': build_routing(model),
    }


def main():
    preview = '--preview' in sys.argv
    try:
        model = load_model()
    except Exception as e:
        print(f'cannot read model: {e}', file=sys.stderr)
        sys.exit(1)
    cfg = build_config(model)
    text = json.dumps(cfg, indent=2, ensure_ascii=False)
    if preview:
        print(text)
        return
    os.makedirs(CONF_DIR, exist_ok=True)
    with open(CONFIG_JSON, 'w') as f:
        f.write(text + '\n')
    # validate
    if not os.path.exists(XRAY_BIN):
        print(f'{XRAY_BIN} not found, skipping test', file=sys.stderr)
        print('OK')
        return
    r = subprocess.run([XRAY_BIN, '-test', '-c', CONFIG_JSON],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        print(f'xray -test failed:\n{r.stderr[-2000:]}', file=sys.stderr)
        sys.exit(1)
    print('OK')


if __name__ == '__main__':
    main()
