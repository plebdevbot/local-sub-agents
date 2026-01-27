# Testing Workflow

## Overview

The test suite validates model capabilities for sub-agent tasks. It provides objective measurements of which models work well with the tool-calling wrapper.

## Test Suite Structure

```
tests/
├── run-tests.sh          # Main test runner (8 tests)
├── compare-results.sh    # Compare results across models
├── README.md             # Test documentation
└── results/              # Output artifacts (gitignored)
    ├── MODEL_TIMESTAMP.md         # Summary results
    └── MODEL_testN_TIMESTAMP/     # Per-test artifacts
        ├── output.log             # Script output
        └── [created files]        # Test outputs
```

## Running Tests

### Basic Usage

```bash
# Run with default model (qwen3:8b)
./tests/run-tests.sh

# Run with specific model
./tests/run-tests.sh rnj-1:8b

# Run with model tag
./tests/run-tests.sh glm-4.7-flash:latest
```

### Expected Output

```
╔═══════════════════════════════════════════════════════════╗
║         Local Sub-Agent Test Suite                        ║
╠═══════════════════════════════════════════════════════════╣
║  Model: qwen3:8b
║  Time:  2026-01-26 14:30:00
╚═══════════════════════════════════════════════════════════╝

[test] Warming up model: qwen3:8b
[test] Running: test1_python
[agent] Model: qwen3:8b
[agent] Workdir: /tmp/tmp.XXX/test1_python
...
[✓] test1_python (12s, 3 iter)

[test] Running: test2_config
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULTS: 8/8 passed (95s total)
QUALITY SCORE: 85/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## The 8 Tests

### Test 1: Python Script (test1_python)

**Purpose:** Validate code generation and execution.

**Prompt:**
```
You MUST use tools. Do NOT output code as text.

Use write_file to create 'password_generator.py' with:
- A function generate_password(length=16) using secrets module
- Main block that prints 3 passwords

Use run_command: python password_generator.py

Call task_complete with summary.
```

**Verification:**
- File exists
- Python runs without error
- Output contains 3+ lines

**Tests:** Basic tool usage, code generation, execution

---

### Test 2: Config File (test2_config)

**Purpose:** Validate structured output generation.

**Prompt:**
```
You MUST use tools. Do NOT output code as text.

Use write_file to create 'docker-compose.yml' with:
- nginx service on port 80
- postgres service with POSTGRES_PASSWORD env var
- redis service on port 6379
- All on network 'app-net'

Call task_complete with summary.
```

**Verification:**
- File exists
- Contains: nginx, postgres, redis, app-net

**Tests:** YAML generation, multi-service config

---

### Test 3: Shell Script (test3_shell)

**Purpose:** Validate bash scripting and execution.

**Prompt:**
```
You MUST use tools. Do NOT output code as text.

Use write_file to create 'sysinfo.sh' that shows:
- hostname and kernel version
- disk usage for /
- top 3 memory processes

Use run_command: chmod +x sysinfo.sh
Use run_command: ./sysinfo.sh

Call task_complete with summary.
```

**Verification:**
- File is executable
- Output contains system info keywords

**Tests:** Shell scripting, chmod, multi-step execution

---

### Test 4: Data Transformation (test4_transform)

**Purpose:** Validate read → process → write workflow.

**Setup:** Pre-created `scores.json`:
```json
[{"name":"Alice","score":85},{"name":"Bob","score":92},{"name":"Carol","score":78}]
```

**Prompt:**
```
You MUST use tools. Do NOT guess or make up data.

1. Use read_file to read 'scores.json' FIRST - it contains the actual data
2. Parse the JSON and calculate the real average from the scores in the file
3. Use write_file to create 'report.txt' with each person's name:score and the average
4. Use run_command: cat report.txt

Call task_complete with summary.
```

**Verification:**
- File exists
- Contains all three names
- Contains average (85 or similar)

**Tests:** File reading, data processing, calculation

---

### Test 5: Error Handling (test5_errors)

**Purpose:** Validate graceful error recovery.

**Prompt:**
```
You MUST use tools.

Use read_file to try reading 'nonexistent.txt' - it will fail.
Then use write_file to create 'error_log.txt' with a message about the missing file.

Call task_complete with summary.
```

**Verification:**
- error_log.txt exists
- Contains error-related text

**Tests:** Error handling, recovery, logging

---

### Test 6: Multi-File (test6_multifile)

**Purpose:** Validate cross-file comprehension.

**Setup:** Pre-created `utils.js` with bug and `main.js` that imports it.

**Prompt:**
```
You MUST use tools.

1. Use run_command: node main.js (it will show a bug - the year shows as literal 'YYYY')
2. Use read_file to examine both 'utils.js' and 'main.js'
3. Find and fix the bug in utils.js using write_file
4. Use run_command: node main.js (should now show correct year like 2026)

Call task_complete with what you fixed.
```

**Verification:**
- Running main.js outputs correct year (202X)

**Tests:** Cross-file understanding, debugging, fix validation

---

### Test 7: Iterative Debugging (test7_debug)

**Purpose:** Validate run → read error → fix → verify cycle.

**Setup:** Pre-created `calculator.py` with NameError bug.

**Prompt:**
```
You MUST use tools. Follow these steps IN ORDER:

STEP 1: run_command with 'python calculator.py' - you will see a NameError
STEP 2: read_file 'calculator.py' to see the code
STEP 3: The bug is using 'count' instead of 'len(numbers)' - fix it with write_file
STEP 4: run_command 'python calculator.py' again to verify the fix works

