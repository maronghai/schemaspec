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

# Test --write mode (in-place formatting)
echo ""
echo "=== --write mode tests ==="

for ss_file in "$TEST_DIR"/*.ss; do
  [ -f "$ss_file" ] || continue
  base=$(basename "$ss_file" .ss)
  [[ "$base" == dialect* ]] && continue  # Skip dialect tests for --write

  expected_file="$EXPECTED_DIR/$base.ss"
  [ -f "$expected_file" ] || continue

  # Copy input to temp, format in-place with --write, compare to expected
  tmp_write=$(mktemp)
  trap "rm -f '$tmp_write'" EXIT
  cp "$ss_file" "$tmp_write"

  if "$COMPILER" format "$tmp_write" --write 2>/dev/null; then
    if diff -u "$expected_file" "$tmp_write" > /dev/null 2>&1; then
      pass "$base --write"
    else
      fail "$base --write" "output differs from expected"
    fi
  else
    fail "$base --write" "format command failed"
  fi
  rm -f "$tmp_write"
done

# Test --dialect mode (dialect-aware formatting)
echo ""
echo "=== --dialect mode tests ==="

# Test MySQL dialect formatting
mysql_input=$(mktemp)
echo '# users
id n pk

@if(dialect=mysql)
id int auto_increment
id2 int unsigned
@endif' > "$mysql_input"

mysql_expected=$(mktemp)
echo '# users
  id n pk

@if(dialect=mysql)
  id int AUTO_INCREMENT
  id2 int UNSIGNED
@endif' > "$mysql_expected"

tmp_dialect=$(mktemp)
trap "rm -f '$mysql_input' '$mysql_expected' '$tmp_dialect'" EXIT

if "$COMPILER" format "$mysql_input" -d mysql -o "$tmp_dialect" 2>/dev/null; then
  if diff -u "$mysql_expected" "$tmp_dialect" > /dev/null 2>&1; then
    pass "dialect-mysql"
  else
    fail "dialect-mysql" "output differs"
    diff -u "$mysql_expected" "$tmp_dialect" | head -20 || true
  fi
else
  fail "dialect-mysql" "format command failed"
fi
rm -f "$mysql_input" "$mysql_expected" "$tmp_dialect"

# Test PostgreSQL dialect formatting
pg_input=$(mktemp)
echo '# users
id n pk

@if(dialect=pg)
id serial
name text returning id
@endif' > "$pg_input"

pg_expected=$(mktemp)
echo '# users
  id n pk

@if(dialect=pg)
  id SERIAL
  name text RETURNING id
@endif' > "$pg_expected"

tmp_pg=$(mktemp)
trap "rm -f '$pg_input' '$pg_expected' '$tmp_pg'" EXIT

if "$COMPILER" format "$pg_input" -d pg -o "$tmp_pg" 2>/dev/null; then
  if diff -u "$pg_expected" "$tmp_pg" > /dev/null 2>&1; then
    pass "dialect-pg"
  else
    fail "dialect-pg" "output differs"
    diff -u "$pg_expected" "$tmp_pg" | head -20 || true
  fi
else
  fail "dialect-pg" "format command failed"
fi
rm -f "$pg_input" "$pg_expected" "$tmp_pg"

summary
