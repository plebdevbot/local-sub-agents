#!/bin/bash
# vllm.sh - vLLM runtime adapter
# Uses OpenAI-compatible API format

RUNTIME_NAME="vllm"
RUNTIME_URL="${VLLM_URL:-http://localhost:8000/v1/chat/completions}"
DEFAULT_MODEL="meta-llama/Llama-3.1-8B-Instruct"

# No special preprocessing for vLLM
preprocess_task() {
    echo "$1"
}

# Check runtime availability
check_runtime() {
    if ! curl -s http://localhost:8000/v1/models > /dev/null 2>&1; then
        error "vLLM is not running. Start it with:"
        error "  vllm serve $DEFAULT_MODEL --port 8000"
        return 1
    fi
    return 0
}

# Make API call - OpenAI format
call_api() {
    local messages="$1"
    local tools="$2"

    timeout "$TIMEOUT" curl -s "$RUNTIME_URL" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --argjson messages "$messages" \
            --argjson tools "$tools" \
            '{
                model: $model,
                messages: $messages,
                tools: $tools,
                temperature: 0.7,
                max_tokens: 4096
            }')"
}

# Parse response - OpenAI format: {choices: [{message: {content, tool_calls}}]}
parse_response() {
    local response="$1"

    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        error "API error: $(echo "$response" | jq -r '.error.message // .error')"
        return 1
    fi

    # Validate response
    if ! echo "$response" | jq -e '.choices[0].message' > /dev/null 2>&1; then
        error "Invalid API response"
        log "Response: $response"
        return 1
    fi

    # Extract and normalize to common format
    echo "$response" | jq '{
        content: .choices[0].message.content,
        tool_calls: .choices[0].message.tool_calls,
        raw_message: .choices[0].message
    }'
}

# Build tool result message for OpenAI format
build_tool_result() {
    local result="$1"
    local tool_call_id="${2:-call_1}"
    jq -n --arg result "$result" --arg id "$tool_call_id" \
        '{"role": "tool", "content": $result, "tool_call_id": $id}'
}
