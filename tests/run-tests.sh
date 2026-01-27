#!/bin/bash
# run-tests.sh - Run all sub-agent tests against a model
# Usage: ./run-tests.sh [model] [--quick]
# Examples:
#   ./run-tests.sh                    # Uses default (qwen3:8b)
#   ./run-tests.sh glm-4.7-flash:latest
#   ./run-tests.sh qwen3:8b --quick   # Skip verification prompts

set -euo pipefail

MODEL="${1:-qwen3:8b}"
QUICK="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="$SCRIPT_DIR/../ollama-agent.sh"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_FILE="$RESULTS_DIR/${MODEL//[:\/]/_}_$TIMESTAMP.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[test]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

mkdir -p "$RESULTS_DIR"
TEST_WORKDIR=$(mktemp -d)
trap "rm -rf $TEST_WORKDIR" EXIT

# Initialize results
cat > "$RESULT_FILE" << EOF
# Test Results: $MODEL

**Date:** $(date "+%Y-%m-%d %H:%M:%S")  
**Model:** $MODEL  
**Host:** $(hostname)  

---

| Test | Result | Time | Iterations | Notes |
|------|--------|------|------------|-------|
EOF

total_tests=0
passed_tests=0
total_time=0
total_iterations=0

# Quality scoring weights
WEIGHT_CORRECTNESS=40
WEIGHT_EFFICIENCY=20
WEIGHT_SPEED=20
WEIGHT_FORMAT=20

# Baseline values for scoring (can be adjusted)
BASELINE_ITERATIONS=3    # Optimal iterations per test
BASELINE_TIME=15         # Optimal seconds per test

run_test() {
    local name="$1"
    local prompt="$2"
    local verify_cmd="$3"
    local timeout_secs="${4:-120}"  # Default 2 min timeout per test
    local workdir="$TEST_WORKDIR/$name"

    mkdir -p "$workdir"

    log "Running: $name"
    local start_time=$(date +%s)

    # Run the agent with timeout
    timeout "$timeout_secs" bash -c "OLLAMA_MODEL=\"$MODEL\" \"$AGENT\" \"$prompt\" \"$workdir\"" > "$workdir/output.log" 2>&1 || true

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    total_time=$((total_time + elapsed))
    total_tests=$((total_tests + 1))

    # Extract iterations from output log
    local iterations=$(grep -oP 'Iteration \K[0-9]+' "$workdir/output.log" | tail -1)
    iterations=${iterations:-0}
    total_iterations=$((total_iterations + iterations))

    # Verify result
    local result="FAIL"
    local notes=""

    if eval "$verify_cmd" > /dev/null 2>&1; then
        result="PASS"
        passed_tests=$((passed_tests + 1))
        pass "$name (${elapsed}s, ${iterations} iter)"
    else
        fail "$name (${elapsed}s, ${iterations} iter)"
        notes="Verification failed"
    fi

    # Log to results file
    echo "| $name | $result | ${elapsed}s | ${iterations} | $notes |" >> "$RESULT_FILE"

    # Save test artifacts
    cp -r "$workdir" "$RESULTS_DIR/${MODEL//[:\/]/_}_${name}_$TIMESTAMP" 2>/dev/null || true
}

# Calculate quality score (0-100) using awk (no bc dependency)
calculate_quality_score() {
    local pass_rate=$1
    local avg_iterations=$2
    local avg_time=$3

    awk -v pr="$pass_rate" -v ai="$avg_iterations" -v at="$avg_time" \
        -v wc="$WEIGHT_CORRECTNESS" -v we="$WEIGHT_EFFICIENCY" \
        -v ws="$WEIGHT_SPEED" -v wf="$WEIGHT_FORMAT" \
        -v bi="$BASELINE_ITERATIONS" -v bt="$BASELINE_TIME" '
    BEGIN {
        # Correctness score
        correctness = pr * wc
        
        # Efficiency score (fewer iterations = better)
        efficiency = we * (1 - (ai - bi) / bi)
        if (efficiency < 0) efficiency = 0
        if (efficiency > we) efficiency = we
        
        # Speed score (faster = better)
        speed = ws * (1 - (at - bt) / bt)
        if (speed < 0) speed = 0
        if (speed > ws) speed = ws
        
        # Format score
        format = pr * wf
        
        # Total
        total = int(correctness + efficiency + speed + format)
        print total
    }'
}

# Check dependencies
check_deps() {
    local missing=()
    command -v jq >/dev/null || missing+=("jq")
    command -v python3 >/dev/null || command -v python >/dev/null || missing+=("python3")
    command -v node >/dev/null || missing+=("node")
    command -v curl >/dev/null || missing+=("curl")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Please install them and try again."
        exit 1
    fi
}

check_deps

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Local Sub-Agent Test Suite                        ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║  Model: $MODEL"
echo "║  Time:  $(date "+%Y-%m-%d %H:%M:%S")"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Error: Ollama is not running. Start it with: ollama serve"
    exit 1
fi

# Ensure model is loaded
log "Warming up model: $MODEL"
if ! curl -s http://localhost:11434/api/chat -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false}" > /dev/null 2>&1; then
    echo "Error: Failed to warm up model. Is '$MODEL' pulled? Try: ollama pull $MODEL"
    exit 1
fi

# ============================================================
# TEST 1: Python Script Generation
# ============================================================
run_test "test1_python" \
"You MUST use tools. Do NOT output code as text.

Use write_file to create 'password_generator.py' with:
- A function generate_password(length=16) using secrets module
- Main block that prints 3 passwords

Use run_command: python password_generator.py

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test1_python/password_generator.py' && python '$TEST_WORKDIR/test1_python/password_generator.py' > '$TEST_WORKDIR/test1_python/output.txt' 2>&1 && test \$(wc -l < '$TEST_WORKDIR/test1_python/output.txt') -ge 3"

# ============================================================
# TEST 2: Config File Generation  
# ============================================================
run_test "test2_config" \
"You MUST use tools. Do NOT output code as text.

Use write_file to create 'docker-compose.yml' with:
- nginx service on port 80
- postgres service with POSTGRES_PASSWORD env var
- redis service on port 6379
- All on network 'app-net'

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test2_config/docker-compose.yml' && grep -q 'nginx' '$TEST_WORKDIR/test2_config/docker-compose.yml' && grep -q 'postgres' '$TEST_WORKDIR/test2_config/docker-compose.yml' && grep -q 'redis' '$TEST_WORKDIR/test2_config/docker-compose.yml' && grep -q 'app-net' '$TEST_WORKDIR/test2_config/docker-compose.yml'"

# ============================================================
# TEST 3: Shell Script with System Commands
# ============================================================
run_test "test3_shell" \
"You MUST use tools. Do NOT output code as text.

Use write_file to create 'sysinfo.sh' that shows:
- hostname and kernel version
- disk usage for /
- top 3 memory processes

Use run_command: chmod +x sysinfo.sh
Use run_command: ./sysinfo.sh

Call task_complete with summary." \
"test -x '$TEST_WORKDIR/test3_shell/sysinfo.sh' && '$TEST_WORKDIR/test3_shell/sysinfo.sh' > '$TEST_WORKDIR/test3_shell/verify.txt' 2>&1 && grep -qiE '(kernel|linux|hostname|disk|mem)' '$TEST_WORKDIR/test3_shell/verify.txt'"

# ============================================================
# TEST 4: Data Transformation (Read + Process + Write)
# ============================================================
mkdir -p "$TEST_WORKDIR/test4_transform"
echo '[{"name":"Alice","score":85},{"name":"Bob","score":92},{"name":"Carol","score":78}]' > "$TEST_WORKDIR/test4_transform/scores.json"

run_test "test4_transform" \
"You MUST use tools. Do NOT guess or make up data.

1. Use read_file to read 'scores.json' FIRST - it contains the actual data
2. Parse the JSON and calculate the real average from the scores in the file
3. Use write_file to create 'report.txt' with each person's name:score and the average
4. Use run_command: cat report.txt

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test4_transform/report.txt' && grep -qi 'alice' '$TEST_WORKDIR/test4_transform/report.txt' && grep -qi 'bob' '$TEST_WORKDIR/test4_transform/report.txt' && grep -qi 'carol' '$TEST_WORKDIR/test4_transform/report.txt' && grep -qE '85(\.0+)?|85\b' '$TEST_WORKDIR/test4_transform/report.txt'"

# ============================================================
# TEST 5: Error Handling
# ============================================================
run_test "test5_errors" \
"You MUST use tools.

Use read_file to try reading 'nonexistent.txt' - it will fail.
Then use write_file to create 'error_log.txt' with a message about the missing file.

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test5_errors/error_log.txt' && grep -qiE '(nonexistent|not found|missing|error|fail)' '$TEST_WORKDIR/test5_errors/error_log.txt'"

# ============================================================
# TEST 6: Multi-File Refactoring
# ============================================================
mkdir -p "$TEST_WORKDIR/test6_multifile"
cat > "$TEST_WORKDIR/test6_multifile/utils.js" << 'JSEOF'
// Utility functions
function formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    // BUG: Returns literal YYYY instead of year variable
    return 'YYYY-' + month + '-' + day;
}

