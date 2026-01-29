# Benchmark Design - Memory Management

## Critical Constraint: One Model at a Time

This benchmark suite is designed to test **one model at a time** with explicit memory management to prevent OOM (out-of-memory) kills.

### Why This Matters

Local LLMs are **huge**:
- Small models (7-8B): ~5GB RAM
- Medium models (15B): ~10GB RAM  
- Large models (20B+): ~13-19GB RAM

Running multiple models simultaneously or leaving models loaded causes:
- ❌ OOM kills from the Linux kernel
- ❌ System instability
- ❌ Incomplete benchmark runs
- ❌ Inaccurate results

### How It Works

Each benchmark run follows this strict sequence:

```
┌─────────────────────────────────────────┐
│ 1. Check: Any models loaded?            │
│    → If yes: Unload them (ollama stop)  │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ 2. Load: Start testing model X          │
│    → Ollama loads model into memory     │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ 3. Test: Run all tests against model X  │
│    → Generate code, verify results      │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ 4. Cleanup: Unload model from memory    │
│    → ollama stop model-name             │
│    → Wait 5 seconds for memory clear    │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ 5. Verify: Confirm no models loaded     │
│    → ollama ps should be empty          │
└─────────────────────────────────────────┘
              ↓
           (Repeat for next model)
```

### Implementation

#### `benchmark-all-models.sh`

```bash
# Before each model:
LOADED=$(ollama ps | tail -n +2 | wc -l)
if [ "$LOADED" -gt 0 ]; then
    ollama ps | tail -n +2 | awk '{print $1}' | xargs -I{} ollama stop {}
fi

# After each model:
ollama stop "$MODEL"
sleep 5  # Wait for memory to clear
```

#### `run-tests.sh`

```bash
# At the end of all tests:
ollama stop "$MODEL"
```

### Manual Verification

To check if cleanup is working:

```bash
# While benchmark is running, in another terminal:
watch -n 1 'ollama ps'

# Should show:
# - Model loads when testing starts
# - Empty when moving between models
# - Clean slate before each new model
```

### Resource Monitoring

Watch memory usage during benchmarks:

```bash
# Terminal 1: Run benchmark
./benchmark-all-models.sh

# Terminal 2: Monitor memory
watch -n 1 'free -h'

# Terminal 3: Monitor Ollama
watch -n 1 'ollama ps'
```

You should see:
- ✅ Memory usage spike when model loads
- ✅ Memory usage drop when model unloads
- ✅ No gradual memory leak across models
- ✅ Clean transitions between models

### What to Avoid

❌ **Never** run multiple benchmark scripts simultaneously  
❌ **Never** manually load a model while benchmark is running  
❌ **Never** skip the cleanup steps  
❌ **Never** assume Ollama auto-unloads (it doesn't!)

### Troubleshooting

**Problem:** Benchmark gets OOM killed mid-run

**Solution:**
1. Check system RAM: `free -h`
2. Verify no other models loaded: `ollama ps`
3. Kill stray processes: `pkill -f ollama-agent`
4. Manually unload: `ollama stop <model-name>`
5. Re-run benchmark

**Problem:** Model doesn't unload after test

**Solution:**
```bash
# Force unload all models
ollama ps | tail -n +2 | awk '{print $1}' | xargs -I{} ollama stop {}

# Verify
ollama ps  # Should show empty
```

### Performance Impact

The explicit unload/reload cycle adds:
- ~5 seconds between models (cleanup wait time)
- ~10-20 seconds per model load (first inference is slow)

**This is acceptable** because it ensures:
- ✅ Reliable, complete benchmark runs
- ✅ Accurate, reproducible results
- ✅ No system crashes
- ✅ Fair comparison (each model gets fresh memory)

---

## Summary

**Golden Rule:** ONE MODEL AT A TIME, ALWAYS.

Before testing: Unload everything  
During testing: Only one model loaded  
After testing: Unload the model  
Between models: Verify clean slate  

This design ensures stable, reliable benchmarking even on consumer hardware with limited RAM.
