# Script Anatomy: ollama-agent.sh

A line-by-line breakdown of the main wrapper script.

## File Structure Overview

```
ollama-agent.sh (approximately 200 lines)
├── Header & Configuration (lines 1-25)
├── Logging Functions (lines 27-31)
├── Model Feature Detection (lines 33-36)
├── Tool Definitions (lines 38-95)
├── Tool Executor (lines 97-150)
└── Main Function (lines 152-230)
```

## Section 1: Header & Configuration

```bash
#!/bin/bash
# ollama-agent.sh - Simple agentic wrapper for Ollama
# Usage: ./ollama-agent.sh "Your task here" [workdir]
#
# Environment variables:
#   OLLAMA_MODEL    - Model to use (default: qwen3:8b)
#   OLLAMA_TIMEOUT  - Timeout in seconds for API calls (default: 120)
#   OLLAMA_QUIET    - Set to 1 to suppress verbose output
#   OLLAMA_URL      - Ollama API URL (default: http://localhost:11434/api/chat)
```

**Purpose:** Documentation header explaining usage and configuration.

```bash
set -euo pipefail
```

**Purpose:** Strict bash mode:
- `-e`: Exit on any error
- `-u`: Error on undefined variables
- `-o pipefail`: Pipeline fails if any command fails

```bash
MODEL="${OLLAMA_MODEL:-qwen3:8b}"
WORKDIR="${2:-.}"
MAX_ITERATIONS="${OLLAMA_MAX_ITERATIONS:-10}"
TIMEOUT="${OLLAMA_TIMEOUT:-120}"
QUIET="${OLLAMA_QUIET:-0}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/chat}"
```

**Purpose:** Configuration with environment variable overrides:
- `${VAR:-default}` syntax uses default if VAR is unset
- `$2` is the second positional argument (workdir)

```bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color
```

**Purpose:** ANSI color codes for terminal output formatting.

## Section 2: Logging Functions

```bash
log() { [[ "$QUIET" == "1" ]] || echo -e "${BLUE}[agent]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
```

**Purpose:** Consistent, colorized output:
- `log()`: Informational (suppressible with QUIET=1)
- `success()`: Successful operations
- `error()`: Errors (to stderr)
- `warn()`: Warnings

**Usage:**
```bash
log "Processing task..."
success "File created"
error "API timeout"
warn "Unusual response"
```

## Section 3: Model Feature Detection

```bash
# Check if model supports /no_think (qwen3 family)
supports_no_think() {
    [[ "$MODEL" == qwen3* ]]
}
```

**Purpose:** Model-specific feature flags.

Qwen3 models include verbose "thinking" output by default. The `/no_think` prefix suppresses this. Other models don't recognize this directive.

**Pattern for adding more features:**
```bash
supports_streaming() {
    [[ "$MODEL" == some-model* ]]
}
```

## Section 4: Tool Definitions

```bash
TOOLS='[
  {
    "type": "function",
    "function": {
      "name": "write_file",
      "description": "Write content to a file. Creates parent directories if needed.",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "File path (relative to workdir)"},
          "content": {"type": "string", "description": "Content to write"}
        },
        "required": ["path", "content"]
      }
    }
  },
  // ... more tools ...
]'
```

**Purpose:** JSON schema defining available tools for the model.

### Tool: write_file

```json
{
  "name": "write_file",
  "description": "Write content to a file. Creates parent directories if needed.",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {"type": "string", "description": "File path (relative to workdir)"},
      "content": {"type": "string", "description": "Content to write"}
    },
    "required": ["path", "content"]
  }
}
```

Creates or overwrites files. Parent directories are created automatically.

### Tool: read_file

```json
{
  "name": "read_file",
  "description": "Read content from a file",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {"type": "string", "description": "File path to read"}
    },
    "required": ["path"]
  }
}
```

Reads and returns file contents. Returns error message if file doesn't exist.

### Tool: run_command

```json
{
  "name": "run_command",
  "description": "Run a shell command and return output",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {"type": "string", "description": "Shell command to execute"}
    },
    "required": ["command"]
  }
}
```

Executes shell commands with full user permissions. Returns stdout, stderr, and exit code.

### Tool: list_files

```json
{
  "name": "list_files",
  "description": "List files in a directory",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {"type": "string", "description": "Directory path (default: current)"}
    }
  }
}
```

Returns `ls -la` output. Path is optional (defaults to current directory).

### Tool: task_complete

