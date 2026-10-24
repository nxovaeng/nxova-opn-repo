#!/usr/local/bin/python3
"""
rule_tool.py - mosdns rule group management and domain test simulator.

Rule groups are the canonical store: one plain-txt domain list per group
under /usr/local/etc/mosdns/rule/groups/. There is NO merge step: the
generated mosdns config lists every enabled group's file directly in the
matching domain_set (mosdns unions any number of files itself), so this
tool only validates content at write time (local groups: strict; remote
fetches: sanitized), keeps the files present, and exports groups.json.

Usage:
  rule_tool.py prepare <manifest.json>   ensure group files + groups.json
  rule_tool.py test <domain> <manifest.json>
  rule_tool.py get_group <uuid> <source>
  rule_tool.py install_group <uuid> <staging>
  rule_tool.py fetch_group <uuid> <url>
  rule_tool.py delete_group <uuid>
  rule_tool.py group_counts
  rule_tool.py export <manifest.json>
  rule_tool.py validate                  (content on stdin)
"""
import sys
import os
import json
import re

RULE_DIR = '/usr/local/etc/mosdns/rule'


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
        if r.startswith('regexp:'):
            try:
                if re.search(rule[7:], domain):
                    return rule, 'regexp'
            except re.error:
                pass
            continue
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





# domain label: 1-63 chars, alnum + hyphen, not leading/trailing hyphen
_LABEL_RE = r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'
_DOMAIN_RE = re.compile(rf'^{_LABEL_RE}(?:\.{_LABEL_RE})+$', re.IGNORECASE)


def validate_rule(line, lineno):
    """Return an error string for an invalid rule line, or None if OK."""
    s = line.strip()
    if not s or s.startswith('#'):
        return None
    low = s.lower()
    if low.startswith('regexp:'):
        # mosdns' domain matcher supports regexp natively; just make sure
        # the pattern compiles (lists like Loyalsoldier's ship a few).
        pat = s[7:]
        if not pat or len(pat) > 512:
            return f'line {lineno}: empty or overlong regexp'
        try:
            re.compile(pat)
        except re.error as e:
            return f'line {lineno}: invalid regexp: {e}'
        return None
    if low.startswith('full:'):
        dom, kind = s[5:], 'full'
    elif low.startswith('domain:'):
        dom, kind = s[7:], 'domain'
    else:
        dom, kind = s, 'domain'  # bare domain = suffix match (single-label
        # TLD entries like 'cn' are unsupported: far too broad, dropped)
    if not dom:
        return f'line {lineno}: empty domain'
    if '://' in s or '/' in dom:
        return f'line {lineno}: must not contain scheme or path: {s}'
    if ':' in dom:
        return f'line {lineno}: must not contain port: {s}'
    if ' ' in dom or '\t' in dom:
        return f'line {lineno}: must not contain whitespace: {s}'
    if not _DOMAIN_RE.match(dom):
        return f'line {lineno}: invalid domain "{dom}"'
    return None


def validate_content(content):
    """Validate full file content. Returns list of error strings (empty = valid)."""
    errors = []
    for i, line in enumerate(content.replace('\r\n', '\n').split('\n'), 1):
        err = validate_rule(line, i)
        if err:
            errors.append(err)
    return errors


def sanitize_content(content):
    """Drop lines outside the supported rule format (for REMOTE lists:
    upstream lists are third-party data, a few bad lines must not reject
    the whole file -- and must never reach mosdns, which exits on a bad
    rule line). Returns (cleaned_content, dropped_lines). Comments and
    blank lines are kept (inert); local group content is NOT sanitized,
    it stays strictly validated so typos surface as errors."""
    kept, dropped, converted = [], [], []
    for line in content.replace('\r\n', '\n').split('\n'):
        t = line.strip()
        if not t or t.startswith('#'):
            if t:
                kept.append(t)
            continue
        if t.startswith('*.') and validate_rule('domain:' + t[2:], 0) is None:
            # wildcard is exactly a suffix match: *.wild.com == domain:wild.com
            kept.append('domain:' + t[2:])
            converted.append(t)
            continue
        if validate_rule(t, 0) is None:
            kept.append(t)
        else:
            dropped.append(t)
    return ('\n'.join(kept) + ('\n' if kept else '')), dropped, converted


