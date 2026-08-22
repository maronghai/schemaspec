#!/usr/bin/env bash
# ── Rune Test Coverage Runner ──
# Runs all test suites and reports a summary.
# Usage: ./test_coverage.sh [--quick] [--fast] [--shard N/M] [--serial] [JOBS=N]
#   --quick      Skip benchmark and slow tests (legacy flag)
#   --fast       Fast mode for PR validation: skip property roundtrip, reduce round-trip
#   --shard N/M  Run shard M of N (for CI parallelism, 1-indexed)
#   --serial     Run suites one at a time (default: parallel with JOBS workers)
#   JOBS=N       Max concurrent suites (default: 4)

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

QUICK=false
FAST=false
SHARD_TOTAL=1
SHARD_INDEX=1
SERIAL=false
JOBS="${JOBS:-4}"

while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --quick) QUICK=true ;;
    --fast) FAST=true ;;
    --serial) SERIAL=true ;;
    --shard)
      shift
      SHARD_SPEC="$1"
      if [[ "$SHARD_SPEC" == */* ]]; then
        SHARD_TOTAL="${SHARD_SPEC%/*}"
        SHARD_INDEX="${SHARD_SPEC#*/}"
      else
        SHARD_TOTAL="$SHARD_SPEC"
        shift
        SHARD_INDEX="$1"
      fi
      ;;
    --shard=*)
      SHARD_SPEC="${arg#--shard=}"
      SHARD_TOTAL="${SHARD_SPEC%/*}"
      SHARD_INDEX="${SHARD_SPEC#*/}"
      ;;
  esac
  shift
done

# Validate shard parameters
if [ "$SHARD_TOTAL" -lt 1 ] || [ "$SHARD_INDEX" -lt 1 ] || [ "$SHARD_INDEX" -gt "$SHARD_TOTAL" ]; then
  echo "ERROR: Invalid shard specification. Use --shard N/M where 1 <= M <= N"
  exit 1
fi

# Shard filter function
should_run() {
  local suite_num=$1
  # Distribute suites evenly across shards
  local mod=$(( (suite_num - 1) % SHARD_TOTAL + 1 ))
  [ "$mod" -eq "$SHARD_INDEX" ]
}

SUITE_NUM=0

echo "═══════════════════════════════════════════════════"
echo "  Rune Test Coverage Report"
if [ "$SHARD_TOTAL" -gt 1 ]; then
  echo "  Shard $SHARD_INDEX of $SHARD_TOTAL"
fi
if [ "$FAST" = true ]; then
  echo "  FAST MODE (reduced test scope)"
fi
echo "═══════════════════════════════════════════════════"
echo ""

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# ── Suite execution: parallel with bounded jobs, or serial ──
# Suites run concurrently (JOBS workers); results print in registration order
# after all complete. Each suite writes to its own temp file — no shared state.
SUITE_CMDS=()
SUITE_NAMES=()
OUTDIR=$(mktemp -d)
trap 'rm -rf "$OUTDIR"' EXIT

run_suite() {
  local name="$1"
  local cmd="$2"
  local skip="${3:-false}"

  SUITE_NUM=$((SUITE_NUM + 1))

  # Check shard filter
  if [ "$SHARD_TOTAL" -gt 1 ] && ! should_run "$SUITE_NUM"; then
    echo "  ⏭  $name (shard $SHARD_INDEX/$SHARD_TOTAL)"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  if [ "$skip" = "true" ]; then
    echo "  ⏭  $name (skipped)"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  TOTAL=$((TOTAL + 1))
  if [ "$SERIAL" = true ]; then
    if output=$(bash -c "$cmd" 2>&1); then
      PASSED=$((PASSED + 1))
      echo "  ✅  $name"
    else
      FAILED=$((FAILED + 1))
      echo "  ❌  $name"
      echo "$output" | tail -3 | sed 's/^/      /'
    fi
  else
    SUITE_NAMES+=("$name")
    SUITE_CMDS+=("$cmd")
  fi
}

