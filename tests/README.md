# Local Sub-Agent Test Suite

A comprehensive benchmark for evaluating local LLM performance on agentic coding tasks.

## Overview

This test suite evaluates models on **14 real-world coding scenarios** that require:
- **Tool usage discipline** (write files, run commands, read output)
- **Iterative problem solving** (debug errors, refactor code)
- **Code quality** (syntax correctness, logic accuracy)
- **Task completion** (following multi-step instructions)

## Quick Start

```bash
# Test a single model
./run-tests.sh qwen3:8b

# Test multiple models
./benchmark-all.sh

# View results
ls results/*.md
```

## Test Categories

### Easy Tests (70-80% pass rate)
- **test1_python** - Generate Python script with stdlib
- **test2_config** - Create docker-compose.yml
- **test4_transform** - Read JSON, transform, write output
- **test5_errors** - Error handling (read missing file)
- **test8_format** - Generate CSV with exact format

### Medium Tests (40-60% pass rate)
- **test3_shell** - Bash script with system commands
- **test7_debug** - Fix Python syntax error
- **test9_api_client** - HTTP client with urllib
- **test12_async** - Async/await with asyncio

### Hard Tests (20-40% pass rate)
- **test6_multifile** - Read and fix bug across multiple files
- **test10_parser** - Expression evaluator with precedence
- **test11_refactor** - Split god-object into separate classes
- **test14_cli** - Argparse CLI tool

### Very Hard Tests (<20% pass rate)
- **test13_sql** - SQLite database with joins and aggregation

## Scoring System

**Quality Score** (0-100) = Weighted sum of:

| Dimension | Weight | Calculation |
|-----------|--------|-------------|
| **Correctness** | 50% | Pass rate × 50 |
| **Efficiency** | 20% | Based on iteration count (lower is better) |
| **Speed** | 10% | Based on time per test (faster is better) |
| **Format** | 20% | Pass rate × 20 |

### Baselines
- **Iterations:** 4 per test (optimal)
- **Time:** 25 seconds per test (optimal)
- More iterations = model struggled
- Faster completion = better efficiency

### Score Interpretation
- **90-100:** Exceptional (better than baseline)
- **80-89:** Excellent (top-tier performance)
- **70-79:** Very Good (strong coding model)
- **60-69:** Good (capable mid-tier)
- **50-59:** Fair (weak but functional)
- **40-49:** Poor (struggles with tool usage)
- **30-39:** Very Poor (fundamental issues)
- **0-29:** Failed (model crashes or incompatible)

## Model Requirements

### Minimum Requirements
- **RAM:** 8GB for 7-8B models, 16GB for 20B+ models
- **Tool calling:** Must support function/tool calling
- **Context:** 4096+ tokens recommended
- **Ollama:** Compatible with latest Ollama version

### Known Incompatibilities
- Models that crash with `GGML_ASSERT` errors
- Models requiring more VRAM than available
- Models without tool calling support

### Pre-Flight Check
The benchmark runs a simple test prompt before starting:
```bash
# If this fails, the model won't work:
ollama run your-model "Use tool to complete task" 
```

## Common Failure Modes

### 1. Tool Adherence Failures
**Symptom:** Model outputs code as text instead of using `write_file`

