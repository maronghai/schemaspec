#!/usr/bin/env bash
# Golden tests for `rune stats --format json`
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

header "Stats JSON Tests"

TEST_DIR="$SCRIPT_DIR"

# Empty schema — all keys present
output=$("$COMPILER" stats "$TEST_DIR"/01-schema-only.ss --format json 2>&1) && exit_code=0 || exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  missing=0
  for key in tables fields indexes templates; do
    echo "$output" | grep -q "\"$key\"" || missing=1
  done
  if [ "$missing" -eq 0 ]; then
    pass "stats json: empty schema keys"
  else
    fail "stats json: empty schema keys" "missing key in: $output"
  fi
else
  fail "stats json: empty schema keys" "exit=$exit_code"
fi

# All-types schema — fields and type breakdown
output=$("$COMPILER" stats "$TEST_DIR"/03-all-types.ss --format json 2>&1) && exit_code=0 || exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  missing=0
  for key in tables fields numeric string datetime boolean templates; do
    echo "$output" | grep -q "\"$key\"" || missing=1
  done
  if [ "$missing" -eq 0 ]; then
    pass "stats json: full key set"
  else
    fail "stats json: full key set" "missing key in: $output"
  fi
else
  fail "stats json: full key set" "exit=$exit_code"
fi

# Indexes counted
output=$("$COMPILER" stats "$TEST_DIR"/20-index-types.ss --format json 2>&1) && exit_code=0 || exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  val=$(echo "$output" | grep -o '"indexes":[0-9]*' | head -1 | cut -d: -f2)
  if [ "${val:-0}" -ge 1 ]; then
    pass "stats json: indexes counted"
  else
    fail "stats json: indexes counted" "indexes=$val, expected ≥ 1"
  fi
else
  fail "stats json: indexes counted" "exit=$exit_code"
fi

summary "Stats JSON"
