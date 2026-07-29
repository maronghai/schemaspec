#!/bin/bash
# ── Rune Parallel Test Library ──
# Helper functions for running test suites concurrently.
# Source this file: source "$(dirname "$0")/lib_parallel.sh"

SCRIPT_DIR_PAR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR_PAR="$(cd "$SCRIPT_DIR_PAR/.." && pwd)"

# Run a test suite in background, capturing output.
# Usage: run_suite "label" "command"
#   e.g. run_suite "MySQL" "bash tests/test.sh"
# Stores result in SUITE_RESULTS array (pass/fail + output).
SUITE_LABELS=()
SUITE_COMMANDS=()
SUITE_PIDS=()
SUITE_TMPDIR=""

run_suite_init() {
  SUITE_TMPDIR=$(mktemp -d)
  SUITE_LABELS=()
  SUITE_COMMANDS=()
  SUITE_PIDS=()
}

run_suite_add() {
  local label="$1"
  local cmd="$2"
  SUITE_LABELS+=("$label")
  SUITE_COMMANDS+=("$cmd")
}

run_suite_run_all() {
  local i
  for i in "${!SUITE_LABELS[@]}"; do
    local label="${SUITE_LABELS[$i]}"
    local cmd="${SUITE_COMMANDS[$i]}"
    local outfile="$SUITE_TMPDIR/${label}.out"

    # Run in background, capturing both stdout and stderr
    (eval "$cmd" > "$outfile" 2>&1) &
    SUITE_PIDS+=($!)
  done
}

run_suite_collect() {
  local total_pass=0
  local total_fail=0
  local all_errors=""
  local i

  for i in "${!SUITE_LABELS[@]}"; do
    local label="${SUITE_LABELS[$i]}"
    local pid="${SUITE_PIDS[$i]}"
    local outfile="$SUITE_TMPDIR/${label}.out"

    wait "$pid" 2>/dev/null
    local exit_code=$?

    local output
    output=$(cat "$outfile" 2>/dev/null || echo "(no output)")

    # Extract pass/fail counts from output (look for summary line)
    local pass_count fail_count
    pass_count=$(echo "$output" | grep -oP '\d+(?=/\d+ passed)' | tail -1 || echo "0")
    fail_count=$(echo "$output" | grep -oP '(?<=, )\d+(?= failed)' | tail -1 || echo "0")

    if [ "$exit_code" -eq 0 ] && [ "$fail_count" = "0" ]; then
      printf "  \033[32m✅\033[0m %s — %s/%s passed\n" "$label" "${pass_count:-?}" "$(( ${pass_count:-0} + ${fail_count:-0} ))"
      total_pass=$((total_pass + ${pass_count:-0}))
    else
      printf "  \033[31m❌\033[0m %s — failed (exit %d)\n" "$label" "$exit_code"
      total_fail=$((total_fail + 1))
      # Show last few lines of output for failed suites
      all_errors="$all_errors\n--- $label ---\n$(echo "$output" | tail -5)"
    fi
  done

  # Cleanup
  rm -rf "$SUITE_TMPDIR"

  echo ""
  printf "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"
  if [ "$total_fail" -eq 0 ]; then
    printf "\033[32mParallel: all %d suites passed\033[0m\n" "${#SUITE_LABELS[@]}"
  else
    printf "\033[31mParallel: %d/%d suites failed\033[0m\n" "$total_fail" "${#SUITE_LABELS[@]}"
    if [ -n "$all_errors" ]; then
      printf "\033[90m%s\033[0m\n" "$all_errors"
    fi
  fi
  printf "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"

  [ "$total_fail" -eq 0 ] && exit 0 || exit 1
}
