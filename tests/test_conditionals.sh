#!/bin/bash
# Tests for conditional schema blocks (@if(dialect=...))
# Usage: bash tests/test_conditionals.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# .exe suffix on Windows/MSYS — the extensionless file is a Linux ELF there.
case "$OSTYPE" in
  msys*|cygwin*|win32) BIN="$ROOT_DIR/rune/zig-out/bin/rune.exe" ;;
  *)                   BIN="$ROOT_DIR/rune/zig-out/bin/rune" ;;
esac
TESTS_DIR="$SCRIPT_DIR/conditionals"

# Create test directory
mkdir -p "$TESTS_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local input="$2"
    local dialect="$3"
    local expect_contains="$4"
    local expect_not_contains="$5"

    local output
    output=$(echo "$input" | "$BIN" -d "$dialect" 2>/dev/null) || true

    local ok=true
    if [ -n "$expect_contains" ]; then
        if ! echo "$output" | grep -q "$expect_contains"; then
            echo -e "${RED}FAIL${NC} $name — expected to contain '$expect_contains'"
            echo "  output: $output"
            ok=false
        fi
    fi
    if [ -n "$expect_not_contains" ]; then
        if echo "$output" | grep -q "$expect_not_contains"; then
            echo -e "${RED}FAIL${NC} $name — expected NOT to contain '$expect_not_contains'"
            echo "  output: $output"
            ok=false
        fi
    fi
    if $ok; then
        echo -e "${GREEN}PASS${NC} $name"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Conditional Schema Block Tests ==="
echo ""

# Test 1: @if(dialect=pg) fields excluded when targeting MySQL
run_test "conditional-exclude-mysql" \
'$ mydb

# users
id N++
name s100

@if(dialect=pg)
bio T
avatar B
@endif' \
    "mysql" \
    "CREATE TABLE \`users\`" \
    "bio"

# Test 2: @if(dialect=pg) fields included when targeting PostgreSQL
run_test "conditional-include-pg" \
'$ mydb

# users
id N++
name s100

@if(dialect=pg)
bio T
avatar B
@endif' \
    "pg" \
    "bio" \
    ""

# Test 3: Multiple dialect conditions
run_test "conditional-multi-dialect" \
'$ mydb

# users
id N++
name s100

@if(dialect=pg|sqlite)
extended_data T
@endif' \
    "pg" \
    "extended_data" \
    ""

run_test "conditional-multi-dialect-exclude" \
'$ mydb

# users
id N++
name s100

@if(dialect=pg|sqlite)
extended_data T
@endif' \
    "mysql" \
    "" \
    "extended_data"

# Test 4: Non-conditional fields always included
run_test "conditional-always-included" \
'$ mydb

# users
id N++
name s100

@if(dialect=pg)
bio T
@endif' \
    "mysql" \
    "name" \
    ""

# Test 5: Field ordering preserved after filtering
run_test "conditional-field-order" \
'$ mydb

# users
id N++
name s100

@if(dialect=pg)
email V255
@endif

created_at d' \
    "mysql" \
    "created_at" \
    "email"

# Test 7: @if inside a table that uses a template (index remap after merge).
# Template's id is inserted BEFORE the block; the block must still wrap bio.
run_test "conditional-template-before" '$ demo

% base
id n++
...

# users > base
name s32
@if(dialect=pg)
bio T
@endif'     "pg"     "bio"     ""

# Test 8: same shape on MySQL - pg_only must be excluded (regression test for
# the stale-index bug where template insertion shifted @if ranges)
run_test "conditional-template-exclude-mysql" '$ demo

% base
id n++
...

# users > base
@if(dialect=pg)
pg_only T
@endif
name s32'     "mysql"     "CREATE TABLE"     "pg_only"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ $FAIL -gt 0 ]; then
    exit 1
fi
