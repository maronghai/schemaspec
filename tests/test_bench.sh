#!/usr/bin/env bash
# ── Rune Benchmark Regression Test ──
# Tests: Compares current build performance against saved baseline.
# Usage: ./test_bench.sh [--save] [--check]
#   --save  Save current performance as new baseline
#   --check Check for regressions >20% (default)

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TEST_DIR="$SCRIPT_DIR"
BENCH_DIR="$TEST_DIR/../bench"
COMPILER="$TEST_DIR/../rune/zig-out/bin/rune.exe"
BASELINE_FILE="$BENCH_DIR/baseline.json"
BENCH_FILE="$TEST_DIR/03-all-types.ss"
ITERATIONS=3

MODE="${1:---check}"

# Ensure compiler exists
if [ ! -f "$COMPILER" ]; then
  echo "ERROR: Compiler not found at $COMPILER"
  echo "Run 'cd rune && zig build' first."
  exit 1
fi

# Ensure bench directory exists
if [ ! -d "$BENCH_DIR" ]; then
  mkdir -p "$BENCH_DIR"
fi

# Check if baseline file exists
if [ "$MODE" = "--check" ] && [ ! -f "$BASELINE_FILE" ]; then
  echo "No baseline found. Saving current run as baseline..."
  MODE="--save"
fi

# Run benchmark
echo "Running benchmark ($ITERATIONS iterations)..."

# Warmup
for i in $(seq 1 3); do
  "$COMPILER" "$BENCH_FILE" > /dev/null 2>&1
done

# Benchmark
total_us=0
min_us=999999
max_us=0

for i in $(seq 1 $ITERATIONS); do
  start=$(date +%s%N)
  "$COMPILER" "$BENCH_FILE" > /dev/null 2>&1
  end=$(date +%s%N)
  elapsed_us=$(( (end - start) / 1000 ))
  total_us=$((total_us + elapsed_us))
  if [ $elapsed_us -lt $min_us ]; then min_us=$elapsed_us; fi
  if [ $elapsed_us -gt $max_us ]; then max_us=$elapsed_us; fi
done

avg_us=$((total_us / ITERATIONS))
avg_ms=$(awk "BEGIN {printf \"%.2f\", $avg_us / 1000}")
min_ms=$(awk "BEGIN {printf \"%.2f\", $min_us / 1000}")
max_ms=$(awk "BEGIN {printf \"%.2f\", $max_us / 1000}")

echo "Current: avg=${avg_ms}ms min=${min_ms}ms max=${max_ms}ms"

if [ "$MODE" = "--save" ]; then
  # Save as baseline
  cat > "$BASELINE_FILE" <<EOF
{
  "file": "03-all-types.ss",
  "iterations": $ITERATIONS,
  "avg_us": $avg_us,
  "min_us": $min_us,
  "max_us": $max_us
}
EOF
  echo "Baseline saved to $BASELINE_FILE"
  exit 0
fi

# Check mode: compare against baseline
if [ ! -f "$BASELINE_FILE" ]; then
  echo "ERROR: Baseline file not found at $BASELINE_FILE"
  echo "Run './test_bench.sh --save' first to create baseline."
  exit 1
fi

# Parse baseline avg_us
baseline_avg_us=$(grep -o '"avg_us": [0-9]*' "$BASELINE_FILE" | grep -o '[0-9]*' || echo "0")

if [ "$baseline_avg_us" = "0" ]; then
  echo "ERROR: Failed to parse baseline"
  exit 1
fi

baseline_avg_ms=$(awk "BEGIN {printf \"%.2f\", $baseline_avg_us / 1000}")

# Calculate regression percentage
REGRESSION=$(awk "BEGIN {printf \"%.1f\", (($avg_us - $baseline_avg_us) / $baseline_avg_us) * 100}")
THRESHOLD=20

echo ""
echo "Baseline: ${baseline_avg_ms}ms"
echo "Current:  ${avg_ms}ms"
echo "Change:   ${REGRESSION}%"

# Check if regression exceeds threshold
EXCEED=$(awk "BEGIN {print ($REGRESSION > $THRESHOLD) ? 1 : 0}")

if [ "$EXCEED" = "1" ]; then
  echo ""
  echo "FAIL: Benchmark regression detected (${REGRESSION}% > ${THRESHOLD}% threshold)"
  exit 1
else
  echo ""
  echo "PASS: No significant regression (threshold: ${THRESHOLD}%)"
  exit 0
fi
