#!/bin/bash

# Hostname and kernel version
echo "Hostname: $(hostname)"
echo "Kernel Version: $(uname -r)"

# Disk usage for /
echo "
Disk Usage for /:";
df -h /

# Top 3 memory processes
echo "
Top 3 Memory Processes:";
ps -eo %mem,cmd --sort -%mem | head -n 4
