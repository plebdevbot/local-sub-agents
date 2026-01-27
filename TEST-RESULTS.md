# Local Sub-Agent Test Results

**Last Updated:** 2026-01-26  
**Test Suite Version:** 2.0 (8 tests)  
**Wrapper:** ollama-agent.sh  

---

## Test Suite Overview

| Test | Name | Purpose | Verification |
|------|------|---------|--------------|
| 1 | Python Script | Code generation, secrets module | Runs, outputs 3+ passwords |
| 2 | Config File | YAML/Docker Compose generation | Contains nginx, postgres, redis, app-net |
| 3 | Shell Script | Bash scripting, chmod, execution | Executable, outputs system info |
| 4 | Data Transform | Read → process → write chain | All names + average calculation |
| 5 | Error Handling | Graceful failure, recovery | Error log references missing file |
| 6 | Multi-File | Cross-file bug fixing | Fix 'YYYY' bug, correct year output |
| 7 | Debugging | Run → read error → fix → verify | Fix undefined variable error |
| 8 | Format Compliance | Exact output format | CSV has 4 lines, correct header |

---

## Model Leaderboard

| Model | Pass Rate | Quality Score | Avg Time | Notes |
|-------|-----------|---------------|----------|-------|
| qwen3:8b | 8/8 | 85+ | ~15s/test | Fast, reliable tool usage |
| rnj-1:8b | 8/8 | 90+ | ~10s/test | Very fast, excellent quality |
| glm-4.7-flash | 7-8/8 | 75+ | ~30s/test | Slower but capable |
| ministral-3 | 5-7/8 | 60+ | ~20s/test | May fail test 3 (shell) |
| llama3.1:8b | 3-5/8 | 40-50 | ~25s/test | Tool format issues |
| mistral:7b | 2-4/8 | 30-40 | ~20s/test | Tool format issues |

*Run `./tests/compare-results.sh` for detailed current results*

---

## Key Findings

### What Works Well

1. **Explicit tool instructions**: "You MUST use tools" dramatically improves compliance
2. **Step-by-step prompts**: Breaking tasks into numbered steps helps models follow
3. **task_complete signal**: Models reliably call this when instructed

### Common Failure Modes

1. **Tool format mismatch**: Some models (llama, mistral) output tool calls as JSON text instead of using Ollama's native tool_calls format
2. **Thinking overhead**: qwen3 models include verbose thinking by default (mitigated with /no_think)
3. **Multi-file confusion**: Weaker models struggle with test 6 (cross-file comprehension)

### Prompt Engineering Tips

```
You MUST use tools. Do NOT output code as text.

1. Use [tool] to [action]
2. Use [tool] to [action]
3. Use run_command to verify: [command]

Call task_complete with your summary when done.
```

---

## Running Tests

```bash
# Run full suite
./tests/run-tests.sh qwen3:8b

# Compare models
./tests/run-tests.sh glm-4.7-flash:latest
./tests/compare-results.sh

# JSON export for automation
./tests/compare-results.sh --json > results.json
```

---

## Quality Score Breakdown

The test suite computes a weighted quality score (0-100):

| Dimension | Weight | Measurement |
|-----------|--------|-------------|
| Correctness | 40% | Tests passed / total |
| Efficiency | 20% | Iterations (fewer = better, baseline: 3/test) |
| Speed | 20% | Time (faster = better, baseline: 15s/test) |
| Format | 20% | Output correctness |

Models scoring 80+ are recommended for production sub-agent use.

---

## Changelog

### v2.0 (2026-01-26)
- Added tests 6-8 (multi-file, debugging, format compliance)
- Added quality scoring system
- Added JSON export for results
- Added /no_think support for qwen3 models
- Improved error handling in ollama-agent.sh

### v1.0 (2026-01-25)
- Initial release with tests 1-5
- Basic pass/fail verification
