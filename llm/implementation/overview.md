# Implementation Overview

## Architecture Summary

Local Sub-Agents is a single-file shell script (`ollama-agent.sh`) that implements an agentic loop for local LLMs. The architecture is intentionally minimal:

```
┌─────────────────────────────────────────────────────────────────┐
│                       ollama-agent.sh                            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Configuration Layer                    │  │
│  │  - Environment variable parsing                          │  │
│  │  - Model selection                                       │  │
│  │  - Timeout/iteration limits                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Tool Definitions                       │  │
│  │  - JSON schema for each tool                             │  │
│  │  - Passed to Ollama API                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Tool Execution                         │  │
│  │  - execute_tool() function                               │  │
│  │  - Handles write_file, read_file, run_command, etc.     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                      Main Loop                            │  │
│  │  - Initialize messages with user task                    │  │
│  │  - Call Ollama API                                       │  │
│  │  - Process tool calls                                    │  │
│  │  - Append results to message history                     │  │
│  │  - Loop until done or max iterations                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Request Flow

```
1. User invokes script:
   ./ollama-agent.sh "Create a Python script" /tmp/workdir

2. Script parses arguments:
   - task = "Create a Python script"
   - workdir = /tmp/workdir

3. Script builds initial message:
   messages = [{"role": "user", "content": task}]

4. Script calls Ollama API:
   POST /api/chat
   {
     "model": "qwen3:8b",
     "messages": messages,
     "tools": TOOLS,
     "stream": false
   }

5. Script receives response:
   {
     "message": {
       "role": "assistant",
       "tool_calls": [...]
     }
   }

6. Script executes tool calls:
   for call in tool_calls:
       result = execute_tool(call.name, call.arguments)
       messages.append({"role": "tool", "content": result})

7. Repeat from step 4 until:
   - task_complete is called, OR
   - No tool calls (model finished), OR
   - Max iterations reached
```

### Message History Growth

```
Iteration 1:
  messages = [
    {"role": "user", "content": "Create hello.py..."}
  ]
  
  → API Response: tool_calls: [{write_file, ...}]
  
  messages = [
    {"role": "user", "content": "Create hello.py..."},
    {"role": "assistant", "tool_calls": [...]},
    {"role": "tool", "content": "File written successfully"}
  ]

Iteration 2:
  → API Response: tool_calls: [{run_command, ...}]
  
  messages = [
    {"role": "user", "content": "Create hello.py..."},
    {"role": "assistant", "tool_calls": [...]},
    {"role": "tool", "content": "File written successfully"},
    {"role": "assistant", "tool_calls": [...]},
    {"role": "tool", "content": "Hello, World!"}
  ]

Iteration 3:
  → API Response: tool_calls: [{task_complete, ...}]
  
  [Script exits with success]
```

## Key Components

### 1. Configuration

```bash
MODEL="${OLLAMA_MODEL:-qwen3:8b}"
WORKDIR="${2:-.}"
MAX_ITERATIONS="${OLLAMA_MAX_ITERATIONS:-10}"
TIMEOUT="${OLLAMA_TIMEOUT:-120}"
QUIET="${OLLAMA_QUIET:-0}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/chat}"
```

All configuration via environment variables with sensible defaults.

### 2. Tool Definitions (TOOLS variable)

JSON array of tool schemas passed to Ollama:
- `write_file` - Create/overwrite files
- `read_file` - Read file contents
- `run_command` - Execute shell commands
- `list_files` - Directory listing
- `task_complete` - Signal completion

### 3. Tool Executor (execute_tool function)

Switch/case that implements each tool:
- Parses arguments from JSON
- Performs file/command operations
- Returns result string

### 4. Main Loop (main function)

- Argument validation
- Message history initialization
- API call loop with timeout
- Response parsing
- Tool call processing

## External Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| `bash` | Script interpreter | Yes |
| `curl` | HTTP requests to Ollama | Yes |
| `jq` | JSON parsing | Yes |
| `timeout` | API call timeout | Yes (coreutils) |

### Dependency Check

```bash
check_deps() {
    for cmd in curl jq; do
        command -v "$cmd" >/dev/null || {
            echo "Missing: $cmd"
            exit 1
        }
    done
}
```

## Error Handling Strategy

### API Errors

```bash
# Timeout handling
response=$(timeout "$TIMEOUT" curl -s ...) && curl_exit=0 || curl_exit=$?

