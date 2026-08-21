#!/usr/bin/env bash
# ── Rune Test Runner ──
# Compiles each .ss test file and diffs against golden .sql output.
# Usage: ./test.sh [test-filter]
#   e.g. ./test.sh           — run all tests
#        ./test.sh 01         — run tests matching "01"
#        ./test.sh template   — run tests matching "template"
# Case-level parallelism: CASE_JOBS=N (default 4).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

run_golden_cases "MySQL" "" ".sql" '^(sqlite-|openapi-|graphql-)'

summary "MySQL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
