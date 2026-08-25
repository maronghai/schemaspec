#!/usr/bin/env bash
# ── Rune Reverse Test Runner ──
# Tests: rune reverse <sql> [-d dialect] produces expected .ss output.
# Usage: ./test_reverse.sh [test-filter]

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR/reverse"

FILTER="${1:-}"

for sql_file in "$TEST_DIR"/*.sql; do
  [ -f "$sql_file" ] || continue
  base=$(basename "$sql_file" .sql)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then
    continue
  fi

  for dialect_suffix in mysql pg sqlite; do
    expected_file="$TEST_DIR/$base.$dialect_suffix.ss"
    if [ ! -f "$expected_file" ]; then
      continue
    fi

    case "$dialect_suffix" in
      mysql)  dialect="mysql" ;;
      pg)     dialect="pg" ;;
      sqlite) dialect="sqlite" ;;
    esac

    tmp_file=$(mktemp)
    trap "rm -f '$tmp_file'" EXIT

    if ! "$COMPILER" reverse "$sql_file" -d "$dialect" -o "$tmp_file" 2>/dev/null; then
      fail "$base ($dialect)" "compiler failed"
      rm -f "$tmp_file"
      continue
    fi

    if compare_files "$expected_file" "$tmp_file"; then
      pass "$base ($dialect)"
    else
      diff_output=$(diff_versions "$expected_file" "$tmp_file")
      fail "$base ($dialect)" "$diff_output"
    fi

    rm -f "$tmp_file"
  done
done

# JSON output validity: `reverse --format json` must produce parseable JSON
# for a schema with columns lacking bool flags and with FKs (the emitter's
# comma discipline broke both shapes before v0.335.0).
if [ -z "$FILTER" ] || [[ "json" == *"$FILTER"* ]]; then
  tmp_sql=$(mktemp)
  tmp_json=$(mktemp)
  printf 'CREATE TABLE orders (id INT PRIMARY KEY, user_id INT NOT NULL);\nALTER TABLE orders ADD FOREIGN KEY (user_id) REFERENCES users(id);\n' > "$tmp_sql"
  if "$COMPILER" reverse "$tmp_sql" --format json > "$tmp_json" 2>/dev/null && python -m json.tool < "$tmp_json" > /dev/null 2>&1; then
    pass "json-output-valid"
  else
    fail "json-output-valid" "reverse --format json did not parse as JSON: $(head -c 200 "$tmp_json")"
  fi
  rm -f "$tmp_sql" "$tmp_json"
fi

summary "Reverse"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
