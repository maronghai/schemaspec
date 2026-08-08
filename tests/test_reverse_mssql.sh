#!/usr/bin/env bash
# ── Rune Reverse MSSQL Test Runner ──
# Tests: rune reverse <sql> -d mssql produces expected .ss output.
# Usage: ./test_reverse_mssql.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR/reverse"

FILTER="${1:-}"

for sql_file in "$TEST_DIR"/mssql-*.sql; do
  [ -f "$sql_file" ] || continue
  base=$(basename "$sql_file" .sql)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  expected_file="$TEST_DIR/$base.mssql.ss"
  if [ ! -f "$expected_file" ]; then
    continue
  fi

  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  if ! "$COMPILER" reverse "$sql_file" -d mssql -o "$tmp_file" 2>/dev/null; then
    fail "$base (mssql)" "compiler failed"
    rm -f "$tmp_file"
    continue
  fi

  if compare_files "$expected_file" "$tmp_file"; then
    pass "$base (mssql)"
  else
    diff_output=$(diff_versions "$expected_file" "$tmp_file")
    fail "$base (mssql)" "$diff_output"
  fi

  rm -f "$tmp_file"
done

summary "Reverse MSSQL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
