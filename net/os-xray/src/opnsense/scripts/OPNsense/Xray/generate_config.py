#!/usr/local/bin/python3
"""
generate_config.py - build /usr/local/etc/xray-os/config.json from the model.

Usage: generate_config.py [--preview]
  Reads /usr/local/etc/xray-os/model.json (dumped by the OPNsense template).
  --preview: print config JSON to stdout instead of writing + testing.
  Otherwise: write config.json, run `xray -test -c`, exit 0 on success.

Write discipline (P0-1/P0-2):
  - The write path takes a flock on /var/run/xray-os-gen.lock so two
    concurrent Applies (or Apply vs subscription refresh) cannot interleave.
  - Config is written to config.json.tmp, fsynced, validated with
    `xray -test -c <tmp>`, and only then atomically renamed over
    config.json. A failed test leaves the previous good config.json
    untouched (the old code wrote first and tested after, so a failed
    test left a broken config.json that killed the next service start).
  - Test/build failures persist to last_validation_error (shown as a
    banner on the settings page); success clears it.

Fail-closed (P0-3): an active_node uuid that no longer resolves to a
node is a hard build error, never a silent fallback to freedom/direct.

Fixed infrastructure inbounds (always present):
  hev-socks-in  127.0.0.1:10808  socks (udp, sniffing http/tls/quic routeOnly)
  dns-in        127.0.0.1:10853  dokodemo-door -> 1.1.1.1:53
  api           127.0.0.1:10085  dokodemo-door (xray stats/handler API, loopback only)
"""
import sys
import os
import json
import subprocess
import fcntl

CONF_DIR = '/usr/local/etc/xray-os'
MODEL_JSON = os.path.join(CONF_DIR, 'model.json')
CONFIG_JSON = os.path.join(CONF_DIR, 'config.json')
VALIDATION_ERROR = os.path.join(CONF_DIR, 'last_validation_error')
LOCK_FILE = '/var/run/xray-os-gen.lock'
XRAY_BIN = '/usr/local/bin/xray'
API_PORT = 10085


def load_model():
    with open(MODEL_JSON) as f:
        return json.load(f)


def iter_items(section):
    """Normalize an ArrayField section from the template dump.

    The OPNsense template engine dumps config.xml to a dict where a
    repeating tag is: missing when 0 items, a single dict (carrying
    @uuid) when 1 item, a list of dicts (each carrying @uuid) when 2+
    items. It NEVER produces a uuid-keyed dict, which is what the old
    code assumed: .items() on a list crashes, and on a single dict it
    iterates field names. Returns [(uuid, fields), ...] in document
    order. (The core's own helpers.toList exists for exactly this
    shape variance; model.json is a raw dump without it.)
    """
    if section is None:
        return []
    if isinstance(section, dict):
        return [(section.get('@uuid') or 'single', section)]
    if isinstance(section, list):
        out = []
        for i, item in enumerate(section):
            if isinstance(item, dict):
                out.append((item.get('@uuid') or f'item-{i}', item))
        return out
    return []


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
        {
            # xray stats/handler API entry (P0-6). Loopback only; the
            # routing section's first rule sends inboundTag "api" to the
            # api service. No pf change needed: local traffic never hits
            # LAN ingress rules.
            'tag': 'api',
            'protocol': 'dokodemo-door',
            'listen': '127.0.0.1',
            'port': API_PORT,
            'settings': {'address': '127.0.0.1'},
        },
    ]
    for _uuid, ib in iter_items((model.get('inbounds') or {}).get('inbound')):
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
    nodes = iter_items((model.get('nodes') or {}).get('node'))
    active = (model.get('general') or {}).get('active_node', '')
    outbounds = []
    active_out = None
    seen_tags = set()
    for uuid, nd in nodes:
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
    elif active:
        # Fail closed (P0-3): the active node uuid is set but resolves to
        # no node (stale reference, e.g. after a subscription refresh that
        # removed it). Falling back to freedom here would silently turn
        # ALL proxy traffic direct, so fail the build loudly instead.
        raise ValueError(
            f'active node {active} not found; pick a new active node')
    else:
        # no active node configured at all: proxy-default falls back to direct
        outbounds.append({'tag': 'proxy-default', 'protocol': 'freedom'})
    outbounds.append({'tag': 'direct', 'protocol': 'freedom'})
    outbounds.append({'tag': 'block', 'protocol': 'blackhole'})
    outbounds.append({'tag': 'dns-out', 'protocol': 'dns'})
    return outbounds


# Explicit xray domain match prefixes. A bare value gets `domain:` (P0-4):
# xray treats a bare domain entry as a SUBSTRING match, so `youtube.com`
# would also match `mynot-youtube.com.fake.tld`. mosdns treats a bare
# domain as a suffix (`domain:`) match, so normalize to the same semantic.
DOMAIN_PREFIXES = ('domain:', 'full:', 'keyword:', 'regexp:', 'geosite:')


def normalize_domain(value):
    v = (value or '').strip()
    if v.startswith(DOMAIN_PREFIXES):
        return v
    return 'domain:' + v


