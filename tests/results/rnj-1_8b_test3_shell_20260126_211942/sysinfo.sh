#!/bin/bash
echo "Hostname: " $(hostname)
echo "Kernel: " $(uname -r)
echo "Disk usage (/):
" df -h /
echo "Top 3 memory-consuming processes:
" ps aux --sort=-%mem | head -n 4
