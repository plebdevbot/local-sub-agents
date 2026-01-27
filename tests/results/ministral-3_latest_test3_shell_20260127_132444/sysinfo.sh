#!/bin/bash

# Display hostname and kernel version
echo "Hostname and Kernel Version:"
echo "Hostname: $(hostname)"
echo "Kernel Version: $(uname -r)"
echo "----------------------------------------"

# Display disk usage for /
echo "Disk Usage for /:"
df -h / | awk 'NR==2'
echo "----------------------------------------"

# Display top 3 memory processes
echo "Top 3 Memory Processes:"
ps aux --sort=-%mem | head -n 4
