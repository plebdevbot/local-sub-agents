# Project Overview

## What is Local Sub-Agents?

Local Sub-Agents is a shell-based agentic wrapper that enables locally-running LLMs (via Ollama) to autonomously complete tasks using tool calling. It bridges the gap between powerful cloud AI agents and fast local models, enabling task delegation for small, well-defined work.

## The Problem It Solves

### The Delegation Bottleneck

When a main AI agent (like Claude) handles user requests, many tasks are simple enough that they don't require the full power (and cost/latency) of a frontier model:

- Creating a simple utility script
- Generating a configuration file
- Parsing and transforming data
- Running system commands

However, delegating these tasks is difficult because:

1. **Local models lack agency** - They generate text but can't execute actions
2. **Tool calling varies** - Different models use different formats
3. **Context is limited** - Local models need clear, structured prompts
4. **No harness exists** - Most tools assume cloud APIs, not local inference

### The Solution

`ollama-agent.sh` provides a minimal, battle-tested agentic harness that:

- Calls Ollama's native API with standard tool definitions
- Executes tool calls (file operations, shell commands)
- Maintains conversation context across iterations
- Signals completion when tasks finish

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           User Request                           │
│            "Organize my downloads folder by file type"          │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Main Agent (Claude/GPT-4/etc)                 │
│                                                                  │
│  Analyzes request:                                               │
│  - Is this delegable? (small, well-defined, no user input)       │
│  - What tools will sub-agent need? (list_files, run_command)     │
│  - What's the expected output? (organized directories)           │
│                                                                  │
│  Creates delegation prompt:                                      │
│  "List files in ~/Downloads, create subdirs by extension,        │
│   move files into appropriate subdirs. Call task_complete."     │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ exec: ollama-agent.sh "prompt" ~/Downloads
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ollama-agent.sh                             │
│                                                                  │
│  1. Parses task and workdir                                     │
│  2. Constructs API request with tool definitions                │
│  3. Sends to Ollama: POST /api/chat                             │
│  4. Receives response with tool_calls array                     │
│  5. Executes each tool, collects results                        │
│  6. Appends tool results to message history                     │
│  7. Loops until task_complete or max iterations                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ HTTP to localhost:11434
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Ollama + Local Model                        │
│                                                                  │
│  Model: qwen3:8b (or rnj-1:8b, glm-4.7-flash, etc.)             │
│                                                                  │
│  Receives:                                                       │
│  - System context (implicit)                                    │
│  - User message with task                                       │
│  - Tool definitions (JSON schema)                               │
│                                                                  │
│  Decides:                                                        │
│  - Which tool to call                                           │
│  - What arguments to pass                                       │
│                                                                  │
│  Returns:                                                        │
│  - Assistant message with tool_calls array                      │
│  - Or text response if done                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Why Shell Script?

The wrapper is deliberately simple:

| Characteristic | Rationale |
|----------------|-----------|
| **Shell (bash)** | Universal availability, no dependencies beyond curl/jq |
| **~200 lines** | Easy to audit, modify, debug |
| **No framework** | Direct API calls, no abstraction leaks |
| **Synchronous** | Clear execution flow, easy logging |

A more sophisticated implementation might use Python or TypeScript, but the shell script approach:
- Works on any Unix system
- Requires no package installation
- Is transparent and hackable
- Matches the "small, focused tool" philosophy

## Design Principles

### 1. Explicit Tool Instructions

Prompts must explicitly tell the model to use tools:

```
❌ "Create a Python script that..."
✅ "Use write_file to create 'script.py' with..."
```

Many local models will output code as text unless instructed to use tools.

### 2. Step-by-Step Structure

Break complex tasks into numbered steps:

```
1. Use list_files to see current directory
2. Use read_file to examine config.json
3. Use write_file to create updated config
4. Use run_command to validate: python -c "import json; json.load(open('config.json'))"
5. Call task_complete with summary
```

### 3. Explicit Completion Signal

Always end prompts with:
```
Call task_complete with a summary of what you accomplished.
```

This prevents the model from stopping mid-task or continuing indefinitely.

### 4. Appropriate Task Scope

**Good candidates for delegation:**
- Single-file operations
- Data transformation (JSON → CSV, etc.)
- Script generation and execution
- Configuration file creation
- File organization tasks

**Keep on main agent:**
- Multi-file refactoring
- Security-sensitive operations
- Tasks requiring user clarification
- Complex debugging sessions
- Anything with uncertain scope

## Resource Constraints

Local models share limited hardware resources:

### GPU Memory
- 8B models need ~5-6GB VRAM
- Larger models need proportionally more
- Only one inference at a time

### Inference Speed
- First run loads model (10-30s)
- Subsequent runs are fast (1-5s per response)
- Don't run parallel tasks

### Quality Tradeoffs
- 8B models handle most tool tasks well
- Larger models better for complex reasoning
- Speed vs capability tradeoff

## Success Criteria

A sub-agent task is successful when:

1. **Completes autonomously** - No human intervention needed
2. **Produces correct output** - Files created, commands executed
3. **Signals completion** - Calls task_complete with summary
4. **Stays in scope** - Doesn't attempt unrelated actions
5. **Handles errors** - Reports problems, doesn't crash

## Comparison to Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **This project** | Simple, reliable, direct API | Shell-based, limited features |
| **OpenCode + Ollama** | Full IDE features | Tool call bugs with Ollama |
| **LangChain** | Rich ecosystem | Heavy dependencies, complexity |
| **AutoGPT-style** | More autonomous | Overkill for simple tasks |
| **Direct Ollama** | Minimal | No tool execution |

Local Sub-Agents occupies a specific niche: minimal, reliable task execution for well-defined work.

## Future Directions

See `PLAN.md` for the improvement roadmap:

- **Tool format compatibility** - Support models that output tool calls as JSON text
- **Quality scoring** - Beyond pass/fail, measure efficiency and format compliance
- **Parallel task queue** - Safely queue tasks (still execute sequentially)
- **Result caching** - Avoid re-running identical tasks
