#!/bin/bash
# orphan_demo.sh - Demonstrating Process Forking and Orphan Reparenting in Pure Bash
# Demonstrates:
#   1. Process forking in Bash
#   2. Inspection of biological PPID via /proc/$BASHPID/status
#   3. Premature worker parent exit without calling wait
#   4. Dynamic kernel reparenting to adoptive guardian (PID 1 or Subreaper)
#   5. Synchronous supervisor coordination to ensure clean terminal output

set -e

echo "============================================================"
echo "   BASH ORPHAN REPARENTING LAB (Pure Bash & /proc)          "
echo "============================================================"

TMP_DIR=$(mktemp -d /tmp/orphan_lab.XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

CHILD_READY="${TMP_DIR}/child_ready"
CHILD_DONE="${TMP_DIR}/child_done"
CHILD_PID_FILE="${TMP_DIR}/child_pid"

SUPERVISOR_PID=$$
echo "[*] [Supervisor: ${SUPERVISOR_PID}] Initializing experiment..."

# Launch Worker Parent in background
(
    WORKER_PID=$$
    echo "[*] [Parent:     ${WORKER_PID}] Worker Parent running. Forking child..."
    
    # Spawn Child subshell
    (
        CHILD_PID=$BASHPID
        echo "${CHILD_PID}" > "${CHILD_PID_FILE}"
        
        # Read biological parent PID directly
        BIO_PPID=$(awk '/^PPid:/ {print $2}' "/proc/${CHILD_PID}/status")
        BIO_NAME=$(cat "/proc/${BIO_PPID}/comm" 2>/dev/null || echo "bash")
        
        echo "[+] [Child:      ${CHILD_PID}] Child running! Biological Parent PPID: ${BIO_PPID} ('${BIO_NAME}')"
        
        # Signal Worker Parent that Child has recorded biological parent
        touch "${CHILD_READY}"
        
        echo "[+] [Child:      ${CHILD_PID}] Waiting for biological parent (${BIO_PPID}) to exit..."
        while [ -d "/proc/${BIO_PPID}" ]; do
            sleep 0.05
        done
        
        # Brief pause for kernel reparenting to complete
        sleep 0.2
        
        # Query new adoptive parent PID from kernel
        ADOPTIVE_PPID=$(awk '/^PPid:/ {print $2}' "/proc/${CHILD_PID}/status")
        GUARDIAN_NAME=$(cat "/proc/${ADOPTIVE_PPID}/comm" 2>/dev/null || echo "guardian")
        
        echo "------------------------------------------------------------"
        echo "[!] [Child:      ${CHILD_PID}] Biological parent terminated! Querying kernel for new PPID..."
        echo "[!] [Child:      ${CHILD_PID}] Adoptive Parent PPID: ${ADOPTIVE_PPID}"
        echo "[!] [Child:      ${CHILD_PID}] Guardian Name: '${GUARDIAN_NAME}' (PID: ${ADOPTIVE_PPID})"
        echo "============================================================"
        touch "${CHILD_DONE}"
    ) &
    
    CHILD_JOB_PID=$!
    
    # Wait until Child signals that it is ready and recorded BIO_PPID
    while [ ! -f "${CHILD_READY}" ]; do
        sleep 0.02
    done
    
    echo "[+] [Parent:     ${WORKER_PID}] Child is ready (PID: ${CHILD_JOB_PID})."
    echo "[+] [Parent:     ${WORKER_PID}] Parent exiting now without waiting for Child!"
    echo "[+] [Parent:     ${WORKER_PID}] Child ${CHILD_JOB_PID} is now an orphan."
    exit 0
) &

PARENT_JOB_PID=$!
wait "${PARENT_JOB_PID}" 2>/dev/null || true
echo "[*] [Supervisor: ${SUPERVISOR_PID}] Observed Worker Parent (PID ${PARENT_JOB_PID}) exit."

# Wait for Child to complete its demonstration
while [ ! -f "${CHILD_DONE}" ]; do
    sleep 0.05
done

echo "[*] [Supervisor: ${SUPERVISOR_PID}] Experiment completed successfully."
