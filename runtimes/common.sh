#!/bin/bash
# common.sh - Shared utilities for all runtime adapters
# This file is sourced by each runtime adapter

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { [[ "$QUIET" == "1" ]] || echo -e "${BLUE}[agent]${NC} $1"; }
success() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Tool definitions in OpenAI function calling format
# This format is compatible with Ollama, vLLM, and llama.cpp
TOOLS='[
  {
    "type": "function",
    "function": {
      "name": "write_file",
      "description": "Write content to a file. Creates parent directories if needed.",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "File path (relative to workdir)"},
          "content": {"type": "string", "description": "Content to write"}
        },
        "required": ["path", "content"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "read_file",
      "description": "Read content from a file",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "File path to read"}
        },
        "required": ["path"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "run_command",
      "description": "Run a shell command and return output",
      "parameters": {
        "type": "object",
        "properties": {
          "command": {"type": "string", "description": "Shell command to execute"}
        },
        "required": ["command"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "list_files",
      "description": "List files in a directory",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Directory path (default: current)"}
        }
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "task_complete",
      "description": "Signal that the task is complete and provide a summary",
      "parameters": {
        "type": "object",
        "properties": {
          "summary": {"type": "string", "description": "Summary of what was accomplished"}
        },
        "required": ["summary"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "web_search",
      "description": "Search the web using private SearXNG instance. Returns titles, URLs, and content snippets.",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {"type": "string", "description": "Search query"},
          "limit": {"type": "number", "description": "Max results to return (default 5)"}
        },
        "required": ["query"]
      }
    }
  }
]'

# Execute a tool call - shared across all runtimes
execute_tool() {
    local name="$1"
    local args="$2"

    case "$name" in
        write_file)
            local path=$(echo "$args" | jq -r '.path')
            local full_path="$WORKDIR/$path"
            mkdir -p "$(dirname "$full_path")"
            echo "$args" | jq -r '.content' > "$full_path"
            success "Wrote $(wc -c < "$full_path") bytes to $path"
            echo "File written successfully: $path"
            ;;
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
        list_files)
            local path=$(echo "$args" | jq -r '.path // "."')
            local full_path="$WORKDIR/$path"
            ls -la "$full_path" 2>&1
            ;;
        task_complete)
            local summary=$(echo "$args" | jq -r '.summary')
            echo ""
            echo "========================================"
            success "TASK COMPLETE"
            echo "$summary"
            echo "========================================"
            exit 0
            ;;
        web_search)
            local query=$(echo "$args" | jq -r '.query')
            local limit=$(echo "$args" | jq -r '.limit // 5')
            log "Searching web for: $query"
            local results=$(curl -s "http://192.168.8.101:8080/search?q=$(echo "$query" | jq -sRr @uri)&format=json" | \
                jq -c --argjson limit "$limit" '.results[:$limit] | map({title, url, content})')
            if [[ -n "$results" && "$results" != "null" ]]; then
                success "Found $(echo "$results" | jq 'length') results"
                echo "$results" | jq -r '.[] | "Title: \(.title)\nURL: \(.url)\nSnippet: \(.content)\n"'
            else
                error "Search failed or no results"
                echo "Error: Search failed"
            fi
            ;;
        *)
            error "Unknown tool: $name"
            echo "Error: Unknown tool: $name"
            ;;
    esac
}

# Parse tool calls from normalized response format
# Input: JSON with {content, tool_calls} structure
# All runtime adapters normalize to this format
process_tool_calls() {
    local tool_calls="$1"

    if [[ -z "$tool_calls" || "$tool_calls" == "null" || "$tool_calls" == "[]" ]]; then
        return 1
    fi

    local num_calls=$(echo "$tool_calls" | jq 'length')

    for ((j=0; j<num_calls; j++)); do
        local call=$(echo "$tool_calls" | jq ".[$j]")
        local name=$(echo "$call" | jq -r '.function.name')
        local args=$(echo "$call" | jq -r '.function.arguments')

        # Handle args as string or object
        if [[ "$args" != "{"* ]]; then
            args=$(echo "$args" | jq -r '.')
        fi

        log "Tool call: $name"
        local result=$(execute_tool "$name" "$args")

        # Return result for message history
        echo "$result"
    done

    return 0
}
