#!/usr/bin/env bash
# ── Rune Migrate Status Test Runner ──
# Tests: rune migrate status lists migration files correctly.
# Tests 3-digit (legacy), 4-digit, mixed prefixes, JSON output, and empty dirs.
# Usage: ./test_migrate_status.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FILTER="${1:-}"

header "Migrate Status Tests"

# Use a local test directory (avoids /tmp path issues on Windows)
TEST_BASE="$SCRIPT_DIR/_migrate_status_test"

cleanup() { rm -rf "$TEST_BASE"; }
trap cleanup EXIT
cleanup
mkdir -p "$TEST_BASE"

# ── Helper: create temp migration dir with specified files ──

setup_dir() {
  local dir="$1"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  for f in "$@"; do
    touch "$dir/$f"
  done
}

# ── Test 1: 4-digit sequences (current format) ──

test_4digit() {
  local tmpdir="$TEST_BASE/t4digit"
  setup_dir "$tmpdir" "0001_add_users.sql" "0002_add_posts.sql" "0003_add_comments.sql"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" 2>&1)

  if echo "$actual" | grep -q "0001.*add_users" && \
     echo "$actual" | grep -q "0002.*add_posts" && \
     echo "$actual" | grep -q "0003.*add_comments"; then
    pass "4-digit sequences"
  else
    fail "4-digit sequences" "output: $actual"
  fi
}

# ── Test 2: 3-digit sequences (legacy format) ──

test_3digit() {
  local tmpdir="$TEST_BASE/t3digit"
  setup_dir "$tmpdir" "001_old_migration.sql" "002_another.sql"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" 2>&1)

  if echo "$actual" | grep -q "001.*old_migration" && \
     echo "$actual" | grep -q "002.*another"; then
    pass "3-digit legacy sequences"
  else
    fail "3-digit legacy sequences" "output: $actual"
  fi
}

# ── Test 3: Mixed 3-digit and 4-digit ──

test_mixed() {
  local tmpdir="$TEST_BASE/tmixed"
  setup_dir "$tmpdir" "001_legacy.sql" "0001_modern.sql" "0002_new.sql"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" 2>&1)

  if echo "$actual" | grep -q "001.*legacy" && \
     echo "$actual" | grep -q "0001.*modern" && \
     echo "$actual" | grep -q "0002.*new"; then
    pass "mixed 3/4-digit sequences"
  else
    fail "mixed 3/4-digit sequences" "output: $actual"
  fi
}

# ── Test 4: Empty directory ──

test_empty() {
  local tmpdir="$TEST_BASE/tempty"
  mkdir -p "$tmpdir"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" 2>&1)

  if echo "$actual" | grep -qi "no migration files"; then
    pass "empty directory"
  else
    fail "empty directory" "output: $actual"
  fi
}

# ── Test 5: Non-migration files are ignored ──

test_non_migration() {
  local tmpdir="$TEST_BASE/tnonmig"
  setup_dir "$tmpdir" "0001_valid.sql" "readme.txt" "schema.sql" "9999_.sql" "abc_not_a_number.sql"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" 2>&1)

  if echo "$actual" | grep -q "0001.*valid" && \
     ! echo "$actual" | grep -q "readme" && \
     ! echo "$actual" | grep -q "schema.sql" && \
     ! echo "$actual" | grep -q "abc_not"; then
    pass "non-migration files ignored"
  else
    fail "non-migration files ignored" "output: $actual"
  fi
}

# ── Test 6: JSON output ──

test_json_output() {
  local tmpdir="$TEST_BASE/tjson"
  setup_dir "$tmpdir" "0001_add_users.sql" "0002_add_posts.sql"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" --json-errors 2>&1)

  if echo "$actual" | grep -q '"files"' && \
     echo "$actual" | grep -q '"count":2' && \
     echo "$actual" | grep -q '"name":"0001_add_users.sql"' && \
     echo "$actual" | grep -q '"label":"add_users"'; then
    pass "JSON output"
  else
    fail "JSON output" "output: $actual"
  fi
}

# ── Test 7: JSON output empty ──

test_json_empty() {
  local tmpdir="$TEST_BASE/tjsonempty"
  mkdir -p "$tmpdir"

  local actual
  actual=$("$COMPILER" migrate status --dir "$tmpdir" --json-errors 2>&1)

  if echo "$actual" | grep -q '"files":\[\]' && \
     echo "$actual" | grep -q '"count":0'; then
    pass "JSON output empty"
  else
    fail "JSON output empty" "output: $actual"
  fi
}

# ── Run tests ──

if [[ -z "$FILTER" || "$FILTER" == *"4digit"* ]]; then test_4digit; fi
if [[ -z "$FILTER" || "$FILTER" == *"3digit"* ]]; then test_3digit; fi
if [[ -z "$FILTER" || "$FILTER" == *"mixed"* ]]; then test_mixed; fi
if [[ -z "$FILTER" || "$FILTER" == *"empty"* ]]; then test_empty; fi
if [[ -z "$FILTER" || "$FILTER" == *"non_migration"* ]]; then test_non_migration; fi
if [[ -z "$FILTER" || "$FILTER" == *"json"* ]]; then test_json_output; fi
if [[ -z "$FILTER" || "$FILTER" == *"json_empty"* ]]; then test_json_empty; fi

summary "Migrate Status"
