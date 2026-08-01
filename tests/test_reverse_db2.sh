#!/usr/bin/env bash
# ── Rune Reverse Db2 Test Runner ──
# Tests: rune reverse <sql> -d db2 produces expected .ss output.
# Usage: ./test_reverse_db2.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR/reverse"

FILTER="${1:-}"

for sql_file in "$TEST_DIR"/db2-*.sql; do
  [ -f "$sql_file" ] || continue
  base=$(basename "$sql_file" .sql)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  expected_file="$TEST_DIR/$base.db2.ss"
  if [ ! -f "$expected_file" ]; then
    continue
  fi

  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  if ! "$COMPILER" reverse "$sql_file" -d db2 -o "$tmp_file" 2>/dev/null; then
    fail "$base (db2)" "compiler failed"
    rm -f "$tmp_file"
    continue
  fi

  if compare_files "$expected_file" "$tmp_file"; then
    pass "$base (db2)"
  else
    diff_output=$(diff_versions "$expected_file" "$tmp_file")
    fail "$base (db2)" "$diff_output"
  fi

  rm -f "$tmp_file"
done

summary "Reverse Db2"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
