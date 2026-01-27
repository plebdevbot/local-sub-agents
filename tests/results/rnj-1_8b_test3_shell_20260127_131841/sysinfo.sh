#!/bin/bash
echo "Hostname: " $(hostname)
echo "Kernel version: " $(uname -r)
echo "Disk usage for /: "
df -h / | tail -n 1
echo "Top 3 memory-consuming processes:"
ps aux --sort=-%mem | head -n 4
