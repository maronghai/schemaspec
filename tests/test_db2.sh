#!/usr/bin/env bash
# ── Rune Db2 Test Runner ──
# Compiles each .ss test file with -d db2 and diffs against golden .db2.sql output.
# Usage: ./test_db2.sh [test-filter]
# Case-level parallelism + single-process batch compile (see lib.sh).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

run_golden_cases "Db2" "db2" ".db2.sql" '^(sqlite-|migrate-|error-recovery|openapi-)'

summary "Db2"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
