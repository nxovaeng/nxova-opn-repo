#!/bin/sh
#
# os-mosdns reconfigure:
#   1. regenerate /usr/local/etc/mosdns/config.yaml and rc.conf.d toggles
#      from the model,
#   2. restart both services; a service whose enable flag is off is stopped
#      and not started (rc.conf.d says NO).
#
set -e

/usr/local/sbin/configctl template reload OPNsense/Mosdns > /dev/null

/usr/sbin/service mosdns restart || true
/usr/sbin/service pf_aliasd restart || true

echo "reconfigure done"
