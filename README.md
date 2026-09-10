# Linux Process Fundamentals & Lifecycle (Day 1)

[![Linux](https://img.shields.io/badge/Linux-Kernel%20Internals-orange.svg)](https://kernel.org)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://gnu.org/software/bash)
[![Python](https://img.shields.io/badge/Language-Python%203-blue.svg)](https://python.org)
[![Architecture](https://img.shields.io/badge/Architecture-x86__64-purple.svg)]()

A comprehensive, production-grade technical deep-dive and hands-on lab exploring Linux process lifecycles, memory isolation, `fork()` and `execve()` mechanics, container PID 1 implications, and SRE best practices.

---

## 📖 Primary Documentation

👉 **Read the full study guide and engineering analysis:**  
**[`day-01-linux-processes.md`](./day-01-linux-processes.md)**

---

## 🔬 Hands-On Lab Experiments

The [`lab/`](./lab) directory contains runnable scripts demonstrating these concepts:

| Script | Language | Description |
| :--- | :--- | :--- |
| **[`lab/inspect_proc.sh`](./lab/inspect_proc.sh)** | Bash | Direct inspection of `/proc` virtual filesystem (`cmdline`, `status`, `fd`, `maps`). |
| **[`lab/orphan_demo.py`](./lab/orphan_demo.py)** | Python 3 | Demonstrates `os.fork()`, parent PID reporting, premature parent exit, and dynamic orphan adoption by PID 1 / subreaper. |
| **[`lab/fd_cloexec_demo.py`](./lab/fd_cloexec_demo.py)** | Python 3 | Proves file descriptor inheritance across `execve()` and verifies `O_CLOEXEC` closure semantics. |
| **[`lab/orphan_demo.sh`](./lab/orphan_demo.sh)** | Bash | Pure Bash implementation of background process orphan creation and PPID inspection. |

### Running the Labs
```bash
# Make scripts executable
chmod +x lab/*.sh lab/*.py

# Run /proc inspection lab
./lab/inspect_proc.sh

# Run orphan reparenting lab
python3 lab/orphan_demo.py

# Run FD inheritance & O_CLOEXEC lab
python3 lab/fd_cloexec_demo.py
```

---

## 🚀 Key Topics Covered
- **Program vs. Process:** Static disk executable vs. dynamic virtual memory execution instance.
- **Kernel Accounting:** `task_struct`, PIDs, PPIDs, UIDs, and file descriptor tables.
- **CPU Scheduling:** CFS and modern EEVDF (Linux 6.6+) as the kernel's traffic police.
- **Memory Isolation:** Virtual Address Space (VAS) and hardware MMU page translation.
- **Process Creation Lifecycle:** The Bash execution loop (`fork` $\to$ `execve` $\to$ `wait` $\to$ `exit`).
- **PID 1 & Init:** Orphan reparenting and legal guardianship.
- **SRE & Production Impact:** Container PID 1 zombie leaks, host PID exhaustion, and signal forwarding solutions (`tini`, `dumb-init`).
- **Gotchas & Edge Cases:** `sudo kill -9 1` kernel immunity, `O_CLOEXEC` file descriptor leaks, and Orphan vs. Zombie comparisons.