module.exports = { formatDate };
JSEOF

cat > "$TEST_WORKDIR/test6_multifile/main.js" << 'JSEOF'
const { formatDate } = require('./utils');

const today = new Date();
console.log('Formatted date:', formatDate(today));
JSEOF

run_test "test6_multifile" \
"You MUST use tools.

1. Use run_command: node main.js (it will show a bug - the year shows as literal 'YYYY')
2. Use read_file to examine both 'utils.js' and 'main.js'
3. Find and fix the bug in utils.js using write_file
4. Use run_command: node main.js (should now show correct year like 2026)

Call task_complete with what you fixed." \
"node '$TEST_WORKDIR/test6_multifile/main.js' 2>&1 | grep -qE '202[4-9]'"

# ============================================================
# TEST 7: Iterative Debugging
# ============================================================
mkdir -p "$TEST_WORKDIR/test7_debug"
cat > "$TEST_WORKDIR/test7_debug/calculator.py" << 'PYEOF'
def calculate_average(numbers):
    """Calculate the average of a list of numbers."""
    total = sum(numbers)
    # BUG: Using undefined variable 'count' instead of len(numbers)
    return total / count

def main():
    scores = [85, 92, 78, 95, 88]
    avg = calculate_average(scores)
    print(f"Average score: {avg}")

