#!/usr/local/bin/python3
"""Flush pf-aliasd managed alias tables, effective immediately.

Per table: send the daemon a CmdFlush over its SEQPACKET socket (clears
the in-memory TTL records AND the tracked pf entries), then sweep with
pfctl -T flush to drop any untracked leftovers (e.g. entries that
survived a daemon restart without startup flush). If the daemon is not
reachable, the pfctl sweep still empties the table and the result says
so. Usage:

    pfalias_flush.py <socket_path> <table>[,<table>...]

Prints one JSON object: {"result": "ok", "tables": [{"table", "before",
"daemon", "after"}, ...]} -- counts come from pfctl -T show.
"""
import json
import socket
import struct
import subprocess
import sys

CMD_FLUSH = 0x03
CMD_ACK = 0x80
STATUS_OK = 0


def pfctl_show_count(table):
    try:
        r = subprocess.run(['/sbin/pfctl', '-t', table, '-T', 'show'],
                           capture_output=True, text=True, timeout=10)
        if r.returncode != 0:
            return None
        return len([ln for ln in r.stdout.splitlines() if ln.strip()])
    except Exception:
        return None


def pfctl_flush(table):
    try:
        r = subprocess.run(['/sbin/pfctl', '-t', table, '-T', 'flush'],
                           capture_output=True, text=True, timeout=10)
        return r.returncode == 0
    except Exception:
        return False


def daemon_flush(sock_path, table, seq):
    """Send one CmdFlush packet; return 'ok', 'down' or 'error'."""
    tb = table.encode()
    if len(tb) > 31:
        return 'error'
    pkt = (b'PF' + bytes([1, CMD_FLUSH]) + struct.pack('>I', seq)
           + b'\x00\x00' + bytes([len(tb)]) + tb)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    s.settimeout(3)
    try:
        s.connect(sock_path)
        s.send(pkt)
        data = s.recv(4096)
    except (FileNotFoundError, ConnectionRefusedError):
        return 'down'
    except OSError:
        return 'error'
    finally:
        s.close()
    if len(data) < 10 or data[0:2] != b'PF' or data[3] != CMD_ACK:
        return 'error'
    return 'ok' if data[8] == STATUS_OK else 'error'


def main():
    if len(sys.argv) != 3:
        print(json.dumps({'result': 'failed',
                          'error': 'usage: pfalias_flush.py <socket> <tables>'}))
        return
    sock_path = sys.argv[1]
    tables = [t.strip() for t in sys.argv[2].split(',') if t.strip()]
    out = []
    for i, table in enumerate(tables):
        before = pfctl_show_count(table)
        daemon = daemon_flush(sock_path, table, 100 + i)
        pfctl_flush(table)
        after = pfctl_show_count(table)
        out.append({'table': table, 'before': before,
                    'daemon': daemon, 'after': after})
    print(json.dumps({'result': 'ok', 'tables': out}, ensure_ascii=False))


if __name__ == '__main__':
    main()
