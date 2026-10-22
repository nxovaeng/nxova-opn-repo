#!/usr/local/bin/python3
"""
sync_rule_groups.py - convert the shared rule groups into xray routing rules.

The canonical rule store is owned by os-mosdns: plain-txt domain groups
(one rule per line: bare / domain: / full:, '#' comments) indexed by
/usr/local/etc/mosdns/rule/groups.json. This script converts the enabled
groups into xray routing rule entries and saves them in xray's own format:

/usr/local/etc/xray-os/group_rules.json
    [{"type": "field", "domain": [...], "outboundTag": "direct|block|proxy-default"}]

Conversion notes:
  bare domain  -> domain:<domain>   (a bare string in xray is a *substring*
                                     match, mosdns treats it as suffix match)
  domain:/full: are kept as-is; other prefixes are dropped.
Group order in the output: block groups, then direct, then proxy (the same
priority mosdns applies), manifest order within each type.
If the shared store does not exist (os-mosdns not installed), an empty
rule list is written.
"""
import json
import os
import sys

STORE_DIR = '/usr/local/etc/mosdns/rule'
MANIFEST = os.path.join(STORE_DIR, 'groups.json')
OUT = '/usr/local/etc/xray-os/group_rules.json'
OUTBOUND = {'direct': 'direct', 'proxy': 'proxy-default', 'block': 'block'}
ORDER = {'block': 0, 'direct': 1, 'proxy': 2}


def convert(lines):
    out = []
    for ln in lines:
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        low = s.lower()
        if low.startswith('domain:') or low.startswith('full:'):
            out.append(s)
        elif ':' in s:
            continue  # keyword:/regexp:/geosite: etc. are not shared-group syntax
        else:
            out.append('domain:' + s)
    return out


def main():
    rules = []
    try:
        with open(MANIFEST) as f:
            manifest = json.load(f)
    except Exception:
        manifest = {'groups': []}
    groups = [g for g in manifest.get('groups', []) if g.get('enabled')]
    groups.sort(key=lambda g: ORDER.get(g.get('type'), 3))
    for g in groups:
        rel = g.get('file') or ''
        if not rel:
            continue
        try:
            with open(os.path.join(STORE_DIR, rel)) as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        domains = convert(lines)
        if not domains:
            continue
        rules.append({
            'type': 'field',
            'domain': domains,
            'outboundTag': OUTBOUND.get(g.get('type'), 'proxy-default'),
        })
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(rules, f, ensure_ascii=False)
    os.replace(tmp, OUT)
    print(json.dumps({'result': 'ok', 'rules': len(rules),
                      'domains': sum(len(r['domain']) for r in rules)}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