if __name__ == "__main__":
    main()
PYEOF

run_test "test7_debug" \
"You MUST use tools. Follow these steps IN ORDER:

STEP 1: run_command with 'python calculator.py' - you will see a NameError
STEP 2: read_file 'calculator.py' to see the code
STEP 3: The bug is using 'count' instead of 'len(numbers)' - fix it with write_file
STEP 4: run_command 'python calculator.py' again to verify the fix works

Call task_complete when the script runs successfully." \
"python '$TEST_WORKDIR/test7_debug/calculator.py' 2>&1 | grep -qE 'Average.*[0-9]+'" \
90

# ============================================================
# TEST 8: Format Compliance
# ============================================================
run_test "test8_format" \
"You MUST use tools.

Create a file 'users.csv' with EXACTLY this format (including header, no extra whitespace):
name,age,city
Alice,30,NYC
Bob,25,LA
Carol,35,Chicago

Then use run_command: cat users.csv

Call task_complete confirming the file was created." \
"test -f '$TEST_WORKDIR/test8_format/users.csv' && test \$(wc -l < '$TEST_WORKDIR/test8_format/users.csv') -eq 4 && head -1 '$TEST_WORKDIR/test8_format/users.csv' | grep -q '^name,age,city$'"

# ============================================================
# Results Summary
# ============================================================

# Calculate metrics (using awk for portability)
pass_rate=$(awk "BEGIN {printf \"%.2f\", $passed_tests / $total_tests}")
avg_iterations=$(awk "BEGIN {printf \"%.1f\", $total_iterations / $total_tests}")
avg_time=$((total_time / total_tests))

# Calculate quality score
quality_score=$(calculate_quality_score "$pass_rate" "$avg_iterations" "$avg_time")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RESULTS: $passed_tests/$total_tests passed (${total_time}s total)"
echo "QUALITY SCORE: ${quality_score}/100"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Append summary to results file
cat >> "$RESULT_FILE" << EOF

---

## Summary

- **Passed:** $passed_tests/$total_tests
- **Total Time:** ${total_time}s
- **Average:** ${avg_time}s per test
- **Total Iterations:** $total_iterations
- **Avg Iterations:** ${avg_iterations} per test
- **Quality Score:** ${quality_score}/100

### Score Breakdown

| Dimension | Weight | Description |
|-----------|--------|-------------|
| Correctness | 40% | Tests passed |
| Efficiency | 20% | Fewer iterations is better (baseline: ${BASELINE_ITERATIONS}/test) |
| Speed | 20% | Faster is better (baseline: ${BASELINE_TIME}s/test) |
| Format | 20% | Output correctness |

## Test Artifacts

Saved to: \`$RESULTS_DIR/\`
EOF

echo ""
echo "Results saved to: $RESULT_FILE"
echo ""
