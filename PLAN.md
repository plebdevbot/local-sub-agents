# Local Sub-Agent Test Benchmark Suite - Improvement Plan

> **Status:** Phase 1-3 COMPLETE, Phase 4-5 PARTIAL  
> **Last Updated:** 2026-01-26

## Executive Summary

After thorough analysis of the current test suite, I've identified key improvements across test coverage, validation robustness, reporting capabilities, and documentation. The current suite successfully differentiates between models (rnj-1:8b champion at 31s vs qwen3:8b at 101s, both 5/5), but has gaps in quality measurement and edge case coverage.

---

## Phase 1: Critical Fixes (Highest Priority)

### 1.1 Fix Tool Call Format Compatibility

**Problem**: llama3.1:8b and mistral:7b fail because they output tool calls as JSON text instead of using Ollama's native tool_calls format.

**File**: `ollama-agent.sh`

**Changes**:
```bash
# Add format detection after receiving response
# If no tool_calls array but content contains JSON tool call pattern,
# attempt to parse it from content

detect_tool_calls_in_content() {
    local content="$1"
    # Check for patterns like {"name": "write_file", "arguments": ...}
    # or [{"name": "tool", ...}]
    if echo "$content" | grep -qE '^\s*\{?\s*"name"\s*:\s*"(write_file|read_file|run_command|list_files|task_complete)"'; then
        # Extract and reformat as proper tool call
        return 0
    fi
    return 1
}
```

**Impact**: Could improve llama3.1 from 3/5 to 5/5, mistral from 2/5 to potentially 4-5/5

---

### 1.2 Strengthen Test Verification

**Problem**: Current verification is too weak. Test 4 only checks `grep -q "alice"` - doesn't verify correct calculation.

**File**: `tests/run-tests.sh`

**Changes per test**:

| Test | Current Verification | Improved Verification |
|------|---------------------|----------------------|
| test1 | File exists + runs | + Output contains 3 lines of passwords (16+ chars each) |
| test2 | File exists + grep nginx,postgres | + YAML valid (`yq` or python yaml.safe_load) + redis present |
| test3 | Executable + runs | + Output contains hostname, kernel, disk usage |
| test4 | File exists + grep alice | + Check average = 85.0 + all 3 names present |
| test5 | error_log.txt exists | + Contains "nonexistent" or "not found" or similar |

**Implementation**:
```bash
# Test 4 - Enhanced verification
verify_test4() {
    local workdir="$1"
    [[ -f "$workdir/report.txt" ]] || return 1
    grep -qi "alice" "$workdir/report.txt" || return 1
    grep -qi "bob" "$workdir/report.txt" || return 1
    grep -qi "carol" "$workdir/report.txt" || return 1
    grep -qE "85(\.0)?" "$workdir/report.txt" || return 1
}
```

---

## Phase 2: New Test Cases (Medium Priority)

### 2.1 Test 6: Multi-File Refactoring

**Purpose**: Test ability to read multiple files, understand relationships, and make coordinated changes.

**Setup**: Create 2 files - `utils.js` and `main.js` where main imports from utils.

**Prompt**:
```
1. Use read_file to read 'utils.js' and 'main.js'
2. The function 'formatDate' in utils.js has a bug - it uses 'YYYY' instead of 'yyyy'
3. Use write_file to fix utils.js
4. Use run_command: node main.js
5. Call task_complete with summary
```

**Verification**: Output shows correctly formatted date (not literal YYYY)

**Why**: Tests multi-file comprehension - critical for real sub-agent tasks

---

### 2.2 Test 7: Iterative Debugging

**Purpose**: Test ability to run code, interpret errors, and fix them.

**Setup**: Provide a Python file with a subtle bug (off-by-one, wrong variable, etc.)

**Prompt**:
```
1. Use run_command: python buggy.py (it will fail)
2. Use read_file to examine buggy.py
3. Identify the bug from the error message
4. Use write_file to fix it
5. Use run_command: python buggy.py (should succeed now)
6. Call task_complete with what you fixed
```

**Verification**: Python runs successfully + output is correct

**Why**: This is the core sub-agent use case - fix a bug with minimal context

---

### 2.3 Test 8: Output Format Compliance

**Purpose**: Test ability to produce output in exact specified format.

**Prompt**:
```
Create a file 'data.csv' with EXACTLY this format (no extra columns/rows):
name,age,city
Alice,30,NYC
Bob,25,LA
Carol,35,Chicago

Then use run_command: wc -l data.csv
Call task_complete with the line count.
```

**Verification**:
- File has exactly 4 lines
- Header matches exactly
- CSV parseable

**Why**: Format compliance is crucial for sub-agent outputs to be usable

---

## Phase 3: Enhanced Reporting (Medium Priority)

### 3.1 JSON Export for Results

**File**: `tests/compare-results.sh`

**Add**:
```bash
# Generate JSON alongside table
generate_json() {
    echo "["
    for result in results/*.md; do
        # Parse and output JSON object
        echo "  {"
        echo "    \"model\": \"$model\","
        echo "    \"passed\": $passed,"
        echo "    \"total\": $total,"
        echo "    \"time_seconds\": $time,"
        echo "    \"date\": \"$date\","
        echo "    \"tests\": ["
        # Individual test results
        echo "    ]"
        echo "  },"
    done
    echo "]"
}
```

**Output**: `results/comparison.json`

---

### 3.2 Quality Score (Beyond Pass/Fail)

**Add scoring dimensions**:

