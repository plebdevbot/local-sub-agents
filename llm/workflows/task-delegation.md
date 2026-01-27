# Task Delegation Workflow

## Overview

Task delegation is the process by which a main AI agent (like Claude) identifies tasks suitable for local execution and hands them off to the `ollama-agent.sh` wrapper.

## Delegation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Request                              │
│     "Create a script to organize my downloads by file type"     │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Main Agent Analysis                           │
│                                                                  │
│  Questions to evaluate:                                          │
│  1. Is this task well-defined? ✅                               │
│  2. Is it self-contained? ✅                                    │
│  3. Does it require user interaction? ❌                        │
│  4. Can it be verified? ✅                                      │
│  5. Is it security-sensitive? ❌                                │
│                                                                  │
│  Decision: DELEGATE                                              │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Prompt Crafting                             │
│                                                                  │
│  "You MUST use tools. Do NOT output code as text.               │
│                                                                  │
│   1. Use list_files to see what's in the directory              │
│   2. Use run_command: mkdir -p Documents Images Videos          │
│   3. Use run_command to move files by extension:                │
│      - *.pdf, *.doc, *.txt → Documents/                         │
│      - *.jpg, *.png, *.gif → Images/                           │
│      - *.mp4, *.mkv → Videos/                                   │
│   4. Use list_files to show final structure                     │
│   5. Call task_complete with summary"                           │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Execution                                 │
│                                                                  │
│  exec command: "./ollama-agent.sh 'prompt' ~/Downloads"         │
│                                                                  │
│  Monitoring: check session output periodically                  │
│  Timeout: configured via OLLAMA_TIMEOUT (default 120s/call)     │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Review                                    │
│                                                                  │
│  - Check created directories exist                              │
│  - Verify files were moved correctly                            │
│  - Read task_complete summary                                   │
│  - Report to user                                               │
└─────────────────────────────────────────────────────────────────┘
```

## Task Classification

### ✅ Good Candidates for Delegation

| Category | Examples |
|----------|----------|
| **Single-file scripts** | Password generator, config parser, utility functions |
| **Configuration files** | docker-compose.yml, nginx.conf, .env templates |
| **Data transformation** | JSON → CSV, log parsing, text processing |
| **File operations** | Renaming, organizing, cleanup scripts |
| **Documentation** | README generation, comment extraction |
| **Simple automation** | Cron job scripts, backup scripts |

### ❌ Keep on Main Agent

| Category | Why |
|----------|-----|
| **Multi-file refactoring** | Requires global context understanding |
| **Security-sensitive** | API keys, credentials, permissions |
| **User interaction** | Clarification questions, confirmations |
| **Complex debugging** | Needs iterative human feedback |
| **Uncertain scope** | "Make this code better" |
| **External services** | API calls, network operations |

### ⚠️ Evaluate Case-by-Case

| Category | Factors |
|----------|---------|
| **Testing** | Scope, complexity, dependencies |
| **Installation scripts** | System permissions, side effects |
| **Git operations** | Complexity, commit messages |

## Prompt Crafting Guidelines

### 1. Explicit Tool Instructions

Always tell the model to use tools:

```
❌ "Create a Python script that generates passwords"

✅ "You MUST use tools. Do NOT output code as text.
   Use write_file to create 'password_generator.py' with..."
```

### 2. Step-by-Step Structure

Number the steps explicitly:

```
1. Use read_file to examine 'data.json'
2. Process the data to calculate averages
3. Use write_file to create 'report.txt' with results
4. Use run_command: cat report.txt
5. Call task_complete with summary
```

### 3. Explicit Completion Signal

Always end with:
```
Call task_complete with a summary of what you accomplished.
```

### 4. Provide Necessary Context

Include relevant details:
- File paths (relative to workdir)
- Expected output format
- Constraints or requirements
- Verification steps

### 5. Avoid Ambiguity

```
❌ "Create a good config file"

✅ "Create 'nginx.conf' with:
   - Server block listening on port 80
   - Location /api proxying to localhost:3000
   - Static files served from /var/www/html"
