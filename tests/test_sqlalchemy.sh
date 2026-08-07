#!/usr/bin/env bash
# ── Rune SQLAlchemy Test Runner ──
# Tests: rune generate sqlalchemy produces expected SQLAlchemy model output.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

for ss_file in "$TEST_DIR"/sqlalchemy-*.ss; do
  [ -f "$ss_file" ] || continue
  base=$(basename "$ss_file" .ss)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  expected_file="$EXPECTED_DIR/${base}.py"
  if [ ! -f "$expected_file" ]; then
    skip "$base" "no expected file"
    continue
  fi

  tmp_file=$(mktemp)

  if ! "$COMPILER" generate sqlalchemy "$ss_file" -o "$tmp_file" 2>/dev/null; then
    fail "$base" "compile failed"
    rm -f "$tmp_file"
    continue
  fi

  if compare_files "$expected_file" "$tmp_file"; then
    pass "$base"
  else
    diff_output=$(diff_versions "$expected_file" "$tmp_file")
    fail "$base" "$diff_output"
  fi

  rm -f "$tmp_file"
done

summary "SQLAlchemy"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
