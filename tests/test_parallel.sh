#!/usr/bin/env bash
# ── Rune Parallel Test Runner ──
# Runs all non-bench test suites concurrently for faster CI.
# Usage: ./test_parallel.sh

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib_parallel.sh"

TEST_DIR="$SCRIPT_DIR_PAR"

run_suite_init

# Add all test suites (non-bench, since bench has side effects)
run_suite_add "MySQL"       "bash '$TEST_DIR/test.sh'"
run_suite_add "PostgreSQL"  "bash '$TEST_DIR/test_postgres.sh'"
run_suite_add "SQLite"      "bash '$TEST_DIR/test_sqlite.sh'"
run_suite_add "Migration"   "bash '$TEST_DIR/test_migrate.sh'"
run_suite_add "Diff"        "bash '$TEST_DIR/test_diff.sh'"
run_suite_add "Reverse"     "bash '$TEST_DIR/test_reverse.sh'"
run_suite_add "ErrorRecov"  "bash '$TEST_DIR/test_error_recovery.sh'"
run_suite_add "JSONSchema"  "bash '$TEST_DIR/test_json_schema.sh'"
run_suite_add "Roundtrip"   "bash '$TEST_DIR/test_roundtrip.sh'"
run_suite_add "Imports"     "bash '$TEST_DIR/test_imports.sh'"
run_suite_add "Stdin"       "bash '$TEST_DIR/test_stdin.sh'"
run_suite_add "RevConf"     "bash '$TEST_DIR/test_reverse_confidence.sh'"

echo ""
printf "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"
printf "\033[1mRunning %d test suites in parallel...\033[0m\n" "${#SUITE_LABELS[@]}"
printf "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"
echo ""

run_suite_run_all
run_suite_collect
