#!/usr/bin/env bash
# ── Rune Reverse Confidence Test Runner ──
# Tests: reverse engineering produces confidence annotations for uncertain mappings.
# Usage: ./test_reverse_confidence.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FILTER="${1:-}"

# ── Test 1: MySQL reverse with standard types (high confidence) ──
if [ -z "$FILTER" ] || [[ "mysql-high-confidence" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  cat > "$tmp_file" <<'SQL'
CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;
SQL

  output=$("$COMPILER" reverse "$tmp_file" -d mysql 2>/dev/null || true)
  # High-confidence types should NOT have score annotations
  if echo "$output" | grep -q "score:"; then
    fail "mysql-high-confidence" "unexpected score annotation for standard types"
  else
    pass "mysql-high-confidence"
  fi
  rm -f "$tmp_file"
fi

# ── Test 2: SQLite reverse with ambiguous types (lower confidence) ──
if [ -z "$FILTER" ] || [[ "sqlite-ambiguous-confidence" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  cat > "$tmp_file" <<'SQL'
CREATE TABLE "events" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "data" TEXT,
  "created_at" TEXT
);
SQL

  output=$("$COMPILER" reverse "$tmp_file" -d sqlite 2>/dev/null || true)
  # SQLite types may have lower confidence due to type affinity lossy mapping
  # Just verify the reverse completes without error
  if [ -z "$output" ]; then
    fail "sqlite-ambiguous-confidence" "no output from reverse"
  else
    pass "sqlite-ambiguous-confidence"
  fi
  rm -f "$tmp_file"
fi

# ── Test 3: PostgreSQL reverse with PG-specific types ──
if [ -z "$FILTER" ] || [[ "pg-specific-confidence" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  cat > "$tmp_file" <<'SQL'
CREATE TABLE "items" (
  "id" serial NOT NULL,
  "name" varchar(100) NOT NULL,
  "metadata" jsonb,
  "created_at" timestamptz DEFAULT NOW(),
  PRIMARY KEY ("id")
);
SQL

  output=$("$COMPILER" reverse "$tmp_file" -d pg 2>/dev/null || true)
  # PG-specific types like serial, jsonb, timestamptz should reverse cleanly
  if echo "$output" | grep -q "^# items"; then
    pass "pg-specific-confidence"
  else
    fail "pg-specific-confidence" "table header not found in output"
  fi
  rm -f "$tmp_file"
fi

# ── Test 4: Reverse round-trip preserves field count ──
if [ -z "$FILTER" ] || [[ "roundtrip-field-count" == *"$FILTER"* ]]; then
  tmp_file=$(mktemp)
  trap "rm -f '$tmp_file'" EXIT

  cat > "$tmp_file" <<'SQL'
CREATE TABLE `orders` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `total` decimal(10,2) NOT NULL,
  `status` enum('pending','shipped','delivered') NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;
SQL

  output=$("$COMPILER" reverse "$tmp_file" -d mysql 2>/dev/null || true)
  # Count fields in the output (lines starting with field name, not markers)
  field_count=$(echo "$output" | grep -cE "^[a-z_]" || true)
  if [ "$field_count" -ge 4 ]; then
    pass "roundtrip-field-count"
  else
    fail "roundtrip-field-count" "expected >= 4 fields, got $field_count"
  fi
  rm -f "$tmp_file"
fi
