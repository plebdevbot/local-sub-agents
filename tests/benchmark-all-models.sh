#!/bin/bash
# benchmark-all-models.sh - Run the sub-agent benchmark against all local ollama models
# Usage: ./benchmark-all-models.sh [--quick]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICK="${1:-}"

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
for MODEL in $MODELS; do
    CURRENT=$((CURRENT + 1))
    log "[$CURRENT/$TOTAL] Testing: $MODEL"
    echo ""
    
    # Record start time
    START_TIME=$(date +%s)
    
    # Run the benchmark
    if [[ "$QUICK" == "--quick" ]]; then
        "$SCRIPT_DIR/run-tests.sh" "$MODEL" --quick 2>&1 | tee -a "/tmp/benchmark_${MODEL//[:\/]/_}.log"
    else
        "$SCRIPT_DIR/run-tests.sh" "$MODEL" 2>&1 | tee -a "/tmp/benchmark_${MODEL//[:\/]/_}.log"
    fi
    
    # Record end time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Add to summary
    echo "### $MODEL" >> "$SUMMARY_FILE"
    echo "- Duration: ${DURATION}s" >> "$SUMMARY_FILE"
    echo "- Log: \`/tmp/benchmark_${MODEL//[:\/]/_}.log\`" >> "$SUMMARY_FILE"
    
    # Extract pass/fail from latest results
    LATEST_RESULT=$(ls -t "$SCRIPT_DIR/results/${MODEL//[:\/]/_}"*.md 2>/dev/null | head -1)
    if [[ -n "$LATEST_RESULT" ]]; then
        PASSES=$(grep -c "| PASS |" "$LATEST_RESULT" 2>/dev/null || echo "0")
        FAILS=$(grep -c "| FAIL |" "$LATEST_RESULT" 2>/dev/null || echo "0")
        echo "- Passed: $PASSES, Failed: $FAILS" >> "$SUMMARY_FILE"
    fi
    echo "" >> "$SUMMARY_FILE"
    
    success "Completed $MODEL in ${DURATION}s"
    echo ""
    echo "---"
    echo ""
    
    # Give ollama a moment to unload the model
    sleep 2
done

log "All benchmarks complete!"
log "Summary saved to: $SUMMARY_FILE"
echo ""
cat "$SUMMARY_FILE"
