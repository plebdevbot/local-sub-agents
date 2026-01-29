#!/bin/bash
# check-model.sh - Pre-flight check for model compatibility
# Usage: ./check-model.sh model-name

set -euo pipefail

MODEL="${1:-}"

if [[ -z "$MODEL" ]]; then
    echo "Usage: $0 MODEL_NAME"
    exit 1
fi

echo "Testing model: $MODEL"
echo ""

# Known incompatible models
INCOMPATIBLE=(
    "ServiceNow-AI/Apriel-1.6-15b-Thinker:Q4_K_M"
    "nemotron-3-nano:latest"
)

for incomp in "${INCOMPATIBLE[@]}"; do
    if [[ "$MODEL" == "$incomp" ]]; then
        echo "❌ ERROR: $MODEL is known to be incompatible"
        echo ""
        echo "Reason: This model crashes with runtime errors on this system."
        echo "Common errors:"
        echo "  - GGML_ASSERT(buffer) failed"
        echo "  - cudaMalloc failed: out of memory"
        echo ""
        echo "This is not a model capability issue - the model cannot run at all."
        echo "Please try a different model or check system requirements."
        exit 1
    fi
done

# Check Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "❌ ERROR: Ollama is not running"
    echo "Start it with: ollama serve"
    exit 1
fi

# Check model is available
echo "Checking if model is pulled..."
if ! curl -s http://localhost:11434/api/tags | jq -e ".models[] | select(.name == \"$MODEL\")" > /dev/null 2>&1; then
    echo "⚠️  WARNING: Model not found locally"
    echo "Pull it with: ollama pull $MODEL"
    exit 1
fi

# Test basic tool calling
echo "Testing basic tool call capability..."
TEMP_WORKDIR=$(mktemp -d)
trap "rm -rf $TEMP_WORKDIR" EXIT

TOOLS='[{"type":"function","function":{"name":"test_tool","description":"Test tool","parameters":{"type":"object","properties":{"message":{"type":"string"}},"required":["message"]}}}]'

RESPONSE=$(timeout 30 curl -s http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Call test_tool with message 'hello'\"}],\"tools\":$TOOLS,\"stream\":false}" 2>&1 || true)

# Check for common error patterns
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error')
    
    if [[ "$ERROR" =~ "GGML_ASSERT" ]]; then
        echo "❌ ERROR: Model crashes with GGML assertion failure"
        echo "This model is incompatible with your system configuration."
        exit 1
    elif [[ "$ERROR" =~ "cudaMalloc failed" ]] || [[ "$ERROR" =~ "out of memory" ]]; then
        echo "❌ ERROR: Model requires more GPU memory than available"
        echo "Try a smaller model or increase GPU memory."
        exit 1
    elif [[ "$ERROR" =~ "terminated" ]]; then
        echo "❌ ERROR: Model process terminated unexpectedly"
        echo "This model cannot run on your system."
        exit 1
    else
        echo "❌ ERROR: Unexpected error from model:"
        echo "$ERROR"
        exit 1
    fi
fi

# Check if model supports tool calling
if echo "$RESPONSE" | jq -e '.message.tool_calls' > /dev/null 2>&1; then
    echo "✅ Model supports tool calling"
elif echo "$RESPONSE" | jq -e '.message.content' > /dev/null 2>&1; then
    echo "⚠️  WARNING: Model responded but did not use tools"
    echo "This model may have poor tool-calling performance."
    echo "Benchmark will still run, but expect low scores."
else
    echo "❌ ERROR: Could not parse model response"
    echo "Response: $RESPONSE"
    exit 1
fi

echo ""
echo "✅ Model is compatible and ready for benchmarking"
echo ""
