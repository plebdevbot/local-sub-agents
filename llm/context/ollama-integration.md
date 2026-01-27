# Ollama Integration

## What is Ollama?

Ollama is a tool for running large language models locally. It provides:

- Easy model management (pull, run, delete)
- OpenAI-compatible API endpoints
- Native tool calling support (for supported models)
- GPU acceleration (CUDA, Metal, ROCm)

## API Overview

Ollama exposes a REST API at `http://localhost:11434`:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/tags` | GET | List available models |
| `/api/pull` | POST | Download a model |
| `/api/chat` | POST | Chat completion (what we use) |
| `/api/generate` | POST | Text completion |

## Chat API Details

`POST /api/chat` is the primary endpoint for tool-calling agents.

### Request Format

```json
{
  "model": "qwen3:8b",
  "messages": [
    {"role": "user", "content": "Create a file..."}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "write_file",
        "description": "Write content to a file",
        "parameters": {
          "type": "object",
          "properties": {
            "path": {"type": "string", "description": "File path"},
            "content": {"type": "string", "description": "Content to write"}
          },
          "required": ["path", "content"]
        }
      }
    }
  ],
  "stream": false
}
```

### Response Format (with tool calls)

```json
{
  "model": "qwen3:8b",
  "message": {
    "role": "assistant",
    "content": "",
    "tool_calls": [
      {
        "function": {
          "name": "write_file",
          "arguments": {
            "path": "hello.py",
            "content": "print('Hello, World!')"
          }
        }
      }
    ]
  },
  "done": true
}
```

### Response Format (text only)

```json
{
  "model": "qwen3:8b",
  "message": {
    "role": "assistant",
    "content": "I've created the file successfully."
  },
  "done": true
}
```

## Tool Call Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Message History                           │
│                                                                  │
│  1. user: "Create hello.py that prints hello world"            │
│                              ▼                                   │
│  2. assistant: (tool_calls: [{write_file, {path, content}}])    │
│                              ▼                                   │
│  3. tool: "File written successfully: hello.py"                 │
│                              ▼                                   │
│  4. assistant: (tool_calls: [{run_command, {command}}])         │
│                              ▼                                   │
│  5. tool: "Hello, World!"                                       │
│                              ▼                                   │
│  6. assistant: (tool_calls: [{task_complete, {summary}}])       │
│                              ▼                                   │
│  [DONE - agent exits]                                           │
└─────────────────────────────────────────────────────────────────┘
```

## Tool Definition Schema

Tools are defined using JSON Schema format:

```json
{
  "type": "function",
  "function": {
    "name": "tool_name",           // Must match execute_tool case
    "description": "...",          // Helps model understand when to use
    "parameters": {
      "type": "object",
      "properties": {
        "param1": {
          "type": "string",        // string, number, boolean, array, object
          "description": "..."
        },
        "param2": {
          "type": "number",
          "description": "..."
        }
      },
      "required": ["param1"]       // Optional: list required params
    }
  }
}
```

### Parameter Types

| Type | JSON Schema | Example |
|------|-------------|---------|
| String | `"type": "string"` | File paths, content |
| Number | `"type": "number"` | Counts, IDs |
| Boolean | `"type": "boolean"` | Flags |
| Array | `"type": "array", "items": {...}` | Lists |
| Object | `"type": "object", "properties": {...}` | Nested data |

## Arguments Format

Tool call arguments can come in two formats:

### Object format (preferred)
```json
{
  "function": {
    "name": "write_file",
    "arguments": {
      "path": "hello.py",
      "content": "print('hello')"
    }
  }
}
```

### String format (some models)
```json
{
  "function": {
    "name": "write_file",
    "arguments": "{\"path\": \"hello.py\", \"content\": \"print('hello')\"}"
  }
}
```

The wrapper handles both:

```bash
# Handle args as string or object
if [[ "$args" == "{"* ]]; then
    : # Already JSON object
else
    args=$(echo "$args" | jq -r '.')  # Parse if string
fi
```

## Streaming vs Non-Streaming

### Non-streaming (what we use)

```json
{
  "stream": false
}
```

Returns complete response once finished. Simpler to parse, easier to handle tool calls.

### Streaming

```json
{
  "stream": true
}
```

Returns chunks as they're generated. Better UX for long responses, but tool calls may be split across chunks.

**We use non-streaming** because:
1. Tool calls need complete JSON to parse
2. Sub-agent tasks are typically fast
3. Simpler error handling

## Model Loading Behavior

### Cold Start
First request to a model loads it into GPU memory:
- Takes 10-30 seconds depending on model size
- Uses significant VRAM
- Model stays loaded until unloaded or server restart

### Hot Inference
Subsequent requests are fast:
- 1-5 seconds for small models
- No loading overhead
- Memory remains allocated

### Warm-up Strategy
The test suite warms up models before benchmarking:

```bash
# Warm up to exclude load time from benchmarks
curl -s http://localhost:11434/api/chat \
  -d '{"model":"qwen3:8b","messages":[{"role":"user","content":"hi"}],"stream":false}'
```

## Error Handling

### Connection Errors

```bash
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Error: Ollama is not running. Start it with: ollama serve"
    exit 1
fi
```

### Model Not Found

```bash
if ! curl -s http://localhost:11434/api/chat -d '...' > /dev/null 2>&1; then
    echo "Error: Model not available. Try: ollama pull $MODEL"
    exit 1
fi
```

### Timeout

```bash
response=$(timeout "$TIMEOUT" curl -s ...) || {
    echo "API timeout after ${TIMEOUT}s"
    exit 1
}
```

### Invalid Response

```bash
if ! echo "$response" | jq -e '.message' > /dev/null 2>&1; then
    echo "Invalid API response"
    exit 1
fi
```

## Qwen3 Special Handling

Qwen3 models include verbose "thinking" output by default. The wrapper suppresses this:

```bash
supports_no_think() {
    [[ "$MODEL" == qwen3* ]]
}

# In main():
if supports_no_think; then
    effective_task="/no_think $task"
fi
```

This prepends `/no_think` to the user message, which Qwen3 interprets as a directive to skip verbose reasoning.

## API Rate Limits

Ollama has no rate limiting by default (it's local). However, **only one inference can run at a time**. The API queues requests but:

- Memory usage increases
- Quality may degrade under load
- Best practice: sequential task execution

## Environment Configuration

```bash
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/chat}"
```

Useful for:
- Remote Ollama servers
- Custom ports
- Docker deployments

## Debugging API Calls

### See raw request/response

```bash
# Add to ollama-agent.sh temporarily:
echo "REQUEST: $(jq -c ...)"
echo "RESPONSE: $response"
```

### Use curl directly

```bash
curl -v http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3:8b",
    "messages": [{"role": "user", "content": "hi"}],
    "stream": false
  }'
```

### Check model status

```bash
ollama ps         # Currently loaded models
ollama list       # All available models
ollama show qwen3:8b  # Model details
```

## Version Compatibility

This project tested with:
- Ollama 0.1.x - 0.5.x
- Tool calling added in Ollama 0.3.0
- API is stable across minor versions

Check Ollama version:
```bash
ollama --version
```