def cmd_validate():
    """Read content from stdin, print validation result as JSON."""
    content = sys.stdin.read()
    errors = validate_content(content)
    if errors:
        print(json.dumps({'result': 'failed', 'errors': errors}, ensure_ascii=False))
        sys.exit(1)
    print(json.dumps({'result': 'ok', 'errors': []}))


# ---------------------------------------------------------------------------
# Rule groups: the canonical store. Each group is a plain-txt domain list
# (bare / domain: / full:, '#' comments) with metadata (name, type, tags,
# source, enabled) kept in the OPNsense model and passed in as a manifest.
#   local group content : rule/groups/<uuid>.txt
#   remote group cache  : rule/groups/<uuid>.cache.txt  (last good fetch)
# The generated mosdns config lists each enabled group's file directly
# in its (source, type) domain_set; custom (local) sets outrank sync
# (remote) sets in the config sequence, so local rules can override stale
# or ill-fitting remote lists. No merge step exists or is needed.
# Rule groups are a mosdns-only, coarse-grained facility: they only
# decide direct/proxy/block at DNS level.
# ---------------------------------------------------------------------------

GROUPS_DIR = os.path.join(RULE_DIR, 'groups')
MANIFEST_OUT = os.path.join(RULE_DIR, 'groups.json')
_UUID_RE = re.compile(r'^[A-Za-z0-9-]{1,64}$')


def group_paths(uuid):
    if not _UUID_RE.match(uuid or ''):
        raise ValueError(f'bad group uuid: {uuid!r}')
    return (os.path.join(GROUPS_DIR, uuid + '.txt'),
            os.path.join(GROUPS_DIR, uuid + '.cache.txt'))


def group_content_path(entry):
    local_p, cache_p = group_paths(entry['uuid'])
    return cache_p if entry.get('source') == 'remote' else local_p


def read_text(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def count_rules(content):
    if not content:
        return 0
    return sum(1 for ln in content.splitlines()
               if ln.strip() and not ln.strip().startswith('#'))


def cmd_get_group(uuid, source):
    local_p, cache_p = group_paths(uuid)
    path = cache_p if source == 'remote' else local_p
    content = read_text(path)
    try:
        mtime = int(os.stat(path).st_mtime)
    except OSError:
        mtime = 0
    print(json.dumps({'result': 'ok', 'exists': content is not None,
                      'content': content or '', 'mtime': mtime,
                      'count': count_rules(content)}, ensure_ascii=False))


def cmd_install_group(uuid, staging):
    """Install a local group's content from a staging file (validated first)."""
    local_p, _ = group_paths(uuid)
    staging = os.path.abspath(staging)
    if not staging.startswith('/tmp/'):
        print('staging path must be under /tmp', file=sys.stderr)
        sys.exit(1)
    with open(staging) as f:
        content = f.read()
    errors = validate_content(content)
    if errors:
        print(json.dumps({'result': 'failed', 'errors': errors}, ensure_ascii=False))
        return
    os.makedirs(GROUPS_DIR, exist_ok=True)
    with open(local_p, 'w') as f:
        f.write(content.replace('\r\n', '\n'))
    os.unlink(staging)
    print('OK')


def cmd_fetch_group(uuid, url):
    """Fetch a remote group's txt into its cache. Never clobbers a good
    cache with a failed or invalid download."""
    import urllib.request
    _, cache_p = group_paths(uuid)
    if not (url.startswith('https://') or url.startswith('http://')):
        print(json.dumps({'result': 'failed', 'error': 'url must be http(s)'}, ensure_ascii=False))
        return
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'os-mosdns rule fetcher'})
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read(8 * 1024 * 1024 + 1)
        if len(raw) > 8 * 1024 * 1024:
            raise ValueError('file too large (>8MB)')
        content = raw.decode('utf-8', 'replace')
    except Exception as e:
        print(json.dumps({'result': 'failed', 'error': f'fetch failed: {e}'}, ensure_ascii=False))
        return
    cleaned, dropped, converted = sanitize_content(content)
    if count_rules(cleaned) == 0:
        print(json.dumps({'result': 'failed',
                          'error': 'no valid rules after dropping unsupported lines',
                          'dropped': len(dropped)}, ensure_ascii=False))
        return
    os.makedirs(GROUPS_DIR, exist_ok=True)
    with open(cache_p, 'w') as f:
        f.write(cleaned)
    print(json.dumps({'result': 'ok', 'count': count_rules(cleaned),
                      'dropped': len(dropped), 'dropped_sample': dropped[:5],
                      'converted': len(converted)},
                     ensure_ascii=False))


