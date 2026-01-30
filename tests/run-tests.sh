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

# ============================================================
# CRITICAL: Trap-based cleanup for bulletproof model unloading
# Ensures model is ALWAYS unloaded, even on abnormal exit
# ============================================================
cleanup_model_on_exit() {
    if [[ -n "${MODEL:-}" ]]; then
        log "Emergency cleanup - unloading $MODEL..."
        ollama stop "$MODEL" 2>/dev/null || true
    fi
}

mkdir -p "$RESULTS_DIR"
TEST_WORKDIR=$(mktemp -d)

# Compound trap: cleanup temp dir AND unload model
trap "rm -rf $TEST_WORKDIR; cleanup_model_on_exit" EXIT INT TERM

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

# Quality scoring weights (heavily prioritize accuracy over speed)
WEIGHT_CORRECTNESS=65  # Pass rate is king
WEIGHT_EFFICIENCY=10   # Iterations still matter for token usage
WEIGHT_SPEED=0         # Speed doesn't matter - accuracy does
WEIGHT_FORMAT=25       # Output correctness is important

# Baseline values for scoring (can be adjusted)
# Note: Tests 9-14 are more complex, so baselines are adjusted
BASELINE_ITERATIONS=4    # Optimal iterations per test (higher for complex tests)
BASELINE_TIME=25         # Optimal seconds per test (higher for API/network tests)

