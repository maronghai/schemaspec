#!/usr/bin/env bash
# ── Rune Stdin Pipeline Test ──
# Tests: rune can read from stdin when no file is provided.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FILTER="${1:-}"

# Test 1: Basic stdin input
if [ -z "$FILTER" ] || [[ "stdin-basic" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  ss_input='# user
id n++
name s'

  if echo "$ss_input" | "$COMPILER" > "$tmp_file" 2>/dev/null; then
    if grep -q "CREATE TABLE" "$tmp_file"; then
      pass "stdin-basic"
    else
      fail "stdin-basic" "no CREATE TABLE in output"
    fi
  else
    fail "stdin-basic" "compile failed"
  fi
  rm -f "$tmp_file"
fi

# Test 2: Stdin with dialect flag
if [ -z "$FILTER" ] || [[ "stdin-pg" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  ss_input='# user
id n++
name s'

  if echo "$ss_input" | "$COMPILER" -d pg > "$tmp_file" 2>/dev/null; then
    if grep -q "CREATE TABLE" "$tmp_file"; then
      pass "stdin-pg"
    else
      fail "stdin-pg" "no CREATE TABLE in output"
    fi
  else
    fail "stdin-pg" "compile failed"
  fi
  rm -f "$tmp_file"
fi

# Test 3: Stdin with output flag
if [ -z "$FILTER" ] || [[ "stdin-output" == *"$FILTER"* ]]; then
  tmp_out=$(mktemp)
  ss_input='# user
id n++
name s'

  if echo "$ss_input" | "$COMPILER" -o "$tmp_out" 2>/dev/null; then
    if grep -q "CREATE TABLE" "$tmp_out"; then
      pass "stdin-output"
    else
      fail "stdin-output" "no CREATE TABLE in output file"
    fi
  else
    fail "stdin-output" "compile failed"
  fi
  rm -f "$tmp_out"
fi

# Test 4: Stdin with check mode
if [ -z "$FILTER" ] || [[ "stdin-check" == *"$FILTER"* ]]; then
  ss_input='# user
id n++
name s'

  output=$(echo "$ss_input" | "$COMPILER" --check 2>&1)
  if echo "$output" | grep -q "schema is valid"; then
    pass "stdin-check"
  else
    fail "stdin-check" "expected 'schema is valid', got: $output"
  fi
fi

summary "Stdin"
