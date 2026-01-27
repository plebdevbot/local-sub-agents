#!/bin/bash
# ollama-agent.sh - Simple agentic wrapper for Ollama
# Usage: ./ollama-agent.sh "Your task here" [workdir]
#
# Environment variables:
#   OLLAMA_MODEL    - Model to use (default: qwen3:8b)
#   OLLAMA_TIMEOUT  - Timeout in seconds for API calls (default: 120)
#   OLLAMA_QUIET    - Set to 1 to suppress verbose output
#   OLLAMA_URL      - Ollama API URL (default: http://localhost:11434/api/chat)

set -euo pipefail

MODEL="${OLLAMA_MODEL:-qwen3:8b}"
WORKDIR="${2:-.}"
MAX_ITERATIONS="${OLLAMA_MAX_ITERATIONS:-10}"
TIMEOUT="${OLLAMA_TIMEOUT:-120}"
QUIET="${OLLAMA_QUIET:-0}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/chat}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { [[ "$QUIET" == "1" ]] || echo -e "${BLUE}[agent]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Check if model supports /no_think (qwen3 family)
supports_no_think() {
    [[ "$MODEL" == qwen3* ]]
}

# Tool definitions
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
  {
    "type": "function",
    "function": {
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
  },
  {
    "type": "function",
    "function": {
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
  },
  {
    "type": "function", 
    "function": {
      "name": "list_files",
      "description": "List files in a directory",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Directory path (default: current)"}
        }
      }
    }
  },
  {
    "type": "function",
    "function": {
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
  }
]'

# Execute a tool call
execute_tool() {
    local name="$1"
    local args="$2"
    
    case "$name" in
        write_file)
            local path=$(echo "$args" | jq -r '.path')
            local full_path="$WORKDIR/$path"
            mkdir -p "$(dirname "$full_path")"
            # Use jq to properly decode content (handles \n, \t, unicode, etc.)
            echo "$args" | jq -r '.content' > "$full_path"
            success "Wrote $(wc -c < "$full_path") bytes to $path"
            echo "File written successfully: $path"
            ;;
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
        list_files)
            local path=$(echo "$args" | jq -r '.path // "."')
            local full_path="$WORKDIR/$path"
            ls -la "$full_path" 2>&1
            ;;
        task_complete)
            local summary=$(echo "$args" | jq -r '.summary')
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            success "TASK COMPLETE"
            echo "$summary"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 0
            ;;
        *)
            error "Unknown tool: $name"
            echo "Error: Unknown tool: $name"
            ;;
    esac
}

# Main agent loop
main() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: $0 \"task description\" [workdir]"
        echo ""
        echo "Environment variables:"
        echo "  OLLAMA_MODEL       Model to use (default: qwen3:8b)"
        echo "  OLLAMA_TIMEOUT     API timeout in seconds (default: 120)"
        echo "  OLLAMA_QUIET       Set to 1 for less output"
        echo "  OLLAMA_MAX_ITERATIONS  Max tool call loops (default: 10)"
        exit 1
    fi
    
    local task="$1"
    cd "$WORKDIR"
    WORKDIR=$(pwd)
    
    log "Model: $MODEL"
    log "Workdir: $WORKDIR"
    log "Timeout: ${TIMEOUT}s"
    log "Task: $task"
    echo ""
    
    # For qwen3 models, prepend /no_think to suppress verbose thinking
    local effective_task="$task"
    if supports_no_think; then
        effective_task="/no_think $task"
        log "Using /no_think mode for qwen3"
    fi
    
    # Initialize conversation with effective task (includes /no_think for qwen3)
    local messages=$(jq -n --arg content "$effective_task" '[{"role": "user", "content": $content}]')
    
    for ((i=1; i<=MAX_ITERATIONS; i++)); do
        log "Iteration $i/$MAX_ITERATIONS"
        
        # Call Ollama with timeout
        local response curl_exit
        response=$(timeout "$TIMEOUT" curl -s "$OLLAMA_URL" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg model "$MODEL" \
                --argjson messages "$messages" \
                --argjson tools "$TOOLS" \
                '{model: $model, messages: $messages, tools: $tools, stream: false}')") && curl_exit=0 || curl_exit=$?
        
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
        
        # Extract message
        local assistant_msg=$(echo "$response" | jq '.message')
        local content=$(echo "$assistant_msg" | jq -r '.content // empty')
        local tool_calls=$(echo "$assistant_msg" | jq -r '.tool_calls // empty')
        
        # Print any content
        if [[ -n "$content" && "$content" != "null" ]]; then
            echo -e "${BLUE}[model]${NC} $content"
        fi
        
        # Add assistant message to history
        messages=$(echo "$messages" | jq --argjson msg "$assistant_msg" '. + [$msg]')
        
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
                messages=$(echo "$messages" | jq --arg result "$result" '. + [{"role": "tool", "content": $result}]')
            done
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
        
        echo ""
    done
    
    if [[ $i -gt $MAX_ITERATIONS ]]; then
        warn "Reached max iterations ($MAX_ITERATIONS)"
    fi
}

main "$@"
