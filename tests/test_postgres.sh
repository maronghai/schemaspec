#!/usr/bin/env bash
# ── Rune PostgreSQL Test Runner ──
# Compiles each .ss test file with -d pg and diffs against golden .pg.sql output.
# Usage: ./test_postgres.sh [test-filter]
# Case-level parallelism + single-process batch compile (see lib.sh).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

run_golden_cases "PostgreSQL" "pg" ".pg.sql" '^(sqlite-|migrate-|error-recovery|openapi-|graphql-)'

summary "PostgreSQL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
