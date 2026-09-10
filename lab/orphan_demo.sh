#!/bin/bash
# orphan_demo.sh - Demonstrating Process Forking and Orphan Reparenting in Bash

echo "============================================================"
echo "[+] [Parent] Launching Parent Script (PID: $$)"
echo "============================================================"

# Spawn a background child process that outlives the parent
(
    child_pid=$BASHPID
    parent_pid=$PPID
    echo "[*] [Child] Spawned with PID: ${child_pid}"
    echo "[*] [Child] Initial PPID (Parent): ${parent_pid}"
    echo "[*] [Child] Sleeping for 2 seconds to let parent terminate..."
    sleep 2
    
    reparented_ppid=$PPID
    echo "------------------------------------------------------------"
    echo "[!] [Child] Woke up! Still running with PID: ${child_pid}"
    echo "[!] [Child] Reparented PPID: ${reparented_ppid}"
    
    # Identify the adoptive parent
    if [ -f "/proc/${reparented_ppid}/comm" ]; then
        guardian=$(cat "/proc/${reparented_ppid}/comm")
        echo "[!] [Child] Adoptive Guardian Name: '${guardian}' (PID: ${reparented_ppid})"
    fi
    echo "============================================================"
) &

CHILD_BG_PID=$!
echo "[+] [Parent] Spawned background child with job PID: ${CHILD_BG_PID}"
echo "[+] [Parent] Parent (PID: $$) is now exiting immediately without waiting."
exit 0
