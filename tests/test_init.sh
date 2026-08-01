#!/bin/bash
# ── Test: rune init command ──
source "$(dirname "$0")/lib.sh"

header "rune init"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Test 1: init creates default schema.ss
TEST_NAME="init creates schema.ss"
cd "$TMPDIR"
"$COMPILER" init > /dev/null 2>&1
if [ -f "schema.ss" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "schema.ss not created"
fi

# Test 2: generated schema compiles without errors
TEST_NAME="generated schema compiles"
OUTPUT=$("$COMPILER" schema.ss 2>&1)
if [ $? -eq 0 ] && echo "$OUTPUT" | grep -q "CREATE TABLE"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 3: init with custom name
TEST_NAME="init with custom name"
"$COMPILER" init myapp > /dev/null 2>&1
if [ -f "myapp.ss" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "myapp.ss not created"
fi

# Test 4: init with -o flag
TEST_NAME="init with -o flag"
"$COMPILER" init -o custom.ss > /dev/null 2>&1
if [ -f "custom.ss" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "custom.ss not created"
fi

# Test 5: completions bash
TEST_NAME="completions bash outputs script"
OUTPUT=$("$COMPILER" completions bash 2>&1)
if echo "$OUTPUT" | grep -q "_rune_completions"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "bash completions not generated"
fi

# Test 6: completions zsh
TEST_NAME="completions zsh outputs script"
OUTPUT=$("$COMPILER" completions zsh 2>&1)
if echo "$OUTPUT" | grep -q "_rune"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "zsh completions not generated"
fi

# Test 7: completions fish
TEST_NAME="completions fish outputs script"
OUTPUT=$("$COMPILER" completions fish 2>&1)
if echo "$OUTPUT" | grep -q "complete -c rune"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "fish completions not generated"
fi

# Test 8: completions powershell
TEST_NAME="completions powershell outputs script"
OUTPUT=$("$COMPILER" completions powershell 2>&1)
if echo "$OUTPUT" | grep -q "Register-ArgumentCompleter"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "powershell completions not generated"
fi

# Test 9: completions unknown shell fails
TEST_NAME="completions unknown shell fails"
"$COMPILER" completions unknown > /dev/null 2>&1
if [ $? -ne 0 ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "should fail for unknown shell"
fi

# Test 10: init schema compiles to MySQL by default
TEST_NAME="default MySQL output"
cd "$TMPDIR"
rm -f schema.ss
"$COMPILER" init > /dev/null 2>&1
OUTPUT=$("$COMPILER" schema.ss 2>&1)
if echo "$OUTPUT" | grep -q "ENGINE=InnoDB"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected MySQL output"
fi

# Test 11: init schema compiles to PostgreSQL
TEST_NAME="PostgreSQL output"
OUTPUT=$("$COMPILER" schema.ss -d pg 2>&1)
if echo "$OUTPUT" | grep -q "CREATE TABLE"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected PostgreSQL output"
fi

# Test 12: init schema compiles to SQLite
TEST_NAME="SQLite output"
OUTPUT=$("$COMPILER" schema.ss -d sqlite 2>&1)
if echo "$OUTPUT" | grep -q "CREATE TABLE"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected SQLite output"
fi

summary "rune init"
exit $FAIL
