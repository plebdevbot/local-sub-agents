#!/bin/bash

# Hostname and kernel version
echo "Hostname: $(hostname)"
echo "Kernel Version: $(uname -r)"

# Disk usage for /
echo "Disk Usage (/":
 df -h /

# Top 3 memory processes
echo "Top 3 Memory Processes":
 ps aux --sort=-%mem | head -n 6
