#!/bin/bash
echo "Hostname: $(hostname)"
echo "Kernel Version: $(uname -r)"
echo "Disk Usage for /:";
df -h /
echo "Top 3 Memory Processes:";
ps aux --sort=-%mem | head -n 5
