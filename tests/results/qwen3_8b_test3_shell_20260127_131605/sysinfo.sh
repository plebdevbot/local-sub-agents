#!/bin/bash

# Hostname and kernel version
echo "Hostname: $(hostname)"
uname -r

# Disk usage for /
df -h /

# Top 3 memory processes
ps aux --sort -%mem | head -n 6
