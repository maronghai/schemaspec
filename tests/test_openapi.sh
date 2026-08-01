#!/usr/bin/env bash
# ── Rune OpenAPI Test Runner ──
# Tests: rune generate openapi produces expected OpenAPI 3.1 output.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

for ss_file in "$TEST_DIR"/openapi-*.ss; do
  [ -f "$ss_file" ] || continue
  base=$(basename "$ss_file" .ss)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  expected_file="$EXPECTED_DIR/${base}.sql"
  if [ ! -f "$expected_file" ]; then
    skip "$base" "no expected file"
    continue
  fi

  tmp_file=$(mktemp)

  if ! "$COMPILER" generate openapi "$ss_file" -o "$tmp_file" 2>/dev/null; then
    fail "$base" "compile failed"
    rm -f "$tmp_file"
    continue
  fi

  if diff -u "$expected_file" "$tmp_file" >/dev/null 2>&1; then
    pass "$base"
  else
    fail "$base" "output differs"
    diff -u "$expected_file" "$tmp_file" | head -20
  fi

  rm -f "$tmp_file"
done

summary "OpenAPI"
