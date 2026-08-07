#!/bin/bash
# Golden tests for `rune lint` command
set -euo pipefail

BIN="${TEST_BIN:-./rune/zig-out/bin/rune}"
DIR="$(cd "$(dirname "$0")" && pwd)"
LINT_DIR="$DIR/lint"
PASS=0
FAIL=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

run_test() {
    local name="$1"
    local input="$2"
    local expected_exit="$3"
    local expected_pattern="$4"

    local actual_exit=0
    local output
    output=$("$BIN" lint "$LINT_DIR/$input" 2>&1) || actual_exit=$?

    if [ "$actual_exit" -ne "$expected_exit" ]; then
        echo -e "  ${RED}✗${RESET} $name (exit $actual_exit, expected $expected_exit)"
        FAIL=$((FAIL + 1))
        return
    fi

    if [ -n "$expected_pattern" ] && ! echo "$output" | grep -q "$expected_pattern"; then
        echo -e "  ${RED}✗${RESET} $name (pattern '$expected_pattern' not found)"
        echo "    Output: $output"
        FAIL=$((FAIL + 1))
        return
    fi

    echo -e "  ${GREEN}✓${RESET} $name"
    PASS=$((PASS + 1))
}

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Rune Lint Golden Tests${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# Test 1: Clean schema passes
run_test "lint_clean" "clean.ss" 0 "No lint issues found"

# Test 2: No PK detected
run_test "lint_no_pk" "no_pk.ss" 0 "no-pk"

# Test 3: Naming conventions
run_test "lint_naming" "naming.ss" 0 "naming"

# Test 4: JSON output
output_json=$("$BIN" lint "$LINT_DIR/no_pk.ss" --json-errors 2>&1) || true
if echo "$output_json" | grep -q '"issues"'; then
    echo -e "  ${GREEN}✓${RESET} lint_json_output"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_json_output (no JSON issues array)"
    FAIL=$((FAIL + 1))
fi

# Test 5: Strict mode exits 1 on warnings
actual_exit=0
"$BIN" lint "$LINT_DIR/no_pk.ss" --strict 2>&1 || actual_exit=$?
if [ "$actual_exit" -eq 1 ]; then
    echo -e "  ${GREEN}✓${RESET} lint_strict_exit1"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_strict_exit1 (exit $actual_exit, expected 1)"
    FAIL=$((FAIL + 1))
fi

# Test 6: Strict mode exits 0 on clean schema
actual_exit=0
"$BIN" lint "$LINT_DIR/clean.ss" --strict 2>&1 || actual_exit=$?
if [ "$actual_exit" -eq 0 ]; then
    echo -e "  ${GREEN}✓${RESET} lint_strict_exit0_clean"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_strict_exit0_clean (exit $actual_exit, expected 0)"
    FAIL=$((FAIL + 1))
fi

# Test 7: Fix --dry-run on no-pk schema
FIX_TMP=$(mktemp)
cp "$LINT_DIR/fix_no_pk.ss" "$FIX_TMP"
output_fix=$("$BIN" lint "$FIX_TMP" --fix --dry-run 2>&1) || true
# File should be unchanged
if diff -q "$FIX_TMP" "$LINT_DIR/fix_no_pk.ss" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} lint_fix_dryrun_no_change"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_fix_dryrun_no_change (file was modified)"
    FAIL=$((FAIL + 1))
fi
# Output should contain id n++
if echo "$output_fix" | grep -q "id       n++"; then
    echo -e "  ${GREEN}✓${RESET} lint_fix_dryrun_shows_pk"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_fix_dryrun_shows_pk (id n++ not in output)"
    FAIL=$((FAIL + 1))
fi
rm -f "$FIX_TMP"

# Test 8: Fix --dry-run on no-timestamps schema
FIX_TMP=$(mktemp)
cp "$LINT_DIR/fix_no_timestamps.ss" "$FIX_TMP"
output_fix_ts=$("$BIN" lint "$FIX_TMP" --fix --dry-run 2>&1) || true
if diff -q "$FIX_TMP" "$LINT_DIR/fix_no_timestamps.ss" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} lint_fix_dryrun_ts_no_change"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_fix_dryrun_ts_no_change (file was modified)"
    FAIL=$((FAIL + 1))
fi
if echo "$output_fix_ts" | grep -q "created_at t"; then
    echo -e "  ${GREEN}✓${RESET} lint_fix_dryrun_shows_ts"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_fix_dryrun_shows_ts (created_at not in output)"
    FAIL=$((FAIL + 1))
fi
rm -f "$FIX_TMP"

# Test 9: Fix modifies file (non-dry-run)
FIX_TMP=$(mktemp)
cp "$LINT_DIR/fix_no_pk.ss" "$FIX_TMP"
"$BIN" lint "$FIX_TMP" --fix 2>&1 || true
if grep -q "id       n++" "$FIX_TMP"; then
    echo -e "  ${GREEN}✓${RESET} lint_fix_writes_file"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_fix_writes_file (id n++ not found in file)"
    FAIL=$((FAIL + 1))
fi
rm -f "$FIX_TMP"

# Test 10: Fix on clean schema does nothing
FIX_TMP=$(mktemp)
cp "$LINT_DIR/clean.ss" "$FIX_TMP"
"$BIN" lint "$FIX_TMP" --fix 2>&1 || true
if diff -q "$FIX_TMP" "$LINT_DIR/clean.ss" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} lint_fix_clean_noop"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${RESET} lint_fix_clean_noop (file was modified)"
    FAIL=$((FAIL + 1))
fi
rm -f "$FIX_TMP"

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}Lint: $PASS passed${RESET}, ${RED}$FAIL failed${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