Call task_complete when the script runs successfully.
```

**Verification:**
- Python runs successfully
- Output shows average calculation

**Tests:** Error diagnosis, code fixing, verification loop

---

### Test 8: Format Compliance (test8_format)

**Purpose:** Validate exact format output.

**Prompt:**
```
You MUST use tools.

Create a file 'users.csv' with EXACTLY this format (including header, no extra whitespace):
name,age,city
Alice,30,NYC
Bob,25,LA
Carol,35,Chicago

Then use run_command: cat users.csv

Call task_complete confirming the file was created.
```

**Verification:**
- File exists
- Exactly 4 lines
- Header matches exactly

**Tests:** Format compliance, instruction following

## Quality Scoring

The test suite computes a weighted quality score (0-100):

### Score Components

| Dimension | Weight | Calculation |
|-----------|--------|-------------|
| Correctness | 40% | (tests passed / total tests) × 40 |
| Efficiency | 20% | Penalty for iterations above baseline |
| Speed | 20% | Penalty for time above baseline |
| Format | 20% | Same as correctness |

### Baselines

```bash
BASELINE_ITERATIONS=3    # Optimal iterations per test
BASELINE_TIME=15         # Optimal seconds per test
```

### Example Calculation

```
Model: qwen3:8b
Passed: 8/8, Avg iterations: 3.2, Avg time: 15s

Correctness: 1.0 × 40 = 40
Efficiency: 20 × (1 - (3.2 - 3) / 3) = 18.7
Speed: 20 × (1 - (15 - 15) / 15) = 20
Format: 1.0 × 20 = 20

Total: 98.7 → 98/100
```

## Comparing Models

### Run Multiple Models

```bash
./tests/run-tests.sh qwen3:8b
./tests/run-tests.sh rnj-1:8b
./tests/run-tests.sh glm-4.7-flash:latest
```

### View Comparison

```bash
./tests/compare-results.sh
```

Output:
```
| Model           | Pass | Score | Time |
|-----------------|------|-------|------|
| rnj-1:8b        | 8/8  | 92    | 85s  |
| qwen3:8b        | 8/8  | 87    | 102s |
| glm-4.7-flash   | 7/8  | 71    | 210s |
```

### JSON Export

```bash
./tests/compare-results.sh --json > results.json
```

## Debugging Failed Tests

### 1. Check Output Log

```bash
cat tests/results/MODEL_testN_TIMESTAMP/output.log
```

Shows:
- Model responses
- Tool calls made
- Errors encountered

### 2. Examine Created Files

```bash
ls -la tests/results/MODEL_testN_TIMESTAMP/
cat tests/results/MODEL_testN_TIMESTAMP/script.py
```

### 3. Run Test Manually

```bash
mkdir /tmp/debug-test
OLLAMA_MODEL=model:tag ./ollama-agent.sh "prompt" /tmp/debug-test
```

### 4. Check Verification Command

Each test has a verification command. Run it manually:

```bash
# From test definition
test -f '/tmp/xxx/password_generator.py' && \
  python '/tmp/xxx/password_generator.py' > /tmp/xxx/output.txt 2>&1 && \
  test $(wc -l < '/tmp/xxx/output.txt') -ge 3
```

## Adding New Tests

### 1. Define the Test

Add to `run-tests.sh`:

```bash
run_test "test_name" \
"Prompt with explicit tool instructions.

1. Use tool_name to do something
2. Use another_tool
3. Call task_complete with summary" \
"verification_command_that_returns_0_on_pass"
```

### 2. Add Setup if Needed

```bash
# Create pre-existing files
mkdir -p "$TEST_WORKDIR/test_name"
echo '{"key": "value"}' > "$TEST_WORKDIR/test_name/input.json"

run_test "test_name" \
"..." \
"..."
```

### 3. Run and Verify

```bash
./tests/run-tests.sh
# Check results
cat tests/results/MODEL_test_name_*/output.log
```

## Test Design Guidelines

### 1. Explicit Instructions

```
❌ "Create a script"
✅ "Use write_file to create 'script.py' with..."
```

### 2. Verifiable Outputs

```
❌ "Make something useful"
✅ "Create 'output.txt' containing exactly 3 lines"
```

### 3. Reasonable Scope

- Tests should complete in <60s
- Focus on one capability per test
- Clear pass/fail criteria

### 4. Setup Isolation

- Each test gets fresh temp directory
- Pre-created files in setup section
- No cross-test dependencies

## Warm-up Handling

The test suite warms up models before benchmarking:

```bash
log "Warming up model: $MODEL"
curl -s http://localhost:11434/api/chat \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false}"
```

This ensures:
- Model is loaded in GPU memory
- First test timing is fair
- Cold start latency excluded from metrics

## Results Interpretation

### Good Results (Recommended)

```
Pass Rate: 8/8
Quality Score: 80+
Avg Time: <20s/test
```

Model is reliable for production sub-agent use.

### Marginal Results (Use with Caution)

```
Pass Rate: 5-7/8
Quality Score: 50-79
Avg Time: 20-40s/test
```

May work for simple tasks. Test specific use cases.

### Poor Results (Not Recommended)

```
Pass Rate: <5/8
Quality Score: <50
```

Model likely has tool format issues or poor instruction following.

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Model Tests

on: [push]

jobs:
  test:
    runs-on: self-hosted  # Needs Ollama access
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Tests
        run: ./tests/run-tests.sh qwen3:8b
        
      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: tests/results/
```

### Automated Comparison

```bash
#!/bin/bash
# compare-models.sh
MODELS="qwen3:8b rnj-1:8b glm-4.7-flash:latest"

for model in $MODELS; do
    echo "Testing $model..."
    ./tests/run-tests.sh "$model"
done

./tests/compare-results.sh --json > comparison.json
```
