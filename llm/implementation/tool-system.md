# Tool System

## Overview

The tool system enables local LLMs to take actions in the real world. Tools bridge the gap between model outputs (text/JSON) and executable operations (file writes, shell commands).

## Tool Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                       Tool Lifecycle                             │
│                                                                  │
│  1. DEFINITION                                                   │
│     ┌────────────────────────────────────────────┐              │
│     │  {                                         │              │
│     │    "type": "function",                     │              │
│     │    "function": {                           │              │
│     │      "name": "write_file",                 │──┐           │
│     │      "description": "...",                 │  │           │
│     │      "parameters": {...}                   │  │           │
│     │    }                                       │  │           │
│     │  }                                         │  │           │
│     └────────────────────────────────────────────┘  │           │
│                                                      │           │
│  2. SELECTION (by model)                            │           │
│     Model receives tools in API request ────────────┘           │
│     Model decides which tool to use                             │
│     Model outputs tool_calls array                              │
│                                                      │           │
│  3. EXECUTION                                       │           │
│     ┌────────────────────────────────────────────┐  │           │
│     │  execute_tool("write_file", args)          │◀─┘           │
│     │    → Parse arguments                       │              │
│     │    → Perform operation                     │              │
│     │    → Return result string                  │              │
│     └────────────────────────────────────────────┘              │
│                               │                                  │
│  4. FEEDBACK                  ▼                                  │
│     Result added to message history                             │
│     Model sees outcome and decides next step                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Tool Definition Format

### JSON Schema Structure

```json
{
  "type": "function",
  "function": {
    "name": "tool_name",
    "description": "What this tool does and when to use it",
    "parameters": {
      "type": "object",
      "properties": {
        "required_param": {
          "type": "string",
          "description": "What this parameter is for"
        },
        "optional_param": {
          "type": "number",
          "description": "Optional parameter with default behavior"
        }
      },
      "required": ["required_param"]
    }
  }
}
```

### Parameter Types

| JSON Type | Description | Example |
|-----------|-------------|---------|
| `string` | Text values | File paths, content |
| `number` | Numeric values | Counts, limits |
| `boolean` | True/false | Flags |
| `array` | Lists | Multiple paths |
| `object` | Nested structures | Configuration |

### Description Best Practices

Good descriptions help the model choose correctly:

```json
// ❌ Vague
"description": "Write a file"

// ✅ Specific
"description": "Write content to a file. Creates parent directories if needed. Path is relative to working directory."
```

## Current Tools

### write_file

**Purpose:** Create or overwrite files with specified content.

**Definition:**
```json
{
  "name": "write_file",
  "description": "Write content to a file. Creates parent directories if needed.",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "File path (relative to workdir)"
      },
      "content": {
        "type": "string",
        "description": "Content to write"
      }
    },
    "required": ["path", "content"]
  }
}
```

**Implementation:**
```bash
write_file)
    local path=$(echo "$args" | jq -r '.path')
    local full_path="$WORKDIR/$path"
    mkdir -p "$(dirname "$full_path")"
    echo "$args" | jq -r '.content' > "$full_path"
    success "Wrote $(wc -c < "$full_path") bytes to $path"
    echo "File written successfully: $path"
    ;;
```

**Key behaviors:**
- Creates parent directories automatically
- Overwrites existing files
- Uses `jq -r` to properly decode escape sequences
- Returns byte count for confirmation

**Example usage by model:**
```json
{
  "function": {
    "name": "write_file",
    "arguments": {
      "path": "scripts/hello.py",
      "content": "#!/usr/bin/env python3\nprint('Hello, World!')"
    }
  }
}
```

---

### read_file

**Purpose:** Read and return file contents.

**Definition:**
```json
{
  "name": "read_file",
  "description": "Read content from a file",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "File path to read"
      }
    },
    "required": ["path"]
  }
}
```

**Implementation:**
```bash
read_file)
    local path=$(echo "$args" | jq -r '.path')
    local full_path="$WORKDIR/$path"
    if [[ -f "$full_path" ]]; then
        cat "$full_path"
    else
        error "File not found: $path"
        echo "Error: File not found: $path"
    fi
    ;;
```

**Key behaviors:**
- Returns raw file contents
- Error message on missing file (helps model recover)
- No size limit (potential issue for very large files)

**Example usage by model:**
```json
{
  "function": {
    "name": "read_file",
    "arguments": {
      "path": "config.json"
    }
  }
}
```

---

### run_command

**Purpose:** Execute shell commands and return output.

**Definition:**
```json
{
  "name": "run_command",
  "description": "Run a shell command and return output",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "Shell command to execute"
      }
    },
    "required": ["command"]
  }
}
```

**Implementation:**
```bash
run_command)
    local cmd=$(echo "$args" | jq -r '.command')
    log "Running: $cmd"
    cd "$WORKDIR"
    local output exit_code
    output=$(bash -c "$cmd" 2>&1) && exit_code=0 || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        success "Command succeeded"
    else
        warn "Command exited with code $exit_code"
        echo "Exit code: $exit_code"
    fi
    echo "$output"
    ;;
```

**Key behaviors:**
- Executes in working directory context
- Captures both stdout and stderr
- Reports exit code for failures
- Always returns output (model needs to see errors)

**Example usage by model:**
```json
{
  "function": {
    "name": "run_command",
    "arguments": {
      "command": "python hello.py"
    }
  }
}
```

**Security note:** This tool has full user permissions. Caller is responsible for appropriate task delegation.

---

### list_files

**Purpose:** List directory contents.

**Definition:**
```json
{
  "name": "list_files",
  "description": "List files in a directory",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Directory path (default: current)"
      }
    }
  }
}
```

