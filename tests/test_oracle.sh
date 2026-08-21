#!/usr/bin/env bash
# ── Rune Oracle Test Runner ──
# Compiles each .ss test file with -d oracle and diffs against golden .oracle.sql output.
# Usage: ./test_oracle.sh [test-filter]
# Case-level parallelism + single-process batch compile (see lib.sh).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

run_golden_cases "Oracle" "oracle" ".oracle.sql" '^(sqlite-|migrate-|error-recovery|openapi-)'

summary "Oracle"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
