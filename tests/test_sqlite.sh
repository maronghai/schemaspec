#!/usr/bin/env bash
# ── Rune SQLite Test Runner ──
# Compiles sqlite-* .ss test files and diffs against golden .sqlite.sql output.
# Usage: ./test_sqlite.sh [test-filter]
# Case-level parallelism + single-process batch compile (see lib.sh).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
EXPECTED_DIR="$SCRIPT_DIR/expected"

FILTER="${1:-}"

run_golden_cases "SQLite" "sqlite" ".sqlite.sql" "" "^sqlite-"

summary "SQLite"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
