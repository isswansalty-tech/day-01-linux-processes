#!/bin/bash
# inspect_proc.sh - Lab: Inspecting Linux Process Anatomy via /proc

echo "=========================================="
echo "   PROCESS INSPECTION LAB (PID: $$)       "
echo "=========================================="

echo -e "\n[1] Command Line (/proc/$$/cmdline):"
cat /proc/$$/cmdline | tr '\0' ' '
echo ""

echo -e "\n[2] Key Process Attributes (/proc/$$/status):"
grep -E '^(Name|State|Tgid|Pid|PPid|Uid|Gid|FDSize|VmSize|VmRSS|Threads):' /proc/$$/status

echo -e "\n[3] Open File Descriptors (/proc/$$/fd):"
ls -la /proc/$$/fd

echo -e "\n[4] Process Memory Mapping summary (/proc/$$/maps - first 5 lines):"
head -n 5 /proc/$$/maps