finish_suites() {
  [ ${#SUITE_NAMES[@]} -eq 0 ] && return

  # Launch all suites with a job-slot throttle.
  local pids=()
  for i in "${!SUITE_NAMES[@]}"; do
    (
      bash -c "${SUITE_CMDS[$i]}" > "$OUTDIR/$i.out" 2>&1
      echo $? > "$OUTDIR/$i.rc"
    ) &
    pids+=($!)
    # Throttle: wait for a slot when JOBS are in flight
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
      sleep 0.2
    done
  done
  wait "${pids[@]}" 2>/dev/null || true

  # Report in registration order
  for i in "${!SUITE_NAMES[@]}"; do
    local rc=1
    [ -f "$OUTDIR/$i.rc" ] && rc=$(cat "$OUTDIR/$i.rc")
    if [ "$rc" -eq 0 ]; then
      PASSED=$((PASSED + 1))
      echo "  ✅  ${SUITE_NAMES[$i]}"
    else
      FAILED=$((FAILED + 1))
      echo "  ❌  ${SUITE_NAMES[$i]}"
      tail -3 "$OUTDIR/$i.out" | sed 's/^/      /' || true
    fi
  done
}

# Unit tests queue alongside the golden suites (parallel mode) so the
# ~40s zig build doesn't block golden-suite startup; in serial mode it
# runs inline as before.
echo "Unit Tests (Zig):"
run_suite "zig build test" "cd rune && zig build test"
echo ""
echo "Golden Tests (Shell):"

# Dialect tests - these are independent and can be sharded
run_suite "MySQL (85 tests)" "bash tests/test.sh"
run_suite "PostgreSQL (86 tests)" "bash tests/test_postgres.sh"
run_suite "SQLite (26 tests)" "bash tests/test_sqlite.sh"
run_suite "MSSQL (26 tests)" "bash tests/test_mssql.sh"
run_suite "Oracle (103 tests)" "bash tests/test_oracle.sh"
run_suite "Db2 (103 tests)" "bash tests/test_db2.sh"

# Migration/Diff/Reverse tests
run_suite "Migration (34 tests)" "bash tests/test_migrate.sh"
run_suite "Migrate Status (7 tests)" "bash tests/test_migrate_status.sh"
run_suite "Diff (12 tests)" "bash tests/test_diff.sh"
run_suite "Reverse (21 tests)" "bash tests/test_reverse.sh"
run_suite "Reverse Oracle (5 tests)" "bash tests/test_reverse_oracle.sh"
run_suite "Reverse Db2 (5 tests)" "bash tests/test_reverse_db2.sh"
run_suite "Reverse MSSQL (3 tests)" "bash tests/test_reverse_mssql.sh"

# Other tests
run_suite "Error Recovery (12 tests)" "bash tests/test_error_recovery.sh"
run_suite "JSON Schema (3 tests)" "bash tests/test_json_schema.sh"

# Round-trip - in fast mode, run reduced dialect set; use parallel dialects in CI
if [ "$FAST" = true ]; then
  run_suite "Round-trip (fast: 2 dialects)" "PARALLEL_DIALECTS=true bash tests/test_roundtrip.sh '' mysql pg"
else
  run_suite "Round-trip (112 tests, 5 dialects)" "PARALLEL_DIALECTS=true bash tests/test_roundtrip.sh ''"
fi

# Property Roundtrip - skip in fast mode, use reduced iterations
if [ "$FAST" = true ]; then
  run_suite "Property Roundtrip (skipped)" "" true
else
  run_suite "Property Roundtrip (5 iterations)" "bash tests/test_property_roundtrip.sh 5 42"
fi

run_suite "Imports (6 tests)" "bash tests/test_imports.sh"
run_suite "Stdin (4 tests)" "bash tests/test_stdin.sh"
run_suite "Reverse Confidence (3 tests)" "bash tests/test_reverse_confidence.sh"
run_suite "Registry (10 tests)" "bash tests/test_registry.sh"
run_suite "Template Override (9 tests)" "bash tests/test_template_override.sh"
run_suite "Composite Types (10 tests)" "bash tests/test_composite.sh"
run_suite "Conditionals (8 tests)" "bash tests/test_conditionals.sh"
run_suite "Init & Completions (12 tests)" "bash tests/test_init.sh"
run_suite "Validate (4 tests)" "bash tests/test_validate.sh"
run_suite "Stats JSON (3 tests)" "bash tests/test_stats_json.sh"
run_suite "OpenAPI (3 tests)" "bash tests/test_openapi.sh"
run_suite "GraphQL (4 tests)" "bash tests/test_graphql.sh"
run_suite "TypeORM (2 tests)" "bash tests/test_typeorm.sh"
run_suite "SQLAlchemy (2 tests)" "bash tests/test_sqlalchemy.sh"
run_suite "Knex (2 tests)" "bash tests/test_knex.sh"
run_suite "Color (5 tests)" "bash tests/test_color.sh"
run_suite "Formatter (10 tests)" "bash tests/test_format.sh"
run_suite "Lint (12 tests)" "bash tests/test_lint.sh"
# Parallel test is a meta-test that runs other suites; skip when sharding (redundant)
  if [ "$SHARD_TOTAL" -gt 1 ]; then
    run_suite "Parallel" "" true
  else
    run_suite "Parallel" "bash tests/test_parallel.sh"
  fi

if [ "$QUICK" = false ] && [ "$FAST" = false ]; then
  echo ""
  echo "Performance Tests:"
  run_suite "Benchmark Regression" "bash tests/test_bench.sh --check"
fi

# Run queued suites (parallel mode) and print results in order.
finish_suites

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
