#!/bin/sh
#
# os-tun2socks reconfigure:
#   1. regenerate the rc.conf.d argument file from the model,
#   2. restart the service; a disabled service is stopped, not started
#      (rc.conf.d says NO).
#
set -e

/usr/local/sbin/configctl template reload OPNsense/Tun2socks > /dev/null

/usr/sbin/service tun2socks restart || true

echo "reconfigure done"
