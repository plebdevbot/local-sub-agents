# Local Sub-Agents

A lightweight agentic wrapper for local LLMs (Ollama) that enables task delegation from a main AI agent to locally-running models.

## Project Overview

This project provides a shell-based tool-calling agent that wraps Ollama models, enabling them to execute tasks autonomously using file operations and shell commands. The primary use case is delegating small, well-defined tasks from a capable main agent (like Claude) to faster, local models running on consumer hardware.

## Quick Start

```bash
# Run a simple task
./ollama-agent.sh "Create a hello world Python script and run it" /tmp

# Use a different model
OLLAMA_MODEL=rnj-1:8b ./ollama-agent.sh "Create a bash script" /tmp

# Run the test suite
./tests/run-tests.sh qwen3:8b
```

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Agent (Claude)                     │
│  - Identifies delegable tasks                               │
│  - Crafts prompts with tool instructions                    │
│  - Spawns ollama-agent.sh                                   │
│  - Reviews completed work                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  ollama-agent.sh (This Project)             │
│  - Calls Ollama API with tool definitions                   │
│  - Executes tool calls (write_file, run_command, etc.)      │
│  - Maintains conversation context                           │
│  - Returns tool results to model                            │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     Ollama + Local Model                     │
│  - Receives task + tool definitions                         │
│  - Decides which tools to call                              │
│  - Processes tool results                                   │
│  - Signals completion via task_complete                     │
└─────────────────────────────────────────────────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `ollama-agent.sh` | Main wrapper script - the agentic loop |
| `README.md` | User-facing documentation |
| `PLAN.md` | Improvement roadmap (Phase 1-3 complete) |
| `TEST-RESULTS.md` | Model comparison and benchmarks |
| `tests/run-tests.sh` | 8-test automated benchmark suite |
| `tests/compare-results.sh` | Compare results across models |

## Common Development Tasks

### Run a task with specific model
```bash
OLLAMA_MODEL=glm-4.7-flash:latest ./ollama-agent.sh "task description" /workdir
```

### Test a model
```bash
./tests/run-tests.sh qwen3:8b
./tests/run-tests.sh rnj-1:8b
./tests/compare-results.sh  # See comparison table
```

### Debug a failing task
```bash
OLLAMA_QUIET=0 ./ollama-agent.sh "task" /workdir  # Verbose output
# Check output.log in test artifacts: tests/results/MODEL_testN_TIMESTAMP/
```

### Add support for a new model
1. Check if model supports Ollama's native tool calling format
2. Run test suite: `./tests/run-tests.sh new-model:tag`
3. Add results to TEST-RESULTS.md leaderboard

## Code Patterns

### Tool Definition Format (Ollama API)
```json
{
  "type": "function",
  "function": {
    "name": "tool_name",
    "description": "What this tool does",
    "parameters": {
      "type": "object",
      "properties": {
        "param": {"type": "string", "description": "..."}
      },
      "required": ["param"]
    }
  }
}
```

### Tool Execution Pattern
```bash
execute_tool() {
    local name="$1"
    local args="$2"
    
    case "$name" in
        write_file)
            local path=$(echo "$args" | jq -r '.path')
            local content=$(echo "$args" | jq -r '.content')
            echo "$content" > "$WORKDIR/$path"
            echo "File written successfully"
            ;;
        # ... other tools
    esac
}
```

### Main Loop Pattern
```bash
while not_done; do
    response = call_ollama(messages, tools)
    
    if has_tool_calls(response); then
        for each tool_call; do
            result = execute_tool(tool_call)
            messages += tool_result(result)
        done
    else
        break  # Model finished
    fi
done
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_MODEL` | `qwen3:8b` | Model to use for inference |
| `OLLAMA_TIMEOUT` | `120` | API timeout in seconds |
| `OLLAMA_QUIET` | `0` | Suppress verbose output (1=quiet) |
| `OLLAMA_MAX_ITERATIONS` | `10` | Maximum tool call loops |
| `OLLAMA_URL` | `http://localhost:11434/api/chat` | Ollama API endpoint |

## Tool Reference

| Tool | Parameters | Description |
|------|------------|-------------|
| `write_file` | path, content | Write content to file (creates parent dirs) |
| `read_file` | path | Read file contents |
| `run_command` | command | Execute shell command, return output |
| `list_files` | path (optional) | List directory contents |
| `task_complete` | summary | Signal task completion |

## Documentation Structure

```
local-sub-agents/
├── CLAUDE.md              # This file - project overview
├── README.md              # User documentation
├── PLAN.md                # Improvement roadmap
├── TEST-RESULTS.md        # Model benchmarks
├── llm/                   # LLM-focused documentation
│   ├── context/           # Background information
│   │   ├── project-overview.md
│   │   ├── ollama-integration.md
│   │   └── model-compatibility.md
│   ├── implementation/    # Code documentation
│   │   ├── overview.md
│   │   ├── script-anatomy.md
│   │   └── tool-system.md
│   └── workflows/         # Process documentation
│       ├── task-delegation.md
│       └── testing-workflow.md
└── tests/                 # Test suite
    ├── README.md
    ├── run-tests.sh
    ├── compare-results.sh
    └── results/           # Test artifacts (gitignored)
```

## Troubleshooting

### Model not responding / timeout
```bash
# Check Ollama is running
ollama ps
curl http://localhost:11434/api/tags

# If not running:
ollama serve
```

### Tool calls fail (model outputs JSON text instead)
- This is a model compatibility issue
- Some models (llama3.1, mistral) don't use Ollama's native tool_calls format
- Use recommended models: qwen3:8b, rnj-1:8b

### Task gets stuck / infinite loop
- Check OLLAMA_MAX_ITERATIONS (default 10)
- Model may not understand task - try clearer prompts
- Add explicit "When done, call task_complete" instruction

### First run is slow
- Normal - Ollama loads model into GPU memory
- Subsequent runs are faster while model stays loaded
- Run warm-up: `ollama run qwen3:8b "hi" && exit`

## Model Recommendations

| Use Case | Model | Why |
|----------|-------|-----|
| General tasks | `qwen3:8b` | Fast, reliable tool usage |
| Speed priority | `rnj-1:8b` | Very fast, excellent quality |
| Complex reasoning | `glm-4.7-flash` | Slower but more capable |

**Avoid for tool calling:** llama3.1:8b, mistral:7b (format issues)

## Contributing

See `PLAN.md` for the improvement roadmap. Key areas:
- Tool call format compatibility (support more models)
- Additional tests for edge cases
- Quality scoring refinements

## Why This Exists

OpenCode's Ollama integration has a bug where tool calls fail with "Invalid Tool" errors. The model understands tasks and attempts tool calls, but OpenCode's tool execution layer doesn't properly handle Ollama's response format.

This custom `ollama-agent.sh` wrapper calls Ollama's native API directly, which works perfectly.
