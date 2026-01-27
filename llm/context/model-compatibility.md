# Model Compatibility

## Overview

Not all local models support tool calling equally. This document explains which models work, why some fail, and how to evaluate new models.

## The Tool Calling Spectrum

```
┌─────────────────────────────────────────────────────────────────┐
│                    Tool Calling Support                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Native Format              Mixed              Text-Only         │
│  ──────────────            ─────              ─────────          │
│  ✅ qwen3:8b               ⚠️ ministral        ❌ llama3.1       │
│  ✅ rnj-1:8b                                   ❌ mistral:7b     │
│  ✅ glm-4.7-flash                                                │
│                                                                  │
│  Uses tool_calls array     Inconsistent       Outputs JSON       │
│  in API response           behavior           as text            │
└─────────────────────────────────────────────────────────────────┘
```

## Tested Models

### Tier 1: Excellent (Recommended)

| Model | Size | Speed | Pass Rate | Notes |
|-------|------|-------|-----------|-------|
| `qwen3:8b` | 5.2 GB | ~15s/test | 8/8 | Reliable, good quality |
| `rnj-1:8b` | ~5 GB | ~10s/test | 8/8 | Fastest, best value |

These models:
- Use Ollama's native `tool_calls` array format
- Consistently follow tool instructions
- Handle multi-step tasks well
- Call `task_complete` when instructed

### Tier 2: Good (Capable but Slower)

| Model | Size | Speed | Pass Rate | Notes |
|-------|------|-------|-----------|-------|
| `glm-4.7-flash` | 19 GB | ~30s/test | 7-8/8 | Better reasoning, heavier |

These models:
- Support tool calling correctly
- Better at complex reasoning tasks
- Slower due to model size
- Good for tasks requiring more intelligence

### Tier 3: Partial (May Work)

| Model | Size | Speed | Pass Rate | Notes |
|-------|------|-------|-----------|-------|
| `ministral-3` | ~3 GB | ~20s/test | 5-7/8 | Fast but inconsistent |

These models:
- Sometimes use native format, sometimes text
- May fail specific test types
- Worth trying for simple tasks

### Tier 4: Limited (Not Recommended)

| Model | Size | Speed | Pass Rate | Notes |
|-------|------|-------|-----------|-------|
| `llama3.1:8b` | ~5 GB | ~25s/test | 3-5/8 | Tool format issues |
| `mistral:7b` | ~4 GB | ~20s/test | 2-4/8 | Tool format issues |

These models:
- Output tool calls as JSON text in `content` field
- Don't use Ollama's native `tool_calls` array
- Would require wrapper modification to support

## Why Models Fail

### Issue 1: Tool Call Format Mismatch

**What native format looks like:**
```json
{
  "message": {
    "role": "assistant",
    "content": "",
    "tool_calls": [
      {
        "function": {
          "name": "write_file",
          "arguments": {"path": "test.py", "content": "..."}
        }
      }
    ]
  }
}
```

**What broken models output:**
```json
{
  "message": {
    "role": "assistant",
    "content": "```json\n{\"name\": \"write_file\", \"arguments\": {\"path\": \"test.py\"}}\n```"
  }
}
```

The wrapper expects `tool_calls` array. When models output JSON as text, no tools execute.

### Issue 2: Not Following Tool Instructions

Some models ignore tool instructions and output code as text:

**Prompt:** "Use write_file to create hello.py with print('hello')"

**Bad response:**
```
Here's the code for hello.py:

```python
print('hello')
```

**Expected response:**
```json
{
  "tool_calls": [{
    "function": {
      "name": "write_file",
      "arguments": {"path": "hello.py", "content": "print('hello')"}
    }
  }]
}
```

**Mitigation:** Use explicit instructions like "You MUST use tools. Do NOT output code as text."

### Issue 3: Incomplete Tool Sequences

Model calls some tools but stops before completion:

```
User: Create script, make it executable, run it, call task_complete
Model: [calls write_file]
Model: "I've created the file."  ← Stops here instead of continuing
```

**Mitigation:** Number steps explicitly:
```
1. Use write_file to create script.py
2. Use run_command: chmod +x script.py
3. Use run_command: ./script.py
4. Call task_complete with summary
```

