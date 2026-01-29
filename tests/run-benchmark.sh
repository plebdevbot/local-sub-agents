#!/bin/bash
# run-benchmark.sh - Wrapper to run benchmark in background with proper logging
# Usage: ./run-benchmark.sh [--quick]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICK="${1:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$SCRIPT_DIR/results/benchmark_run_$TIMESTAMP.log"
PID_FILE="$SCRIPT_DIR/.benchmark.pid"

mkdir -p "$SCRIPT_DIR/results"

# Check if already running
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "❌ Benchmark already running (PID: $OLD_PID)"
        echo "   Log: tail -f $SCRIPT_DIR/results/benchmark_run_*.log"
        exit 1
    fi
    rm -f "$PID_FILE"
fi

echo "🚀 Starting benchmark in background..."
echo "   Log: $LOG_FILE"
echo "   Monitor: tail -f $LOG_FILE"
echo ""

# Run in background, capture PID
if [[ "$QUICK" == "--quick" ]]; then
    nohup "$SCRIPT_DIR/benchmark-all-models.sh" --quick > "$LOG_FILE" 2>&1 &
else
    nohup "$SCRIPT_DIR/benchmark-all-models.sh" > "$LOG_FILE" 2>&1 &
fi

BENCHMARK_PID=$!
echo "$BENCHMARK_PID" > "$PID_FILE"

echo "✅ Benchmark started (PID: $BENCHMARK_PID)"
echo ""
echo "Commands:"
echo "  Check status: ps -p $BENCHMARK_PID"
echo "  View log:     tail -f $LOG_FILE"
echo "  Stop:         kill $BENCHMARK_PID"
echo ""

# Wait a second to see if it crashes immediately
sleep 2
if ! kill -0 "$BENCHMARK_PID" 2>/dev/null; then
    echo "❌ Benchmark died immediately! Check log:"
    tail -20 "$LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
fi

echo "🏃 Benchmark running successfully"
