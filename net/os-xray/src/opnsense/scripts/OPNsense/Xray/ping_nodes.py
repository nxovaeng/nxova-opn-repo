#!/usr/local/bin/python3
"""
ping_nodes.py - TCP connect latency test for nodes.

Usage: ping_nodes.py '<json array of {uuid, address, port}>'
Output: JSON object {uuid: rtt_ms or -1} on stdout.
"""
import sys
import json
import socket
import time
from concurrent.futures import ThreadPoolExecutor


def ping(t):
    try:
        start = time.monotonic()
        s = socket.create_connection((t['address'], int(t['port'])), timeout=2)
        s.close()
        return t['uuid'], int((time.monotonic() - start) * 1000)
    except Exception:
        return t['uuid'], -1


def main():
    targets = json.loads(sys.argv[1]) if len(sys.argv) > 1 else []
    result = {}
    with ThreadPoolExecutor(max_workers=10) as ex:
        for uuid, rtt in ex.map(ping, targets):
            result[uuid] = rtt
    print(json.dumps(result))


if __name__ == '__main__':
    main()
