#!/bin/bash
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Disk usage for /:"
df -h / | tail -n 1
echo "Top 3 memory-consuming processes:"
pidof -x "" | xargs -n1 stat -c "%d" | sort -nr | head -n 3 | xargs -I{} ps -p {} -o comm=
