#!/usr/bin/env bash
# ── Rune Test Coverage Runner ──
# Runs all test suites and reports a summary.
# Usage: ./test_coverage.sh [--quick]
#   --quick  Skip benchmark and slow tests

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

QUICK=false
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=true ;;
  esac
done

echo "═══════════════════════════════════════════════════"
echo "  Rune Test Coverage Report"
echo "═══════════════════════════════════════════════════"
echo ""

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

run_suite() {
  local name="$1"
  local cmd="$2"
  local skip="${3:-false}"

  if [ "$skip" = "true" ]; then
    echo "  ⏭  $name (skipped)"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  TOTAL=$((TOTAL + 1))
  if output=$(bash -c "$cmd" 2>&1); then
    PASSED=$((PASSED + 1))
    echo "  ✅  $name"
  else
    FAILED=$((FAILED + 1))
    echo "  ❌  $name"
    echo "$output" | tail -3 | sed 's/^/      /'
  fi
}

echo "Unit Tests (Zig):"
run_suite "zig build test" "cd rune && zig build test"

echo ""
echo "Golden Tests (Shell):"
run_suite "MySQL (86 tests)" "bash tests/test.sh"
run_suite "PostgreSQL (87 tests)" "bash tests/test_postgres.sh"
run_suite "SQLite (26 tests)" "bash tests/test_sqlite.sh"
run_suite "MSSQL (26 tests)" "bash tests/test_mssql.sh"
run_suite "Oracle (103 tests)" "bash tests/test_oracle.sh"
run_suite "Db2 (103 tests)" "bash tests/test_db2.sh"
run_suite "Migration (34 tests)" "bash tests/test_migrate.sh"
run_suite "Diff (12 tests)" "bash tests/test_diff.sh"
run_suite "Reverse (21 tests)" "bash tests/test_reverse.sh"
run_suite "Reverse Oracle (3 tests)" "bash tests/test_reverse_oracle.sh"
run_suite "Reverse Db2 (3 tests)" "bash tests/test_reverse_db2.sh"
run_suite "Error Recovery (12 tests)" "bash tests/test_error_recovery.sh"
run_suite "JSON Schema (3 tests)" "bash tests/test_json_schema.sh"
run_suite "Round-trip (112 tests, 5 dialects)" "bash tests/test_roundtrip.sh"
run_suite "Property Roundtrip (30+ iterations)" "bash tests/test_property_roundtrip.sh 30 42"
run_suite "Imports (6 tests)" "bash tests/test_imports.sh"
run_suite "Stdin (4 tests)" "bash tests/test_stdin.sh"
run_suite "Reverse Confidence (4 tests)" "bash tests/test_reverse_confidence.sh"
run_suite "Init & Completions (12 tests)" "bash tests/test_init.sh"
run_suite "OpenAPI (3 tests)" "bash tests/test_openapi.sh"
run_suite "GraphQL (4 tests)" "bash tests/test_graphql.sh"

if [ "$QUICK" = false ]; then
  echo ""
  echo "Performance Tests:"
  run_suite "Benchmark Regression" "bash tests/test_bench.sh --check"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════"
echo "  Suites run:    $TOTAL"
echo "  Suites passed: $PASSED"
echo "  Suites failed: $FAILED"
echo "  Suites skipped: $SKIPPED"
echo ""

if [ $FAILED -gt 0 ]; then
  echo "  ❌ SOME TEST SUITES FAILED"
  exit 1
else
  echo "  ✅ ALL TEST SUITES PASSED"
  exit 0
fi
