#!/usr/bin/env python3
"""
orphan_demo.py - Process Creation, Forking, and Orphan Reparenting in Python
"""
import os
import sys
import time

def main():
    parent_pid = os.getpid()
    print("=" * 65)
    print(f"[*] [Parent: {parent_pid}] Starting process lifecycle experiment")
    print(f"[*] [Parent: {parent_pid}] Calling os.fork()...")
    print("=" * 65)
    sys.stdout.flush()

    pid = os.fork()

    if pid > 0:
        # --- PARENT PROCESS ---
        print(f"[+] [Parent: {parent_pid}] fork() returned Child PID: {pid}")
        print(f"[+] [Parent: {parent_pid}] Parent will terminate now without calling wait().")
        print(f"[+] [Parent: {parent_pid}] Child {pid} is now an orphan!")
        sys.stdout.flush()
        sys.exit(0)
    else:
        # --- CHILD PROCESS ---
        child_pid = os.getpid()
        initial_ppid = os.getppid()
        print(f"[+] [Child:  {child_pid}] Child process running!")
        print(f"[+] [Child:  {child_pid}] Initial PPID (Biological Parent): {initial_ppid}")
        print(f"[+] [Child:  {child_pid}] Sleeping 2 seconds to ensure parent terminates first...")
        sys.stdout.flush()
        
        time.sleep(2)
        
        reparented_ppid = os.getppid()
        print("-" * 65)
        print(f"[!] [Child:  {child_pid}] Child awoke! Querying kernel for current PPID...")
        print(f"[!] [Child:  {child_pid}] New PPID (Adoptive Parent): {reparented_ppid}")
        
        try:
            with open(f"/proc/{reparented_ppid}/comm", "r") as f:
                guardian_name = f.read().strip()
            print(f"[!] [Child:  {child_pid}] Guardian Name: '{guardian_name}' (PID: {reparented_ppid})")
        except Exception:
            pass
        print("=" * 65)
        sys.stdout.flush()

if __name__ == "__main__":
    main()
