# Local Sub-Agent Benchmark - Quick Start

## Multi-Runtime Support ✅

The benchmark now supports **3 runtime backends:**

| Runtime | API | Port | Model Example |
|---------|-----|------|---------------|
| **Ollama** | Native | 11434 | `qwen3:8b` |
| **vLLM** | OpenAI-compatible | 8000 | `meta-llama/Llama-3.1-8B-Instruct` |
| **llama.cpp** | OpenAI-compatible | 8080 | `qwen3-8b` |

## Quick Commands

### Run Agent (Direct)

```bash
# Ollama (default)
./agent-wrapper.sh "Create hello.py that prints 'Hi'" /tmp

# Specify runtime
./agent-wrapper.sh --runtime ollama "task" /path
./agent-wrapper.sh --runtime vllm "task" /path
./agent-wrapper.sh --runtime llamacpp "task" /path
```

### Run Benchmark Tests

```bash
# Full test suite (18 tests)
./tests/run-tests.sh qwen3:8b --runtime ollama

# Quick mode (8 basic tests, skip complex 9-18)
./tests/run-tests.sh qwen3:8b --quick --runtime ollama

# Test different runtimes
./tests/run-tests.sh qwen3:8b --runtime ollama
./tests/run-tests.sh meta-llama/Llama-3.1-8B-Instruct --runtime vllm
./tests/run-tests.sh qwen3-8b --runtime llamacpp
```

### Compare Results

```bash
./tests/compare-results.sh

# Shows results across all runtimes with:
# - Pass/fail rates
# - Quality scores
# - Execution times
# - Iteration counts
```

## Environment Variables

Override default settings:

```bash
# Custom model
MODEL=qwen3:latest ./agent-wrapper.sh --runtime ollama "task" /path

# Custom API endpoints
OLLAMA_URL=http://192.168.1.100:11434/api/chat \
  ./agent-wrapper.sh --runtime ollama "task" /path

VLLM_URL=http://10.0.0.5:8000/v1/chat/completions \
  ./agent-wrapper.sh --runtime vllm "task" /path

# Timeout and verbosity
AGENT_TIMEOUT=300 AGENT_QUIET=1 \
  ./agent-wrapper.sh --runtime ollama "task" /path
```

## File Structure

```
local-sub-agents/
├── ollama-agent.sh          # Original (unchanged, still works)
├── agent-wrapper.sh         # New generic wrapper
├── runtimes/
│   ├── common.sh            # Shared tool definitions
│   ├── ollama.sh            # Ollama adapter
│   ├── vllm.sh              # vLLM adapter
│   └── llamacpp.sh          # llama.cpp adapter
└── tests/
    ├── run-tests.sh         # Benchmark runner (updated)
    ├── compare-results.sh   # Results analyzer (updated)
    └── results/
        ├── ollama_qwen3_8b_20260202_091500.md
        ├── vllm_Llama-3.1-8B-Instruct_20260202_092000.md
        └── llamacpp_qwen3-8b_20260202_092500.md
```

## Result Filenames

Format: `{runtime}_{model}_{timestamp}.md`

Examples:
- `ollama_qwen3_8b_20260202_091500.md`
- `vllm_Llama-3.1-8B-Instruct_20260202_092000.md`
- `llamacpp_qwen3-8b_20260202_092500.md`

## Backward Compatibility

✅ Old scripts still work:

```bash
# Still works exactly as before
./ollama-agent.sh "task" /path

# Equivalent new syntax
./agent-wrapper.sh --runtime ollama "task" /path
```

## Starting Runtime Servers

### Ollama (Default)
```bash
# Usually already running as system service
ollama list  # Check available models
```

### vLLM
```bash
# Start vLLM server with model
python -m vllm.entrypoints.openai.api_server \
    --model meta-llama/Llama-3.1-8B-Instruct \
    --port 8000 \
    --dtype auto

# Or use vllm CLI
vllm serve meta-llama/Llama-3.1-8B-Instruct --port 8000
```

### llama.cpp
```bash
# Start llama-server with GGUF model
llama-server \
    --model ./models/qwen3-8b.gguf \
    --port 8080 \
    --ctx-size 8192

# Check server
curl http://localhost:8080/health
```

## Common Tasks

### Test Single Model

```bash
./tests/run-tests.sh qwen3:8b --runtime ollama
```

### Compare All Results

```bash
# Run tests with different runtimes
./tests/run-tests.sh qwen3:8b --runtime ollama
./tests/run-tests.sh meta-llama/Llama-3.1-8B-Instruct --runtime vllm
./tests/run-tests.sh qwen3-8b --runtime llamacpp

# Compare
./tests/compare-results.sh
```

### Quick Smoke Test

```bash
./agent-wrapper.sh --runtime ollama "Create test.txt with 'OK'" /tmp
cat /tmp/test.txt  # Should show: OK
```

## Troubleshooting

### Connection Errors

```bash
# Check if runtime is running
curl -s http://localhost:11434/api/tags    # Ollama
curl -s http://localhost:8000/health        # vLLM
curl -s http://localhost:8080/health        # llama.cpp

# Override URL if running elsewhere
OLLAMA_URL=http://192.168.1.5:11434/api/chat \
  ./agent-wrapper.sh --runtime ollama "task" /path
```

### Model Not Found

```bash
# Ollama: Pull model first
ollama pull qwen3:8b

# vLLM/llama.cpp: Specify correct model name/path
MODEL=my-model-name ./agent-wrapper.sh --runtime vllm "task" /path
```

### Timeout Issues

```bash
# Increase timeout (default: 120s)
AGENT_TIMEOUT=300 ./agent-wrapper.sh --runtime ollama "task" /path
```

## See Also

- `MULTI_RUNTIME_REFACTOR.md` - Full implementation details
- `ALTERNATIVE_RUNTIMES.md` - Runtime comparison and setup
- `README.md` - Project overview

---

**Status:** ✅ Production-ready  
**Last Updated:** 2026-02-02
