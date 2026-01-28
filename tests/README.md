# Local Sub-Agent Test Suite

Reproducible benchmark tests for comparing local LLM performance as sub-agents.

## Quick Start

```bash
# Run tests with default model (qwen3:8b)
./run-tests.sh

# Run tests with specific model
./run-tests.sh glm-4.7-flash:latest

# Run full model suite (all installed models)
./benchmark-all-models.sh

# Compare results across models
./compare-results.sh

# Export results as JSON
./compare-results.sh --json > results.json
```

## Test Descriptions

### Basic Tests (1-8)

| Test | Name | What It Tests | Timeout |
|------|------|---------------|---------|
| 1 | Python Script | Code generation, secrets module, main block | 240s |
| 2 | Config File | YAML generation, multi-service Docker config | 240s |
| 3 | Shell Script | Bash scripting, system commands, chmod | 240s |
| 4 | Data Transform | read_file → process → write_file chain | 240s |
| 5 | Error Handling | Graceful failure, recovery, logging | 240s |
| 6 | Multi-File | Cross-file comprehension, bug fixing | 240s |
| 7 | Debugging | Run → interpret error → fix → verify | 240s |
| 8 | Format Compliance | Exact output format, instruction following | 240s |

### Advanced Tests (9-14) — Stdlib Only

| Test | Name | What It Tests | Timeout |
|------|------|---------------|---------|
| 9 | API Client | HTTP client class (urllib), error handling | 200s |
| 10 | Expression Parser | Parsing, operator precedence, parentheses | 200s |
| 11 | Refactor Class | Split god object into 4 separate classes | 240s |
| 12 | Async Processor | asyncio.gather, concurrent task processing | 240s |
| 13 | SQL Database | SQLite schema, joins, aggregation, CSV export | 200s |
| 14 | CLI Tool | argparse subcommands, JSON persistence | 200s |

**Note:** Tests 9 and 12 use Python stdlib only (urllib, asyncio) — no external packages required.

### Test Difficulty Progression

- **Tests 1-4**: Basic tool usage — can the model use tools at all?
- **Tests 5-8**: Error recovery and multi-step — can it handle problems?
- **Tests 9-11**: Complex code generation — can it write non-trivial code?
- **Tests 12-14**: Advanced patterns — async, SQL, CLI architecture

## Scoring System

### Pass/Fail
Each test is pass/fail based on verification command:
- **PASS**: Output file exists AND verification succeeds
- **FAIL**: Missing file OR verification failed

### Quality Score (0-100)

Tests compute a weighted quality score emphasizing **accuracy over speed**:

| Dimension | Weight | Measurement |
|-----------|--------|-------------|
| **Correctness** | **50%** | Tests passed / total tests |
| Efficiency | 20% | Iterations used (fewer is better, baseline: 4/test) |
| Speed | 10% | Time taken (faster is better, baseline: 25s/test) |
| Format | 20% | Output correctness (tied to pass rate) |

Higher scores indicate better overall sub-agent performance.

## Latest Benchmark Results

**qwen3:8b** (our current best local model):

| Metric | Value |
|--------|-------|
| Tests Passed | 10/14 |
| Quality Score | 73/100 |
| Total Time | 569s |
| Avg Iterations | 2.7/test |

**Test Breakdown:**
- ✅ test1-6, test8, test10-12 (10 passed)
- ❌ test7, test9, test13, test14 (4 failed)

## Model Compatibility

| Model | Status | Notes |
|-------|--------|-------|
| qwen3:8b | 🥇 Best | 10/14 passed, fast, reliable |
| rnj-1:8b | Good | Fast, decent quality |
| devstral-small-2 | Good | All basic tests pass |
| gpt-oss:20b | Good | Larger but capable |
| glm-4.7-flash | Decent | Slower but passes basics |
| ministral-3 | Partial | May fail complex tests |
| llama3.1:8b | Limited | Tool format issues |
| mistral:7b | Limited | Tool format issues |

### Known Issues

**Llama/Mistral models**: May output tool calls as JSON text instead of using Ollama's native tool_calls format. This causes the wrapper to not execute tools properly.

## Adding Models

1. Pull the model: `ollama pull <model>`
2. Run tests: `./run-tests.sh <model>`
3. Compare: `./compare-results.sh`

## Results Format

Results saved to `./results/` with format:
```
{model}_{timestamp}.md          # Summary report with scores
{model}_{testname}_{timestamp}/ # Test artifacts (code, logs)
```

### JSON Export

Use `./compare-results.sh --json` for machine-readable output:

```json
{
  "generated": "2026-01-27T12:00:00+00:00",
  "results": [
    {
      "model": "qwen3:8b",
      "passed": 10,
      "total": 14,
      "quality_score": 73,
      "time_seconds": 569,
      "tests": [...]
    }
  ]
}
```

## Test Requirements

### Required
- Ollama running (`ollama serve`)
- Model pulled (`ollama pull <model>`)
- Python 3.x
- Node.js (for test 6)
- SQLite3 (for test 13)
- Basic Unix tools (grep, awk, cat, timeout, jq)

### Optional
- Internet connection (test 9 uses httpbin.org)

**No pip packages required** — all tests use Python stdlib only.

## What Makes a Good Sub-Agent Model?

1. **Tool compliance** — Actually uses tools instead of outputting text
2. **Instruction following** — Does what's asked, nothing more
3. **Accuracy** — Correct code, proper syntax
4. **Error recovery** — Graceful handling of failures
5. **Multi-file comprehension** — Understands context across files
6. **Debugging ability** — Can interpret errors and fix issues
7. **Efficiency** — Completes tasks in fewer iterations
8. **Design patterns** — Can structure code into classes (tests 9, 11)
9. **Algorithm knowledge** — Operator precedence, async patterns (tests 10, 12)
10. **Database skills** — SQL joins, aggregation (test 13)
11. **CLI architecture** — Subcommands, argument parsing (test 14)

## Example Output

```
╔═══════════════════════════════════════════════════════════╗
║         Local Sub-Agent Test Suite                        ║
╠═══════════════════════════════════════════════════════════╣
║  Model: qwen3:8b
║  Time:  2026-01-27 21:48:48
╚═══════════════════════════════════════════════════════════╝

[test] Running: test1_python
[PASS] test1_python (13s, 2 iter)
[test] Running: test2_config
[PASS] test2_config (18s, 2 iter)
...
[test] Running: test11_refactor
[PASS] test11_refactor (149s, 10 iter)
[test] Running: test12_async
[PASS] test12_async (29s, 2 iter)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULTS: 10/14 passed (569s total)
QUALITY SCORE: 73/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Troubleshooting

### Model doesn't use tools
- Ensure prompt includes "You MUST use tools. Do NOT output code as text."
- Some models (llama, mistral) have tool format issues

### Test fails but output looks correct
- Check verification command in run-tests.sh
- Verify expected content matches actual output format

### High iteration count
- Model may be retrying or exploring unnecessarily
- Consider if prompt is clear enough

### Test times out
- Default timeouts: 200-240s per test
- Complex tests (11, 12) may need all iterations

### Ollama connection refused
- Run `ollama serve` in another terminal
- Check Ollama is running: `curl http://localhost:11434/api/tags`

## Contributing

1. Add tests following the existing pattern in `run-tests.sh`
2. Ensure tests use stdlib only (no pip dependencies)
3. Include clear verification commands
4. Update this README with test descriptions
