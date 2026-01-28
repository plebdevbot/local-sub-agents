# Local Sub-Agents

**Purpose:** Delegate small tasks to local LLMs running via Ollama + custom agentic wrapper.

## Latest Benchmark (2026-01-27)

| Model | Tests Passed | Score | Status |
|-------|--------------|-------|--------|
| **qwen3:8b** | **10/14** | **73/100** | 🥇 Best |
| gpt-oss:20b | 7/8* | 70/100 | Good |
| devstral-small-2 | 8/8* | 69/100 | Good |
| ministral-3 | 6/8* | 79/100 | Decent |

*Earlier benchmark with 8 tests. Full 14-test suite pending.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Agent (Claude)                     │
│                                                             │
│  1. Receives task from user                                 │
│  2. Decides if delegable (small, well-defined)              │
│  3. Crafts detailed prompt for sub-agent                    │
│  4. Spawns: ollama-agent.sh "prompt" /workdir               │
│  5. Monitors completion                                     │
│  6. Reviews work                                            │
│  7. Reports back to user                                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Local Sub-Agent                          │
│                                                             │
│  Provider: Ollama (qwen3:8b)                                │
│  Harness:  ollama-agent.sh (custom wrapper)                 │
│                                                             │
│  Tools available:                                           │
│  - write_file: Create/overwrite files                       │
│  - read_file: Read file contents                            │
│  - run_command: Execute shell commands                      │
│  - list_files: List directory contents                      │
│  - task_complete: Signal completion with summary            │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

```bash
# Run a task
./ollama-agent.sh "Create a hello world script" /tmp

# With different model
OLLAMA_MODEL=glm-4.7-flash:latest ./ollama-agent.sh "task" /dir

# Run benchmark suite
cd tests && ./run-tests.sh qwen3:8b

# Compare models
cd tests && ./compare-results.sh
```

---

## Test Suite

**14 tests** covering basic to advanced coding tasks:

| Tests | Focus | Examples |
|-------|-------|----------|
| 1-8 | Basics | Python scripts, configs, shell, debugging |
| 9-14 | Advanced | API clients, parsers, async, SQL, CLI tools |

**Scoring weights** (accuracy > speed):
- Correctness: 50%
- Efficiency: 20%  
- Speed: 10%
- Format: 20%

See [tests/README.md](tests/README.md) for details.

---

## Hardware Constraints

**⚠️ Critical:** Local models share limited GPU/CPU resources.

- **One inference at a time** — never parallel
- Queue tasks sequentially
- Wait for completion before starting next
- Parallel runs cause: memory thrashing, OOM kills, degraded output quality

---

## Available Models

| Model | Size | Speed | Tool Support | Notes |
|-------|------|-------|--------------|-------|
| `qwen3:8b` | 5.2 GB | Fast | ✅ Excellent | **Recommended default** |
| `rnj-1:8b` | ~5 GB | Very fast | ✅ Excellent | Best speed/quality ratio |
| `devstral-small-2` | ~8 GB | Medium | ✅ Good | Passes all basic tests |
| `gpt-oss:20b` | ~13 GB | Slower | ✅ Good | Larger, more capable |
| `glm-4.7-flash` | 19 GB | Slower | ✅ Good | Better reasoning |
| `ministral-3` | ~3 GB | Fast | ⚠️ Partial | May fail complex tests |
| `llama3.1:8b` | ~5 GB | Medium | ❌ Limited | Tool format issues |
| `mistral:7b` | ~4 GB | Medium | ❌ Limited | Tool format issues |

Default: `qwen3:8b` (set via `OLLAMA_MODEL` env var)

### Environment Variables

```bash
OLLAMA_MODEL=qwen3:8b          # Model to use
OLLAMA_TIMEOUT=120             # API timeout in seconds
OLLAMA_QUIET=1                 # Suppress verbose output
OLLAMA_MAX_ITERATIONS=10       # Max tool call loops
```

---

## Task Delegation Criteria

### ✅ Good for Local Sub-Agent
- Single-file scripts
- Config file generation
- Simple utilities
- Data transformation
- Documentation snippets
- Test file creation

### ❌ Keep on Main Agent
- Multi-file architectural changes
- Security-sensitive operations
- Tasks requiring user interaction
- Complex debugging
- Anything needing clarification mid-task

---

## Tool Reference

| Tool | Parameters | Description |
|------|------------|-------------|
| `write_file` | path, content | Write content to file (creates dirs) |
| `read_file` | path | Read file contents |
| `run_command` | command | Execute shell command |
| `list_files` | path (optional) | List directory contents |
| `task_complete` | summary | Signal done, provide summary |

---

## Example Prompts

**Simple script:**
```
Create a bash script called cleanup.sh that removes all .tmp files 
from the current directory. Include a dry-run flag (-n). 
Make it executable. When done, call task_complete with a summary.
```

**Config generation:**
```
Create a nginx.conf for a reverse proxy that:
- Listens on port 80
- Proxies /api to localhost:3000
- Serves static files from /var/www/html
When done, call task_complete with a summary.
```

---

## Files

```
local-sub-agents/
├── ollama-agent.sh          # Main wrapper script
├── README.md                # This documentation
└── tests/
    ├── run-tests.sh         # Test runner (14 tests)
    ├── benchmark-all-models.sh  # Full model comparison
    ├── compare-results.sh   # Compare results (--json)
    ├── README.md            # Test documentation
    └── results/             # Test output (gitignored)
```

---

## Troubleshooting

**Model outputs garbage:**
- Check if another inference is running (`ollama ps`)
- Wait for it to finish, try again

**Tool calls fail:**
- Ensure Ollama is running (`ollama serve`)
- Check model supports tools (`qwen3:8b` does)

**Slow responses:**
- Normal for first run (model loading)
- Subsequent runs faster while model is hot

---

## Why Not OpenCode?

OpenCode's Ollama integration has a bug where tool calls fail with "Invalid Tool" errors. 
Our custom `ollama-agent.sh` wrapper calls Ollama's native API directly, which works perfectly.
