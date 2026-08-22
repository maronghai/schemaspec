#!/usr/bin/env bash
# Test colored diff output (--color flag)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# .exe suffix on Windows/MSYS — the extensionless file is a Linux ELF there.
case "$OSTYPE" in
  msys*|cygwin*|win32) BIN="$ROOT_DIR/rune/zig-out/bin/rune.exe" ;;
  *)                   BIN="$ROOT_DIR/rune/zig-out/bin/rune" ;;
esac

pass=0
fail=0

# Test: --color never produces plain text (no ANSI escape codes)
echo "Test: --color never produces no ANSI escape codes"
output=$("$BIN" diff "$ROOT_DIR/tests/diff/table-drop-old.ss" "$ROOT_DIR/tests/diff/table-drop-new.ss" --color never 2>&1 || true)
if echo "$output" | grep -q $'\x1b\['; then
    echo "  FAIL: --color never output contains ANSI escape codes"
    fail=$((fail + 1))
else
    echo "  PASS: --color never produces plain text"
    pass=$((pass + 1))
fi

# Test: --color always produces ANSI escape codes (when diff has changes)
echo "Test: --color always produces ANSI escape codes"
output=$("$BIN" diff "$ROOT_DIR/tests/diff/table-drop-old.ss" "$ROOT_DIR/tests/diff/table-drop-new.ss" --color always 2>&1 || true)
if echo "$output" | grep -q $'\x1b\['; then
    echo "  PASS: --color always produces ANSI escape codes"
    pass=$((pass + 1))
else
    echo "  FAIL: --color always output missing ANSI escape codes"
    fail=$((fail + 1))
fi

# Test: --color always diff contains colored DROP TABLE (red)
echo "Test: --color always contains red for DROP TABLE"
output=$("$BIN" diff "$ROOT_DIR/tests/diff/table-drop-old.ss" "$ROOT_DIR/tests/diff/table-drop-new.ss" --color always 2>&1 || true)
if echo "$output" | grep -q $'\x1b\[31m'; then
    echo "  PASS: DROP TABLE is red"
    pass=$((pass + 1))
else
    echo "  FAIL: DROP TABLE missing red color"
    fail=$((fail + 1))
fi

# Test: diff summary shows table count
echo "Test: diff summary shows table count"
output=$("$BIN" diff "$ROOT_DIR/tests/diff/table-drop-old.ss" "$ROOT_DIR/tests/diff/table-drop-new.ss" --color never 2>&1 || true)
if echo "$output" | grep -q "table.*changed"; then
    echo "  PASS: diff summary present"
    pass=$((pass + 1))
else
    echo "  FAIL: diff summary missing"
    fail=$((fail + 1))
fi

# Test: no diff produces no summary
echo "Test: identical files produce no summary"
output=$("$BIN" diff "$ROOT_DIR/tests/diff/same.ss" "$ROOT_DIR/tests/diff/same.ss" --color never 2>&1 || true)
if echo "$output" | grep -q "table.*changed"; then
    echo "  FAIL: identical files should not show summary"
    fail=$((fail + 1))
else
    echo "  PASS: identical files produce no summary"
    pass=$((pass + 1))
fi

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
