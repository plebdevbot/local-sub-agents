#!/bin/bash
# compare-results.sh - Compare test results across models
# Usage: ./compare-results.sh [--json]
#   --json    Output results as JSON instead of markdown table

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
JSON_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json) JSON_MODE=true; shift ;;
        *) shift ;;
    esac
done

if [ ! -d "$RESULTS_DIR" ] || [ -z "$(ls -A $RESULTS_DIR/*.md 2>/dev/null)" ]; then
    if $JSON_MODE; then
        echo '{"error": "No results found", "results": []}'
    else
        echo "No results found. Run tests first:"
        echo "  ./run-tests.sh qwen3:8b"
        echo "  ./run-tests.sh glm-4.7-flash:latest"
    fi
    exit 1
fi

# Collect all results
declare -a results_json=()
declare -a results_table=()

for result in "$RESULTS_DIR"/*.md; do
    [ -f "$result" ] || continue

    filename=$(basename "$result")

    # Parse runtime and model from filename
    # New format: runtime_model_timestamp.md (e.g., ollama_qwen3_8b_20260202_120000.md)
    # Old format: model_timestamp.md (e.g., qwen3_8b_20260202_120000.md)
    if [[ "$filename" =~ ^(ollama|vllm|llamacpp)_ ]]; then
        runtime=$(echo "$filename" | cut -d'_' -f1)
        model=$(echo "$filename" | sed "s/^${runtime}_//" | sed 's/_[0-9]\{8\}_[0-9]\{6\}\.md$//' | tr '_' ':' | sed 's/:latest//')
    else
        runtime="ollama"
        model=$(echo "$filename" | sed 's/_[0-9]*\.md$//' | tr '_' ':' | sed 's/:latest//')
    fi

    # Extract stats from the file
    passed=$(grep -oP "Passed:\*\* \K[0-9]+" "$result" 2>/dev/null || echo "0")
    total=$(grep -oP "Passed:\*\* [0-9]+/\K[0-9]+" "$result" 2>/dev/null || echo "0")
    total_time=$(grep -oP "Total Time:\*\* \K[0-9]+" "$result" 2>/dev/null || echo "0")
    avg=$(grep -oP "Average:\*\* \K[0-9]+" "$result" 2>/dev/null || echo "0")
    date=$(grep -oP "Date:\*\* \K[0-9-]+" "$result" 2>/dev/null || echo "unknown")
    quality_score=$(grep -oP "Quality Score:\*\* \K[0-9]+" "$result" 2>/dev/null || echo "-")
    total_iterations=$(grep -oP "Total Iterations:\*\* \K[0-9]+" "$result" 2>/dev/null || echo "0")
    avg_iterations=$(grep -oP "Avg Iterations:\*\* \K[0-9.]+" "$result" 2>/dev/null || echo "0")

    # Extract individual test results
    test_results=""
    while IFS='|' read -r _ name status time iter _; do
        name=$(echo "$name" | xargs)
        status=$(echo "$status" | xargs)
        time=$(echo "$time" | xargs | sed 's/s$//')
        iter=$(echo "$iter" | xargs)
        if [[ "$name" =~ ^test ]]; then
            if [ -n "$test_results" ]; then
                test_results+=","
            fi
            test_results+="{\"name\":\"$name\",\"status\":\"$status\",\"time\":${time:-0},\"iterations\":${iter:-0}}"
        fi
    done < "$result"

    results_json+=("{\"runtime\":\"$runtime\",\"model\":\"$model\",\"passed\":$passed,\"total\":$total,\"time_seconds\":$total_time,\"avg_seconds\":$avg,\"quality_score\":${quality_score:--1},\"total_iterations\":$total_iterations,\"avg_iterations\":$avg_iterations,\"date\":\"$date\",\"tests\":[$test_results]}")
    results_table+=("| $runtime | $model | $passed/$total | ${quality_score:-?} | ${total_time}s | ${avg}s | $date |")
done

if $JSON_MODE; then
    # Output JSON
    echo "{"
    echo "  \"generated\": \"$(date -Iseconds)\","
    echo "  \"results\": ["
    for i in "${!results_json[@]}"; do
        if [ $i -gt 0 ]; then echo ","; fi
        echo -n "    ${results_json[$i]}"
    done
    echo ""
    echo "  ]"
    echo "}"
else
    # Output markdown table
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         Model Comparison Report                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "| Runtime | Model | Passed | Score | Total Time | Avg/Test | Date |"
    echo "|---------|-------|--------|-------|------------|----------|------|"
    for row in "${results_table[@]}"; do
        echo "$row"
    done
    echo ""
    echo "Detailed results in: $RESULTS_DIR/"
    echo ""
fi
