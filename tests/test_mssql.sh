#!/usr/bin/env bash
# ── Rune MSSQL Test Runner ──
# Compiles each .ss test file with -d mssql and diffs against golden .mssql.sql output.
# Usage: ./test_mssql.sh [test-filter]
# Case-level parallelism + single-process batch compile (see lib.sh).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

run_golden_cases "MSSQL" "mssql" ".mssql.sql" '^(sqlite-|migrate-|error-recovery|openapi-)'

summary "MSSQL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
