#!/bin/bash
# ── Test: rune registry command (Schema Registry foundation) ──
source "$(dirname "$0")/lib.sh"

header "rune registry"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Isolate the registry under a temp HOME so ~/.rune/registry does not pollute
# the real user environment and tests stay deterministic.
REG_HOME="$TMPDIR/home"
mkdir -p "$REG_HOME"
export HOME="$REG_HOME"
export USERPROFILE="$REG_HOME"

# A sample template file for `registry add`.
TMPL="$TMPDIR/audit.ss"
cat > "$TMPL" <<'EOF'
// User audit columns template
T audit {
  + created_at t
  + updated_at t
}
EOF

# Test 1: registry with no subcommand fails
TEST_NAME="registry with no subcommand fails"
"$COMPILER" registry > /dev/null 2>&1
if [ $? -ne 0 ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected non-zero exit"
fi

# Test 2: list before init shows friendly error
TEST_NAME="list before init errors"
OUTPUT=$("$COMPILER" registry list 2>&1)
if echo "$OUTPUT" | grep -q "Registry not initialized"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 3: init creates registry directory
TEST_NAME="init creates ~/.rune/registry"
"$COMPILER" registry init > /dev/null 2>&1
if [ -d "$REG_HOME/.rune/registry" ] && [ -f "$REG_HOME/.rune/registry/meta.json" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "registry dir/meta not created"
fi

# Test 4: add a template
TEST_NAME="add template"
"$COMPILER" registry add audit "$TMPL" > /dev/null 2>&1
if [ -f "$REG_HOME/.rune/registry/templates/audit/template.ss" ] && [ -f "$REG_HOME/.rune/registry/templates/audit/meta.json" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "template.ss/meta.json not created"
fi

# Test 5: list shows the template
TEST_NAME="list shows template"
OUTPUT=$("$COMPILER" registry list 2>&1)
if echo "$OUTPUT" | grep -q "audit" && echo "$OUTPUT" | grep -q "User audit columns template"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 6: show displays metadata + content
TEST_NAME="show displays content"
OUTPUT=$("$COMPILER" registry show audit 2>&1)
if echo "$OUTPUT" | grep -q "Template: audit" && echo "$OUTPUT" | grep -q "created_at t"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 7: add with missing file fails
TEST_NAME="add missing file fails"
"$COMPILER" registry add missing "$TMPDIR/does-not-exist.ss" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected non-zero exit"
fi

# Test 8: show nonexistent fails
TEST_NAME="show nonexistent fails"
"$COMPILER" registry show nope > /dev/null 2>&1
if [ $? -ne 0 ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected non-zero exit"
fi

# Test 9: remove template
TEST_NAME="remove template"
"$COMPILER" registry remove audit > /dev/null 2>&1
if [ ! -d "$REG_HOME/.rune/registry/templates/audit" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "template dir still present"
fi

# Test 10: list empty after remove
TEST_NAME="list empty after remove"
OUTPUT=$("$COMPILER" registry list 2>&1)
if echo "$OUTPUT" | grep -q "No templates in registry"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

summary "rune registry"
exit $FAIL
