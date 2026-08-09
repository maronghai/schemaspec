#!/usr/bin/env bash
# ── Rune Formatter Test Runner ──
# Formats each .ss test file and diffs against golden expected output.
# Usage: ./test_format.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR/format"
EXPECTED_DIR="$SCRIPT_DIR/format/expected"

FILTER="${1:-}"

PASS=0
FAIL=0
SKIP=0

for ss_file in "$TEST_DIR"/*.ss; do
  [ -f "$ss_file" ] || continue
  base=$(basename "$ss_file" .ss)

  # Apply filter
  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  expected_file="$EXPECTED_DIR/$base.ss"
  if [ ! -f "$expected_file" ]; then
    skip "$base" "no golden file"
    continue
  fi

  # Format to temp file
  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  if ! "$COMPILER" format "$ss_file" -o "$tmp_file" 2>/dev/null; then
    fail "$base" "format command failed"
    continue
  fi

  if diff -u "$expected_file" "$tmp_file" > /dev/null 2>&1; then
    pass "$base"
  else
    fail "$base" "output differs"
    echo "  Expected: $expected_file"
    echo "  Got:      $tmp_file"
    diff -u "$expected_file" "$tmp_file" | head -20 || true
  fi
done

# Also test --check mode
echo ""
echo "=== --check mode tests ==="

for ss_file in "$TEST_DIR"/*.ss; do
  [ -f "$ss_file" ] || continue
  base=$(basename "$ss_file" .ss)

  expected_file="$EXPECTED_DIR/$base.ss"
  [ -f "$expected_file" ] || continue

  # If input matches expected, --check should succeed
  if diff -u "$ss_file" "$expected_file" > /dev/null 2>&1; then
    if "$COMPILER" format "$ss_file" --check 2>/dev/null; then
      pass "$base --check (formatted)"
    else
      fail "$base --check (formatted)" "should pass but failed"
    fi
  else
    # If input differs from expected, --check should fail
    if "$COMPILER" format "$ss_file" --check 2>/dev/null; then
      fail "$base --check (needs format)" "should fail but passed"
    else
      pass "$base --check (needs format)"
    fi
  fi
done

summary
