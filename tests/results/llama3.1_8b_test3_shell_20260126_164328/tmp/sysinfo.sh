#!/bin/bash

echo hostname:
hostname -a

echo kernel version:
uname -r

echo disk usage for /: 
cdf -P /

echo top 3 memory processes:
pcs -l | head -n 3
