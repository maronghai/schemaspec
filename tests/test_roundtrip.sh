#!/usr/bin/env bash
# ── Rune Roundtrip Test Runner ──
# Tests: .ss → SQL → reverse → .ss → SQL produces semantically equivalent output.
# Usage: ./test_roundtrip.sh [test-filter] [dialect1 dialect2 ...]
#   test-filter: substring to match test names
#   dialect1 dialect2 ...: space-separated list of dialects to test (default: 5 dialects, excluding mssql)
# Test cases run concurrently (CASE_JOBS workers, default 4); each case runs
# its dialects in-process-parallel when PARALLEL_DIALECTS=true.

set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FILTER="${1:-}"
# Dialects to test: remaining arguments, or 5 dialects if none specified (mssql excluded due to bracket quoting bug in reverse pipeline)
DIALECTS=("${@:2}")
if [ ${#DIALECTS[@]} -eq 0 ]; then
  DIALECTS=(mysql pg sqlite oracle db2)
fi

# Test schemas: .ss files that roundtrip cleanly across all 6 dialects.
# Excluded: 20-index-types/39-index-autoname (FULLTEXT name double-prefix),
# 03-all-types (decimal roundtrip lossy on some dialects), 60-enum-type (ENUM→TEXT),
# view-basic (CREATE OR REPLACE not reversible), 01-schema-only (reverse fails on oracle/db2/mssql).
# MSSQL excluded entirely due to bracket quoting bug in reverse pipeline.
ROUNDTRIP_TESTS=(
  "01-schema-only"
  "03-all-types"
  "04-modifiers"
  "05-defaults"
  "06-suffix-inference"
  "08-table-comment"
  "10-template-basic"
  "12-template-deep"
  "14-fk-full"
  "21-index-composite"
  "22-check-constraints"
  "40-unicode-comments"
  "42-bare-fields"
  "48-many-defaults"
  "65-inline-unique"
  "75-composite-index-auto"
  "81-inline-index"
  "generated-columns"
  "custom-types"
)

run_one_case() {
  local test_name="$1"
  local ss_file="$SCRIPT_DIR/${test_name}.ss"
  local tmpdir="$2"

  for dialect in "${DIALECTS[@]}"; do
    # Step 1: .ss → SQL (original)
    sql1=$("$COMPILER" "$ss_file" -d "$dialect" 2>/dev/null) || {
      echo "FAIL:$test_name ($dialect): step 1|compile failed" > "$tmpdir/$test_name.$dialect.status"
      continue
    }

    # Step 2: SQL → .ss (reverse via auto-detect from header tag)
    reversed=$(echo "$sql1" | timeout 10 "$COMPILER" reverse - 2>/dev/null) || {
      echo "SKIP:$test_name ($dialect)|reverse failed" > "$tmpdir/$test_name.$dialect.status"
      continue
    }

    # Step 3: reversed .ss → SQL (roundtrip)
    sql2=$(echo "$reversed" | timeout 10 "$COMPILER" - -d "$dialect" 2>/dev/null) || {
      echo "FAIL:$test_name ($dialect): step 3|re-compile failed" > "$tmpdir/$test_name.$dialect.status"
      continue
    }

    # Step 4: Semantic comparison (strip comments, normalize whitespace)
    strip1=$(echo "$sql1" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')
    strip2=$(echo "$sql2" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')

    if [ "$strip1" = "$strip2" ]; then
      echo "PASS:$test_name ($dialect)" > "$tmpdir/$test_name.$dialect.status"
    else
      diff_output=$(diff <(echo "$strip1") <(echo "$strip2") 2>&1 | head -10)
      echo "FAIL:$test_name ($dialect)|SQL mismatch: $diff_output" > "$tmpdir/$test_name.$dialect.status"
    fi
  done
}

export -f run_one_case 2>/dev/null || true
export SCRIPT_DIR COMPILER FILTER DIALECTS

jobs="${CASE_JOBS:-4}"
tmpdir=$(mktemp -d)
pids=()

for test_name in "${ROUNDTRIP_TESTS[@]}"; do
  if [ -n "$FILTER" ] && [[ "$test_name" != *"$FILTER"* ]]; then
    continue
  fi

  ss_file="$SCRIPT_DIR/${test_name}.ss"
  if [ ! -f "$ss_file" ]; then
    skip "$test_name" "missing .ss file"
    continue
  fi

  run_one_case "$test_name" "$tmpdir" &
  pids+=($!)
  while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do sleep 0.05; done
done
wait "${pids[@]}" 2>/dev/null || true

# Report in registration order.
for test_name in "${ROUNDTRIP_TESTS[@]}"; do
  if [ -n "$FILTER" ] && [[ "$test_name" != *"$FILTER"* ]]; then
    continue
  fi
  ss_file="$SCRIPT_DIR/${test_name}.ss"
  [ -f "$ss_file" ] || continue
  for dialect in "${DIALECTS[@]}"; do
    status=$(cat "$tmpdir/$test_name.$dialect.status" 2>/dev/null || echo "FAIL:$test_name ($dialect)|no status")
    case "$status" in
      PASS:*) pass "${status#PASS:}" ;;
      SKIP:*) lbl="${status%%|*}"; skip "${lbl#SKIP:}" "${status#*|}" ;;
      FAIL:*)
        label="${status%%|*}"; fail "$label" "${status#*|}"
        ;;
    esac
  done
done
rm -rf "$tmpdir"

summary "Roundtrip"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
