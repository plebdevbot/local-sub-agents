#!/bin/bash
# ollama.sh - Ollama runtime adapter
# Uses Ollama's native API format (not OpenAI-compatible)

RUNTIME_NAME="ollama"
RUNTIME_URL="${OLLAMA_URL:-http://localhost:11434/api/chat}"
DEFAULT_MODEL="qwen3:8b"

# Check if model supports /no_think (qwen3 family)
supports_no_think() {
    [[ "$MODEL" == qwen3* ]]
}

# Preprocess task for model-specific features
preprocess_task() {
    local task="$1"
    if supports_no_think; then
        log "Using /no_think mode for qwen3"
        echo "/no_think $task"
    else
        echo "$task"
    fi
}

# Check runtime availability
check_runtime() {
    if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        error "Ollama is not running. Start it with: ollama serve"
        return 1
    fi
    return 0
}

# Make API call - Ollama native format
call_api() {
    local messages="$1"
    local tools="$2"

    timeout "$TIMEOUT" curl -s "$RUNTIME_URL" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --argjson messages "$messages" \
            --argjson tools "$tools" \
            '{model: $model, messages: $messages, tools: $tools, stream: false}')"
}

# Parse response - Ollama returns {message: {content, tool_calls}}
parse_response() {
    local response="$1"

    # Validate response
    if ! echo "$response" | jq -e '.message' > /dev/null 2>&1; then
        error "Invalid API response"
        log "Response: $response"
        return 1
    fi

    # Extract and normalize to common format
    echo "$response" | jq '{
        content: .message.content,
        tool_calls: .message.tool_calls,
        raw_message: .message
    }'
}

# Build tool result message for Ollama format
build_tool_result() {
    local result="$1"
    jq -n --arg result "$result" '{"role": "tool", "content": $result}'
}
