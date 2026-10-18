#!/bin/sh
# Build pf-aliasd as a static FreeBSD amd64 binary.
# Usage: ./scripts/build-daemon.sh [output-dir]
# Output: <output-dir>/pf-aliasd-freebsd-amd64 (default: ./dist)
set -eu

OUTDIR="${1:-dist}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_DIR="$REPO_ROOT/daemon/pf-aliasd"

if [ -z "${GO_BIN:-}" ]; then
	if [ -x "$HOME/opt/go/bin/go" ]; then
		GO_BIN="$HOME/opt/go/bin/go"
	elif command -v go >/dev/null 2>&1; then
		GO_BIN="go"
	else
		echo "error: Go toolchain not found (tried \$HOME/opt/go/bin/go and PATH)" >&2
		exit 1
	fi
fi

case "$OUTDIR" in
/*) ;; # absolute path: use as-is
*) OUTDIR="$REPO_ROOT/$OUTDIR" ;;
esac
mkdir -p "$OUTDIR"
cd "$DAEMON_DIR"

# Offline-friendly: use module cache only if network is unavailable.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64

"$GO_BIN" build -trimpath -ldflags="-s -w" -o "$OUTDIR/pf-aliasd-freebsd-amd64" ./cmd/pf-aliasd

echo "built: $OUTDIR/pf-aliasd-freebsd-amd64"
file "$OUTDIR/pf-aliasd-freebsd-amd64" 2>/dev/null || true