if [[ $curl_exit -eq 124 ]]; then
    error "API timeout after ${TIMEOUT}s"
    exit 1
fi
```

### Invalid JSON

```bash
# Validate response structure
if ! echo "$response" | jq -e '.message' > /dev/null 2>&1; then
    error "Invalid API response"
    exit 1
fi
```

### Tool Execution Errors

```bash
# Command execution with exit code capture
output=$(bash -c "$cmd" 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    warn "Command exited with code $exit_code"
fi
echo "$output"  # Always return output to model
```

## Security Model

### Sandboxing: None

The script runs tools with the invoking user's permissions. This is intentional:
- Sub-agents need file system access to be useful
- Caller (main agent) is responsible for appropriate task delegation
- Workdir parameter provides implicit scope limitation

### Risks

| Risk | Mitigation |
|------|------------|
| Arbitrary code execution | Trust the model selection; avoid untrusted prompts |
| File system damage | Use workdir to scope operations |
| Resource exhaustion | MAX_ITERATIONS and TIMEOUT limits |
| Sensitive data exposure | Don't delegate tasks involving secrets |

### Recommendations

1. **Run in containers/VMs** for untrusted tasks
2. **Use dedicated work directories** to limit blast radius
3. **Review generated files** before using in production
4. **Don't expose to untrusted input** (prompts)

## File Operations

### Working Directory

All file operations are relative to WORKDIR:

```bash
local full_path="$WORKDIR/$path"
mkdir -p "$(dirname "$full_path")"
```

This prevents:
- Accidental writes outside project
- Path traversal issues (though not security-hardened)

### Content Handling

Files are written using jq to properly decode content:

```bash
# Handles \n, \t, unicode, etc. correctly
echo "$args" | jq -r '.content' > "$full_path"
```

This ensures code with special characters renders correctly.

## Performance Characteristics

### Latency Breakdown

| Phase | Typical Time | Notes |
|-------|--------------|-------|
| Model cold start | 10-30s | First request only |
| API request | 1-5s | Per iteration |
| Tool execution | <1s | File ops are fast |
| Network overhead | <100ms | Local connection |

### Optimization Opportunities

1. **Warm-up before benchmarking** - Ensure fair comparison
2. **Reduce iterations** - Better prompts = fewer round trips
3. **Model selection** - Smaller models are faster

## Extending the System

### Adding a New Tool

1. Add to TOOLS JSON array:
```json
{
  "type": "function",
  "function": {
    "name": "new_tool",
    "description": "What it does",
    "parameters": {...}
  }
}
```

2. Add case to execute_tool:
```bash
new_tool)
    local arg=$(echo "$args" | jq -r '.arg')
    # Implementation
    echo "Result"
    ;;
```

### Adding Model-Specific Handling

```bash
supports_feature() {
    case "$MODEL" in
        qwen3*) return 0 ;;  # Supports feature
        *) return 1 ;;
    esac
}

# Usage
if supports_feature; then
    # Apply model-specific handling
fi
```

## Testing Integration

The test suite (`tests/run-tests.sh`) validates:

1. **Tool execution** - Tools actually work
2. **Output verification** - Results are correct
3. **Iteration tracking** - Performance metrics
4. **Quality scoring** - Beyond pass/fail

See `llm/workflows/testing-workflow.md` for details.

## Comparison to Similar Projects

| Feature | This Project | LangChain | AutoGPT |
|---------|--------------|-----------|---------|
| Complexity | ~200 LOC | 100k+ LOC | 10k+ LOC |
| Dependencies | 2 (curl, jq) | Many | Many |
| Setup time | 0 | Significant | Significant |
| Customization | Edit script | Plugins | Plugins |
| Use case | Task execution | General agents | Autonomous agents |

The simplicity is a feature: easy to understand, modify, and debug.
