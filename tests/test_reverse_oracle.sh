#!/usr/bin/env bash
# ── Rune Reverse Oracle Test Runner ──
# Tests: rune reverse <sql> -d oracle produces expected .ss output.
# Usage: ./test_reverse_oracle.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR/reverse"

FILTER="${1:-}"

for sql_file in "$TEST_DIR"/oracle-*.sql; do
  [ -f "$sql_file" ] || continue
  base=$(basename "$sql_file" .sql)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  expected_file="$TEST_DIR/$base.oracle.ss"
  if [ ! -f "$expected_file" ]; then
    continue
  fi

  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  if ! "$COMPILER" reverse "$sql_file" -d oracle -o "$tmp_file" 2>/dev/null; then
    fail "$base (oracle)" "compiler failed"
    rm -f "$tmp_file"
    continue
  fi

  if compare_files "$expected_file" "$tmp_file"; then
    pass "$base (oracle)"
  else
    diff_output=$(diff_versions "$expected_file" "$tmp_file")
    fail "$base (oracle)" "$diff_output"
  fi

  rm -f "$tmp_file"
done

summary "Reverse Oracle"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
