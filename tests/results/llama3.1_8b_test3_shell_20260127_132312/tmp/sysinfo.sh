#!/bin/bash
hostname
uname -a
df -h /
ps -eo pid,cmd --sort=-%mem | head -3
