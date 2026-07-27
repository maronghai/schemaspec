#!/usr/bin/env bash
# ── Rune Import System Test ──
# Tests: @import directive — normal, circular, nested imports.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
FILTER="${1:-}"

# ─── Test 1: Basic import ────────────────────────────────────────
if [ -z "$FILTER" ] || [[ "import-basic" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  if "$COMPILER" "$TEST_DIR/import_test2.ss" -o "$tmp_file" 2>/dev/null; then
    # Should contain fields from both import_test2.ss and import_simple.ss
    if grep -q "name" "$tmp_file" && grep -q "items" "$tmp_file"; then
      pass "import-basic"
    else
      fail "import-basic" "missing imported fields"
    fi
  else
    fail "import-basic" "compiler failed"
  fi
  rm -f "$tmp_file"
fi

# ─── Test 2: Import template ────────────────────────────────────
if [ -z "$FILTER" ] || [[ "import-template" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  if "$COMPILER" "$TEST_DIR/import_tmpl_main.ss" -o "$tmp_file" 2>/dev/null; then
    # Should contain template-inherited fields
    if grep -q "created_at" "$tmp_file"; then
      pass "import-template"
    else
      fail "import-template" "missing template fields"
    fi
  else
    fail "import-template" "compiler failed"
  fi
  rm -f "$tmp_file"
fi

# ─── Test 3: Nested import (A imports B imports C) ──────────────
if [ -z "$FILTER" ] || [[ "import-nested" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  if "$COMPILER" "$TEST_DIR/import_nested_main.ss" -o "$tmp_file" 2>/dev/null; then
    # Should contain fields from nested imports
    if grep -q "created_at" "$tmp_file"; then
      pass "import-nested"
    else
      fail "import-nested" "missing nested imported fields"
    fi
  else
    fail "import-nested" "compiler failed"
  fi
  rm -f "$tmp_file"
fi

# ─── Test 4: Circular import detection ──────────────────────────
if [ -z "$FILTER" ] || [[ "import-circular" == *"$FILTER"* ]]; then
  # Create temporary circular import files
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" EXIT

  cat > "$tmp_dir/a.ss" <<'EOF'
@import "b.ss"
# table_a
id n++
EOF

  cat > "$tmp_dir/b.ss" <<'EOF'
@import "a.ss"
# table_b
id n++
EOF

  # Should fail with circular import error
  if "$COMPILER" "$tmp_dir/a.ss" 2>/dev/null; then
    fail "import-circular" "should have failed on circular import"
  else
    pass "import-circular"
  fi
fi

# ─── Test 5: Import missing file ────────────────────────────────
if [ -z "$FILTER" ] || [[ "import-missing" == *"$FILTER"* ]]; then
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" EXIT

  cat > "$tmp_dir/main.ss" <<'EOF'
@import "nonexistent.ss"
# table
id n++
EOF

  # Should fail with file not found error
  if "$COMPILER" "$tmp_dir/main.ss" 2>/dev/null; then
    fail "import-missing" "should have failed on missing import"
  else
    pass "import-missing"
  fi
fi

# ─── Test 6: Import with different dialects ─────────────────────
if [ -z "$FILTER" ] || [[ "import-dialect" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  if "$COMPILER" "$TEST_DIR/import_test2.ss" -d pg -o "$tmp_file" 2>/dev/null; then
    if grep -q "name" "$tmp_file"; then
      pass "import-dialect"
    else
      fail "import-dialect" "missing imported fields with pg dialect"
    fi
  else
    fail "import-dialect" "compiler failed with pg dialect"
  fi
  rm -f "$tmp_file"
fi

summary "Import"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