run_test() {
    local name="$1"
    local prompt="$2"
    local verify_cmd="$3"
    local timeout_secs="${4:-120}"  # Default 2 min timeout per test
    local workdir="$TEST_WORKDIR/$name"

    mkdir -p "$workdir"

    log "Running: $name"
    local start_time=$(date +%s)

    # Run the agent with timeout (use --kill-after to ensure cleanup)
    timeout --kill-after=10s "$timeout_secs" bash -c "OLLAMA_MODEL=\"$MODEL\" \"$AGENT\" \"$prompt\" \"$workdir\"" > "$workdir/output.log" 2>&1 || true
    
    # Ensure any lingering child processes are killed
    pkill -P $$ -f "ollama-agent.sh" 2>/dev/null || true

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    total_time=$((total_time + elapsed))
    total_tests=$((total_tests + 1))

    # Extract iterations from output log
    local iterations=$(grep -oP 'Iteration \K[0-9]+' "$workdir/output.log" | tail -1)
    iterations=${iterations:-0}
    total_iterations=$((total_iterations + iterations))

    # Verify result with timeout (prevent hangs from buggy generated code)
    local result="FAIL"
    local notes=""
    local verify_timeout=30  # 30 seconds max for verification

    if timeout "$verify_timeout" bash -c "$verify_cmd" > /dev/null 2>&1; then
        result="PASS"
        passed_tests=$((passed_tests + 1))
        pass "$name (${elapsed}s, ${iterations} iter)"
    else
        local verify_exit=$?
        if [[ $verify_exit -eq 124 ]]; then
            fail "$name (${elapsed}s, ${iterations} iter)"
            notes="Verification timeout (${verify_timeout}s)"
        else
            fail "$name (${elapsed}s, ${iterations} iter)"
            notes="Verification failed"
        fi
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
        
        # Speed score omitted (WEIGHT_SPEED=0 - we prioritize quality over speed)
        
        # Format score
        format = pr * wf
        
        # Total
        total = int(correctness + efficiency + format)
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

# Quick mode indicator
if [[ "$QUICK" == "--quick" ]]; then
    log "Quick mode: Running tests 1-8 only (skipping complex tests 9-14)"
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
"test -f '$TEST_WORKDIR/test4_transform/report.txt' && grep -qiE '(alice.*85|85.*alice)' '$TEST_WORKDIR/test4_transform/report.txt' && grep -qiE '(bob.*92|92.*bob)' '$TEST_WORKDIR/test4_transform/report.txt' && grep -qiE '(carol.*78|78.*carol)' '$TEST_WORKDIR/test4_transform/report.txt'"

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
"output=\$(node '$TEST_WORKDIR/test6_multifile/main.js' 2>&1) && echo \"\$output\" | grep -qvF 'YYYY-' && echo \"\$output\" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'"

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
240

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
# QUICK MODE: Skip complex tests 9-14 if --quick flag is set
# ============================================================
if [[ "$QUICK" != "--quick" ]]; then

# ============================================================
# TEST 9: REST API Client with Error Handling (stdlib only)
# ============================================================
run_test "test9_api_client" \
"You MUST use tools. Do NOT output code as text.

Create a Python REST API client using ONLY stdlib (urllib). Use write_file to create 'api_client.py' with:

1. A class HttpBinClient with:
   - __init__(self, base_url='https://httpbin.org')
   - get(self, endpoint) method - uses urllib.request to make GET request, returns JSON dict
   - post(self, endpoint, data) method - uses urllib.request to make POST request with JSON body, returns JSON dict
   - Both methods must have try/except for urllib.error.URLError
   - Both methods should handle non-2xx status codes

2. A simple test at the bottom:
   if __name__ == '__main__':
       client = HttpBinClient()
       # Test GET
       result = client.get('/get')
       print('GET test:', 'url' in result)
       # Test POST
       result = client.post('/post', {'test': 'data'})
       print('POST test:', 'json' in result)

Use run_command: python api_client.py

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test9_api_client/api_client.py' && \
 grep -q 'class HttpBinClient' '$TEST_WORKDIR/test9_api_client/api_client.py' && \
 grep -qE '(urllib|URLError|try:)' '$TEST_WORKDIR/test9_api_client/api_client.py' && \
 python '$TEST_WORKDIR/test9_api_client/api_client.py' 2>&1 | grep -q 'True'" \
240

# ============================================================
# TEST 10: Expression Parser with Operator Precedence
# ============================================================
run_test "test10_parser" \
"You MUST use tools. Do NOT output code as text.

Create a math expression parser. Use write_file to create 'expr_parser.py' with:

1. A function parse_and_eval(expression) that:
   - Takes a string like '2 + 3 * 4' and returns the numeric result
   - Handles +, -, *, / operators
   - Respects operator precedence (* and / before + and -)
   - Handles parentheses like '(2 + 3) * 4'
   - Handles negative numbers
   - Returns a float or int

2. Test cases at bottom:
   if __name__ == '__main__':
       tests = [
           ('2 + 3 * 4', 14),
           ('(2 + 3) * 4', 20),
           ('10 / 2 + 3', 8),
           ('2 * 3 + 4 * 5', 26),
           ('(1 + 2) * (3 + 4)', 21),
       ]
       for expr, expected in tests:
           result = parse_and_eval(expr)
           status = 'PASS' if abs(result - expected) < 0.001 else 'FAIL'
           print(f'{expr} = {result} (expected {expected}) [{status}]')

Use run_command: python expr_parser.py

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test10_parser/expr_parser.py' && \
 grep -q 'parse_and_eval' '$TEST_WORKDIR/test10_parser/expr_parser.py' && \
 python '$TEST_WORKDIR/test10_parser/expr_parser.py' 2>&1 | grep -c 'PASS' | grep -qE '^5$'" \
200

# ============================================================
# TEST 11: Refactor a Messy Class
# ============================================================
mkdir -p "$TEST_WORKDIR/test11_refactor"
cat > "$TEST_WORKDIR/test11_refactor/messy_code.py" << 'PYEOF'
# This is a messy "god object" that needs refactoring
# DO NOT just fix bugs - you must refactor into multiple classes

class DataProcessor:
    def __init__(self):
        self.data = []
        self.users = []
        self.log_entries = []
        
    def add_data(self, item):
        self.data.append(item)
        self.log_entries.append("Added data: " + str(item))
        
    def add_user(self, name, email):
        user = {"name": name, "email": email, "active": True}
        self.users.append(user)
        self.log_entries.append("Added user: " + name)
        
    def process_data(self):
        result = []
        for item in self.data:
            if isinstance(item, int):
                result.append(item * 2)
                self.log_entries.append("Processed int: " + str(item))
            elif isinstance(item, str):
                result.append(item.upper())
                self.log_entries.append("Processed str: " + item)
        return result
    
    def get_active_users(self):
        active = []
        for user in self.users:
            if user["active"]:
                active.append(user)
                self.log_entries.append("Found active user: " + user["name"])
        return active
    
    def deactivate_user(self, name):
        for user in self.users:
            if user["name"] == name:
                user["active"] = False
                self.log_entries.append("Deactivated: " + name)
                
    def get_log(self):
        return self.log_entries
    
    def calculate_stats(self):
        total = 0
        count = 0
        for item in self.data:
            if isinstance(item, int):
                total = total + item
                count = count + 1
        if count == 0:
            return {"total": 0, "count": 0, "average": 0}
        return {"total": total, "count": count, "average": total / count}

# Test the messy code (these tests must still pass after refactoring)
if __name__ == "__main__":
    # These tests verify the refactored code works
    
    # Test 1: Data operations
    from refactored import DataManager
    dm = DataManager()
    dm.add(10)
    dm.add(20)
    dm.add("hello")
    processed = dm.process()
    assert 20 in processed, "Should double integers"
    assert 40 in processed, "Should double integers"
    assert "HELLO" in processed, "Should uppercase strings"
    print("DataManager: PASS")
    
    # Test 2: User operations  
    from refactored import UserManager
    um = UserManager()
    um.add_user("Alice", "alice@test.com")
    um.add_user("Bob", "bob@test.com")
    um.deactivate("Alice")
    active = um.get_active()
    assert len(active) == 1, "Should have 1 active user"
    assert active[0]["name"] == "Bob", "Bob should be active"
    print("UserManager: PASS")
    
    # Test 3: Logging
    from refactored import Logger
    log = Logger()
    log.log("Test message")
    entries = log.get_entries()
    assert len(entries) >= 1, "Should have log entries"
    print("Logger: PASS")
    
    # Test 4: Stats calculation
    from refactored import StatsCalculator
    sc = StatsCalculator()
    sc.add(10)
    sc.add(20)
    sc.add(30)
    stats = sc.calculate()
    assert stats["total"] == 60, "Total should be 60"
    assert stats["average"] == 20, "Average should be 20"
    print("StatsCalculator: PASS")
    
    print("\nAll refactoring tests passed!")
PYEOF

run_test "test11_refactor" \
"You MUST use tools. This is a REFACTORING task.

1. Use read_file to read 'messy_code.py' - it contains a 'god object' that does too much
2. The file also contains tests at the bottom that import from 'refactored.py'
3. You must create 'refactored.py' with FOUR separate classes:
   - DataManager: handles data list, add(), process()
   - UserManager: handles users list, add_user(), deactivate(), get_active()
   - Logger: handles log entries, log(), get_entries()
   - StatsCalculator: handles numeric stats, add(), calculate()

4. Use write_file to create 'refactored.py' with all four classes
5. Use run_command: python messy_code.py (runs the tests that verify your refactoring)

The tests in messy_code.py must pass - they import from refactored.py.

Call task_complete with summary of what you refactored." \
"test -f '$TEST_WORKDIR/test11_refactor/refactored.py' && \
 grep -q 'class DataManager' '$TEST_WORKDIR/test11_refactor/refactored.py' && \
 grep -q 'class UserManager' '$TEST_WORKDIR/test11_refactor/refactored.py' && \
 grep -q 'class Logger' '$TEST_WORKDIR/test11_refactor/refactored.py' && \
 grep -q 'class StatsCalculator' '$TEST_WORKDIR/test11_refactor/refactored.py' && \
 cd '$TEST_WORKDIR/test11_refactor' && python messy_code.py 2>&1 | grep -q 'All refactoring tests passed'" \
240

# ============================================================
# TEST 12: Async Task Processing (stdlib only)
# ============================================================
run_test "test12_async" \
"You MUST use tools. Do NOT output code as text.

Create an async task processor using ONLY stdlib. Use write_file to create 'async_processor.py' with:

1. An async function process_item(item, delay) that:
   - Simulates async work with await asyncio.sleep(delay)
   - Returns a dict with 'item', 'result' (item * 2 if int, item.upper() if str), 'delay'

2. An async function process_all(items) that:
   - Processes all items concurrently using asyncio.gather
   - Uses these fixed delays: [0.1, 0.2, 0.3, 0.4, 0.5] for the 5 items respectively
   - Returns list of results

3. Main block that tests:
   if __name__ == '__main__':
       import asyncio
       import time
       items = [1, 2, 'hello', 3, 'world']
       start = time.time()
       results = asyncio.run(process_all(items))
       elapsed = time.time() - start
       print('Processed', len(results), 'items in', round(elapsed, 2), 'seconds')
       for r in results:
           print(' ', r.get('item'), '->', r.get('result'))
       # Verify concurrency: should take less than 1s total (not 2.5s sequential)
       print('Concurrent:', elapsed < 1.0)

Use run_command: python async_processor.py

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test12_async/async_processor.py' && \
 grep -qE 'async def|asyncio' '$TEST_WORKDIR/test12_async/async_processor.py' && \
 grep -q 'gather' '$TEST_WORKDIR/test12_async/async_processor.py' && \
 python '$TEST_WORKDIR/test12_async/async_processor.py' 2>&1 | grep -qE 'Processed [0-9]+ items'" \
240

# ============================================================
# TEST 13: SQLite Database Operations
# ============================================================
run_test "test13_sql" \
"You MUST use tools. Do NOT output code as text.

Create a SQLite database manager. Use write_file to create 'database.py' with:

1. Create a database 'shop.db' with TWO tables:
   - products: id (PRIMARY KEY), name (TEXT), price (REAL), category (TEXT)
   - orders: id (PRIMARY KEY), product_id (FOREIGN KEY), quantity (INTEGER), order_date (TEXT)

2. Insert sample data:
   - Products: ('Laptop', 999.99, 'Electronics'), ('Mouse', 29.99, 'Electronics'), ('Desk', 299.99, 'Furniture'), ('Chair', 199.99, 'Furniture')
   - Orders: at least 5 orders referencing products with different quantities

3. Write and execute these queries, printing results:
   - Total revenue per category (join products and orders, sum price * quantity, group by category)
   - Top selling product by quantity
   - Average order value

4. Export the category revenue results to 'revenue.csv'

Use run_command: python database.py

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test13_sql/database.py' && \
 cd '$TEST_WORKDIR/test13_sql' && python database.py 2>&1 && \
 test -f '$TEST_WORKDIR/test13_sql/shop.db' && \
 test -f '$TEST_WORKDIR/test13_sql/revenue.csv' && \
 sqlite3 '$TEST_WORKDIR/test13_sql/shop.db' 'SELECT COUNT(*) FROM products' | grep -qE '^[4-9]' && \
 sqlite3 '$TEST_WORKDIR/test13_sql/shop.db' 'SELECT COUNT(*) FROM orders' | grep -qE '^[5-9]' && \
 grep -qiE '(electronics|furniture)' '$TEST_WORKDIR/test13_sql/revenue.csv'" \
200

# ============================================================
# TEST 14: CLI Tool with Argparse
# ============================================================
run_test "test14_cli" \
"You MUST use tools. Do NOT output code as text.

Build a CLI note-taking tool. Use write_file to create 'notes_cli.py' with argparse:

1. Subcommand 'add' with arguments:
   - --title TITLE (required)
   - --content CONTENT (required)  
   - Appends note to 'notes.json' file (create if not exists)

2. Subcommand 'list':
   - Reads and displays all notes from 'notes.json'
   - Shows title and first 50 chars of content

3. Subcommand 'search' with argument:
   - --query QUERY
   - Searches notes by title or content, prints matches

4. Proper help text for all commands

Test it by running these commands IN ORDER:
- python notes_cli.py add --title 'First Note' --content 'This is my first note content'
- python notes_cli.py add --title 'Second Note' --content 'Another note about Python programming'  
- python notes_cli.py list
- python notes_cli.py search --query 'Python'

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test14_cli/notes_cli.py' && \
 grep -q 'argparse' '$TEST_WORKDIR/test14_cli/notes_cli.py' && \
 grep -q 'add_subparsers\|subparsers' '$TEST_WORKDIR/test14_cli/notes_cli.py' && \
 cd '$TEST_WORKDIR/test14_cli' && \
 python notes_cli.py add --title 'Test' --content 'Testing the CLI tool' && \
 python notes_cli.py list 2>&1 | grep -qi 'test' && \
 test -f '$TEST_WORKDIR/test14_cli/notes.json'" \
200

# ============================================================
# TEST 15: Web Search and Data Aggregation (Agentic) - Simplified
# ============================================================
run_test "test15_web_search" \
"You MUST use tools. Search the web and create a summary.

1. Use web_search to find information about 'Python programming latest version'
2. Use write_file to create 'python_info.txt' with:
   - What you learned about Python from the search
   - At least 2 URLs from the search results
   - Total: at least 5 lines of content

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test15_web_search/python_info.txt' && \
 grep -qi 'python' '$TEST_WORKDIR/test15_web_search/python_info.txt' && \
 grep -qi 'http' '$TEST_WORKDIR/test15_web_search/python_info.txt' && \
 test \$(wc -l < '$TEST_WORKDIR/test15_web_search/python_info.txt') -ge 5" \
150

# ============================================================
# TEST 16: System Configuration (Agentic) - Simplified
# ============================================================
run_test "test16_config" \
"You MUST use tools. Create configuration files for a dev environment.

1. Use write_file to create 'gitconfig.txt' with these exact lines:
   [user]
   name = Test User
   email = test@example.com

2. Use write_file to create 'env_setup.sh' with:
   - Export PATH with ~/bin appended: export PATH=\"\$PATH:~/bin\"
   - One alias: alias ll='ls -la'
   - Echo message: echo \"Environment configured\"

3. Use run_command: chmod +x env_setup.sh
4. Use run_command: bash env_setup.sh (to test it runs)

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test16_config/gitconfig.txt' && \
 test -f '$TEST_WORKDIR/test16_config/env_setup.sh' && \
 test -x '$TEST_WORKDIR/test16_config/env_setup.sh' && \
 grep -q 'Test User' '$TEST_WORKDIR/test16_config/gitconfig.txt' && \
 grep -q 'PATH' '$TEST_WORKDIR/test16_config/env_setup.sh' && \
 bash '$TEST_WORKDIR/test16_config/env_setup.sh' 2>&1 | grep -q 'configured'" \
180

# ============================================================
# TEST 17: Research and Report Generation (Multi-step Agentic) - Simplified
# ============================================================
run_test "test17_research" \
"You MUST use tools. Research a topic and write a report.

1. Use web_search to find 'artificial intelligence 2025'
2. Use write_file to create 'ai_report.md' with:
   - A brief summary of what you found (3-5 sentences)
   - List at least 3 key points from your search
   - Include at least 1 URL source

Minimum 10 lines total.

Call task_complete with summary." \
"test -f '$TEST_WORKDIR/test17_research/ai_report.md' && \
 grep -qiE 'ai|artificial|intelligence' '$TEST_WORKDIR/test17_research/ai_report.md' && \
 grep -qi 'http' '$TEST_WORKDIR/test17_research/ai_report.md' && \
 test \$(wc -l < '$TEST_WORKDIR/test17_research/ai_report.md') -ge 10" \
200

# ============================================================
# TEST 18: File Organization (Agentic) - Simplified
# ============================================================
run_test "test18_organize" \
"You MUST use tools. Create and organize files.

1. Create 3 text files with write_file:
   - notes1.txt with content \"Meeting notes\"
   - notes2.txt with content \"Project ideas\"
   - readme.md with content \"# Documentation\"

2. Create two directories using run_command:
   - mkdir text_files
   - mkdir markdown_files

3. Move files to appropriate folders using run_command:
   - mv notes*.txt text_files/
   - mv *.md markdown_files/

4. Create 'file_list.txt' using write_file that lists:
   - All files in text_files/ directory
   - All files in markdown_files/ directory

5. Use run_command: cat file_list.txt

Call task_complete with summary." \
"test -d '$TEST_WORKDIR/test18_organize/text_files' && \
 test -d '$TEST_WORKDIR/test18_organize/markdown_files' && \
 test -f '$TEST_WORKDIR/test18_organize/text_files/notes1.txt' && \
 test -f '$TEST_WORKDIR/test18_organize/text_files/notes2.txt' && \
 test -f '$TEST_WORKDIR/test18_organize/markdown_files/readme.md' && \
 test -f '$TEST_WORKDIR/test18_organize/file_list.txt'" \
180

fi  # End of full test suite (tests 9-18 skipped in quick mode)

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
| Correctness | 65% | Tests passed (primary factor) |
| Efficiency | 10% | Fewer iterations is better (baseline: ${BASELINE_ITERATIONS}/test) |
| Speed | 0% | Not weighted (accuracy matters more than speed) |
| Format | 25% | Output correctness |

## Test Artifacts

Saved to: \`$RESULTS_DIR/\`
EOF

echo ""
echo "Results saved to: $RESULT_FILE"
echo ""

# ============================================================
# Cleanup: Unload model from memory
# ============================================================
# CRITICAL: Always unload the model after testing to free memory
# This prevents OOM issues when running multiple models sequentially
log "Unloading model from memory..."
ollama stop "$MODEL" 2>/dev/null || true
log "Model unloaded, memory freed"
echo ""
