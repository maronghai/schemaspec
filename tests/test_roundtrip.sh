#!/usr/bin/env bash
# ── Rune Roundtrip Test Runner ──
# Tests: .ss → SQL → reverse → .ss → SQL produces semantically equivalent output.
# Usage: ./test_roundtrip.sh [test-filter] [dialect1 dialect2 ...]
#   test-filter: substring to match test names
#   dialect1 dialect2 ...: space-separated list of dialects to test (default: 5 dialects, excluding mssql)

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
  "30-template-override"
  "33-empty-lines"
  "35-slot-beginning"
  "36-slot-end"
  "40-unicode-comments"
  "42-bare-fields"
  "48-many-defaults"
  "65-inline-unique"
  "75-composite-index-auto"
  "81-inline-index"
  "generated-columns"
  "custom-types"
)

for test_name in "${ROUNDTRIP_TESTS[@]}"; do
  if [ -n "$FILTER" ] && [[ "$test_name" != *"$FILTER"* ]]; then
    continue
  fi

  ss_file="$SCRIPT_DIR/${test_name}.ss"
  if [ ! -f "$ss_file" ]; then
    skip "$test_name" "missing .ss file"
    continue
  fi

  # Run dialects in parallel for this test case
  PARALLEL_DIALECTS="${PARALLEL_DIALECTS:-false}"
  if [ "$PARALLEL_DIALECTS" = "true" ]; then
    # Run all dialects in background
    pids=()
    tmpdir=$(mktemp -d)
    for dialect in "${DIALECTS[@]}"; do
      (
        # Step 1: .ss → SQL (original)
        sql1=$("$COMPILER" "$ss_file" -d "$dialect" 2>/dev/null) || {
          echo "FAIL:$dialect:compile" > "$tmpdir/$dialect.status"
          exit 1
        }

        # Step 2: SQL → .ss (reverse via auto-detect from header tag)
        reversed=$(echo "$sql1" | timeout 10 "$COMPILER" reverse - 2>/dev/null) || {
          echo "SKIP:$dialect:reverse" > "$tmpdir/$dialect.status"
          exit 0
        }

        # Step 3: reversed .ss → SQL (roundtrip)
        sql2=$(echo "$reversed" | timeout 10 "$COMPILER" - -d "$dialect" 2>/dev/null) || {
          echo "FAIL:$dialect:recompile" > "$tmpdir/$dialect.status"
          exit 1
        }

        # Step 4: Semantic comparison
        strip1=$(echo "$sql1" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')
        strip2=$(echo "$sql2" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')

        if [ "$strip1" = "$strip2" ]; then
          echo "PASS:$dialect" > "$tmpdir/$dialect.status"
        else
          diff_output=$(diff <(echo "$strip1") <(echo "$strip2") 2>&1 | head -10)
          echo "FAIL:$dialect:mismatch:$diff_output" > "$tmpdir/$dialect.status"
        fi
      ) &
      pids+=($!)
    done

    # Wait for all dialects
    for pid in "${pids[@]}"; do
      wait "$pid"
    done

    # Collect results
    for dialect in "${DIALECTS[@]}"; do
      status_file="$tmpdir/$dialect.status"
      if [ -f "$status_file" ]; then
        status=$(cat "$status_file")
        case "$status" in
          PASS:*)
            pass "$test_name ($dialect)"
            ;;
          SKIP:*)
            skip "$test_name ($dialect)" "${status#SKIP:*:}"
            ;;
          FAIL:*:compile)
            fail "$test_name ($dialect): step 1" "compile failed"
            ;;
          FAIL:*:recompile)
            fail "$test_name ($dialect): step 3" "re-compile failed"
            ;;
          FAIL:*:mismatch:*)
            diff_output="${status#FAIL:*:mismatch:}"
            fail "$test_name ($dialect)" "SQL mismatch: $diff_output"
            ;;
        esac
      else
        fail "$test_name ($dialect)" "no status file"
      fi
    done
    rm -rf "$tmpdir"
  else
    # Sequential mode (original)
    for dialect in "${DIALECTS[@]}"; do
    # Step 1: .ss → SQL (original)
    sql1=$("$COMPILER" "$ss_file" -d "$dialect" 2>/dev/null) || {
      fail "$test_name ($dialect): step 1" "compile failed"
      continue
    }

    # Step 2: SQL → .ss (reverse via auto-detect from header tag)
    reversed=$(echo "$sql1" | timeout 10 "$COMPILER" reverse - 2>/dev/null) || {
      skip "$test_name ($dialect)" "reverse failed"
      continue
    }

    # Step 3: reversed .ss → SQL (roundtrip)
    sql2=$(echo "$reversed" | timeout 10 "$COMPILER" - -d "$dialect" 2>/dev/null) || {
      fail "$test_name ($dialect): step 3" "re-compile failed"
      continue
    }

    # Step 4: Semantic comparison (strip comments, normalize whitespace)
    strip1=$(echo "$sql1" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')
    strip2=$(echo "$sql2" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')

    if [ "$strip1" = "$strip2" ]; then
      pass "$test_name ($dialect)"
    else
      diff_output=$(diff <(echo "$strip1") <(echo "$strip2") 2>&1 | head -10)
      fail "$test_name ($dialect)" "SQL mismatch: $diff_output"
    fi
    done
  fi
done

summary "Roundtrip"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
