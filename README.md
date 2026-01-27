# Local Sub-Agents

**Purpose:** Delegate small tasks to local LLMs running via Ollama + custom agentic wrapper.

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
~/Desktop/local-sub-agents/ollama-agent.sh "Create a hello world script" /tmp

# With different model
OLLAMA_MODEL=glm-4.7-flash:latest ~/Desktop/local-sub-agents/ollama-agent.sh "task" /dir
```

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
| `qwen3:8b` | 5.2 GB | Fast | ✅ Excellent | Recommended default |
| `rnj-1:8b` | ~5 GB | Very fast | ✅ Excellent | Best speed/quality ratio |
| `glm-4.7-flash:latest` | 19 GB | Slower | ✅ Good | Better reasoning |
| `ministral-3:latest` | ~3 GB | Fast | ⚠️ Partial | May fail shell tests |
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

## Flow

### 1. Task Identification
Main agent identifies tasks suitable for delegation:
- **Size:** Small, focused (avoid huge multi-file refactors)
- **Scope:** Well-defined, single objective
- **Examples:** 
  - Write a utility script
  - Create a config file
  - Generate test cases
  - Parse/transform data
  - Simple file operations

### 2. Prompt Crafting
Include in your prompt:
- Clear objective
- Working directory context
- Specific requirements
- Expected output files
- "When done, call task_complete with a summary"

### 3. Execution
```bash
# From main agent (background)
exec pty:true background:true command:"~/Desktop/local-sub-agents/ollama-agent.sh 'Your task. When done, call task_complete.' /workdir"

# Monitor
process action:log sessionId:XXX
```

### 4. Review
- Check created files
- Validate syntax/functionality
- Report to user

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
The model understands tasks and attempts tool calls, but OpenCode's tool execution layer 
doesn't properly handle Ollama's response format.

Our custom `ollama-agent.sh` wrapper calls Ollama's native API directly, which works perfectly.

---

## Files

```
local-sub-agents/
├── ollama-agent.sh      # Main wrapper script
├── README.md            # This documentation
├── PLAN.md              # Improvement roadmap
├── TEST-RESULTS.md      # Test results summary
└── tests/
    ├── run-tests.sh     # Automated test runner (8 tests)
    ├── compare-results.sh # Compare models (supports --json)
    ├── README.md        # Test documentation
    └── results/         # Test output (gitignored)
```

## Comparing Models

```bash
# Run tests against different models
cd tests/
./run-tests.sh qwen3:8b
./run-tests.sh glm-4.7-flash:latest

# Compare results
./compare-results.sh
```