def cmd_delete_group(uuid):
    for p in group_paths(uuid):
        try:
            os.unlink(p)
        except OSError:
            pass
    print('OK')


def load_manifest(staging):
    staging = os.path.abspath(staging)
    if not staging.startswith('/tmp/'):
        print('staging path must be under /tmp', file=sys.stderr)
        sys.exit(1)
    with open(staging) as f:
        manifest = json.load(f)
    os.unlink(staging)
    if not isinstance(manifest, list):
        print('manifest must be a list', file=sys.stderr)
        sys.exit(1)
    return manifest


def export_manifest(manifest):
    """Write rule/groups.json: the exported index of the group store."""
    import time
    groups = []
    for g in manifest:
        path = group_content_path(g)
        content = read_text(path)
        groups.append({
            'uuid': g.get('uuid', ''),
            'name': g.get('name', ''),
            'type': g.get('type', 'direct'),
            'tags': [t.strip() for t in (g.get('tags') or '').split(',') if t.strip()],
            'source': g.get('source', 'local'),
            'url': g.get('url', ''),
            'enabled': g.get('enabled') in ('1', 1, True),
            'file': os.path.relpath(path, RULE_DIR),
            'count': count_rules(content),
        })
    data = {'version': 1, 'generated': int(time.time()), 'groups': groups}
    os.makedirs(RULE_DIR, exist_ok=True)
    tmp = MANIFEST_OUT + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, MANIFEST_OUT)
    return data


def cmd_prepare(staging):
    """Make sure every group's content file exists and refresh the
    exported groups.json. The generated mosdns config references group
    files directly (domain_set unions them), and mosdns refuses to
    start on a missing file -- so an enabled group whose file was never
    written (local group not edited yet, remote group never fetched)
    gets an empty placeholder here. Content itself is validated at
    write time (install_group / fetch_group), never re-checked here,
    which keeps Apply O(groups) instead of O(total rules)."""
    manifest = load_manifest(staging)
    os.makedirs(GROUPS_DIR, exist_ok=True)
    warnings = []
    for g in manifest:
        if g.get('enabled') not in ('1', 1, True):
            continue  # disabled groups are not referenced by the config
        path = group_content_path(g)
        if not os.path.exists(path):
            with open(path, 'w') as f:
                f.write('')
            name = g.get('name') or g.get('uuid', '')
            kind = '在线组尚未拉取' if g.get('source') == 'remote' else '自定义组尚无内容'
            warnings.append(f'组「{name}」{kind}，已按空组处理')
    export_manifest(manifest)
    print(json.dumps({'result': 'ok', 'warnings': warnings},
                     ensure_ascii=False))


def cmd_export(staging):
    manifest = load_manifest(staging)
    export_manifest(manifest)
    print('OK')


