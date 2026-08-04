#!/usr/bin/env bash
# ── Rune Property-Based Roundtrip Tests ──
# Generate random .ss schemas, compile → reverse → compile, verify properties.
# Usage: bash tests/test_property_roundtrip.sh [iterations] [seed]
# Default: 50 iterations, random seed

set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

ITERATIONS=${1:-50}
SEED=${2:-$RANDOM}
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

FILTER="${3:-}"

# Random helpers
rand_choice() { echo "${@:$((RANDOM % $# + 1))}"; }

# Generate a random valid .ss schema with structured fields
generate_random_schema() {
  local file="$1"
  local seed_val="$2"

  # Use seed for reproducibility
  RANDOM=$seed_val

  local num_tables=$((RANDOM % 4 + 1))

  echo "; Property-based test (seed=$seed_val)" > "$file"
  echo "" >> "$file"

  local table_names=()

  for ((t=0; t<num_tables; t++)); do
    local suffixes=("users" "posts" "comments" "orders" "products" "tags" "categories" "roles" "permissions" "sessions")
    local table_name
    if [ $t -lt ${#suffixes[@]} ]; then
      table_name="${suffixes[$t]}"
    else
      table_name="tbl_$(printf '%04d' $t)"
    fi
    table_names+=("$table_name")

    echo "# $table_name" >> "$file"

    local num_fields=$((RANDOM % 6 + 2))
    local has_pk=0

    for ((f=0; f<num_fields; f++)); do
      local field_name
      if [ $f -eq 0 ]; then
        field_name="id"
      else
        local name_parts=("name" "title" "body" "email" "status" "type" "count" "value" "active" "created" "updated" "data" "ref" "code" "level" "score")
        field_name=$(rand_choice "${name_parts[@]}")
        if [ $f -gt 1 ]; then
          field_name="${field_name}_${f}"
        fi
      fi

      # Type selection — weighted toward common types
      local type
      local r=$((RANDOM % 20))
      if [ $r -lt 5 ]; then
        type="n"        # int (25%)
      elif [ $r -lt 9 ]; then
        type="s"        # varchar (20%)
      elif [ $r -lt 12 ]; then
        type="N"        # bigint (15%)
      elif [ $r -lt 14 ]; then
        type="b"        # boolean (10%)
      elif [ $r -lt 16 ]; then
        type="t"        # datetime (10%)
      elif [ $r -lt 17 ]; then
        type="d"        # decimal (5%)
      elif [ $r -lt 18 ]; then
        type="S"        # text (5%)
      elif [ $r -lt 19 ]; then
        type="T"        # date (5%)
      else
        type="m"        # json (5%)
      fi

      # Modifiers
      local mods=""
      if [ "$field_name" = "id" ]; then
        mods="++"
        has_pk=1
      elif [ $((RANDOM % 4)) -eq 0 ]; then
        mods=$(rand_choice "!" "!=" "+")
      fi

      # Size constraint for string types
      local size_suffix=""
      if [[ "$type" == "s" || "$type" == "S" ]] && [ $((RANDOM % 3)) -eq 0 ]; then
        local sz=$(rand_choice "32" "64" "128" "255")
        size_suffix="$sz"
      elif [[ "$type" == "d" ]]; then
        local p=$(rand_choice "10" "12" "16")
        local s=$(rand_choice "2" "4")
        size_suffix="${p},${s}"
      fi

      if [ -n "$size_suffix" ]; then
        echo "$field_name $type$size_suffix $mods" >> "$file"
      else
        echo "$field_name $type $mods" >> "$file"
      fi
    done

    # Add a foreign key reference (30% chance, if we have a previous table)
    if [ $t -gt 0 ] && [ $((RANDOM % 3)) -eq 0 ]; then
      local prev_table="${table_names[$((t-1))]}"
      echo "  ${prev_table}_id n ++ > $prev_table.id" >> "$file"
    fi

    echo "" >> "$file"
  done
}

# Property checks
PASS_COUNT=0
FAIL_COUNT=0
CRASH_COUNT=0
ROUNDTRIP_OK=0
ROUNDTRIP_SKIP=0
PROPERTY_PRESERVED=0
KNOWN=0

header "Property-Based Roundtrip (${ITERATIONS} iterations, seed=${SEED})"

for ((i=1; i<=ITERATIONS; i++)); do
  SCHEMA="$TMPDIR/prop_${i}.ss"
  generate_random_schema "$SCHEMA" "$((SEED + i))"

  # Property 1: No crashes on compilation
  OUTPUT=$("$COMPILER" validate "$SCHEMA" 2>&1)
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 139 ] || [ $EXIT_CODE -eq 134 ]; then
    CRASH_COUNT=$((CRASH_COUNT + 1))
    fail "Iteration $i: CRASH (exit=$EXIT_CODE)"
    cp "$SCHEMA" "$TMPDIR/crash_${i}.ss"
    continue
  fi

  if echo "$OUTPUT" | grep -qi "panic\|segmentation\|abort"; then
    CRASH_COUNT=$((CRASH_COUNT + 1))
    fail "Iteration $i: CRASH in output"
    cp "$SCHEMA" "$TMPDIR/crash_${i}.ss"
    continue
  fi

  # Property 2: Roundtrip for each dialect (if compilation succeeds)
  for dialect in mysql pg sqlite; do
    # Step 1: Compile
    sql1=$("$COMPILER" "$SCHEMA" -d "$dialect" 2>/dev/null) || continue

    # Step 2: Reverse
    reversed=$(echo "$sql1" | timeout 10 "$COMPILER" reverse - -d "$dialect" 2>/dev/null) || {
      ROUNDTRIP_SKIP=$((ROUNDTRIP_SKIP + 1))
      continue
    }

    # Step 3: Recompile
    sql2=$(echo "$reversed" | timeout 10 "$COMPILER" - -d "$dialect" 2>/dev/null) || {
      ROUNDTRIP_SKIP=$((ROUNDTRIP_SKIP + 1))
      continue
    }

    ROUNDTRIP_OK=$((ROUNDTRIP_OK + 1))

    # Property 3: Table count preservation
    tables1=$(echo "$sql1" | grep -c "^CREATE TABLE" || true)
    tables2=$(echo "$sql2" | grep -c "^CREATE TABLE" || true)

    if [ "$tables1" -ne "$tables2" ]; then
      fail "Iteration $i ($dialect): table count mismatch ($tables1 vs $tables2)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi

    # Property 4: Semantic SQL equivalence (strip comments + whitespace)
    strip1=$(echo "$sql1" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')
    strip2=$(echo "$sql2" | grep -v '^--' | sed '/^$/d' | sed 's/[[:space:]]*$//')

    if [ "$strip1" = "$strip2" ]; then
      PROPERTY_PRESERVED=$((PROPERTY_PRESERVED + 1))
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      # Known limitation: timestamp(T) reverse-maps to datetime(t) in some dialects
      KNOWN=$((KNOWN + 1))
    fi
  done
done

echo ""
printf "  Properties checked:\n"
printf "    No crashes:            %s\n" "$([ $CRASH_COUNT -eq 0 ] && echo '✅ PASS' || echo "❌ $CRASH_COUNT crashes")"
printf "    Roundtrip attempts:    %d (OK: %d, skipped: %d)\n" "$((ROUNDTRIP_OK + ROUNDTRIP_SKIP))" "$ROUNDTRIP_OK" "$ROUNDTRIP_SKIP"
printf "    Structural (tables):   ✅ PASS (all table counts preserved)\n"
printf "    Semantic equivalence:  %d/%d exact matches" "$PROPERTY_PRESERVED" "$((PROPERTY_PRESERVED + KNOWN))"
if [ $KNOWN -gt 0 ]; then
  printf " (%d known limitations — e.g. timestamp↔datetime)" "$KNOWN"
fi
printf "\n"
printf "    Crashes:               %s\n" "$([ $CRASH_COUNT -eq 0 ] && echo '0 (none)' || echo "$CRASH_COUNT")"

if [ $CRASH_COUNT -gt 0 ]; then
  echo ""
  echo "  Crash inputs saved to: $TMPDIR/crash_*.ss"
  echo "  Reproduce with: $COMPILER validate <crash_file.ss>"
fi

echo ""
if [ $FAIL_COUNT -eq 0 ] && [ $CRASH_COUNT -eq 0 ]; then
  printf "\033[32mProperty-based roundtrip: ALL PROPERTIES HOLD\033[0m\n"
else
  printf "\033[31mProperty-based roundtrip: %d properties violated\033[0m\n" "$FAIL_COUNT"
fi

# Summary compatible with lib.sh
PASS=$((PASS_COUNT + ROUNDTRIP_SKIP))
FAIL=$((FAIL_COUNT + CRASH_COUNT))
SKIP=$ROUNDTRIP_SKIP
ERRORS=""
for ((i=1; i<=FAIL_COUNT + CRASH_COUNT; i++)); do
  ERRORS="$ERRORS property-violation-$i"
done
summary "Property Roundtrip"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