```json
{
  "name": "task_complete",
  "description": "Signal that the task is complete and provide a summary",
  "parameters": {
    "type": "object",
    "properties": {
      "summary": {"type": "string", "description": "Summary of what was accomplished"}
    },
    "required": ["summary"]
  }
}
```

Special tool that terminates the agent loop. Should always be called at task end.

## Section 5: Tool Executor

```bash
execute_tool() {
    local name="$1"
    local args="$2"
    
    case "$name" in
```

**Purpose:** Implements each tool's actual functionality.

### write_file Implementation

```bash
write_file)
    local path=$(echo "$args" | jq -r '.path')
    local full_path="$WORKDIR/$path"
    mkdir -p "$(dirname "$full_path")"
    # Use jq to properly decode content (handles \n, \t, unicode, etc.)
    echo "$args" | jq -r '.content' > "$full_path"
    success "Wrote $(wc -c < "$full_path") bytes to $path"
    echo "File written successfully: $path"
    ;;
```

**Key details:**
- `jq -r '.path'`: Extract path from JSON args
- `$WORKDIR/$path`: Scope to working directory
- `mkdir -p`: Create parent directories
- `jq -r '.content'`: Properly decode content (handles escape sequences)
- Returns success message for model

### read_file Implementation

```bash
read_file)
    local path=$(echo "$args" | jq -r '.path')
    local full_path="$WORKDIR/$path"
    if [[ -f "$full_path" ]]; then
        cat "$full_path"
    else
        error "File not found: $path"
        echo "Error: File not found: $path"
    fi
    ;;
```

**Key details:**
- Checks file existence before reading
- Returns contents directly to model
- Error message helps model understand failures

### run_command Implementation

```bash
run_command)
    local cmd=$(echo "$args" | jq -r '.command')
    log "Running: $cmd"
    cd "$WORKDIR"
    local output exit_code
    output=$(bash -c "$cmd" 2>&1) && exit_code=0 || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        success "Command succeeded"
    else
        warn "Command exited with code $exit_code"
        echo "Exit code: $exit_code"
    fi
    echo "$output"
    ;;
```

**Key details:**
- `cd "$WORKDIR"`: Execute in working directory context
- `bash -c "$cmd"`: Run as bash command (not direct execution)
- `2>&1`: Capture both stdout and stderr
- Exit code capture pattern: `cmd && exit_code=0 || exit_code=$?`
- Always return output (even on failure) for model to process

### list_files Implementation

```bash
list_files)
    local path=$(echo "$args" | jq -r '.path // "."')
    local full_path="$WORKDIR/$path"
    ls -la "$full_path" 2>&1
    ;;
```

**Key details:**
- `.path // "."`: Default to current directory if not specified
- `ls -la`: Detailed listing including hidden files
- `2>&1`: Capture errors (e.g., directory not found)

### task_complete Implementation

```bash
task_complete)
    local summary=$(echo "$args" | jq -r '.summary')
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "TASK COMPLETE"
    echo "$summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
    ;;
```

**Key details:**
- Prints summary with visual formatting
- `exit 0`: Terminates script successfully
- This is the clean exit path for completed tasks

### Unknown Tool Handler

```bash
*)
    error "Unknown tool: $name"
    echo "Error: Unknown tool: $name"
    ;;
```

**Purpose:** Graceful handling of undefined tools. Returns error to model.

## Section 6: Main Function

### Argument Validation

```bash
main() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: $0 \"task description\" [workdir]"
        echo ""
        echo "Environment variables:"
        echo "  OLLAMA_MODEL       Model to use (default: qwen3:8b)"
        # ... more help text ...
        exit 1
    fi
```

**Purpose:** Print usage if no task provided.

### Initialization

```bash
    local task="$1"
    cd "$WORKDIR"
    WORKDIR=$(pwd)  # Convert to absolute path
    
    log "Model: $MODEL"
    log "Workdir: $WORKDIR"
    log "Timeout: ${TIMEOUT}s"
    log "Task: $task"
```

**Purpose:** Set up working environment and log configuration.

### Model-Specific Handling

```bash
    # For qwen3 models, prepend /no_think to suppress verbose thinking
    local effective_task="$task"
    if supports_no_think; then
        effective_task="/no_think $task"
        log "Using /no_think mode for qwen3"
    fi
```

**Purpose:** Apply qwen3-specific optimization.

### Message Initialization

```bash
    # Initialize conversation with effective task
    local messages=$(jq -n --arg content "$effective_task" \
        '[{"role": "user", "content": $content}]')
```

**Purpose:** Create initial message array with user task.

