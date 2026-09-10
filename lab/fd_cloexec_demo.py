#!/usr/bin/env python3
"""
fd_cloexec_demo.py - Demonstrating File Descriptor survival across execve()
"""
import os
import sys

def main():
    print("==================================================")
    print("   FILE DESCRIPTOR INHERITANCE ACROSS EXECVE()    ")
    print("==================================================")

    # 1. Open a file WITHOUT O_CLOEXEC (inheritable)
    fd_leaked = os.open("/tmp/leaked_secret.txt", os.O_CREAT | os.O_RDWR)
    os.set_inheritable(fd_leaked, True)

    # 2. Open a file WITH O_CLOEXEC (not inheritable)
    fd_cloexec = os.open("/tmp/closed_secret.txt", os.O_CREAT | os.O_RDWR)
    os.set_inheritable(fd_cloexec, False)

    print(f"Parent process PID: {os.getpid()}")
    print(f"FD {fd_leaked} -> /tmp/leaked_secret.txt (Inheritable: {os.get_inheritable(fd_leaked)})")
    print(f"FD {fd_cloexec} -> /tmp/closed_secret.txt (Inheritable: {os.get_inheritable(fd_cloexec)})")
    print("\nCalling os.execve() to replace memory with '/bin/ls -l /proc/self/fd'...")
    sys.stdout.flush()

    # Replace current process memory with ls
    os.execv("/bin/ls", ["ls", "-l", "/proc/self/fd"])

if __name__ == "__main__":
    main()