**Implementation:**
```bash
list_files)
    local path=$(echo "$args" | jq -r '.path // "."')
    local full_path="$WORKDIR/$path"
    ls -la "$full_path" 2>&1
    ;;
```

**Key behaviors:**
- Defaults to current directory
- Shows hidden files (`-a`)
- Shows detailed info (`-l`)
- Reports errors for missing directories

**Example usage by model:**
```json
{
  "function": {
    "name": "list_files",
    "arguments": {
      "path": "src"
    }
  }
}
```

---

### task_complete

**Purpose:** Signal successful task completion.

**Definition:**
```json
{
  "name": "task_complete",
  "description": "Signal that the task is complete and provide a summary",
  "parameters": {
    "type": "object",
    "properties": {
      "summary": {
        "type": "string",
        "description": "Summary of what was accomplished"
      }
    },
    "required": ["summary"]
  }
}
```

**Implementation:**
```bash
task_complete)
    local summary=$(echo "$args" | jq -r '.summary')
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "TASK COMPLETE"
    echo "$summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
    ;;
```

**Key behaviors:**
- Terminates the script with success (exit 0)
- Prints formatted summary
- Should always be instructed in prompts

**Example usage by model:**
```json
{
  "function": {
    "name": "task_complete",
    "arguments": {
      "summary": "Created password_generator.py with generate_password() function. Tested successfully - generates 3 unique 16-character passwords."
    }
  }
}
```

## Adding New Tools

### Step 1: Define the Tool Schema

Add to the `TOOLS` JSON array:

```bash
TOOLS='[
  // ... existing tools ...
  {
    "type": "function",
    "function": {
      "name": "search_text",
      "description": "Search for text pattern in files",
      "parameters": {
        "type": "object",
        "properties": {
          "pattern": {
            "type": "string",
            "description": "Text or regex pattern to search"
          },
          "path": {
            "type": "string",
            "description": "Directory to search (default: current)"
          }
        },
        "required": ["pattern"]
      }
    }
  }
]'
```

### Step 2: Implement the Tool

Add a case to `execute_tool`:

```bash
execute_tool() {
    local name="$1"
    local args="$2"
    
    case "$name" in
        # ... existing tools ...
        
        search_text)
            local pattern=$(echo "$args" | jq -r '.pattern')
            local path=$(echo "$args" | jq -r '.path // "."')
            local full_path="$WORKDIR/$path"
            grep -r "$pattern" "$full_path" 2>&1 || echo "No matches found"
            ;;
            
        *)
            error "Unknown tool: $name"
            echo "Error: Unknown tool: $name"
            ;;
    esac
}
```

### Step 3: Test the Tool

Create a test case in `tests/run-tests.sh`:

```bash
run_test "test_search" \
"Use write_file to create 'sample.txt' with 'Hello World'
Use search_text to find 'World' in current directory
Call task_complete with summary" \
"grep -q 'World' '$TEST_WORKDIR/test_search/sample.txt'"
```

## Tool Design Guidelines

### 1. Return Useful Feedback

```bash
# ❌ No feedback
echo "$content" > "$path"

# ✅ Informative feedback
echo "$content" > "$path"
echo "File written successfully: $path ($(wc -c < "$path") bytes)"
```

### 2. Handle Errors Gracefully

```bash
# ❌ Silent failure
cat "$path"

# ✅ Clear error message
if [[ -f "$path" ]]; then
    cat "$path"
else
    echo "Error: File not found: $path"
fi
```

### 3. Respect Working Directory

```bash
# ❌ Absolute paths only
local full_path="$path"

# ✅ Relative to workdir
local full_path="$WORKDIR/$path"
```

### 4. Capture Both Outputs

```bash
# ❌ Loses stderr
output=$(command)

# ✅ Captures everything
output=$(command 2>&1)
```

### 5. Report Exit Codes

```bash
# ❌ Ignores failures
output=$(command)

# ✅ Reports status
output=$(command 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    echo "Exit code: $exit_code"
fi
echo "$output"
```

## Tool Selection Heuristics

The model chooses tools based on:

1. **Tool name** - Should be intuitive (`write_file` for writing)
2. **Description** - Helps disambiguate similar tools
3. **Task context** - What the user asked for
4. **Prior results** - What happened in previous iterations

### Helping Model Choose Correctly

**In prompts:**
```
Use write_file to create 'config.json' with...
```

**In descriptions:**
```json
"description": "Write content to a file. Use this when you need to create or update a file."
```

## Arguments Handling

Ollama may return arguments in two formats:

### Object Format (Common)
```json
{
  "function": {
    "name": "write_file",
    "arguments": {
      "path": "test.py",
      "content": "print('hi')"
    }
  }
}
```

### String Format (Some Models)
```json
{
  "function": {
    "name": "write_file",
    "arguments": "{\"path\": \"test.py\", \"content\": \"print('hi')\"}"
  }
}
```

The wrapper handles both:

```bash
local args=$(echo "$call" | jq -r '.function.arguments')

# Handle args as string or object
if [[ "$args" == "{"* ]]; then
    : # Already JSON object
else
    args=$(echo "$args" | jq -r '.')  # Parse if string
fi
```

## Potential Tool Additions

### search_text
Search for patterns in files:
```bash
grep -r "$pattern" "$path" 2>&1
```

### edit_file
Modify existing files (find/replace):
```bash
sed -i "s/$find/$replace/g" "$path"
```

### download_url
Fetch remote content:
```bash
curl -s "$url"
```

### list_processes
Show running processes:
```bash
ps aux | grep "$filter"
```

### git_status
Git operations:
```bash
cd "$WORKDIR" && git status
```

Each would follow the same pattern: JSON schema + case implementation.
