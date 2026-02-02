# Alternative Runtimes for Local Sub-Agent Benchmark

## Current Setup
- **Runtime:** Ollama (http://localhost:11434)
- **Harness:** Custom bash wrapper (`ollama-agent.sh`)
- **Interface:** Direct Ollama API calls (tool calling)

## Yes, We Can Swap Runtimes! 🎯

The benchmark can work with ANY runtime that supports:
1. **Tool/function calling** (crucial for the agent)
2. **HTTP API** (or command-line interface)
3. **Streaming or non-streaming responses**

---

## Option 1: OpenCode Built-in (Already Works!)

OpenCode is already installed and supports multiple providers:

**Available providers:**
```bash
opencode models
# Shows:
# - opencode/* (free tier models)
# - ollama/* (our current setup)
```

**To use OpenCode directly:**
```bash
# Instead of ollama-agent.sh, create opencode-agent.sh:
opencode run --model ollama/qwen3:8b "Your task here"
# Or with other providers:
opencode run --model opencode/glm-4.7-free "Your task here"
```

**Pros:**
- ✅ Already installed
- ✅ Supports multiple providers
- ✅ Has tool calling built-in
- ✅ Can use free tier models

**Cons:**
- ⚠️ May have different tool calling format
- ⚠️ Less control over low-level behavior

---

## Option 2: llama.cpp Server

**What it is:** C++ inference engine with OpenAI-compatible API

**Setup:**
```bash
# Install llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make

# Download a GGUF model
cd models
wget https://huggingface.co/.../model.gguf

# Start server
./llama-server -m models/model.gguf --port 8080
```

**Adapter script:**
```bash
#!/bin/bash
# llamacpp-agent.sh
# Point to http://localhost:8080/v1/chat/completions
# (OpenAI-compatible endpoint)
```

**Pros:**
- ✅ Fast C++ inference
- ✅ Very low memory usage
- ✅ OpenAI-compatible API
- ✅ Supports most GGUF models

**Cons:**
- ⚠️ Requires GGUF format models
- ⚠️ More setup required

---

## Option 3: vLLM (High Performance)

**What it is:** Fast inference server with PagedAttention

**Setup:**
```bash
# Install vLLM
pip install vllm

# Start server
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-3.1-8B-Instruct \
  --port 8000
```

**Pros:**
- ✅ Extremely fast inference
- ✅ Great for large models
- ✅ OpenAI-compatible API
- ✅ Batch processing support

**Cons:**
- ⚠️ Requires NVIDIA GPU (CUDA)
- ⚠️ More memory hungry than llama.cpp
- ⚠️ Requires HuggingFace models

---

## Option 4: LocalAI (Multi-Backend)

**What it is:** OpenAI-compatible API supporting multiple backends

**Setup:**
```bash
# Docker
docker run -p 8080:8080 localai/localai:latest

# Or install locally
# Supports: llama.cpp, whisper, stable-diffusion, etc.
```

**Pros:**
- ✅ Supports many backends (llama.cpp, GPT4All, etc.)
- ✅ OpenAI-compatible
- ✅ Easy Docker setup
- ✅ Multi-modal support

**Cons:**
- ⚠️ Docker overhead
- ⚠️ Another abstraction layer

---

## Option 5: HuggingFace Transformers (Direct)

**What it is:** Direct Python inference (no server)

**Setup:**
```bash
pip install transformers torch accelerate
```

**Adapter script:**
```python
#!/usr/bin/env python3
# transformers-agent.py
from transformers import AutoModelForCausalLM, AutoTokenizer

model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen2.5-7B-Instruct")
tokenizer = AutoTokenizer.from_pretrained("Qwen/Qwen2.5-7B-Instruct")

# Implement tool calling manually
```

**Pros:**
- ✅ Direct control
- ✅ No server needed
- ✅ Most flexible

**Cons:**
- ⚠️ Tool calling implementation required
- ⚠️ More complex
- ⚠️ Slower than optimized servers

---

## Option 6: Claude Code / OpenCode API Mode

**What it is:** Use existing CLI tools as runtime

```bash
# Already installed!
which opencode  # ✓
which claude    # ✓
```

**Create adapter:**
```bash
#!/bin/bash
# opencode-wrapper.sh
opencode run --model ollama/qwen3:8b "$@"
```

**Pros:**
- ✅ Zero setup (already works)
- ✅ Tool calling built-in
- ✅ Good UX

**Cons:**
- ⚠️ Less control over tool format
- ⚠️ May need adapting test harness

---

## Recommended Path Forward

### Quick Win (5 minutes)
**Use OpenCode directly:**
```bash
# Create opencode-agent.sh wrapper
cp ollama-agent.sh opencode-agent.sh
# Modify to call: opencode run --model ollama/qwen3:8b
```

### Best Performance (30 minutes)
**Set up llama.cpp server:**
- Fast C++ inference
- OpenAI-compatible
- Works with existing test harness (minimal changes)

### Most Flexible (1 hour)
**Set up vLLM (if you have GPU):**
- Fastest inference
- Great for benchmarking multiple models
- Production-ready

---

## Implementation Plan

**To adapt the benchmark:**

1. **Create new wrapper script:**
   ```bash
   cp ollama-agent.sh llamacpp-agent.sh
   # or
   cp ollama-agent.sh opencode-agent.sh
   ```

2. **Modify API endpoint:**
   ```bash
   # Change:
   OLLAMA_URL="http://localhost:11434/api/chat"
   # To:
   API_URL="http://localhost:8080/v1/chat/completions"
   ```

3. **Update test runner:**
   ```bash
   # In run-tests.sh, change:
   AGENT="$SCRIPT_DIR/../ollama-agent.sh"
   # To:
   AGENT="$SCRIPT_DIR/../llamacpp-agent.sh"
   ```

4. **Run benchmark:**
   ```bash
   ./tests/run-tests.sh --runtime llamacpp
   ```

---

## Comparison Table

| Runtime | Speed | Memory | Setup | API | Tool Support |
|---------|-------|--------|-------|-----|--------------|
| **Ollama** | Fast | Low | ✅ Easy | Custom | ✅ Native |
| **llama.cpp** | Fastest | Lowest | ⚙️ Medium | OpenAI | ✅ Yes |
| **vLLM** | Fastest* | High | ⚙️ Medium | OpenAI | ✅ Yes |
| **LocalAI** | Fast | Medium | ✅ Easy | OpenAI | ✅ Yes |
| **OpenCode** | Fast | Low | ✅ Zero | Custom | ✅ Native |
| **Transformers** | Slow | Medium | ⚙️ Complex | None | ❌ Manual |

*Requires GPU

---

## Next Steps

1. **Choose runtime** based on your goals:
   - **Fastest setup:** OpenCode (already works)
   - **Best performance:** llama.cpp or vLLM
   - **Most compatible:** LocalAI

2. **Create adapter script** (5-30 min depending on runtime)

3. **Test with one model** before full benchmark

4. **Run comparison** between Ollama and new runtime

**Want me to implement one of these?** 🚀
