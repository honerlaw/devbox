#!/usr/bin/env bash
# Links bin/devbox onto your PATH and checks prerequisites. Safe to re-run.
# Does not touch DigitalOcean; run `devbox init` afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${DEVBOX_BIN_DIR:-$HOME/.local/bin}"

missing=""
for c in doctl docker jq ssh rsync curl lsof; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
if [ -n "$missing" ]; then
  echo "Missing:$missing" >&2
  echo "Install with Homebrew, e.g.: brew install doctl jq   (docker: Docker Desktop or 'brew install docker')" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
chmod +x "$ROOT/bin/devbox"
ln -sfn "$ROOT/bin/devbox" "$BIN_DIR/devbox"
echo "linked $BIN_DIR/devbox -> $ROOT/bin/devbox"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on your PATH; add it to your shell profile" >&2 ;;
esac

if ! doctl account get >/dev/null 2>&1; then
  echo "note: doctl is not authenticated yet; run: doctl auth init" >&2
fi

echo "next: devbox init [--region nyc3] [--size s-4vcpu-8gb]"
