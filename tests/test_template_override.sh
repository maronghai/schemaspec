#!/bin/bash
# ── Test: template overrides (.rune-template files) ──
source "$(dirname "$0")/lib.sh"

header "template override"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/app.ss" <<'EOF'
$ myapp

#user : 用户表
id    n++
name  s32
email s128

#order
id      n++
user_id
amount  m

> user_id user.id
EOF

cd "$TMPDIR"

# Test 1: no template → built-in output (fallback)
TEST_NAME="no template falls back to builtin output"
OUTPUT=$("$COMPILER" generate prisma app.ss --dry-run 2>&1)
if echo "$OUTPUT" | grep -q 'model user {' && ! echo "$OUTPUT" | grep -q 'TEMPLATE-MARKER'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 2: project-local .rune/templates/ override applies
TEST_NAME="project-local .rune/templates override applies"
mkdir -p .rune/templates
cat > .rune/templates/prisma.rune-template <<'EOF'
// TEMPLATE-MARKER {{SCHEMA_NAME}} {{DIALECT}}
{{#TABLES}}entity {{TABLE_NAME}}
{{/TABLES}}
EOF
OUTPUT=$("$COMPILER" generate prisma app.ss --dry-run 2>&1)
if echo "$OUTPUT" | grep -q 'TEMPLATE-MARKER myapp mysql' \
   && echo "$OUTPUT" | grep -q '^entity user$' \
   && echo "$OUTPUT" | grep -q '^entity order$' \
   && ! echo "$OUTPUT" | grep -q '@default(autoincrement)'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 3: --template-dir explicit dir wins over project-local
TEST_NAME="--template-dir explicit dir wins over project-local"
mkdir -p explicit
echo '// EXPLICIT-MARKER {{GENERATOR}}' > explicit/prisma.rune-template
OUTPUT=$("$COMPILER" generate prisma app.ss --dry-run --template-dir explicit 2>&1)
if echo "$OUTPUT" | grep -q 'EXPLICIT-MARKER prisma' && ! echo "$OUTPUT" | grep -q 'TEMPLATE-MARKER'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 4: loop expansion with multiple tables in order
TEST_NAME="tables loop expands every table in order"
rm -f explicit/prisma.rune-template
OUTPUT=$("$COMPILER" generate prisma app.ss --dry-run 2>&1)
if [ "$(echo "$OUTPUT" | grep -c '^entity ')" -eq 2 ] \
   && echo "$OUTPUT" | grep -q '^entity user$' \
   && echo "$OUTPUT" | grep -q '^entity order$'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 5: batch mode — overridden generator uses template, others stay builtin
TEST_NAME="batch mode mixes override and builtin output"
OUTPUT=$("$COMPILER" generate --generators prisma,drizzle app.ss --dry-run 2>&1)
if echo "$OUTPUT" | grep -q 'TEMPLATE-MARKER myapp' \
   && echo "$OUTPUT" | grep -q 'mysqlTable'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 6: unmatched {{#TABLES}} block errors and exits non-zero
TEST_NAME="unmatched tables block errors with non-zero exit"
echo '{{#TABLES}}never closed' > .rune/templates/prisma.rune-template
"$COMPILER" generate prisma app.ss --dry-run > /dev/null 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "expected non-zero exit, got 0"
fi

# Test 7: unknown placeholders pass through verbatim
TEST_NAME="unknown placeholders remain verbatim"
echo '// KEEPME {{NOT_A_PLACEHOLDER}} {{SCHEMA_NAME}}' > .rune/templates/prisma.rune-template
OUTPUT=$("$COMPILER" generate prisma app.ss --dry-run 2>&1)
if echo "$OUTPUT" | grep -q '{{NOT_A_PLACEHOLDER}}' && echo "$OUTPUT" | grep -q 'myapp'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 8: --dry-run combination does not write files
TEST_NAME="override with --dry-run writes no files"
rm -f .rune/templates/prisma.rune-template
cat > .rune/templates/json-schema.rune-template <<'EOF'
{"overridden": "{{SCHEMA_NAME}}"}
EOF
rm -f json-schema.json
"$COMPILER" generate json-schema app.ss --dry-run > /dev/null 2>&1
if [ ! -f "json-schema.json" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "json-schema.json was written despite --dry-run"
fi

# Test 9: override without --dry-run writes the rendered content to file
TEST_NAME="override without dry-run writes rendered file"
"$COMPILER" generate json-schema app.ss -o out.json > /dev/null 2>&1
if [ -f "out.json" ] && grep -q '"overridden": "myapp"' out.json; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$(cat out.json 2>/dev/null || echo 'out.json missing')"
fi

summary