**jq breakdown:**
- `jq -n`: Create new JSON (don't read input)
- `--arg content "$effective_task"`: Bind shell variable to jq variable
- `'[{"role": "user", "content": $content}]'`: JSON template with variable substitution

### Main Loop

```bash
    for ((i=1; i<=MAX_ITERATIONS; i++)); do
        log "Iteration $i/$MAX_ITERATIONS"
```

**Purpose:** Bounded iteration to prevent infinite loops.

### API Call

```bash
        # Call Ollama with timeout
        local response curl_exit
        response=$(timeout "$TIMEOUT" curl -s "$OLLAMA_URL" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg model "$MODEL" \
                --argjson messages "$messages" \
                --argjson tools "$TOOLS" \
                '{model: $model, messages: $messages, tools: $tools, stream: false}')") \
            && curl_exit=0 || curl_exit=$?
```

**Key details:**
- `timeout "$TIMEOUT"`: Kill if exceeds timeout
- `curl -s`: Silent mode (no progress bar)
- `jq -n`: Construct request JSON
- `--argjson`: Pass JSON values (not strings)
- Exit code capture for error handling

### Error Handling

```bash
        # Handle timeout or connection errors
        if [[ $curl_exit -eq 124 ]]; then
            error "API timeout after ${TIMEOUT}s"
            exit 1
        elif [[ $curl_exit -ne 0 ]]; then
            error "API request failed (exit code: $curl_exit)"
            exit 1
        fi
        
        # Validate response is valid JSON
        if ! echo "$response" | jq -e '.message' > /dev/null 2>&1; then
            error "Invalid API response"
            log "Response: $response"
            exit 1
        fi
```

**Purpose:** Fail fast on API problems.

### Response Processing

```bash
        # Extract message
        local assistant_msg=$(echo "$response" | jq '.message')
        local content=$(echo "$assistant_msg" | jq -r '.content // empty')
        local tool_calls=$(echo "$assistant_msg" | jq -r '.tool_calls // empty')
        
        # Print any content
        if [[ -n "$content" && "$content" != "null" ]]; then
            echo -e "${BLUE}[model]${NC} $content"
        fi
```

**Purpose:** Extract and display model response.

### Message History Update

```bash
        # Add assistant message to history
        messages=$(echo "$messages" | jq --argjson msg "$assistant_msg" '. + [$msg]')
```

**Purpose:** Append assistant message to conversation history.

### Tool Call Processing

```bash
        # Process tool calls
        if [[ -n "$tool_calls" && "$tool_calls" != "null" && "$tool_calls" != "[]" ]]; then
            local num_calls=$(echo "$tool_calls" | jq 'length')
            
            for ((j=0; j<num_calls; j++)); do
                local call=$(echo "$tool_calls" | jq ".[$j]")
                local name=$(echo "$call" | jq -r '.function.name')
                local args=$(echo "$call" | jq -r '.function.arguments')
                
                # Handle args as string or object
                if [[ "$args" == "{"* ]]; then
                    : # Already JSON object
                else
                    args=$(echo "$args" | jq -r '.')  # Parse if string
                fi
                
                log "Tool call: $name"
                local result=$(execute_tool "$name" "$args")
                
                # Add tool result to messages
                messages=$(echo "$messages" | jq --arg result "$result" \
                    '. + [{"role": "tool", "content": $result}]')
            done
```

**Key details:**
- Check for presence of tool calls
- Iterate through each tool call
- Handle both object and string argument formats
- Execute tool and capture result
- Append tool result to message history

### Loop Exit Conditions

```bash
        else
            # No tool calls - model is done or stuck
            if [[ -n "$content" ]]; then
                warn "Model responded without tool calls. Task may be complete."
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "Final response:"
                echo "$content"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            fi
            break
        fi
```

**Purpose:** Handle case where model finishes without calling `task_complete`.

### Max Iterations Warning

```bash
    if [[ $i -gt $MAX_ITERATIONS ]]; then
        warn "Reached max iterations ($MAX_ITERATIONS)"
    fi
}

main "$@"
```

**Purpose:** Warn if loop terminated due to iteration limit.

## Summary: Execution Flow

```
1. Script invoked with task and workdir
2. Configuration parsed from env vars
3. Initial message created
4. Loop begins:
   a. Call Ollama API
   b. Check for errors
   c. Extract tool calls
   d. If tool calls:
      - Execute each tool
      - Add results to history
      - Continue loop
   e. If no tool calls:
      - Print final response
      - Exit loop
5. Script exits (0 on success, 1 on error)
```
