#!/bin/bash
# agent-wrapper.sh - Generic agentic wrapper supporting multiple runtimes
# Usage: ./agent-wrapper.sh [--runtime RUNTIME] "task description" [workdir]
#
# Runtimes: ollama (default), vllm, llamacpp
#
# Environment variables:
#   MODEL              - Model to use (default: runtime-specific)
#   AGENT_TIMEOUT      - Timeout in seconds for API calls (default: 120)
#   AGENT_QUIET        - Set to 1 to suppress verbose output
#   AGENT_MAX_ITERATIONS - Max tool call loops (default: 10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse arguments
RUNTIME="ollama"
TASK=""
WORKDIR="."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime)
            RUNTIME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--runtime RUNTIME] \"task description\" [workdir]"
            echo ""
            echo "Runtimes:"
            echo "  ollama   - Ollama native API (default)"
            echo "  vllm     - vLLM OpenAI-compatible API"
            echo "  llamacpp - llama.cpp OpenAI-compatible API"
            echo ""
            echo "Environment variables:"
            echo "  MODEL                Model to use"
            echo "  AGENT_TIMEOUT        API timeout (default: 120)"
            echo "  AGENT_QUIET          Set to 1 for less output"
            echo "  AGENT_MAX_ITERATIONS Max tool loops (default: 10)"
            exit 0
            ;;
        *)
            if [[ -z "$TASK" ]]; then
                TASK="$1"
            else
                WORKDIR="$1"
            fi
            shift
            ;;
    esac
done

# Validate runtime
RUNTIME_FILE="$SCRIPT_DIR/runtimes/${RUNTIME}.sh"
if [[ ! -f "$RUNTIME_FILE" ]]; then
    echo "Error: Unknown runtime '$RUNTIME'"
    echo "Available runtimes: ollama, vllm, llamacpp"
    exit 1
fi

# Load shared utilities
source "$SCRIPT_DIR/runtimes/common.sh"

# Load runtime adapter
source "$RUNTIME_FILE"

# Configuration (with backward-compatible env vars)
MODEL="${MODEL:-${OLLAMA_MODEL:-$DEFAULT_MODEL}}"
MAX_ITERATIONS="${AGENT_MAX_ITERATIONS:-${OLLAMA_MAX_ITERATIONS:-10}}"
TIMEOUT="${AGENT_TIMEOUT:-${OLLAMA_TIMEOUT:-120}}"
QUIET="${AGENT_QUIET:-${OLLAMA_QUIET:-0}}"

# Validate task
if [[ -z "$TASK" ]]; then
    echo "Usage: $0 [--runtime RUNTIME] \"task description\" [workdir]"
    echo ""
    echo "Environment variables:"
    echo "  MODEL                Model to use (default: $DEFAULT_MODEL)"
    echo "  AGENT_TIMEOUT        API timeout (default: 120)"
    echo "  AGENT_QUIET          Set to 1 for less output"
    echo "  AGENT_MAX_ITERATIONS Max tool loops (default: 10)"
    exit 1
fi

# Setup workdir
cd "$WORKDIR"
WORKDIR=$(pwd)

# Check runtime is available
if ! check_runtime; then
    exit 1
fi

log "Runtime: $RUNTIME_NAME"
log "Model: $MODEL"
log "Workdir: $WORKDIR"
log "Timeout: ${TIMEOUT}s"
log "Task: $TASK"
echo ""

# Preprocess task (runtime-specific, e.g., /no_think for qwen3)
effective_task=$(preprocess_task "$TASK")

# Initialize conversation
messages=$(jq -n --arg content "$effective_task" '[{"role": "user", "content": $content}]')

# Main agentic loop
for ((i=1; i<=MAX_ITERATIONS; i++)); do
    log "Iteration $i/$MAX_ITERATIONS"

    # Call runtime API
    response=$(call_api "$messages" "$TOOLS") && curl_exit=0 || curl_exit=$?

    # Handle timeout or connection errors
    if [[ $curl_exit -eq 124 ]]; then
        error "API timeout after ${TIMEOUT}s"
        exit 1
    elif [[ $curl_exit -ne 0 ]]; then
        error "API request failed (exit code: $curl_exit)"
        exit 1
    fi

    # Parse response using runtime adapter
    parsed=$(parse_response "$response")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    content=$(echo "$parsed" | jq -r '.content // empty')
    tool_calls=$(echo "$parsed" | jq -r '.tool_calls // empty')
    raw_message=$(echo "$parsed" | jq '.raw_message')

    # Print any content
    if [[ -n "$content" && "$content" != "null" ]]; then
        echo -e "${BLUE}[model]${NC} $content"
    fi

    # Add assistant message to history
    messages=$(echo "$messages" | jq --argjson msg "$raw_message" '. + [$msg]')

    # Process tool calls
    if [[ -n "$tool_calls" && "$tool_calls" != "null" && "$tool_calls" != "[]" ]]; then
        num_calls=$(echo "$tool_calls" | jq 'length')

        for ((j=0; j<num_calls; j++)); do
            call=$(echo "$tool_calls" | jq ".[$j]")
            name=$(echo "$call" | jq -r '.function.name')
            args=$(echo "$call" | jq -r '.function.arguments')
            tool_call_id=$(echo "$call" | jq -r '.id // "call_'$j'"')

            # Handle args as string or object
            if [[ "$args" != "{"* ]]; then
                args=$(echo "$args" | jq -r '.' 2>/dev/null || echo "$args")
            fi

            log "Tool call: $name"
            result=$(execute_tool "$name" "$args")

            # Add tool result to messages using runtime-specific format
            tool_msg=$(build_tool_result "$result" "$tool_call_id")
            messages=$(echo "$messages" | jq --argjson msg "$tool_msg" '. + [$msg]')
        done
    else
        # No tool calls - model is done or stuck
        if [[ -n "$content" ]]; then
            warn "Model responded without tool calls. Task may be complete."
            echo ""
            echo "========================================"
            echo "Final response:"
            echo "$content"
            echo "========================================"
        fi
        break
    fi

    echo ""
done

if [[ $i -gt $MAX_ITERATIONS ]]; then
    warn "Reached max iterations ($MAX_ITERATIONS)"
fi
