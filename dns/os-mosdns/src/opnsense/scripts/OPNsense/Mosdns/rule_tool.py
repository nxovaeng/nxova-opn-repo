#!/usr/local/bin/python3
"""
rule_tool.py - mosdns rule file management and domain test simulator.

Usage:
  rule_tool.py list
  rule_tool.py get <name>
  rule_tool.py set <name>   (reads content from stdin)
  rule_tool.py test <domain>

Rule files live in /usr/local/etc/mosdns/rule/.
Editable: custom-direct.txt, custom-proxy.txt, custom-block.txt
Read-only: cn.txt, gfw.txt
"""
import sys
import os
import json

RULE_DIR = '/usr/local/etc/mosdns/rule'
EDITABLE = {'custom-direct.txt', 'custom-proxy.txt', 'custom-block.txt'}
ALL_FILES = ['cn.txt', 'gfw.txt', 'custom-direct.txt', 'custom-proxy.txt', 'custom-block.txt']


def load_rules(path):
    rules = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                rules.append(line)
    except OSError:
        pass
    return rules


def match_domain(domain, rules):
    """Return (matched_rule, kind) or (None, None). kind: full/domain."""
    domain = domain.lower().strip()
    # strip scheme/path/port
    for prefix in ('https://', 'http://'):
        if domain.startswith(prefix):
            domain = domain[len(prefix):]
    domain = domain.split('/')[0].split(':')[0]
    for rule in rules:
        r = rule.lower()
        if r.startswith('full:'):
            if domain == r[5:]:
                return rule, 'full'
        elif r.startswith('domain:'):
            pat = r[7:]
            if domain == pat or domain.endswith('.' + pat):
                return rule, 'domain'
        else:
            # bare domain = suffix match
            if domain == r or domain.endswith('.' + r):
                return rule, 'domain'
    return None, None


def cmd_list():
    result = []
    for name in ALL_FILES:
        path = os.path.join(RULE_DIR, name)
        rules = load_rules(path)
        try:
            st = os.stat(path)
            mtime, size = int(st.st_mtime), st.st_size
        except OSError:
            mtime, size = 0, 0
        result.append({
            'name': name,
            'editable': name in EDITABLE,
            'count': len(rules),
            'mtime': mtime,
            'size': size,
        })
    print(json.dumps(result))


def cmd_get(name):
    if name not in ALL_FILES:
        print(f'unknown file: {name}', file=sys.stderr)
        sys.exit(1)
    path = os.path.join(RULE_DIR, name)
    try:
        with open(path) as f:
            sys.stdout.write(f.read())
    except OSError as e:
        print(f'cannot read: {e}', file=sys.stderr)
        sys.exit(1)


def cmd_install(name, staging):
    """Install a rule file from a staging path (written by the PHP API)."""
    if name not in EDITABLE:
        print(f'file is read-only: {name}', file=sys.stderr)
        sys.exit(1)
    # staging must be under /tmp to avoid path tricks
    staging = os.path.abspath(staging)
    if not staging.startswith('/tmp/'):
        print('staging path must be under /tmp', file=sys.stderr)
        sys.exit(1)
    with open(staging) as f:
        content = f.read()
    # normalize: LF, strip blank lines
    lines = []
    for line in content.replace('\r\n', '\n').split('\n'):
        line = line.strip()
        if line:
            lines.append(line)
    path = os.path.join(RULE_DIR, name)
    os.makedirs(RULE_DIR, exist_ok=True)
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n' if lines else '')
    os.unlink(staging)
    print('OK')


def cmd_test(domain):
    # load config mode from a JSON file dumped by template (or defaults)
    mode = 'whitelist'
    fallback = 'proxy'
    block_enabled = True
    cfg_path = '/usr/local/etc/mosdns/mode.json'
    try:
        with open(cfg_path) as f:
            cfg = json.load(f)
            mode = cfg.get('mode', mode)
            fallback = cfg.get('custom_default_route', fallback)
            block_enabled = cfg.get('block_enabled', '1') == '1'
    except OSError:
        pass

    direct_rules = []
    proxy_rules = []
    block_rules = []
    for name in ['cn.txt', 'custom-direct.txt']:
        direct_rules += load_rules(os.path.join(RULE_DIR, name))
    for name in ['gfw.txt', 'custom-proxy.txt']:
        proxy_rules += load_rules(os.path.join(RULE_DIR, name))
    block_rules = load_rules(os.path.join(RULE_DIR, 'custom-block.txt'))

    result = {'domain': domain, 'mode': mode}
    if block_enabled:
        m, kind = match_domain(domain, block_rules)
        if m:
            result.update({'action': 'block', 'matched_file': 'custom-block.txt',
                           'matched_rule': m, 'explain': f'命中阻止名单 ({kind}匹配)，直接拒绝'})
            print(json.dumps(result, ensure_ascii=False))
            return

    dm, dkind = match_domain(domain, direct_rules)
    pm, pkind = match_domain(domain, proxy_rules)

    if mode == 'whitelist':
        if dm:
            result.update({'action': 'direct', 'matched_file': 'direct list',
                           'matched_rule': dm, 'explain': f'命中直连名单 ({dkind}匹配)，走本地上游'})
        else:
            result.update({'action': 'proxy', 'matched_file': None,
                           'matched_rule': None, 'sync_pf': True,
                           'explain': '白名单模式：未命中直连名单，走远端代理并同步到 pf 表'})
    elif mode == 'blacklist':
        if pm:
            result.update({'action': 'proxy', 'matched_file': 'proxy list',
                           'matched_rule': pm, 'sync_pf': True,
                           'explain': f'命中代理名单 ({pkind}匹配)，走远端代理并同步到 pf 表'})
        else:
            result.update({'action': 'direct', 'matched_file': None,
                           'matched_rule': None,
                           'explain': '黑名单模式：未命中代理名单，走本地上游'})
    else:  # custom
        if dm:
            result.update({'action': 'direct', 'matched_file': 'direct list',
                           'matched_rule': dm, 'explain': f'命中直连名单 ({dkind}匹配)，走本地上游'})
        elif pm:
            result.update({'action': 'proxy', 'matched_file': 'proxy list',
                           'matched_rule': pm, 'sync_pf': True,
                           'explain': f'命中代理名单 ({pkind}匹配)，走远端代理并同步到 pf 表'})
        else:
            fb = fallback
            result.update({'action': fb, 'matched_file': None, 'matched_rule': None,
                           'sync_pf': fb == 'proxy',
                           'explain': f'混合模式：未命中任何名单，按兜底走{"远端代理" if fb == "proxy" else "本地上游"}'})
    print(json.dumps(result, ensure_ascii=False))


def main():
    if len(sys.argv) < 2:
        print('usage: rule_tool.py list|get|set|test ...', file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == 'list':
        cmd_list()
    elif cmd == 'get' and len(sys.argv) == 3:
        cmd_get(sys.argv[2])
    elif cmd == 'install' and len(sys.argv) == 4:
        cmd_install(sys.argv[2], sys.argv[3])
    elif cmd == 'test' and len(sys.argv) == 3:
        cmd_test(sys.argv[2])
    else:
        print('bad arguments', file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
