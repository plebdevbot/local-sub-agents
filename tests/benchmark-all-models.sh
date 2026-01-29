#!/bin/bash
# benchmark-all-models.sh - Run the sub-agent benchmark against all local ollama models
# Usage: ./benchmark-all-models.sh [--quick]
#
# IMPORTANT: This script runs ONE MODEL AT A TIME:
#   1. Verify no models are loaded
#   2. Load and test the model
#   3. Explicitly unload the model from memory (ollama stop)
#   4. Wait for memory to clear
#   5. Move to next model
#
# This prevents OOM kills and ensures stable benchmarking.

# Don't exit on errors - continue with next model
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICK="${1:-}"
MODEL_TIMEOUT=1800  # 30 minutes per model max

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[benchmark]${NC} $1"; }
success() { echo -e "${GREEN}[success]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; }

# ============================================================
# CRITICAL: Trap-based cleanup for bulletproof model unloading
# This ensures models are ALWAYS unloaded, even on:
#   - Script errors
#   - SIGTERM (kill)
#   - SIGINT (Ctrl+C)
#   - Abnormal exit
# ============================================================
cleanup_on_exit() {
    log "Cleanup triggered - unloading all models..."
    ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | xargs -I{} ollama stop {} 2>/dev/null || true
    log "All models unloaded"
}
trap cleanup_on_exit EXIT INT TERM

# Get all available models
MODELS=$(ollama list | tail -n +2 | awk '{print $1}')
TOTAL=$(echo "$MODELS" | wc -l)

log "Found $TOTAL models to benchmark:"
echo "$MODELS" | while read model; do
    echo "  - $model"
done
echo ""

SUMMARY_FILE="$SCRIPT_DIR/results/BENCHMARK_SUMMARY_$(date +%Y%m%d_%H%M%S).md"
mkdir -p "$SCRIPT_DIR/results"

cat > "$SUMMARY_FILE" << EOF
# Full Model Benchmark Summary

**Date:** $(date "+%Y-%m-%d %H:%M:%S")
**Host:** $(hostname)
**Total Models:** $TOTAL

---

## Results by Model

EOF

CURRENT=0
FAILED_MODELS=()

for MODEL in $MODELS; do
    CURRENT=$((CURRENT + 1))
    log "[$CURRENT/$TOTAL] Testing: $MODEL"
    echo ""
    
    # CRITICAL: Ensure no models are loaded before starting
    log "Checking for loaded models..."
    LOADED=$(ollama ps 2>/dev/null | tail -n +2 | wc -l)
    if [ "$LOADED" -gt 0 ]; then
        warn "Found $LOADED loaded model(s), unloading..."
        ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | xargs -I{} ollama stop {} 2>/dev/null || true
        sleep 3
    fi
    log "Memory clear, starting $MODEL"
    echo ""
    
    # Record start time
    START_TIME=$(date +%s)
    
    # Run the benchmark with timeout and error handling
    EXIT_CODE=0
    if [[ "$QUICK" == "--quick" ]]; then
        timeout $MODEL_TIMEOUT "$SCRIPT_DIR/run-tests.sh" "$MODEL" --quick 2>&1 | tee -a "/tmp/benchmark_${MODEL//[:\/]/_}.log" || EXIT_CODE=$?
    else
        timeout $MODEL_TIMEOUT "$SCRIPT_DIR/run-tests.sh" "$MODEL" 2>&1 | tee -a "/tmp/benchmark_${MODEL//[:\/]/_}.log" || EXIT_CODE=$?
    fi
    
    # Record end time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Add to summary
    echo "### $MODEL" >> "$SUMMARY_FILE"
    echo "- Duration: ${DURATION}s" >> "$SUMMARY_FILE"
    echo "- Log: \`/tmp/benchmark_${MODEL//[:\/]/_}.log\`" >> "$SUMMARY_FILE"
    
    # Check exit status
    if [ $EXIT_CODE -eq 124 ]; then
        error "$MODEL timed out after ${MODEL_TIMEOUT}s"
        echo "- Status: TIMEOUT" >> "$SUMMARY_FILE"
        FAILED_MODELS+=("$MODEL (timeout)")
    elif [ $EXIT_CODE -ne 0 ]; then
        error "$MODEL failed with exit code $EXIT_CODE"
        echo "- Status: FAILED (exit $EXIT_CODE)" >> "$SUMMARY_FILE"
        FAILED_MODELS+=("$MODEL (exit $EXIT_CODE)")
    else
        success "Completed $MODEL in ${DURATION}s"
        echo "- Status: SUCCESS" >> "$SUMMARY_FILE"
    fi
    
    # Extract pass/fail from latest results
    LATEST_RESULT=$(ls -t "$SCRIPT_DIR/results/${MODEL//[:\/]/_}"*.md 2>/dev/null | head -1)
    if [[ -n "$LATEST_RESULT" ]]; then
        PASSES=$(grep -c "| PASS |" "$LATEST_RESULT" 2>/dev/null || echo "0")
        FAILS=$(grep -c "| FAIL |" "$LATEST_RESULT" 2>/dev/null || echo "0")
        SCORE=$(grep "QUALITY SCORE:" "$LATEST_RESULT" 2>/dev/null | awk '{print $3}' || echo "N/A")
        echo "- Passed: $PASSES, Failed: $FAILS" >> "$SUMMARY_FILE"
        echo "- Score: $SCORE" >> "$SUMMARY_FILE"
    fi
    echo "" >> "$SUMMARY_FILE"
    
    echo ""
    log "Cleaning up after $MODEL"
    echo ""
    
    # Kill any lingering processes
    pkill -f "ollama-agent.sh" 2>/dev/null || true
    
    # CRITICAL: Explicitly unload the model from memory
    log "Unloading model from memory..."
    ollama stop "$MODEL" 2>/dev/null || true
    
    # Wait for model to fully unload
    sleep 5
    
    # Verify no models are loaded
    LOADED=$(ollama ps 2>/dev/null | tail -n +2 | wc -l)
    if [ "$LOADED" -gt 0 ]; then
        warn "Model still loaded, forcing stop..."
        ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | xargs -I{} ollama stop {} 2>/dev/null || true
        sleep 3
    fi
    
    log "Memory cleared, ready for next model"
    echo "---"
    echo ""
done

# Final summary
if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    echo "" >> "$SUMMARY_FILE"
    echo "## Failed Models" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    for failed in "${FAILED_MODELS[@]}"; do
        echo "- $failed" >> "$SUMMARY_FILE"
    done
fi

log "All benchmarks complete!"
log "Successful: $((TOTAL - ${#FAILED_MODELS[@]}))/$TOTAL"
if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    warn "Failed models: ${FAILED_MODELS[*]}"
fi
log "Summary saved to: $SUMMARY_FILE"
echo ""
cat "$SUMMARY_FILE"
