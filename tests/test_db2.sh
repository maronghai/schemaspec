#!/usr/bin/env bash
# ── Rune Db2 Test Runner ──
# Compiles each .ss test file with -d db2 and diffs against golden .db2.sql output.
# Usage: ./test_db2.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

for ss_file in "$TEST_DIR"/*.ss; do
  [ -f "$ss_file" ] || continue
  base=$(basename "$ss_file" .ss)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  # Skip SQLite-only, migrate, error-recovery, and non-SQL test files
  if [[ "$base" == sqlite-* ]] || [[ "$base" == migrate-* ]] || [[ "$base" == error-recovery* ]] || [[ "$base" == openapi-* ]]; then
    continue
  fi

  expected_file="$EXPECTED_DIR/$base.db2.sql"
  if [ ! -f "$expected_file" ]; then
    skip "$base" "no Db2 golden file"
    continue
  fi

  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  if ! "$COMPILER" "$ss_file" -d db2 -o "$tmp_file" 2>/dev/null; then
    fail "$base" "compiler failed"
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

summary "Db2"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