### Issue 4: Thinking Verbosity

Qwen3 models include extended reasoning by default:

```
<think>
Let me analyze this task. The user wants me to create a Python script.
I should consider what libraries to use. The secrets module would be
appropriate for password generation. I'll structure the code with a
function and a main block...
</think>

I'll create the password generator script.

[tool_calls...]
```

**Mitigation:** The wrapper prepends `/no_think` for qwen3 models:

```bash
if supports_no_think; then
    effective_task="/no_think $task"
fi
```

## Evaluating New Models

### Step 1: Check Ollama Compatibility

```bash
# See if model is available
ollama list | grep model-name

# Or pull it
ollama pull model-name:tag
```

### Step 2: Manual Tool Test

```bash
curl -s http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "new-model:tag",
    "messages": [{"role": "user", "content": "Use write_file to create test.txt with content \"hello\". You MUST use tools."}],
    "tools": [{"type":"function","function":{"name":"write_file","description":"Write to file","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}],
    "stream": false
  }' | jq '.message'
```

**Check for:**
- `tool_calls` array present (good)
- Tool call in `content` as text (bad)
- No tool attempt at all (bad)

### Step 3: Run Test Suite

```bash
./tests/run-tests.sh new-model:tag
```

### Step 4: Analyze Results

```bash
# Check specific test artifacts
cat tests/results/new-model_tag_test1_python_*/output.log

# Compare to known-good model
./tests/compare-results.sh
```

### Evaluation Criteria

| Criterion | Weight | What to Check |
|-----------|--------|---------------|
| Tool format | High | Uses native `tool_calls` array |
| Instruction following | High | Actually uses tools when told |
| Completion signaling | Medium | Calls `task_complete` |
| Error handling | Medium | Handles failures gracefully |
| Speed | Low | Acceptable response time |

## Potential Fixes for Incompatible Models

### Option 1: Content Parsing (PLAN.md Phase 1.1)

Add fallback parsing for JSON in `content`:

```bash
detect_tool_calls_in_content() {
    local content="$1"
    if echo "$content" | grep -qE '"name"\s*:\s*"(write_file|read_file|...)'; then
        # Extract and reformat as tool call
        return 0
    fi
    return 1
}
```

**Pros:** Supports more models
**Cons:** Fragile, model-specific heuristics

### Option 2: System Prompt Tuning

Some models respond better with explicit system prompts:

```json
{
  "messages": [
    {
      "role": "system",
      "content": "You are a task execution agent. ALWAYS use the provided tools. NEVER output code as plain text."
    },
    {"role": "user", "content": "..."}
  ]
}
```

**Pros:** No code changes
**Cons:** Uses tokens, not always effective

### Option 3: Model Fine-Tuning

Fine-tune models specifically for tool calling format.

**Pros:** Best results
**Cons:** Requires significant effort, hardware

## Model Size vs Capability

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  Capability                                                      │
│      ▲                                                          │
│      │                         ● glm-4.7-flash (19GB)           │
│      │                                                          │
│      │              ● qwen3:8b (5GB)                            │
│      │              ● rnj-1:8b (5GB)                            │
│      │                                                          │
│      │    ● ministral-3 (3GB)                                   │
│      │                                                          │
│      └──────────────────────────────────────────────▶ Speed     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

For most sub-agent tasks, 8B models hit the sweet spot:
- Fast enough for interactive use
- Capable enough for tool calling
- Fit on consumer GPUs (8GB VRAM)

## Recommendations by Use Case

| Use Case | Recommended Model | Why |
|----------|-------------------|-----|
| General automation | `qwen3:8b` | Balanced, reliable |
| Speed priority | `rnj-1:8b` | Fastest good model |
| Complex tasks | `glm-4.7-flash` | More reasoning power |
| Low VRAM (<6GB) | `ministral-3` | Smaller footprint |
| Experimentation | Any | Run tests to evaluate |

## Adding Results to Leaderboard

After testing a new model:

1. Run full test suite: `./tests/run-tests.sh new-model:tag`
2. Note pass rate and timing
3. Update `TEST-RESULTS.md` leaderboard
4. Add notes about any quirks or failures