# Private ranges that never go through the proxy (P0-5, defense in depth:
# pf/mosdns already keep these off the tun, this is the xray-side backstop).
PRIVATE_CIDRS = [
    '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8',
    '::1/128', 'fc00::/7', 'fe80::/10',
]


def rule_order(rule):
    try:
        return int(rule.get('order') or 100)
    except (TypeError, ValueError):
        return 100


def build_routing(model):
    rules = []
    # api service entry must be first (P0-6)
    rules.append({
        'type': 'field',
        'inboundTag': ['api'],
        'outboundTag': 'api',
    })
    rules.append({
        'type': 'field',
        'inboundTag': ['dns-in'],
        'outboundTag': 'dns-out',
    })
    # System rules, always before user rules (P0-5):
    # - port 53 -> direct: xray's own DNS dialing goes through the routing
    #   engine too; without this, a catch-all -> proxy rule would drag DNS
    #   dialing into the tunnel and a node outage would kill all DNS.
    # - private ranges -> direct (see PRIVATE_CIDRS).
    rules.append({
        'type': 'field',
        'port': '53',
        'outboundTag': 'direct',
    })
    rules.append({
        'type': 'field',
        'ip': PRIVATE_CIDRS,
        'outboundTag': 'direct',
    })
    user_rules = [
        (uuid, r) for uuid, r in
        iter_items((model.get('rules') or {}).get('rule'))
        if r.get('enabled') == '1'
    ]
    # sort is stable: equal order values keep model insertion order
    user_rules.sort(key=lambda kv: rule_order(kv[1]))
    for _uuid, r in user_rules:
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
            entry['domain'] = [normalize_domain(v) for v in values]
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
        # stats/api/policy (P0-6): prerequisite for traffic stats, the
        # handler API (balancer override, statsquery) and sane timeouts.
        # connIdle 3600 replaces xray's 300s default, which kills pooled
        # idle connections on a gateway; the two system stats switches
        # are what make outbound traffic queryable at all.
        'stats': {},
        'api': {
            'tag': 'api',
            'services': ['StatsService', 'HandlerService', 'RoutingService'],
        },
        'policy': {
            'levels': {
                '0': {
                    'handshake': 10,
                    'connIdle': 3600,
                    'uplinkOnly': 0,
                    'downlinkOnly': 0,
                },
            },
            'system': {
                'statsOutboundUplink': True,
                'statsOutboundDownlink': True,
            },
        },
        'inbounds': build_inbounds(model),
        'outbounds': build_outbounds(model),
        'routing': build_routing(model),
    }


def persist_validation_error(text):
    try:
        os.makedirs(CONF_DIR, exist_ok=True)
        with open(VALIDATION_ERROR, 'w') as f:
            f.write(text)
    except OSError:
        pass


def clear_validation_error():
    try:
        os.remove(VALIDATION_ERROR)
    except OSError:
        pass


def acquire_gen_lock():
    fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o644)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def main():
    preview = '--preview' in sys.argv
    try:
        model = load_model()
    except Exception as e:
        print(f'cannot read model: {e}', file=sys.stderr)
        sys.exit(1)
    try:
        cfg = build_config(model)
    except Exception as e:
        # build failure (e.g. stale active node) is also an Apply failure:
        # surface it instead of a traceback, and never write a half config.
        print(f'cannot build config: {e}', file=sys.stderr)
        if not preview:
            persist_validation_error(f'cannot build config: {e}\n')
        sys.exit(1)
    text = json.dumps(cfg, indent=2, ensure_ascii=False)
    if preview:
        print(text)
        return
    os.makedirs(CONF_DIR, exist_ok=True)
    # held for the whole write+test+replace window, released on exit
    # (finally below) so a later in-process call cannot self-deadlock
    lock_fd = acquire_gen_lock()
    try:
        tmp = CONFIG_JSON + '.tmp'
        with open(tmp, 'w') as f:
            f.write(text + '\n')
            f.flush()
            os.fsync(f.fileno())
        # validate the temp file first; only a passing config replaces the live one
        if not os.path.exists(XRAY_BIN):
            print(f'{XRAY_BIN} not found, skipping test', file=sys.stderr)
            os.replace(tmp, CONFIG_JSON)
            clear_validation_error()
            print('OK')
            return
        r = subprocess.run([XRAY_BIN, '-test', '-c', tmp],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            # xray may report on stdout, stderr, or both; capture both,
            # otherwise the persisted error is empty exactly when the
            # detail is needed (seen on cloudopn: 'xray -test failed:'
            # with nothing after it).
            detail = ((r.stdout or '') + (r.stderr or ''))[-2000:]
            err = f'xray -test failed:\n{detail}'
            print(err, file=sys.stderr)
            persist_validation_error(err + '\n')
            try:
                os.remove(tmp)
            except OSError:
                pass
            sys.exit(1)
        os.replace(tmp, CONFIG_JSON)
        try:
            dfd = os.open(CONF_DIR, os.O_RDONLY)
            try:
                os.fsync(dfd)
            finally:
                os.close(dfd)
        except OSError:
            pass
        clear_validation_error()
        print('OK')
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass


if __name__ == '__main__':
    main()
