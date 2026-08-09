#!/bin/bash
# Tests for conditional schema blocks (@if(dialect=...))
# Usage: bash tests/test_conditionals.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT_DIR/rune/zig-out/bin/rune"
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
'$ users
id N
name V100

@if(dialect=pg)
bio T
avatar B
@endif' \
    "mysql" \
    "CREATE TABLE \`users\`" \
    "bio"

# Test 2: @if(dialect=pg) fields included when targeting PostgreSQL
run_test "conditional-include-pg" \
'$ users
id N
name V100

@if(dialect=pg)
bio T
avatar B
@endif' \
    "pg" \
    "bio" \
    ""

# Test 3: Multiple dialect conditions
run_test "conditional-multi-dialect" \
'$ users
id N
name V100

@if(dialect=pg|sqlite)
extended_data T
@endif' \
    "pg" \
    "extended_data" \
    ""

run_test "conditional-multi-dialect-exclude" \
'$ users
id N
name V100

@if(dialect=pg|sqlite)
extended_data T
@endif' \
    "mysql" \
    "" \
    "extended_data"

# Test 4: Non-conditional fields always included
run_test "conditional-always-included" \
'$ users
id N
name V100

@if(dialect=pg)
bio T
@endif' \
    "mysql" \
    "name" \
    ""

# Test 5: Field ordering preserved after filtering
run_test "conditional-field-order" \
'$ users
id N
name V100

@if(dialect=pg)
email V255
@endif

created_at d' \
    "mysql" \
    "created_at" \
    "email"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ $FAIL -gt 0 ]; then
    exit 1
fi
