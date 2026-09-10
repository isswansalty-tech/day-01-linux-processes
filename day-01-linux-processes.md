# Day 1: Linux Process Fundamentals & Lifecycle

> **Portfolio Documentation & Systems Engineering Deep Dive**  
> *Author:* abir ([isswansalty-tech](https://github.com/isswansalty-tech))  
> *Topic:* Linux Kernel Internals, Process Lifecycles, Memory Isolation, and SRE Best Practices

---

## Table of Contents
1. [Core Conceptual Architecture: Program vs. Process](#1-core-conceptual-architecture-program-vs-process)
2. [Process Anatomy & Kernel Accounting](#2-process-anatomy--kernel-accounting)
3. [CPU Scheduling & Memory Management: The Illusion of Isolation](#3-cpu-scheduling--memory-management-the-illusion-of-isolation)
4. [Process Creation & Transformation: `fork()` and `execve()`](#4-process-creation--transformation-fork-and-execve)
5. [Visual Process Lifecycle Flowchart](#5-visual-process-lifecycle-flowchart)
6. [PID 1: The Root Guardian & Orphan Management](#6-pid-1-the-root-guardian--orphan-management)
7. [Production & SRE Context: Containers, PID 1, and Host Exhaustion](#7-production--sre-context-containers-pid-1-and-host-exhaustion)
8. [Critical Gotchas & Systems Edge Cases](#8-critical-gotchas--systems-edge-cases)
9. [Hands-On Terminal Lab & Proof of Work](#9-hands-on-terminal-lab--proof-of-work)
10. [Systems Engineer Reference & Cheat Sheet](#10-systems-engineer-reference--cheat-sheet)

---

## 1. Core Conceptual Architecture: Program vs. Process

At the foundation of operating systems lies a critical distinction between static code resting on non-volatile storage and active computation executing within memory.

```
+-------------------------------------------------------------+
|                      STORAGE DISK                           |
|  +-------------------------------------------------------+  |
|  |  Executable File (e.g. /usr/bin/bash, binary.exe)     |  |
|  |  - Compiled Machine Code (.text)                      |  |
|  |  - Initialized Data (.data)                           |  |
|  |  - ELF Headers & Symbols                              |  |
|  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
                              |
                     [ Kernel Loader: execve() ]
                              v
+-------------------------------------------------------------+
|                     SYSTEM MEMORY (RAM)                     |
|                                                             |
|  Process Instance A (PID 1042)    Process Instance B (PID 1043)
|  +--------------------------+     +--------------------------+
|  | Code / Text Segment      |     | Code / Text Segment      |
|  | Heap (Dynamic Alloc)     |     | Heap (Dynamic Alloc)     |
|  | Stack (Local Frames)     |     | Stack (Local Frames)     |
|  | File Descriptors [0,1,2] |     | File Descriptors [0,1,2] |
|  +--------------------------+     +--------------------------+
+-------------------------------------------------------------+
```

### The Program: Static Inanimate Blueprint
- A **Program** is a passive sequence of instructions and static data stored as a file on disk (an executable binary such as an ELF on Linux or `.exe` on Windows).
- It consumes disk space, not CPU or RAM.
- It defines *what* computation should occur, but it is not currently computing anything.

### The Process: Dynamic Living Instance
- A **Process** is a live execution of a program loaded into memory.
- It possesses state: an instruction pointer (Program Counter), CPU register states, a private virtual memory footprint, open file descriptors, network sockets, security credentials, and signal handlers.
- **One Program $\to$ Multiple Processes:** A single program file on disk (such as `/usr/bin/bash` or `/usr/bin/python3`) can instantiate dozens of independent processes concurrently.
- **PID Uniqueness & Recycling:** Each process is assigned a unique positive integer known as its **Process Identifier (PID)**. When a process terminates and its exit status is reaped, its PID is released back into the kernel's PID pool for eventual reuse.

---

## 2. Process Anatomy & Kernel Accounting

A process does not exist in isolation; the Linux kernel tracks and manages every active entity via an internal data structure called the **Process Control Block (PCB)**, represented in kernel source by `struct task_struct` (defined in `include/linux/sched.h`).

For every live process, the kernel meticulously maintains:

| Attribute | Internal Kernel Meaning | Real-World Inspection Point |
| :--- | :--- | :--- |
| **PID & PPID** | Process ID and Parent Process ID. Every process (except PID 0) has a parent. | `/proc/<PID>/status` (`Pid:`, `PPid:`) |
| **Credentials** | Real UID/GID, Effective UID/GID (for permissions), Saved UID/GID. | `/proc/<PID>/status` (`Uid:`, `Gid:`) |
| **Virtual Memory** | Memory descriptor (`struct mm_struct`) pointing to page tables and address mappings. | `/proc/<PID>/maps`, `/proc/<PID>/smaps` |
| **File Descriptors (FD)** | Table of open files, sockets, pipes, and devices (`struct files_struct`). | `/proc/<PID>/fd/` |
| **Execution State** | Current scheduling state (`R` Running, `S` Interruptible Sleep, `D` Disk Sleep, `Z` Zombie). | `/proc/<PID>/stat` |
| **Signal Dispositions** | Pending signals, blocked masks, and registered custom signal handlers. | `/proc/<PID>/status` (`SigCgt:`, `SigIgn:`) |

---

## 3. CPU Scheduling & Memory Management: The Illusion of Isolation

Two core abstractions allow thousands of competing processes to coexist predictably on physical hardware: **Scheduling** and **Virtual Memory**.

### The CPU Scheduler: The Kernel's Traffic Police
Modern multi-core systems frequently run hundreds or thousands of threads with only 8, 16, or 64 physical CPU cores available. 

- **The Role:** The Linux CPU scheduler functions exactly like an ultra-fast **traffic police officer**. It constantly monitors the runqueue, determines which process gains access to a CPU core, decides precisely which core it lands on, and calculates how many milliseconds (or nanoseconds) it may execute before being preempted.
- **Fairness & Urgency:** The scheduler prioritizes execution based on dynamic priority, latency sensitivity, and niceness values.
- **Evolution (CFS to EEVDF):** For over a decade, Linux relied on the **CFS (Completely Fair Scheduler)**, which utilized a red-black tree indexed by virtual runtime (`vruntime`) to guarantee fair CPU time. Starting with **Linux kernel 6.6**, Linux introduced **EEVDF (Earliest Eligible Virtual Deadline First)**. EEVDF improves upon CFS by scheduling tasks based on both eligibility (fair allocation) and latency deadlines, ensuring that interactive and latency-critical processes are not delayed behind throughput-heavy background batch jobs.

### Virtual Address Space: The Isolation Illusion
A user space process **never communicates directly with your physical RAM chips**.

```
+-----------------------------+         +-----------------------------+
|    Process A (PID 101)      |         |    Process B (PID 102)      |
| Virtual Address Space (VAS) |         | Virtual Address Space (VAS) |
|   0x00007fff8000 (Virtual)  |         |   0x00007fff8000 (Virtual)  |
+--------------+--------------+         +--------------+--------------+
               |                                       |
               |  [ MMU: Hardware Page Translation ]   |
               +-------------------+   +---------------+
                                   |   |
                                   v   v
                 +-----------------------------------+
                 |         PHYSICAL RAM (DDR5)       |
                 |  Frame 0x1A400 (Process A Page)   |
                 |  Frame 0x8F200 (Process B Page)   |
                 +-----------------------------------+
```

- **The Private Universe:** The kernel provides each process with its own separate **Virtual Address Space (VAS)**. To Process A, it appears as though it owns a contiguous, multi-terabyte block of memory all to itself (e.g., up to 128 TB of user-space addresses in standard 48-bit x86_64 architecture).
- **Hardware-Enforced Translation:** The CPU's hardware **Memory Management Unit (MMU)** works in tandem with kernel page tables to secretly translate these virtual memory addresses into discrete physical RAM frames.
- **Absolute Memory Protection:** Even if Process A and Process B use identical virtual addresses (e.g., `0x00007fff8000`), the MMU translates them to completely different physical RAM frames. A non-privileged process is strictly incapable of reading, corrupting, or modifying the memory of another process or the kernel.

---

## 4. Process Creation & Transformation: `fork()` and `execve()`

Processes in Unix-like operating systems do not materialize out of thin air. With the exception of `swapper` (PID 0) and `init` (PID 1) during machine boot, every single process is created through a standardized two-step lifecycle: **Cloning (`fork`)** followed by **Transformation (`execve`)**.

### The Shell Execution Loop: Bash Cloning Itself
When an engineer types a command into an interactive shell (e.g., `ls -l` in Bash):

1. **Bash clones itself (`fork`):** Bash issues the `fork()` system call. The operating system creates an exact twin copy of the Bash process.
2. **The Parent Waits:** The parent Bash process yields the CPU, calling `wait()` or `waitpid()`. It enters an interruptible sleep state (`TASK_INTERRUPTIBLE`), pausing until the child terminates.
3. **The Child Wipes its Brain (`execve`):** The cloned child Bash process executes `execve("/usr/bin/ls", ...)`. It completely wipes out its inherited Bash code, data, and memory structures, loading the `/usr/bin/ls` binary into its address space.
4. **Execution & Exit:** The newly loaded `ls` command runs, writes directory listings to stdout, and exits with a status code (e.g., `0`).
5. **Wakeup & Reap:** The parent Bash process receives a `SIGCHLD` signal from the kernel, wakes up from `wait()`, harvests the child's exit code, reaps its entry from the process table, and presents a fresh shell prompt to the user.

```
       [ Parent: bash (PID 4000) ]
                    |
                    | calls fork()
                    v
  +-----------------+-----------------+
  |                                   |
  | returns PID 4001                  | returns 0
  v                                   v
[ Parent: bash (PID 4000) ]         [ Child: bash clone (PID 4001) ]
  |                                   |
  | calls wait()                      | calls execve("/usr/bin/ls")
  | [ Enters Sleeping State ]         | [ Memory Wiped & Binary Loaded ]
  |                                   v
  |                                 [ Program: /bin/ls (PID 4001) ]
  |                                   |
  |                                   | runs & finishes
  |                                   | calls exit(0)
  |                                   v
  |                                 [ Zombie State (PID 4001) ]
  |                                   |
  | receives SIGCHLD                  |
  +<----------------------------------+
  |
  | reaps exit code (0)
  v
[ Parent: bash (PID 4000) ]
(Displays next command prompt)
```

### Deep Dive: `fork()`
- **Dual Return Values:** `fork()` is unique because it is called once, but **returns twice**:
  - In the **Parent Process**, `fork()` returns the **PID of the newly created child** (a positive integer, e.g., `3721`). This allows the parent to track, monitor, or signal its offspring.
  - In the **Child Process**, `fork()` returns **`0`**. This allows the process code to easily determine: *"I am the child; I must proceed with child duties or call execve."*
  - If process creation fails (e.g., system PID limit reached), it returns `-1` to the parent.
- **Copy-On-Write (COW):** Modern Linux does not physically copy all of the parent's RAM pages during `fork()`. Doing so would make spawning processes painfully slow. Instead, the kernel duplicates the page table entries and marks all memory pages as **read-only**. Only when either the parent or child attempts to *write* to a page does the MMU trigger a page fault, prompting the kernel to allocate and copy that specific 4 KB page.

### Deep Dive: `execve()`
- **System Call Signature:**
  ```c
  int execve(const char *pathname, char *const argv[], char *const envp[]);
  ```
- **What `execve()` Does:**
  - Deallocates and wipes the calling process's current code, data, heap, and stack segments.
  - Loads the newly specified ELF executable binary into the address space.
  - Sets the instruction pointer to the new program entry point (`main()`).
  - **CRITICAL:** `execve()` does **NOT** create a new process. The PID and PPID remain completely unchanged!
- **What Survives `execve()`:**
  - **Open File Descriptors:** File descriptors remain open and valid across `execve()` unless explicitly marked with the `O_CLOEXEC` flag (or `FD_CLOEXEC`).
  - **Environment Variables:** The `envp` array is passed to the new program image.
  - **Process Identity:** PID, PPID, real/effective UID/GID, session ID, and working directory persist across the execution boundary.

---

## 5. Visual Process Lifecycle Flowchart

The following Mermaid diagram maps the comprehensive state machine and system call orchestration across the entire execution loop:

```mermaid
flowchart TD
    subgraph Shell_Execution_Loop ["Linux Process Lifecycle Loop"]
        A["Parent Process: Bash<br><code>PID: 4000</code>"] -->|"1. User enters command<br>calls fork()"| B{"Kernel Syscall: fork()"}
        
        %% Fork branches
        B -->|"Returns Child PID (4001)"| C["Parent enters wait()<br><code>State: S (TASK_INTERRUPTIBLE)</code>"]
        B -->|"Returns 0"| D["Child Process Clone<br><code>PID: 4001 (Identical Memory)</code>"]
        
        %% Execve transition
        D -->|"2. Child calls execve('/usr/bin/ls')"| E["Kernel Memory Wipe<br><i>Code, Stack, Heap replaced</i><br><b>PID 4001 preserved</b>"]
        E -->|"3. Binary loaded & starts"| F["Executable Running: ls<br><code>State: R (TASK_RUNNING)</code>"]
        
        %% Execution and exit
        F -->|"4. Program finishes execution"| G["calls exit(status_code)"]
        G -->|"5. Kernel deallocates memory"| H["Child Enters Zombie State<br><code>State: Z (EXIT_ZOMBIE)</code><br><i>Keeps PCB, PID & exit status</i>"]
        
        %% Signal & Reap
        H -.->|"6. Kernel sends SIGCHLD"| C
        C -->|"7. Parent wakes up<br>harvests exit status"| I["Kernel Clears PCB & Frees PID 4001"]
        I -->|"8. Shell displays prompt"| A
    end

    classDef active fill:#1e3a8a,stroke:#3b82f6,stroke-width:2px,color:#ffffff;
    classDef kernel fill:#701a75,stroke:#d946ef,stroke-width:2px,color:#ffffff;
    classDef waiting fill:#854d0e,stroke:#eab308,stroke-width:2px,color:#ffffff;
    classDef dead fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,color:#ffffff;

    class A,D,F active;
    class B,E,I kernel;
    class C waiting;
    class G,H dead;
```

---

## 6. PID 1: The Root Guardian & Orphan Management

When a Linux machine boots, the kernel mounts the root filesystem and directly executes the initial user-space program at `/sbin/init` (in modern distributions, a symlink to `systemd`). This process becomes **PID 1**.

```
                           [ Kernel Boot ]
                                  |
                                  v
                        [ PID 1: /sbin/init ]
                           (systemd init)
                                  |
                +-----------------+-----------------+
                |                                   |
                v                                   v
       [ sshd.service ]                    [ dbus.service ]
                |
                v
       [ bash (PID 2100) ]
                |
                v (parent dies!)
       [ orphan (PID 2150) ] ---------> (Reparented to PID 1 or Subreaper)
```

### The Special Nature of PID 1
PID 1 is fundamentally distinct from every other process running on the operating system:
1. **Ancestral Root:** PID 1 is the great ancestor of every user-space process on the host.
2. **Default Signal Immunity:** The Linux kernel treats signals sent to PID 1 with special handling. If PID 1 has not explicitly installed a handler for a signal, the kernel silently discards it—even fatal signals.
3. **The Orphan Adoption Agency:** In a dynamic multi-tasking OS, parent processes may crash, segfault, or be killed while their children are still actively executing. 

### Orphan Processes & Automatic Reparenting
- **What is an Orphan?** An orphan is a live, running process whose parent has terminated before the child exited.
- **Linux Does Not Kill Orphans:** Unlike some naive operating systems, Linux never terminates a child simply because its parent died. Instead, the Linux kernel detects that the child's `PPID` is now dead and **automatically reparents the orphan process**.
- **The Legal Guardian:** By default, the orphan is reparented to **PID 1** (or to the nearest designated ancestor **subreaper** defined via `prctl(PR_SET_CHILD_SUBREAPER, 1)`).
- **Why Reparenting is Essential:** When an orphan eventually finishes execution and calls `exit()`, its exit status must be read by a parent. Because PID 1 continuously runs an asynchronous event loop that handles `SIGCHLD` and calls `waitpid(-1, &status, WNOHANG)`, PID 1 immediately reaps the orphan's exit status, preventing it from remaining a permanent zombie.

---

## 7. Production & SRE Context: Containers, PID 1, and Host Exhaustion

In modern containerized environments (Docker, Podman, Kubernetes), container isolation is built using Linux **Namespaces** (PID, Mount, Network, IPC, UTS, User) and **Cgroups**.

### The Container PID 1 Trap
When you launch a Docker container:
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY . .
CMD ["node", "server.js"]
```
Because the container runs inside a dedicated PID namespace, your application binary (`node server.js`) runs as **PID 1 of that container**!

Standard enterprise application runtimes (Node.js, Python, Java, Ruby, Go) were built to be web applications or services—**they were never engineered to be operating system init systems**. This mismatch triggers severe production failures:

```
+-------------------------------------------------------------------------+
|                  CONTAINER PID NAMESPACE (WITHOUT INIT)                 |
|                                                                         |
|  [ PID 1: node server.js ]  <-- Does NOT reap zombies, ignores SIGTERM  |
|         |                                                               |
|         +-- Spawns worker script (PID 12)                               |
|                  |                                                      |
|                  +-- Spawns ffmpeg/child (PID 18)                       |
|                           | (worker PID 12 crashes!)                    |
|                           v                                             |
|              [ Orphan PID 18 reparents to PID 1 ]                       |
|                           |                                             |
|                           v (PID 18 exits)                              |
|              [ Zombie PID 18: <defunct> ]                               |
|              [ Zombie PID 19: <defunct> ]  --> PERMANENT LEAK!          |
|              [ Zombie PID 20: <defunct> ]                               |
+-------------------------------------------------------------------------+
                                    |
            [ Leaks PIDs into Host Kernel PID Table ]
                                    v
          HOST OUTAGE: "fork: Resource temporarily unavailable"
```

### Problem 1: Zombie Leaks & Host PID Exhaustion
- If your containerized application spawns child processes (e.g., executing shell commands, image resizing utilities, or database dump tools) and those workers crash or orphan, the orphaned processes reparent to **PID 1 inside the container** (`node`).
- Node.js does not run a background `waitpid(-1)` reap loop. 
- When those orphaned children finish, they enter the `Z` (Zombie) state and remain stuck in the kernel's process table forever.
- **The Catastrophic Host Outage:** While container memory or CPU may appear normal, each zombie consumes an entry in the Linux kernel's global process table. Linux limits maximum system PIDs via `/proc/sys/kernel/pid_max` (typically 32,768 or 4,194,304). As zombies accumulate inside unmonitored containers, the host kernel reaches its PID exhaustion ceiling. When that happens, **the entire host stops functioning**: no new SSH connections can be opened, monitoring agents crash, Kubernetes nodes become `NotReady`, and any `fork()` across the entire physical server fails with `EAGAIN: Resource temporarily unavailable`.

### Problem 2: Signal Handling & Graceful Shutdown Failure
- Under Linux signal semantics, PID 1 does not receive default signal handlers.
- When an engineer or Kubernetes issues `docker stop <container>` or deletes a Pod, the container runtime sends **`SIGTERM` (signal 15)** to PID 1, granting it 10 seconds (by default) to drain active HTTP connections, commit transactions, and flush buffers.
- If your app running as PID 1 has not explicitly registered a signal listener for `SIGTERM`, the kernel drops the signal entirely. Your application completely ignores the shutdown request!
- After 10 seconds, Docker times out and issues a brutal **`SIGKILL` (signal 9)**. Your application is killed instantly, severing customer database transactions, corrupting write caches, and leaving external state broken.

### The Production SRE Solution: Init Wrappers
To resolve this, SRE and production engineering best practices require placing a lightweight init wrapper as PID 1:

1. **Docker Native Init Flag:** Pass `--init` to `docker run`:
   ```bash
   docker run --init -d -p 8080:8080 my-web-app:latest
   ```
2. **`tini` (Lightweight Init for Containers):**
   ```dockerfile
   # Add Tini to your Dockerfile
   ENV TINI_VERSION v0.19.0
   ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
   RUN chmod +x /tini
   ENTRYPOINT ["/tini", "--"]
   CMD ["node", "server.js"]
   ```
3. **`dumb-init` (Yelp's Container Init):**
   ```dockerfile
   RUN apt-get update && apt-get install -y dumb-init
   ENTRYPOINT ["/usr/bin/dumb-init", "--"]
   CMD ["python3", "app.py"]
   ```

**What Init Wrappers Guarantee in Production:**
- **Proper Signal Forwarding:** When `SIGTERM` arrives, the wrapper forwards it to the entire process group, allowing worker processes to shut down gracefully.
- **Asynchronous Zombie Reaping:** The wrapper registers a `SIGCHLD` handler that continuously calls `waitpid(-1, &status, WNOHANG)`, instantly reaping any orphaned child processes.

---

## 8. Critical Gotchas & Systems Edge Cases

Systems interviews, production outages, and security audits frequently hinge on understanding these three subtle Unix nuances:

### Gotcha 1: `sudo kill -9 1` Immunity
If an administrator executes:
```bash
sudo kill -9 1
```
**PID 1 does not die.** The system does not crash or reboot. Why?
- `SIGKILL` (signal 9) and `SIGSTOP` cannot be caught, blocked, or ignored by regular processes.
- However, inside the Linux kernel's signal dispatch implementation (`kernel/signal.c`), the kernel explicitly verifies whether the target process is the root `init` process (`PID == 1`).
- The kernel will **only** deliver signals to PID 1 for which PID 1 has explicitly registered a custom signal handler. Because `SIGKILL` cannot have a custom handler by definition, the kernel silently drops the `SIGKILL` request from user-space. This prevents catastrophic operating system crashes caused by rogue scripts or accidental administrator typos.

### Gotcha 2: File Descriptors Survive `execve()` Unless `O_CLOEXEC` is Set
- When a process calls `execve()`, its virtual memory (stack, heap, code) is completely wiped.
- **However, open file descriptors (FDs) are preserved across `execve()` by default!**
- **The Security & Stability Vulnerability:**
  If a privileged parent process opens a sensitive database connection, an encryption keyfile, or an administrative Unix domain socket (e.g., FD 3), and subsequently executes an untrusted or non-privileged program without closing it, the child program inherits open access to FD 3!
- **The Solution:** Always open file descriptors with the `O_CLOEXEC` flag (or toggle the `FD_CLOEXEC` descriptor flag via `fcntl`):
  ```c
  // C example ensuring file descriptor closes immediately upon execve()
  int fd = open("/etc/secure.key", O_RDONLY | O_CLOEXEC);
  ```
  ```python
  # Python 3.4+ sets O_CLOEXEC (inheritable=False) on all created file descriptors by default
  import os
  fd = os.open("/tmp/secure.dat", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC)
  ```

### Gotcha 3: Orphan Process vs. Zombie Process
Engineers often confuse orphans and zombies. They are opposite stages of the process lifecycle:

| Comparative Dimension | Orphan Process | Zombie Process (`<defunct>`, State `Z`) |
| :--- | :--- | :--- |
| **Execution State** | **Alive and actively executing.** Consuming CPU cycles and RAM. | **Dead and finished.** Execution stopped; no code is running. |
| **Memory Footprint** | Has full virtual memory space (code, heap, stack, maps). | **Zero memory.** Code, heap, and stack have been freed by kernel. |
| **Parent Status** | Biological parent is **dead**. | Parent is **alive**, but hasn't called `wait()` / `waitpid()`. |
| **Kernel Representation**| Active `task_struct` and full resource allocation. | Minimal `task_struct` entry in Process Table holding exit code. |
| **Resolution** | Kernel reparents it to PID 1 or subreaper for guardianship. | Cleared when parent calls `wait()`, or when parent dies. |
| **Can you kill it?** | Yes, via `kill <PID>` like any normal running process. | **No.** You cannot kill a zombie; it is already dead (`kill -9` does nothing). |

---

## 9. Hands-On Terminal Lab & Proof of Work

The following section contains tested, reproducible experiments performed in an authentic Linux environment (Ubuntu 26.04 LTS / Linux Kernel 6.6+).

```
================================================================================
LAB WORKSPACE OVERVIEW
Repository Directory : scratch/day-01-linux-processes/lab/
Lab Script 1         : inspect_proc.sh (Direct /proc inspection & FD tracking)
Lab Script 2         : orphan_demo.py (Forking, child PID return & reparenting)
Lab Script 3         : fd_cloexec_demo.py (FD inheritance & O_CLOEXEC verification)
================================================================================
```

### Lab 1: Direct Inspection of `/proc` Filesystem
The `/proc` virtual filesystem is the window directly into the Linux kernel's internal process tables. 

#### Reproducible Inspection Script (`inspect_proc.sh`)
```bash
#!/bin/bash
# inspect_proc.sh - Inspecting Linux Process Anatomy via /proc

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

echo -e "\n[4] Virtual Address Space Mapping (/proc/$$/maps - First 5 entries):"
head -n 5 /proc/$$/maps
```

#### Actual Terminal Execution Output
```console
$ bash lab/inspect_proc.sh
==========================================
   PROCESS INSPECTION LAB (PID: 4250)       
==========================================

[1] Command Line (/proc/4250/cmdline):
bash lab/inspect_proc.sh 

[2] Key Process Attributes (/proc/4250/status):
Name:	bash
State:	S (sleeping)
Tgid:	4250
Pid:	4250
PPid:	4249
Uid:	1000	1000	1000	1000
Gid:	1000	1000	1000	1000
FDSize:	256
VmSize:	    4948 kB
VmRSS:	    3680 kB
Threads:	1

[3] Open File Descriptors (/proc/4250/fd):
total 0
dr-x------ 2 abir abir  6 Sep 11 03:38 .
dr-xr-xr-x 9 abir abir  0 Sep 11 03:38 ..
lr-x------ 1 abir abir 64 Sep 11 03:38 0 -> pipe:[26056]
l-wx------ 1 abir abir 64 Sep 11 03:38 1 -> pipe:[26057]
l-wx------ 1 abir abir 64 Sep 11 03:38 2 -> pipe:[26058]
lrwx------ 1 abir abir 64 Sep 11 03:38 7 -> /dev/ptmx
lrwx------ 1 abir abir 64 Sep 11 03:38 10 -> /dev/ptmx
lr-x------ 1 abir abir 64 Sep 11 03:38 255 -> /mnt/c/Users/pc/.gemini/antigravity/scratch/day-01-linux-processes/lab/inspect_proc.sh

[4] Virtual Address Space Mapping (/proc/4250/maps - First 5 entries):
5dd78685f000-5dd786890000 r--p 00000000 08:30 1503                       /usr/bin/bash
5dd786890000-5dd786993000 r-xp 00031000 08:30 1503                       /usr/bin/bash
5dd786993000-5dd7869ca000 r--p 00134000 08:30 1503                       /usr/bin/bash
5dd7869ca000-5dd7869ce000 r--p 0016b000 08:30 1503                       /usr/bin/bash
5dd7869ce000-5dd7869d7000 rw-p 0016f000 08:30 1503                       /usr/bin/bash
```

---

### Lab 2: Process Creation, Forking, and Orphan Reparenting
This experiment demonstrates process cloning with `os.fork()`, observes parent PID return values, lets the parent terminate prematurely, and verifies that the Linux kernel reparents the live orphan to a guardian subreaper / PID 1.

#### Verification Script (`orphan_demo.py`)
```python
#!/usr/bin/env python3
"""
orphan_demo.py - Process Creation, Forking, and Orphan Reparenting
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
        # --- PARENT PROCESS BRANCH ---
        print(f"[+] [Parent: {parent_pid}] fork() returned Child PID: {pid}")
        print(f"[+] [Parent: {parent_pid}] Parent will terminate now without calling wait().")
        print(f"[+] [Parent: {parent_pid}] Child {pid} is now an orphan!")
        sys.stdout.flush()
        sys.exit(0)
    else:
        # --- CHILD PROCESS BRANCH ---
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
        except Exception as e:
            print(f"[!] [Child:  {child_pid}] Guardian PID {reparented_ppid}")
            
        print("=" * 65)
        sys.stdout.flush()

if __name__ == "__main__":
    main()
```

#### Actual Terminal Execution Output
```console
$ python3 lab/orphan_demo.py
=================================================================
[*] [Parent: 4345] Starting process lifecycle experiment
[*] [Parent: 4345] Calling os.fork()...
=================================================================
[+] [Parent: 4345] fork() returned Child PID: 4346
[+] [Parent: 4345] Parent will terminate now without calling wait().
[+] [Parent: 4345] Child 4346 is now an orphan!
[+] [Child:  4346] Child process running!
[+] [Child:  4346] Initial PPID (Biological Parent): 4345
[+] [Child:  4346] Sleeping 2 seconds to ensure parent terminates first...
-----------------------------------------------------------------
[!] [Child:  4346] Child awoke! Querying kernel for current PPID...
[!] [Child:  4346] New PPID (Adoptive Parent): 4337
[!] [Child:  4346] Guardian Name: 'Relay(4338)' (PID: 4337)
=================================================================
```
> **Observation:** Notice how Child `PID 4346` initially had `PPID 4345`. When Parent `4345` died, the kernel dynamically reparented the running child to the active subreaper guardian (`PID 4337`), proving the adoption mechanism in real time.

---

### Lab 3: Proving File Descriptor Survival & `O_CLOEXEC` across `execve()`
This lab verifies that file descriptors without `O_CLOEXEC` leak across an `execve()` boundary into the new binary, whereas descriptors marked with `O_CLOEXEC` are closed automatically by the kernel.

#### Verification Script (`fd_cloexec_demo.py`)
```python
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

    # 1. Open a file WITHOUT O_CLOEXEC (inheritable across execve)
    fd_leaked = os.open("/tmp/leaked_secret.txt", os.O_CREAT | os.O_RDWR)
    os.set_inheritable(fd_leaked, True)

    # 2. Open a file WITH O_CLOEXEC (not inheritable across execve)
    fd_cloexec = os.open("/tmp/closed_secret.txt", os.O_CREAT | os.O_RDWR)
    os.set_inheritable(fd_cloexec, False)

    print(f"Parent Process PID: {os.getpid()}")
    print(f"FD {fd_leaked} -> /tmp/leaked_secret.txt (Inheritable: {os.get_inheritable(fd_leaked)})")
    print(f"FD {fd_cloexec} -> /tmp/closed_secret.txt (Inheritable: {os.get_inheritable(fd_cloexec)})")
    print("\nCalling os.execve() to replace memory with '/bin/ls -l /proc/self/fd'...")
    sys.stdout.flush()

    # Replace current process memory with ls
    os.execv("/bin/ls", ["ls", "-l", "/proc/self/fd"])

if __name__ == "__main__":
    main()
```

#### Actual Terminal Execution Output
```console
$ python3 lab/fd_cloexec_demo.py
==================================================
   FILE DESCRIPTOR INHERITANCE ACROSS EXECVE()    
==================================================
Parent Process PID: 4373
FD 3 -> /tmp/leaked_secret.txt (Inheritable: True)
FD 4 -> /tmp/closed_secret.txt (Inheritable: False)

Calling os.execve() to replace memory with '/bin/ls -l /proc/self/fd'...
total 0
lr-x------ 1 abir abir 64 Sep 11 03:39 0 -> pipe:[27398]
l-wx------ 1 abir abir 64 Sep 11 03:39 1 -> pipe:[27399]
l-wx------ 1 abir abir 64 Sep 11 03:39 2 -> pipe:[27400]
lrwx------ 1 abir abir 64 Sep 11 03:39 3 -> /tmp/leaked_secret.txt
lr-x------ 1 abir abir 64 Sep 11 03:39 4 -> /proc/4373/fd
lrwx------ 1 abir abir 64 Sep 11 03:39 7 -> /dev/ptmx
lrwx------ 1 abir abir 64 Sep 11 03:39 10 -> /dev/ptmx
```
> **Proof:** When `/bin/ls` executes under PID 4373, **FD 3 remains open and pointed directly at `/tmp/leaked_secret.txt`**, demonstrating that unflagged file descriptors leak across `execve()`. Meanwhile, **FD 4 was closed automatically** by the kernel upon `execve()`, and was reused by `ls` to read the directory itself.

---

### Lab 4: Proving PID 1 Immunity against `kill -9 1`
This terminal experiment tests what happens when root attempts to kill PID 1 (`systemd`).

#### Terminal Command & Real Output
```console
$ sudo kill -9 1
$ echo "Exit Status: $?"
Exit Status: 0

$ ps -p 1 -o pid,stat,comm
    PID STAT COMMAND
      1 Ss   systemd
```
> **Proof:** Even though root issued `kill -9 1` and the syscall completed with exit code 0, `systemd` (PID 1) is still running in state `Ss`. The Linux kernel silently discarded the `SIGKILL` to protect operating system stability.

---

## 10. Systems Engineer Reference & Cheat Sheet

### Essential CLI Commands

```bash
# 1. View process tree with PIDs and ownership
pstree -p -u

# 2. Detailed process inspection showing PID, PPID, State, Command
ps -eo pid,ppid,stat,user,%cpu,%mem,comm

# 3. Locate all zombie processes currently on the host
ps -eo pid,ppid,stat,comm | grep -w 'Z'

# 4. Check system-wide maximum PID ceiling
cat /proc/sys/kernel/pid_max

# 5. Inspect open file descriptors for a specific PID
ls -la /proc/<PID>/fd/

# 6. Read command line arguments as null-delimited strings
tr '\0' ' ' < /proc/<PID>/cmdline; echo

# 7. Check memory usage and virtual address space mappings
cat /proc/<PID>/status | grep -E '^(VmSize|VmRSS|Threads):'
```

### Core System Call Summary

| Syscall | Purpose | Signature / Crucial Parameter |
| :--- | :--- | :--- |
| **`fork()`** | Clones caller process. Returns 0 to child, child PID to parent. | `pid_t fork(void);` |
| **`execve()`** | Replaces memory space with new binary without changing PID. | `int execve(const char *path, char *const argv[], char *const envp[]);` |
| **`waitpid()`** | Pauses caller until specified child process changes state / exits. | `pid_t waitpid(pid_t pid, int *status, int options);` |
| **`exit()`** | Terminates caller, yields status code, turns process into zombie until reaped. | `void exit(int status);` |
| **`prctl()`** | Configures process controls, such as registering as a child subreaper. | `prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0);` |

---

*Document created as part of the Systems & Linux Engineering Mastery Series.*