| Dimension | Weight | Measurement |
|-----------|--------|-------------|
| Correctness | 40% | All verifications pass |
| Efficiency | 20% | Fewer iterations to complete |
| Speed | 20% | Normalized time (excluding first warm-up) |
| Format compliance | 20% | Output matches expected format exactly |

**New metric in results**:
```
## Quality Score: 87/100
- Correctness: 40/40 (all tests pass)
- Efficiency: 15/20 (avg 2.3 iterations vs optimal 2.0)
- Speed: 18/20 (31s, baseline 25s)
- Format: 14/20 (minor formatting deviations)
```

---

### 3.3 Leaderboard Generation

**New file**: `tests/generate-leaderboard.sh`

```bash
#!/bin/bash
# Generates markdown leaderboard from all results

echo "# Sub-Agent Model Leaderboard"
echo ""
echo "| Rank | Model | Score | Pass Rate | Avg Time |"
echo "|------|-------|-------|-----------|----------|"
# Sort by score descending, output rows
```

---

## Phase 4: Test Infrastructure (Lower Priority)

### 4.1 Warm-up Run Handling

**File**: `tests/run-tests.sh`

**Change**: Current warm-up is good, but:
- Add `--cold` flag to include first-run timing
- Default to excluding warm-up from timing
- Record warm-up time separately for analysis

```bash
# Before timing begins
warmup_time=$(warmup_model)
echo "Warm-up time: ${warmup_time}s (excluded from results)"
```

---

### 4.2 Timeout Configuration

**Add to `ollama-agent.sh`**:
```bash
TIMEOUT=${OLLAMA_TIMEOUT:-120}  # Default 2 minutes per test

# Wrap API call with timeout
timeout $TIMEOUT curl ... || {
    echo "[agent] API timeout after ${TIMEOUT}s"
    exit 1
}
```

---

### 4.3 Test Isolation Improvements

**Current**: Uses temp directories (good)

**Add**:
- Clean up temp dirs after test (configurable)
- `--keep-artifacts` flag to preserve for debugging
- Ensure no cross-test pollution

---

## Phase 5: Documentation Updates

### 5.1 Update `tests/README.md`

**Add sections**:
- Model compatibility matrix (which models work)
- Known issues per model
- Scoring methodology explanation
- How to interpret results
- Troubleshooting failed tests

### 5.2 Update main `README.md`

**Add**:
- Link to test results
- Model recommendations based on testing
- Performance characteristics section

### 5.3 Create `CONTRIBUTING.md`

**Content**:
- How to add new tests
- Test writing guidelines
- Verification best practices
- Submitting model results

---

## Implementation Priority Order

### Immediate (Do First)
1. ✅ **1.2** - Strengthen test verification (quick win, high value)
2. ✅ **2.2** - Add Test 7: Iterative Debugging (core use case)
3. ✅ **3.1** - JSON export (enables automation)

### Short-term (This Week)
4. ✅ **2.1** - Add Test 6: Multi-File Refactoring
5. ✅ **2.3** - Add Test 8: Format Compliance
6. ✅ **3.2** - Quality scoring system
7. ✅ **5.1** - Update tests/README.md

### Medium-term (When Needed)
8. ⏳ **1.1** - Tool call format compatibility (complex, model-specific) — *Deferred: requires significant refactoring*
9. ✅ **4.1** - Warm-up handling improvements
10. ✅ **4.2** - Timeout configuration — *Added to ollama-agent.sh*
11. ⏳ **3.3** - Leaderboard generation — *Can use compare-results.sh*
12. ✅ **5.2, 5.3** - Additional documentation — *TEST-RESULTS.md updated*

---

## New Test Summary Table

| Test | Name | Purpose | Differentiates |
|------|------|---------|----------------|
| 1 | python | Code gen + execution | Basic capability |
| 2 | config | Structured output (YAML) | Format compliance |
| 3 | shell | Script gen + chmod + exec | Multi-step |
| 4 | transform | Read → Process → Write | Data handling |
| 5 | errors | Error detection + logging | Recovery |
| **6** | **multi-file** | **Cross-file understanding** | **Context window** |
| **7** | **debugging** | **Run → Read error → Fix** | **Core agent loop** |
| **8** | **format** | **Exact output compliance** | **Instruction following** |

---

## Expected Outcomes

After implementing these improvements:

1. **Better differentiation**: New tests will reveal quality differences between models that currently both score 5/5
2. **Actionable metrics**: Quality scores beyond pass/fail help choose the right model for specific tasks
3. **Broader compatibility**: Format detection will support more model families
4. **Reproducible benchmarks**: JSON export enables tracking over time
5. **Clear documentation**: New users can run benchmarks and interpret results

---

## Files to Modify

| File | Changes |
|------|---------|
| `tests/run-tests.sh` | Add tests 6-8, enhance verification, warm-up timing |
| `tests/compare-results.sh` | Add JSON export, quality scoring |
| `ollama-agent.sh` | Tool call format detection (Phase 1.1), timeout |
| `tests/README.md` | Comprehensive update |
| `README.md` | Add test results section |
| `tests/generate-leaderboard.sh` | New file |
| `CONTRIBUTING.md` | New file |

---

## Questions Before Implementation

1. **Test difficulty**: Should new tests be harder than existing ones, or similar difficulty but testing different capabilities?

2. **Backward compatibility**: Should we version the test suite so old results remain comparable?

3. **Model-specific prompts**: Should we allow different prompts per model family to maximize compatibility, or keep prompts identical for fair comparison?

4. **Quality score weights**: Are the proposed weights (40/20/20/20) appropriate, or should correctness be weighted even higher?
