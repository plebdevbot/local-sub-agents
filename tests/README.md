# Local Sub-Agent Test Suite

Reproducible benchmark tests for comparing local LLM performance as sub-agents.

## Quick Start

```bash
# Run tests with default model (qwen3:8b)
./run-tests.sh

# Run tests with specific model
./run-tests.sh glm-4.7-flash:latest

# Compare results across models
./compare-results.sh

# Export results as JSON
./compare-results.sh --json > results.json
```

## Test Descriptions

### Basic Tests (1-8)

| Test | Name | What It Tests | Verification |
|------|------|---------------|--------------|
| 1 | Python Script | Code generation, secrets module, main block | Runs and outputs 3+ passwords |
| 2 | Config File | YAML generation, multi-service Docker config | Contains nginx, postgres, redis, app-net |
| 3 | Shell Script | Bash scripting, system commands, chmod | Executable, outputs system info |
| 4 | Data Transform | read_file -> process -> write_file chain | All names present + average = 85 |
| 5 | Error Handling | Graceful failure, recovery, logging | Error log references missing file |
| 6 | Multi-File | Cross-file comprehension, bug fixing | Fix 'YYYY' bug, output shows year |
| 7 | Debugging | Run -> interpret error -> fix -> verify | Fix undefined variable, runs successfully |
| 8 | Format Compliance | Exact output format, instruction following | CSV has 4 lines, correct header |

### Advanced Tests (9-14)

| Test | Name | What It Tests | Verification |
|------|------|---------------|--------------|
| 9 | API Client | HTTP client class, error handling, requests lib | Class exists, handles GET/POST, runs successfully |
| 10 | Expression Parser | Parsing, operator precedence, parentheses | Evaluates 5 test expressions correctly (4+ PASS) |
| 11 | Refactor Class | Split god object into 4 classes | All 4 classes exist, original tests pass |
| 12 | Async Fetcher | asyncio, aiohttp, concurrent requests | Uses async/gather, fetches multiple URLs |
| 13 | SQL Database | SQLite schema, queries, joins, CSV export | Creates DB with tables, exports revenue.csv |
| 14 | CLI Tool | argparse subcommands, file I/O, persistence | Has subparsers, add/list/search work |

### Test Difficulty Progression

- **Tests 1-4**: Basic tool usage - can the model use tools at all?
- **Tests 5-8**: Error recovery and multi-step - can it handle problems?
- **Tests 9-11**: Complex code generation - can it write non-trivial code?
- **Tests 12-14**: Advanced patterns - async, SQL, CLI architecture

## Scoring System

### Pass/Fail
Each test is pass/fail based on verification command:
- **PASS**: Output file exists AND verification succeeds
- **FAIL**: Missing file OR verification failed

### Quality Score (0-100)
Beyond pass/fail, tests compute a weighted quality score:

| Dimension | Weight | Measurement |
|-----------|--------|-------------|
| Correctness | 40% | Tests passed / total tests |
| Efficiency | 20% | Iterations used (fewer is better, baseline: 4/test) |
| Speed | 20% | Time taken (faster is better, baseline: 25s/test) |
| Format | 20% | Output correctness (tied to pass rate) |

Higher scores indicate better overall sub-agent performance.

**Note**: Baselines increased for advanced tests 9-14 which require network calls and complex logic.

## Model Compatibility

| Model | Status | Notes |
|-------|--------|-------|
| qwen3:8b | Excellent | Fast, reliable tool usage |
| rnj-1:8b | Excellent | Very fast, good quality |
| glm-4.7-flash | Good | Slower but capable |
| ministral-3 | Partial | May fail test 3 |
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
  "generated": "2026-01-26T12:00:00+00:00",
  "results": [
    {
      "model": "qwen3:8b",
      "passed": 8,
      "total": 8,
      "quality_score": 85,
      "time_seconds": 120,
      "tests": [...]
    }
  ]
}
```

## Test Requirements

- Ollama running (`ollama serve`)
- Model pulled (`ollama pull <model>`)
- Python 3 available
- Node.js available (for test 6)
- jq (JSON processor)
- Basic Unix tools (grep, awk, cat, timeout)
- SQLite3 (for test 13)
- Internet connection (for tests 9, 12 - HTTP requests)
- `requests` Python package (for test 9)
- `aiohttp` Python package (for test 12, auto-installed)

## What Makes a Good Sub-Agent Model?

1. **Tool compliance** - Actually uses tools instead of outputting text
2. **Speed** - Faster is better for small delegated tasks
3. **Accuracy** - Correct code, proper syntax
4. **Instruction following** - Does what's asked, nothing more
5. **Error recovery** - Graceful handling of failures
6. **Multi-file comprehension** - Understands context across files
7. **Debugging ability** - Can interpret errors and fix issues
8. **Design patterns** - Can structure code into classes (tests 9, 11)
9. **Algorithm knowledge** - Operator precedence, async patterns (tests 10, 12)
10. **Database skills** - SQL joins, aggregation, normalization (test 13)
11. **CLI architecture** - Subcommands, argument parsing (test 14)

## Example Output

```
╔═══════════════════════════════════════════════════════════╗
║         Local Sub-Agent Test Suite                        ║
╠═══════════════════════════════════════════════════════════╣
║  Model: qwen3:8b
║  Time:  2026-01-26 15:45:00
╚═══════════════════════════════════════════════════════════╝

[test] Running: test1_python
[PASS] test1_python (12s, 2 iter)
[test] Running: test2_config
[PASS] test2_config (8s, 1 iter)
...
[test] Running: test13_sql
[PASS] test13_sql (45s, 4 iter)
[test] Running: test14_cli
[PASS] test14_cli (38s, 3 iter)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULTS: 12/14 passed (280s total)
QUALITY SCORE: 72/100
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

### Ollama connection refused
- Run `ollama serve` in another terminal
- Check Ollama is running: `curl http://localhost:11434/api/tags`