```

## Execution Patterns

### Synchronous (Blocking)

Wait for task completion:

```bash
# Main agent waits
./ollama-agent.sh "task" /workdir
# Continues after completion
```

Use for:
- Quick tasks (<30s)
- Sequential dependencies
- When result needed immediately

### Asynchronous (Background)

Start task and check later:

```bash
# Start in background
./ollama-agent.sh "task" /workdir &
# ... do other things ...
# Check completion
wait $!
```

Use for:
- Longer tasks
- Parallel work
- User can do other things

### With Main Agent (Clawdbot)

```bash
# Start background task
exec pty:true background:true \
  command:"./ollama-agent.sh 'Create a cleanup script...' /tmp/project"

# Check progress
process action:log sessionId:XXX limit:50

# After completion, review
ls /tmp/project/
cat /tmp/project/cleanup.sh
```

## Monitoring and Review

### During Execution

1. **Log monitoring**: Check session output for progress
2. **Timeout handling**: Default 120s per API call
3. **Iteration tracking**: Max 10 iterations by default

### After Completion

1. **Verify outputs exist**:
   ```bash
   ls -la /workdir/expected_file.py
   ```

2. **Check file contents**:
   ```bash
   head -20 /workdir/script.py
   ```

3. **Run validation**:
   ```bash
   python -c "import script"  # Syntax check
   ./script.py  # Execution test
   ```

4. **Read summary**:
   The `task_complete` call includes a summary of what was done.

### Error Recovery

If task fails:
1. Check output log for error messages
2. Examine partial outputs
3. Decide: retry with clearer prompt, or handle manually
4. Report status to user

## Resource Management

### Hardware Constraints

```
⚠️ CRITICAL: Local models share limited resources
```

- **GPU memory**: One model loaded at a time
- **Inference**: Sequential, not parallel
- **Timeouts**: Set appropriate limits

### Best Practices

1. **Queue tasks**: Don't run parallel sub-agent calls
2. **Warm up models**: First call is slower (loading)
3. **Set timeouts**: Prevent infinite hangs
4. **Clean up**: Remove temp files after review

## Example Delegation Scenarios

### Scenario 1: Utility Script

**User request:** "Create a script to find duplicate files"

**Main agent analysis:**
- Well-defined ✅
- Self-contained ✅
- No user interaction ✅
- Verifiable ✅

**Delegation prompt:**
```
You MUST use tools. Do NOT output code as text.

Use write_file to create 'find_duplicates.py' that:
- Walks through a directory tree
- Calculates MD5 hash for each file
- Groups files by hash
- Prints duplicates (same hash, different path)

Use run_command: python find_duplicates.py .
Call task_complete with summary.
```

### Scenario 2: Data Processing

**User request:** "Parse this CSV and generate a summary"

**Main agent analysis:**
- Well-defined ✅
- Self-contained ✅
- Input data available ✅

**Delegation prompt:**
```
You MUST use tools.

1. Use read_file to read 'sales.csv'
2. Parse the CSV data
3. Calculate: total sales, average per month, top product
4. Use write_file to create 'summary.txt' with formatted results
5. Use run_command: cat summary.txt
6. Call task_complete with summary.
```

### Scenario 3: Configuration Generation

**User request:** "Create a docker-compose for a web stack"

**Main agent analysis:**
- Well-defined ✅
- Standard format ✅
- Verifiable ✅

**Delegation prompt:**
```
You MUST use tools.

Use write_file to create 'docker-compose.yml' with:
- nginx:latest on port 80
- node:18 running on port 3000
- postgres:15 with volume for data
- redis:7 for caching
- Internal network 'webnet'

Call task_complete with summary.
```

## Anti-Patterns

### ❌ Vague Tasks

```
"Make the code better"
"Fix the bugs"
"Improve performance"
```

These require judgment and iteration that local models handle poorly.

### ❌ Multi-Step Dependencies

```
"Update the API, then update all the tests, then update the docs"
```

Break into separate, focused tasks.

### ❌ Security-Sensitive

```
"Generate an API key and configure the service"
"Set up SSH access"
```

Handle these on main agent with proper review.

### ❌ Unclear Scope

```
"Refactor the codebase"
"Modernize the project"
```

Define specific, measurable objectives.

## Delegation Checklist

Before delegating a task:

- [ ] Is the task well-defined with clear outputs?
- [ ] Can it be completed without user input?
- [ ] Is the scope small enough for local model?
- [ ] Are there no security concerns?
- [ ] Can results be verified?
- [ ] Have I provided explicit tool instructions?
- [ ] Did I include task_complete instruction?
- [ ] Is appropriate timeout set?