def cmd_test(domain, staging):
    manifest = load_manifest(staging)
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

    def _hit(source, gtype):
        """First (group, rule, kind) hit among enabled groups of this
        (source, type), in manifest order; mirrors the generated config,
        whose domain_set unions the same group files."""
        for g in manifest:
            if (g.get('source') or 'local') != source or g.get('type') != gtype \
                    or g.get('enabled') not in ('1', 1, True):
                continue
            m, kind = match_domain(domain, load_rules(group_content_path(g)))
            if m:
                return g, m, kind
        return None, None, None

    result = {'domain': domain, 'mode': mode}

    def _report(hit, action, explain, sync_pf=False):
        g, m, kind = hit
        if g is None:
            return False
        result.update({'action': action, 'matched_file': g.get('name') or g.get('uuid', ''),
                       'matched_rule': m, 'explain': explain.format(kind=kind)})
        if sync_pf:
            result['sync_pf'] = True
        print(json.dumps(result, ensure_ascii=False))
        return True

    # priority: custom block > custom direct > custom proxy (pf alias) >
    #           sync block > mode over sync direct/proxy > mode default
    if block_enabled and _report(_hit('local', 'block'), 'block', '命中自定义阻止组 ({kind}匹配)，直接拒绝'):
        return
    if _report(_hit('local', 'direct'), 'direct', '命中自定义直连组 ({kind}匹配)，走本地上游'):
        return
    if _report(_hit('local', 'proxy'), 'proxy', '命中自定义代理组 ({kind}匹配)，走远端代理并同步到 pf 表', sync_pf=True):
        return
    if block_enabled and _report(_hit('remote', 'block'), 'block', '命中同步阻止组 ({kind}匹配)，直接拒绝'):
        return

    dhit = _hit('remote', 'direct')
    phit = _hit('remote', 'proxy')

    if mode == 'whitelist':
        if dhit[0] is not None:
            _report(dhit, 'direct', '命中同步直连组 ({kind}匹配)，走本地上游')
        else:
            result.update({'action': 'proxy', 'matched_file': None,
                           'matched_rule': None, 'sync_pf': True,
                           'explain': '白名单模式：未命中同步直连名单，走远端代理并同步到 pf 表'})
            print(json.dumps(result, ensure_ascii=False))
    elif mode == 'blacklist':
        if phit[0] is not None:
            _report(phit, 'proxy', '命中同步代理组 ({kind}匹配)，走远端代理并同步到 pf 表', sync_pf=True)
        else:
            result.update({'action': 'direct', 'matched_file': None,
                           'matched_rule': None,
                           'explain': '黑名单模式：未命中同步代理名单，走本地上游'})
            print(json.dumps(result, ensure_ascii=False))
    else:  # custom
        if dhit[0] is not None:
            _report(dhit, 'direct', '命中同步直连组 ({kind}匹配)，走本地上游')
        elif phit[0] is not None:
            _report(phit, 'proxy', '命中同步代理组 ({kind}匹配)，走远端代理并同步到 pf 表', sync_pf=True)
        else:
            fb = fallback
            result.update({'action': fb, 'matched_file': None, 'matched_rule': None,
                           'sync_pf': fb == 'proxy',
                           'explain': f'混合模式：未命中任何名单，按兜底走{"远端代理" if fb == "proxy" else "本地上游"}'})
            print(json.dumps(result, ensure_ascii=False))


def cmd_group_counts():
    """{uuid: rule count} for every stored group (local .txt + remote
    .cache.txt), so the grids can show a plain count per group."""
    counts = {}
    if os.path.isdir(GROUPS_DIR):
        for name in os.listdir(GROUPS_DIR):
            if name.endswith('.cache.txt'):
                uuid = name[:-len('.cache.txt')]
            elif name.endswith('.txt'):
                uuid = name[:-len('.txt')]
            else:
                continue
            try:
                with open(os.path.join(GROUPS_DIR, name), encoding='utf-8',
                          errors='replace') as f:
                    counts[uuid] = count_rules(f.read())
            except OSError:
                pass
    print(json.dumps({'result': 'ok', 'counts': counts}, ensure_ascii=False))


def main():
    if len(sys.argv) < 2:
        print('usage: rule_tool.py prepare|test|get_group|install_group|'
              'fetch_group|delete_group|group_counts|export|validate ...',
              file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == 'get_group' and len(sys.argv) == 4:
        cmd_get_group(sys.argv[2], sys.argv[3])
    elif cmd == 'install_group' and len(sys.argv) == 4:
        cmd_install_group(sys.argv[2], sys.argv[3])
    elif cmd == 'fetch_group' and len(sys.argv) == 4:
        cmd_fetch_group(sys.argv[2], sys.argv[3])
    elif cmd == 'delete_group' and len(sys.argv) == 3:
        cmd_delete_group(sys.argv[2])
    elif cmd == 'prepare' and len(sys.argv) == 3:
        cmd_prepare(sys.argv[2])
    elif cmd == 'group_counts':
        cmd_group_counts()
    elif cmd == 'export' and len(sys.argv) == 3:
        cmd_export(sys.argv[2])
    elif cmd == 'validate':
        cmd_validate()
    elif cmd == 'test' and len(sys.argv) == 4:
        cmd_test(sys.argv[2], sys.argv[3])
    else:
        print('bad arguments', file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
