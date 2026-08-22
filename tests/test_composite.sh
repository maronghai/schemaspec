#!/bin/bash
# ── Test: composite types (* name declarations + embeds) ──
source "$(dirname "$0")/lib.sh"

header "composite types"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/app.ss" <<'EOF'
$ myapp

* audit
created_at t+
updated_at t++
created_by s64 > users.id

* soft_delete
deleted_at t?

#users
id   n++
name s32

#orders
id n++
*audit
total m
*soft_delete
status e(open,paid,shipped)

#logs
id n++
*audit
message S
EOF

cd "$TMPDIR"

# Test 1: composite fields expand at embed position with modifiers intact
TEST_NAME="composite expands in place with modifiers"
OUTPUT=$("$COMPILER" app.ss 2>&1)
if echo "$OUTPUT" | grep -q '`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP' \
   && echo "$OUTPUT" | grep -q '`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 2: embed position is respected (fields appear between surrounding columns)
TEST_NAME="embed position respected (audit before total)"
OUTPUT=$("$COMPILER" app.ss 2>&1)
ORDER=$(echo "$OUTPUT" | sed -n '/CREATE TABLE `orders`/,/ENGINE/p' | grep -oE '^\s+`[a-z_]+`' | tr -d ' `' | paste -sd, -)
if [ "$ORDER" = "id,created_at,updated_at,created_by,total,deleted_at,status" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (got: $ORDER)" "$OUTPUT"
fi

# Test 3: inline FK inside a composite is preserved
TEST_NAME="inline FK inside composite preserved"
OUTPUT=$("$COMPILER" app.ss 2>&1)
if echo "$OUTPUT" | grep -q 'FOREIGN KEY (`created_by`) REFERENCES `users`(`id`)'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 4: same composite embedded in multiple tables
TEST_NAME="same composite embeds into multiple tables"
OUTPUT=$("$COMPILER" app.ss 2>&1)
CNT=$(echo "$OUTPUT" | grep -c '`created_by` varchar(64) NOT NULL')
if [ "$CNT" = "2" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (count=$CNT)" "$OUTPUT"
fi

# Test 5: unknown composite reference errors
cat > "$TMPDIR/bad1.ss" <<'EOF'
$ myapp

#t1
id n++
*nope
EOF
TEST_NAME="unknown composite errors"
OUTPUT=$("$COMPILER" bad1.ss 2>&1)
RC=$?
if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -q "unknown composite: 'nope'"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (rc=$RC)" "$OUTPUT"
fi

# Test 6: duplicate composite definition errors
cat > "$TMPDIR/bad2.ss" <<'EOF'
$ myapp

* dup
x n

* dup
y n

#t1
id n++
*dup
EOF
TEST_NAME="duplicate composite definition errors"
OUTPUT=$("$COMPILER" bad2.ss 2>&1)
RC=$?
if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -q "duplicate composite definition: 'dup'"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (rc=$RC)" "$OUTPUT"
fi

# Test 7: unused composite warns but compiles
cat > "$TMPDIR/warn.ss" <<'EOF'
$ myapp

* orphan
x n

#t1
id n++
EOF
TEST_NAME="unused composite warns without failing"
OUTPUT=$("$COMPILER" warn.ss 2>&1)
RC=$?
if [ $RC -eq 0 ] && echo "$OUTPUT" | grep -q "unused composite: 'orphan'"; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (rc=$RC)" "$OUTPUT"
fi

# Test 8: consecutive composite declarations are sequential (no explicit terminator)
cat > "$TMPDIR/seq.ss" <<'EOF'
$ myapp

* first
x n

* second
y s32

#t1
id n++
*first
*second
EOF
TEST_NAME="consecutive composite declarations are sequential"
OUTPUT=$("$COMPILER" seq.ss 2>&1)
RC=$?
if [ $RC -eq 0 ] && echo "$OUTPUT" | grep -q '`x` int NOT NULL' && echo "$OUTPUT" | grep -q '`y` varchar(32) NOT NULL'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (rc=$RC)" "$OUTPUT"
fi

# Test 9: suffix inference works on expanded fields (autofk + _id inference)
cat > "$TMPDIR/sfx.ss" <<'EOF'
$ myapp autofk

* audit
owner_id

#orders
id n++
*audit
EOF
TEST_NAME="suffix inference applies to expanded composite fields"
OUTPUT=$("$COMPILER" sfx.ss 2>&1)
if echo "$OUTPUT" | grep -q '`owner_id` int NOT NULL'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 10: composite works across dialects (pg)
TEST_NAME="composite compiles for pg dialect"
OUTPUT=$("$COMPILER" app.ss -d pg 2>&1)
if echo "$OUTPUT" | grep -q '"created_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP' \
   && echo "$OUTPUT" | grep -q '"deleted_at" timestamp'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME" "$OUTPUT"
fi

# Test 11: @if(dialect=) wrapping an embed line gates the expansion
cat > "$TMPDIR/cond.ss" <<'EOF'
$ myapp

* audit
created_at t+
updated_at t++

#orders
id n++
@if(dialect=pg)
*audit
@endif
name s32
EOF
TEST_NAME="@if-wrapped embed expands only for matching dialect"
PG_OUT=$("$COMPILER" cond.ss -d pg 2>&1)
SQLITE_OUT=$("$COMPILER" cond.ss -d sqlite 2>&1)
if echo "$PG_OUT" | grep -q '"created_at"' && ! echo "$SQLITE_OUT" | grep -q 'created_at'; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (pg has audit: $(echo "$PG_OUT" | grep -c created_at), sqlite has audit: $(echo "$SQLITE_OUT" | grep -c created_at))" "$SQLITE_OUT"
fi

# Test 12: embed position survives template merge (template inserts before it)
cat > "$TMPDIR/tpl.ss" <<'EOF'
$ myapp

* audit
created_at t+
updated_at t++

% base
id n++

#users > base
*audit
name s32
EOF
TEST_NAME="embed lands after template-merged fields"
TPL_OUT=$("$COMPILER" tpl.ss 2>&1)
ORDER=$(echo "$TPL_OUT" | sed -n '/CREATE TABLE `users`/,/ENGINE/p' | grep -oE '^\s+`[a-z_]+`' | tr -d ' `' | paste -sd, -)
if [ "$ORDER" = "id,created_at,updated_at,name" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (got: $ORDER)" "$TPL_OUT"
fi

# Test 13: embed position shifts when a conditional field before it is stripped
cat > "$TMPDIR/shift.ss" <<'EOF'
$ myapp

* audit
created_at t+

#orders
id n++
@if(dialect=mysql)
mysql_only T
@endif
*audit
name s32
EOF
TEST_NAME="embed position shifts after conditional strip"
PG_OUT=$("$COMPILER" shift.ss -d pg 2>&1)
MYSQL_OUT=$("$COMPILER" shift.ss -d mysql 2>&1)
PG_ORDER=$(echo "$PG_OUT" | sed -n '/CREATE TABLE "orders"/,/);/p' | grep -oE '^\s+"[a-z_]+"' | tr -d ' "' | paste -sd, -)
MYSQL_ORDER=$(echo "$MYSQL_OUT" | sed -n '/CREATE TABLE `orders`/,/ENGINE/p' | grep -oE '^\s+`[a-z_]+`' | tr -d ' `' | paste -sd, -)
if [ "$PG_ORDER" = "id,created_at,name" ] && [ "$MYSQL_ORDER" = "id,mysql_only,created_at,name" ]; then
  pass "$TEST_NAME"
else
  fail "$TEST_NAME (pg: $PG_ORDER, mysql: $MYSQL_ORDER)" "$PG_OUT"
fi

summary
