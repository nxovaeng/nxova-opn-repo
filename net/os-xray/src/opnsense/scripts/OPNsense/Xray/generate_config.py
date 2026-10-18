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


def build_outbounds(model):
    nodes = (model.get('nodes') or {}).get('node', {})
    active = (model.get('general') or {}).get('active_node', '')
    outbounds = []
    active_out = None
    seen_tags = set()
    for uuid, nd in nodes.items():
        if nd.get('enabled') != '1':
            continue
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
        if (r.get('type') or 'domain') == 'ip':
            entry['ip'] = values
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
