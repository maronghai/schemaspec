#!/usr/bin/env bash
# sync-version.sh — propagate VERSION to packaging manifests.
#
# VERSION is the single source of truth. This script writes it into every
# package.json that carries a release version, or verifies they already match.
#
# Usage:
#   bash scripts/sync-version.sh            # sync: write VERSION into all manifests
#   bash scripts/sync-version.sh --check    # verify only; exit 1 on mismatch (CI mode)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
MANIFESTS=(
  "$ROOT_DIR/packaging/npm/package.json"
  "$ROOT_DIR/packaging/vscode/package.json"
)

if [ ! -f "$VERSION_FILE" ]; then
  echo "error: $VERSION_FILE not found" >&2
  exit 1
fi
VERSION="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
if [ -z "$VERSION" ]; then
  echo "error: VERSION file is empty" >&2
  exit 1
fi

mode="sync"
if [ "${1:-}" = "--check" ]; then
  mode="check"
fi

status=0
for manifest in "${MANIFESTS[@]}"; do
  if [ ! -f "$manifest" ]; then
    echo "error: manifest not found: $manifest" >&2
    exit 1
  fi
  current="$(jq -r '.version // empty' "$manifest")"
  rel="${manifest#"$ROOT_DIR"/}"
  if [ "$current" = "$VERSION" ]; then
    echo "ok   $rel = $VERSION"
    continue
  fi
  if [ "$mode" = "check" ]; then
    echo "FAIL $rel = ${current:-<missing>} (expected $VERSION)"
    status=1
  else
    tmp="$(mktemp)"
    jq --arg v "$VERSION" '.version = $v' "$manifest" > "$tmp"
    # jq always emits LF; restore the manifest's existing line endings so a
    # sync on Windows doesn't rewrite every line (same class of bug as the
    # v0.324.0 lint --fix CRLF fix).
    if head -c 200 "$manifest" | grep -q $'\r'; then
      sed -i 's/$/\r/' "$tmp"
    fi
    mv "$tmp" "$manifest"
    echo "sync $rel: ${current:-<missing>} -> $VERSION"
  fi
done

if [ "$mode" = "check" ] && [ "$status" -ne 0 ]; then
  echo ""
  echo "version mismatch: run 'bash scripts/sync-version.sh' and recommit" >&2
fi
exit "$status"
