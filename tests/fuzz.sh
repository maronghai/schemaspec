#!/bin/bash
# ── Rune Fuzz Testing ──
# Generate random .ss input and check for parser crashes.
# Usage: bash tests/fuzz.sh [iterations] [seed]
# Default: 100 iterations, random seed

source "$(dirname "$0")/lib.sh"

ITERATIONS=${1:-100}
SEED=${2:-$RANDOM}
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

header "Fuzz Testing (${ITERATIONS} iterations, seed=${SEED})"

CRASHES=0
ERRORS=0
PASS=0

# Random helpers
rand_int() { echo $((RANDOM % $1)); }
rand_choice() { echo "${@:$((RANDOM % $# + 1))}"; }

generate_random_schema() {
  local file="$1"
  local num_tables=$((RANDOM % 5 + 1))

  echo "; Fuzz test — auto-generated random schema" > "$file"
  echo "" >> "$file"

  for ((t=0; t<num_tables; t++)); do
    local table_name="tbl_$(cat /dev/urandom | tr -dc 'a-z' | head -c 8)"
    echo "# $table_name" >> "$file"

    local num_fields=$((RANDOM % 8 + 1))
    for ((f=0; f<num_fields; f++)); do
      local field_name="col_$(cat /dev/urandom | tr -dc 'a-z' | head -c 6)"
      local type=$(rand_choice "n" "N" "s" "S" "b" "d" "t" "m" "j" "16" "32" "s64" "s128")
      local mods=""
      if [ $((RANDOM % 3)) -eq 0 ]; then
        mods=$(rand_choice "++" "!" "*" "+")
      fi
      echo "$field_name $type $mods" >> "$file"
    done
    echo "" >> "$file"
  done
}

for ((i=1; i<=ITERATIONS; i++)); do
  SCHEMA="$TMPDIR/fuzz_$i.ss"
  generate_random_schema "$SCHEMA"

  # Run validate (should not crash, even on invalid input)
  OUTPUT=$("$COMPILER" validate "$SCHEMA" 2>&1)
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 139 ] || [ $EXIT_CODE -eq 134 ]; then
    # Segfault or abort
    CRASHES=$((CRASHES + 1))
    fail "Iteration $i: CRASH (exit=$EXIT_CODE)" "$(head -5 "$SCHEMA")"
    # Save crashing input
    cp "$SCHEMA" "$TMPDIR/crash_$i.ss"
  elif echo "$OUTPUT" | grep -qi "panic\|segmentation\|abort"; then
    CRASHES=$((CRASHES + 1))
    fail "Iteration $i: CRASH in output" "$(head -5 "$SCHEMA")"
    cp "$SCHEMA" "$TMPDIR/crash_$i.ss"
  else
    PASS=$((PASS + 1))
  fi
done

echo ""
printf "  Results: \033[32m%d passed\033[0m, \033[31m%d crashes\033[0m\n" "$PASS" "$CRASHES"

if [ $CRASHES -gt 0 ]; then
  echo ""
  echo "  Crash inputs saved to: $TMPDIR/crash_*.ss"
  echo "  Reproduce with: $COMPILER validate <crash_file.ss>"
  exit 1
fi

summary "Fuzz Testing"
exit 0