**Example:**
```
❌ Model says: "Here's the code: ```python..."
✅ Model should: call write_file(path="script.py", content="...")
```

**Affected models:** Smaller/weaker models (7B and below)

### 2. Syntax Errors
**Symptom:** Code is written to file but doesn't run

**Example:**
```python
if __name__ == 'main':  # ❌ Wrong! Should be '__main__'
```

**Affected models:** Models with poor code training

### 3. Logic Errors
**Symptom:** Code runs but produces wrong output

**Example:**
```python
return ''.join(letters + digits)[:length]  # ❌ Wrong slicing
```

**Affected models:** Models that don't test their code

### 4. Premature Completion
**Symptom:** Model calls `task_complete` without doing the work

**Example:**
```
Iteration 1: task_complete("I will create the file...")  # ❌ Didn't actually do it
```

**Affected models:** Models that misunderstand tool semantics

## Test Details

### Test 1: Python Script Generation
**Goal:** Generate password_generator.py using secrets module  
**Key Skills:** Basic Python, stdlib knowledge, tool usage  
**Timeout:** 120s  
**Verification:** File exists, runs without errors, outputs 3+ passwords

### Test 2: Config File Generation
**Goal:** Create docker-compose.yml with 3 services  
**Key Skills:** YAML syntax, Docker knowledge  
**Timeout:** 120s  
**Verification:** Valid YAML with nginx, postgres, redis, network

### Test 3: Shell Script
**Goal:** Create sysinfo.sh showing system info  
**Key Skills:** Bash scripting, system commands  
**Timeout:** 120s  
**Verification:** Executable, outputs hostname/kernel/disk/memory  
**Note:** May hit JSON parsing bug with complex shell variables

### Test 4: Data Transformation
**Goal:** Read scores.json, calculate average, write report  
**Key Skills:** Read → Process → Write pipeline, JSON parsing  
**Timeout:** 120s  
**Verification:** Report contains all names and correct data (not made-up numbers)

### Test 5: Error Handling
**Goal:** Attempt to read missing file, handle error gracefully  
**Key Skills:** Error handling, logging  
**Timeout:** 120s  
**Verification:** Error log file mentions the missing file

### Test 6: Multi-File Debugging
**Goal:** Find and fix bug in utils.js affecting main.js  
**Key Skills:** Read multiple files, debug, iterative testing  
**Timeout:** 120s  
**Verification:** Fixed code produces correct year output

### Test 7: Iterative Debugging
**Goal:** Run buggy Python script, see error, fix, re-run  
**Key Skills:** Read errors, diagnose, fix  
**Timeout:** 240s (needs multiple iterations)  
**Verification:** Fixed script runs and prints average

### Test 8: Format Compliance
**Goal:** Create CSV with exact format (no extra whitespace)  
**Key Skills:** Precise formatting, attention to detail  
**Timeout:** 120s  
**Verification:** Exactly 4 lines, correct header, proper format

### Test 9: REST API Client
**Goal:** Build HTTP client using urllib (stdlib only)  
**Key Skills:** HTTP, JSON, error handling, OOP  
**Timeout:** 240s (network requests)  
**Verification:** Class exists, uses urllib, passes tests

### Test 10: Expression Parser
**Goal:** Build math parser with operator precedence  
**Key Skills:** Parsing, recursion/evaluation, algorithm design  
**Timeout:** 240s (complex task)  
**Verification:** Parser passes 4-5 test cases with correct results

### Test 11: Code Refactoring
**Goal:** Split god-object into 4 separate classes  
**Key Skills:** OOP design, refactoring, maintaining behavior  
**Timeout:** 240s (needs reading and restructuring)  
**Verification:** 4 classes exist, tests pass

### Test 12: Async Programming
**Goal:** Use asyncio for concurrent task processing  
**Key Skills:** async/await, concurrency, stdlib  
**Timeout:** 240s  
**Verification:** Uses asyncio.gather, demonstrates concurrency

### Test 13: Database Operations
**Goal:** Create SQLite db, insert data, run complex queries, export CSV  
**Key Skills:** SQL, joins, aggregation, file I/O  
**Timeout:** 240s  
**Verification:** DB exists, tables populated, queries correct, CSV exported

### Test 14: CLI Tool
**Goal:** Build note-taking CLI with argparse subcommands  
**Key Skills:** CLI design, argparse, JSON persistence  
**Timeout:** 240s  
**Verification:** Argparse used, subcommands work, notes.json created

## Known Issues & Limitations

### Issue 1: Ollama JSON Parsing Bug
**Impact:** Tests with shell scripts (test3, test6) may fail due to Ollama returning improperly escaped JSON when content contains `$` or complex escape sequences.

**Workaround:** This is an Ollama API bug. Results for test3/test6 may be slightly pessimistic for some models.

**Filed:** [Issue reference TBD]

### Issue 2: Model Compatibility
Some models crash with runtime errors:
- `ServiceNow-AI/Apriel-1.6-15b-Thinker:Q4_K_M` - GGML_ASSERT failures
- `nemotron-3-nano:latest` - CUDA out of memory

These models are **excluded** from benchmark results as their scores don't reflect capability.

### Issue 3: Tool Calling Quality Varies
Not all models support tool calling equally:
- Strong: qwen3, gpt-oss, deepseek-coder families
- Weak: llama3.1, mistral 7B (often output code as text)

This is a **feature, not a bug** - the benchmark correctly identifies this weakness.

## Interpreting Results

### High Score + High Iterations
**Example:** 80/100 score, 7 avg iterations  
**Meaning:** Model gets there eventually but struggles  
**Good for:** Tasks where correctness matters more than speed

### High Score + Low Iterations
**Example:** 85/100 score, 3 avg iterations  
**Meaning:** Model is efficient and accurate  
**Good for:** Production use, speed-critical tasks

### Low Score + Low Iterations
**Example:** 40/100 score, 1.5 avg iterations  
**Meaning:** Model gives up quickly or outputs text instead of using tools  
**Problem:** Fundamental tool-calling issues

### Low Score + High Iterations
**Example:** 50/100 score, 8 avg iterations  
**Meaning:** Model tries hard but produces buggy code  
**Problem:** Code quality or logic errors

## Debugging Failed Tests

### Check the Logs
```bash
# View test output
cat results/MODEL_NAME_testN_TESTNAME_TIMESTAMP/output.log

# Check what was actually written
ls results/MODEL_NAME_testN_TESTNAME_TIMESTAMP/
cat results/MODEL_NAME_testN_TESTNAME_TIMESTAMP/file.py
```

### Common Patterns

**"Verification failed" + 1 iteration:**
→ Model crashed or refused to use tools

**"Verification failed" + 2-4 iterations:**
→ Code has bugs (syntax or logic errors)

**"Verification failed" + 8-10 iterations:**
→ Model is stuck in a loop, can't figure out the fix

**"Invalid API response":**
→ Ollama error (check model compatibility)

## Contributing

### Adding New Tests

1. Add test to `run-tests.sh`
2. Choose appropriate timeout (120s simple, 240s complex)
3. Write clear verification command
4. Test with 3-4 different models
5. Document in this README

### Improving Prompts

If models are confused by a prompt:
1. Make instructions more explicit
2. Add examples of what NOT to do
3. Emphasize tool usage
4. Test that strong models still pass

### Reporting Issues

Include:
1. Model name and version
2. Test that failed
3. Log output
4. Expected vs actual behavior

## Changelog

### 2026-01-28 - Polish & Documentation
- Added comprehensive README
- Enhanced prompts for clarity
- Documented known issues
- Added pre-flight compatibility check

### 2026-01-27 - Initial Release
- 14 tests covering easy → very hard scenarios
- Quality scoring system
- Support for Ollama models with tool calling

---

**License:** MIT  
**Author:** Local Sub-Agent Benchmark Project  
**Version:** 1.0
