#!/usr/bin/env python3
"""
orphan_demo.py - Process Creation, Forking, and Orphan Reparenting in Python
Demonstrates:
  1. Process creation via os.fork()
  2. Fork return values (Child PID to parent, 0 to child)
  3. Premature parent termination leaving the child orphaned
  4. Automatic kernel reparenting to adoptive guardian (PID 1 or Subreaper)
  5. Synchronous supervisor coordination to ensure clean terminal output
"""
import os
import sys
import time

def read_kernel_ppid(pid: int) -> int:
    """Read true PPid directly from kernel via /proc/<pid>/status."""
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (FileNotFoundError, IndexError, ValueError):
        pass
    return os.getppid()

def read_comm_name(pid: int) -> str:
    """Read process name directly from /proc/<pid>/comm."""
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError):
        return "system/guardian"

def run_experiment():
    supervisor_pid = os.getpid()
    print("=" * 65)
    print(f"[*] [Supervisor: {supervisor_pid}] Starting process lifecycle experiment")
    print("=" * 65)
    sys.stdout.flush()

    # Pipe for synchronizing Child PID to Supervisor
    r_pipe, w_pipe = os.pipe()

    # Step 1: Supervisor forks Parent Worker
    parent_worker_pid = os.fork()

    if parent_worker_pid == 0:
        # Inside Worker Parent
        os.close(r_pipe)
        p_pid = os.getpid()
        print(f"[*] [Parent:     {p_pid}] Worker Parent running. Calling os.fork() to spawn child...")
        sys.stdout.flush()

        child_pid = os.fork()

        if child_pid == 0:
            # Inside Child
            c_pid = os.getpid()
            bio_ppid = os.getppid()
            bio_name = read_comm_name(bio_ppid)
            print(f"[+] [Child:      {c_pid}] Child created! Biological Parent PPID: {bio_ppid} ('{bio_name}')")
            sys.stdout.flush()

            # Pass child PID to supervisor
            os.write(w_pipe, f"{c_pid}\n".encode())
            os.close(w_pipe)

            # Wait for biological parent to terminate
            print(f"[+] [Child:      {c_pid}] Waiting for Biological Parent ({bio_ppid}) to terminate...")
            sys.stdout.flush()
            while os.path.exists(f"/proc/{bio_ppid}"):
                time.sleep(0.05)

            # Allow kernel reparenting lock to settle
            time.sleep(0.2)

            adoptive_ppid = os.getppid()
            adoptive_name = read_comm_name(adoptive_ppid)
            print("-" * 65)
            print(f"[!] [Child:      {c_pid}] Biological Parent died! Querying kernel for new PPID...")
            print(f"[!] [Child:      {c_pid}] Adoptive Parent PPID: {adoptive_ppid}")
            print(f"[!] [Child:      {c_pid}] Guardian Name: '{adoptive_name}' (PID: {adoptive_ppid})")
            print("=" * 65)
            sys.stdout.flush()
            sys.exit(0)
        else:
            # Inside Worker Parent: exit immediately without waiting for Child
            print(f"[+] [Parent:     {p_pid}] fork() returned Child PID: {child_pid}")
            print(f"[+] [Parent:     {p_pid}] Parent will now EXIT IMMEDIATELY without calling wait().")
            print(f"[+] [Parent:     {p_pid}] Child {child_pid} is now an orphan!")
            sys.stdout.flush()
            sys.exit(0)

    # Inside Supervisor:
    os.close(w_pipe)
    # Wait for Parent Worker to exit
    _, status = os.waitpid(parent_worker_pid, 0)
    print(f"[*] [Supervisor: {supervisor_pid}] Observed Worker Parent {parent_worker_pid} exit cleanly.")
    sys.stdout.flush()

    # Read child PID from pipe
    child_line = os.read(r_pipe, 128).decode().strip()
    os.close(r_pipe)

    if child_line:
        child_pid = int(child_line)
        # Wait for orphan child to finish execution before returning shell prompt
        while os.path.exists(f"/proc/{child_pid}"):
            time.sleep(0.05)

    print(f"[*] [Supervisor: {supervisor_pid}] Experiment completed successfully.")

if __name__ == "__main__":
    run_experiment()
