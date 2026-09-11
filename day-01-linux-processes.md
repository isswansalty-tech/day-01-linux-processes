# Day 1: Linux Process Fundamentals & Lifecycle

> *A deep dive into kernel internals, the Bash execution loop, and why running PID 1 in Docker breaks things in production.*  
> **Author:** abir ([@isswansalty-tech](https://github.com/isswansalty-tech))  
> **Series:** 100 Days of Systems & Linux Engineering  

---

## What We're Breaking Down Today
Ever wonder what *actually* happens under the hood when you open up a terminal, type a command like `ls` or `python app.py`, and hit `Enter`? 

Today is **Day 1** of my systems engineering deep-dive. We are cutting past the high-level fluff to inspect the actual mechanics of the Linux kernel: how processes come to life, how the kernel isolates memory, how processes transform themselves, and why understanding process lifecycles separates junior devs from senior SREs when production goes down.

Here is the game plan:
1. [The Foundation: Program vs. Process](#1-the-foundation-program-vs-process)
2. [How the Kernel Tracks Everything](#2-how-the-kernel-tracks-everything)
3. [CPU & Memory: The Great Kernel Illusion](#3-cpu--memory-the-great-kernel-illusion)
4. [Process Creation: Bash Clones Itself (`fork` + `execve`)](#4-process-creation-bash-clones-itself-fork--execve)
5. [The Execution Loop (Visualized)](#5-the-execution-loop-visualized)
6. [PID 1: The First Process & Guardian of Orphans](#6-pid-1-the-first-process--guardian-of-orphans)
7. [Production & SRE Reality: The Container PID 1 Trap](#7-production--sre-reality-the-container-pid-1-trap)
8. [Edge Cases & Interview Gotchas](#8-edge-cases--interview-gotchas)
9. [Terminal Lab: Proving It in Real Time](#9-terminal-lab-proving-it-in-real-time)

---

## 1. The Foundation: Program vs. Process

Let's start with the most fundamental mental model in systems programming:

```
[ Disk Storage ]                             [ System Memory (RAM) ]
+----------------------------+               +----------------------------+
|  Program File (.exe, ELF)  |  -- Executed --> |     Running Process        |
|  (Passive Blueprint)       |               |     (Active Instance)      |
+----------------------------+               +----------------------------+
```

### The Mental Model: *"An Instance is a Process"*
- **A Program is just dead bytes on a disk.** It's an executable file (`.exe` on Windows, or an ELF binary like `/usr/bin/bash` on Linux). It sits there taking up disk space, doing absolutely nothing until someone tells the OS to run it.
- **A Process is alive.** It is an active execution of that program loaded into memory, consuming CPU cycles, allocating heap space, and opening file descriptors.
- **1 Program $\to$ Multiple Processes:** Just like you can open five different Chrome windows or run three background Python scripts from the exact same script file, a single program on disk can have dozens of live running processes.
- **PIDs and Recycling:** Every process gets a unique numeric ID called a **PID (Process Identifier)**. PIDs aren't infinite—when a process dies and gets reaped, its PID goes back into the kernel pool to be reused later.

---

## 2. How the Kernel Tracks Everything

The Linux kernel is obsessive about bookkeeping. For every single process running on the machine, the kernel maintains an internal structure called the **Process Control Block (`struct task_struct`)**. 

Whenever a process does anything, the kernel references this struct to check:
- **PID & PPID:** Who are you (`PID`), and who created you (`PPID` — Parent PID)?
- **Credentials (UID / GID):** Which user and group own this process? What are its permissions?
- **Virtual Memory Map:** What parts of memory does this process think it owns?
- **File Descriptor Table (FDs):** What files, terminal pipes, or network sockets does it currently have open? (FD 0 is `stdin`, FD 1 is `stdout`, FD 2 is `stderr`).

---

## 3. CPU & Memory: The Great Kernel Illusion

### The Scheduler: Your CPU's Traffic Police
Your computer might have 8 or 16 CPU cores, but your system is running hundreds of processes right now. How do they all run at once?

Enter the **Linux CPU Scheduler** (historically CFS, and in modern Linux 6.6+, **EEVDF** — Earliest Eligible Virtual Deadline First). 
- Think of the scheduler as **traffic police** standing at a busy intersection.
- It decides which process gets onto which CPU core, how many milliseconds it gets to run (its timeslice), and when it needs to be kicked off so another process gets a turn.
- High-priority and urgent tasks get green-lighted first, while background batch jobs wait in line.

### Virtual Memory: The RAM Illusion
Here is a wild fact: **A process never, ever touches your physical RAM chips directly.**

Instead, the Linux kernel gives every single process its own private **Virtual Address Space (VAS)**. 
- It’s an illusion: the process genuinely believes it owns a massive, continuous block of memory all to itself (e.g., from `0x000000000000` up to `0x7FFFFFFFFFFF` on 64-bit x86).
- Behind the scenes, the kernel and the CPU's **Memory Management Unit (MMU)** work together like secret translators. They map those fake virtual addresses to scattered, real physical RAM pages.
- If Process A writes to address `0x4000`, and Process B writes to address `0x4000`, they will never overwrite each other. They map to completely different physical hardware memory. Complete isolation.

---

## 4. Process Creation: Bash Clones Itself (`fork` + `execve`)

Processes don't just appear out of thin air. In Linux, brand new processes are born through a two-step ritual: **`fork()`** followed by **`execve()`**.

```
[ Bash Shell (PID 4000) ]
        │
        ├── 1. Calls fork()
        │      └── Clones itself into an exact twin!
        │
        ├── 2. Parent Bash goes to sleep (calls wait())
        │
[ Child Bash (PID 4001) ]
        │
        └── 3. Calls execve("/bin/ls")
               └── Wipes its Bash brain, loads 'ls' binary, runs it!
```

### 1. `fork()` — The Clone
When you run a command in your terminal, the current Bash process literally **clones itself**:
- `fork()` creates an exact replica child process.
- It copies memory mappings (using **Copy-on-Write / COW**, so it doesn't waste RAM unless one of them writes to a page).
- **The Dual Return Trick:** `fork()` is famous in Unix because it is called once, but **returns twice**:
  - In the **parent**, `fork()` returns the **Child's PID** (e.g., `4001`) so the parent knows who its kid is.
  - In the **child**, `fork()` returns **`0`** so the code can say: *"Hey, I'm the child, time to do my job."*

### 2. `execve()` — The Brain Wipe
Now you have two Bash processes. But you didn't want two Bashes—you wanted to run `ls`!
- The child process calls `execve()`.
- What does `execve()` do? It **wipes the calling process's memory clean**. The Bash code, stack, and heap vanish, and the kernel loads the new program binary (`/bin/ls`) into that space.
- **Key rule:** `execve()` does **NOT** create a new process! The PID stays exactly the same (`4001`). It just swaps the clothes and brain of the existing process.
- What survives `execve()`? Environment variables and open file descriptors stay intact (unless `O_CLOEXEC` is set).

### Demystifying: *"Child returns with 0. Parent returns with 3721"*
In introductory study notes, people often write:
> *"Child returns with 0. Parent returns value with 3721."*

Let's demystify what that actually means in the kernel:
1. **Those return values belong to `fork()`, NOT `execve()`.**
2. **`execve()` NEVER returns on success.** Why? Because your original code was wiped from memory! The CPU points its instruction pointer directly at the `main()` function of the new binary. `execve()` only returns if it *fails* (like file not found, returning `-1`).
3. **The `0` at the end:** When the program finishes, it calls `exit(0)`. That `0` is the program's exit code, which the sleeping parent harvests when it wakes up.

---

## 5. The Execution Loop (Visualized)

Here is the exact lifecycle loop that happens every single time you hit `Enter` in your terminal:

```mermaid
flowchart TD
    %% Execution Loop
    ParentBash["1. Parent Process: Bash<br>[PID: 4000]"] -->|"calls fork()"| SyscallFork{"Kernel: fork()"}
    
    %% Fork Branches
    SyscallFork -->|"Returns Child PID (4001)"| ParentSleep["2. Parent Sleeps<br>calls wait() / waitpid()<br>State: S (TASK_INTERRUPTIBLE)"]
    SyscallFork -->|"Returns 0"| ChildClone["2. Child Process Clone<br>[PID: 4001, PPID: 4000]"]
    
    %% Child Transformation
    ChildClone -->|"calls execve('/bin/ls')"| ExecveTransition["3. Child calls execve()<br>Memory Wiped, Binary Loaded<br>PID 4001 Preserved"]
    
    %% Running and Exit
    ExecveTransition -->|"starts execution"| ProgramRun["4. Program Runs & Exits<br>ls runs, prints directory<br>calls exit(0)"]
    
    %% Zombie and Signal
    ProgramRun -->|"kernel frees memory"| ZombieState["Child Enters Zombie State<br>State: Z (EXIT_ZOMBIE)<br>Holds exit code 0"]
    
    %% Wakeup and Reap
    ZombieState -.->|"Kernel sends SIGCHLD"| ParentSleep
    ParentSleep -->|"5. Parent wakes up via wait()<br>Harvests exit code (0)"| Reaped["Process Reaped<br>PID 4001 Freed from Table"]
    Reaped -->|"Ready for next command"| ParentBash

    %% Clean theme-agnostic styling
    classDef default fill:#f8fafc,stroke:#475569,stroke-width:1px,color:#0f172a;
    classDef highlight fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#1e3a8a;
    classDef kernel fill:#f3e8ff,stroke:#9333ea,stroke-width:2px,color:#581c87;
    classDef waiting fill:#fef3c7,stroke:#d97706,stroke-width:2px,color:#78350f;
    classDef dead fill:#fee2e2,stroke:#dc2626,stroke-width:2px,color:#7f1d1d;

    class ParentBash,ChildClone,ProgramRun highlight;
    class SyscallFork,ExecveTransition,Reaped kernel;
    class ParentSleep waiting;
    class ZombieState dead;
```

---

## 6. PID 1: The First Process & Guardian of Orphans

### What is PID 1?
**PID 1 is the very first user-space process started by the Linux kernel at boot time.**
When the Linux kernel finishes initializing hardware, it mounts the root filesystem and executes `/sbin/init` (which on modern systems is `systemd`). That process is assigned **PID 1**.

PID 1 is the ancestor of every other user process on the machine. But it also has two superpower responsibilities:

### 1. The Orphan Adoption Agency
What happens if a parent process dies, crashes, or gets killed while its child process is still running?
- That child is now an **orphan**.
- Linux does **not** kill orphaned children.
- Instead, the Linux kernel instantly steps in and **reparents** the orphan process. It assigns a new legal guardian: **PID 1** (or the nearest designated ancestor **subreaper**).
- **Why?** Because when any process exits, its parent *must* read its exit status. PID 1 runs a continuous loop waiting for signals and reaps dead orphans immediately so they don't get stuck in limbo.

### 2. Immunity to `sudo kill -9 1`
Try running `sudo kill -9 1` on any Linux box. **Nothing happens.**
- Normally, `SIGKILL` (signal 9) is uncatchable and fatal.
- But inside the Linux kernel's signal dispatch code, there is a hardcoded rule: **signals sent to PID 1 are dropped unless PID 1 has explicitly registered a handler for them.**
- Since `SIGKILL` cannot have a handler by definition, the kernel ignores it. This protects your entire operating system from immediately crashing if an admin makes a typo.

---

## 7. Production & SRE Reality: The Container PID 1 Trap

Now let's take these computer science fundamentals into the real world. Why should an SRE, DevOps engineer, or cloud developer care?

Because when you run a container in Docker or Kubernetes:
```dockerfile
FROM node:20-alpine
CMD ["node", "server.js"]
```
**`node server.js` runs as PID 1 inside that container's PID namespace!**

And here is the catch: Node.js, Python, and Java were built to serve web requests—**they were never built to act as an operating system init system.**

```
+-------------------------------------------------------------------------+
|                  CONTAINER PID NAMESPACE (WITHOUT INIT)                 |
|                                                                         |
|  [ PID 1: node server.js ]  <-- Doesn't reap zombies, ignores SIGTERM   |
|         │                                                               |
|         └── Spawns worker script (PID 12)                               |
|                  │                                                      |
|                  └── Spawns ffmpeg/child (PID 18)                       |
|                           │ (worker PID 12 crashes!)                    |
|                           ▼                                             |
|              [ Orphan PID 18 reparents to PID 1 ]                       |
|                           │                                             |
|                           ▼ (PID 18 finishes & exits)                   |
|              [ Zombie PID 18: <defunct> ]                               |
|              [ Zombie PID 19: <defunct> ]  --> PERMANENT LEAK!          |
|              [ Zombie PID 20: <defunct> ]                               |
+-------------------------------------------------------------------------+
                                    │
            [ Leaks PIDs into the Host Kernel PID Table ]
                                    ▼
          HOST OUTAGE: "fork: Resource temporarily unavailable"
```

### Disaster 1: Zombie Accumulation & Host PID Exhaustion
- If your container app spawns sub-processes (e.g. running an image optimizer or shell utility) and intermediate processes die, those children reparent to **PID 1** inside the container (`node`).
- Node.js doesn't run a background `waitpid()` reaper loop.
- When those children exit, they become **Zombies (`<defunct>`)** and sit in the process table forever.
- **The Host Blast Radius:** Containers share the host kernel. Linux has a global PID limit (`/proc/sys/kernel/pid_max`, often 32,768). Once zombie processes fill that table, **the entire physical server freezes**. No new SSH sessions, monitoring crashes, and any `fork()` fails with `EAGAIN: Resource temporarily unavailable`.

### Disaster 2: Graceful Shutdown Fails (The 10-Second Delay)
- When Docker or Kubernetes wants to stop your container, it sends **`SIGTERM` (signal 15)** to PID 1.
- Because PID 1 drops signals that don't have explicit listeners, your application might completely ignore `SIGTERM`.
- Kubernetes waits 10 or 30 seconds, gives up, and sends a brutal **`SIGKILL` (signal 9)**.
- Result: Customer database transactions get severed mid-flight, file caches get corrupted, and logs don't flush.

### The Fix: Init Wrappers
Always use a lightweight init wrapper as your container's entrypoint:
1. **Docker CLI:** Pass `--init` (`docker run --init ...`)
2. **`tini`:**
   ```dockerfile
   ENTRYPOINT ["/tini", "--"]
   CMD ["node", "server.js"]
   ```
3. **`dumb-init`:**
   ```dockerfile
   ENTRYPOINT ["/usr/bin/dumb-init", "--"]
   CMD ["python3", "app.py"]
   ```
Init wrappers do two things perfectly: they forward signals properly to your app, and they reap dead zombie children in the background.

---

## 8. Edge Cases & Interview Gotchas

### Gotcha 1: File Descriptors Survive `execve()` by Default
When `execve()` wipes a process's memory, you might think everything is gone. **Wrong.**
- Open file descriptors (FDs) survive `execve()`!
- If your parent process opened a database connection, a secret encryption key file, or a socket, and forgot to close it before executing another binary, that child binary **inherits open access to that file**.
- **The Fix:** Always open files with the **`O_CLOEXEC`** flag (`open(path, O_RDONLY | O_CLOEXEC)`), or in Python 3.4+, file descriptors are set to `inheritable=False` by default.

### Gotcha 2: Orphan vs. Zombie (The Showdown)
People mix these up constantly. Here is the cheat sheet:

| Feature | Orphan Process | Zombie Process (`<defunct>`, State `Z`) |
| :--- | :--- | :--- |
| **Is it alive?** | **YES.** Running code, using CPU and RAM. | **NO.** It's dead. Execution stopped. |
| **Memory Footprint** | Has full virtual memory (code, heap, stack). | **Zero.** Memory was already freed by the kernel. |
| **Parent Status** | Original parent is **dead**. | Parent is **alive**, but forgot to call `wait()`. |
| **What happens?** | Kernel reparents it to PID 1 / subreaper. | Sits in the process table holding its exit code. |
| **Can you kill it?** | Yes, with `kill <PID>`. | **No.** You can't kill what's already dead (`kill -9` does nothing). |

---

## 9. Terminal Lab: Proving It in Real Time

Everything above is grounded in real experiments. You can run all of these yourself from the [`lab/`](./lab) directory in this repo:

### Experiment 1: Peeking Inside `/proc`
In Linux, `/proc` isn't real disk storage; it's a window directly into the kernel's memory.

Run [`lab/inspect_proc.sh`](./lab/inspect_proc.sh):
```console
$ ./lab/inspect_proc.sh
==========================================
   PROCESS INSPECTION LAB (PID: 5702)       
==========================================

[1] Command Line (/proc/5702/cmdline):
/bin/bash ./lab/inspect_proc.sh 

[2] Key Process Attributes (/proc/5702/status):
Name:	inspect_proc.sh
State:	S (sleeping)
Pid:	5702
PPid:	5700
Uid:	1000	1000	1000	1000
Gid:	1000	1000	1000	1000
FDSize:	256
VmSize:	    4948 kB
VmRSS:	    3684 kB

[3] Open File Descriptors (/proc/5702/fd):
lr-x------ 1 abir abir 64 Sep 11 03:49 0 -> pipe:[34388]
l-wx------ 1 abir abir 64 Sep 11 03:49 1 -> pipe:[34389]
l-wx------ 1 abir abir 64 Sep 11 03:49 2 -> pipe:[34390]
lr-x------ 1 abir abir 64 Sep 11 03:49 255 -> ./lab/inspect_proc.sh
```

---

### Experiment 2: Watching an Orphan Get Adopted
In [`lab/orphan_demo.py`](./lab/orphan_demo.py), a parent process forks a child, prints the child PID, and intentionally terminates immediately without calling `wait()`. Watch what the kernel does:

```console
$ python3 lab/orphan_demo.py
=================================================================
[*] [Supervisor: 5718] Starting process lifecycle experiment
=================================================================
[*] [Parent:     5725] Worker Parent running. Calling os.fork() to spawn child...
[+] [Parent:     5725] fork() returned Child PID: 5726
[+] [Parent:     5725] Parent will now EXIT IMMEDIATELY without calling wait().
[+] [Parent:     5725] Child 5726 is now an orphan!
[+] [Child:      5726] Child created! Biological Parent PPID: 5725 ('python3')
[+] [Child:      5726] Waiting for Biological Parent (5725) to terminate...
[*] [Supervisor: 5718] Observed Worker Parent 5725 exit cleanly.
-----------------------------------------------------------------
[!] [Child:      5726] Biological Parent died! Querying kernel for new PPID...
[!] [Child:      5726] Adoptive Parent PPID: 5717
[!] [Child:      5726] Guardian Name: 'Relay(5718)' (PID: 5717)
=================================================================
[*] [Supervisor: 5718] Experiment completed successfully.
```
> **What happened here?** The child started with parent `PID 5725`. As soon as the biological parent died, the Linux kernel dynamically reassigned the child's PPID to guardian `PID 5717` (the active system subreaper). The orphan was adopted in real time!

---

### Experiment 3: Proving File Descriptor Leaks & `O_CLOEXEC`
In [`lab/fd_cloexec_demo.py`](./lab/fd_cloexec_demo.py), we open two file descriptors: FD 3 without `O_CLOEXEC`, and FD 4 with `O_CLOEXEC`. Then we call `execve()` to replace our entire memory with `/bin/ls -l /proc/self/fd`:

```console
$ python3 lab/fd_cloexec_demo.py
==================================================
   FILE DESCRIPTOR INHERITANCE ACROSS EXECVE()    
==================================================
Parent process PID: 5751
FD 3 -> /tmp/leaked_secret.txt (Inheritable: True)
FD 4 -> /tmp/closed_secret.txt (Inheritable: False)

Calling os.execve() to replace memory with '/bin/ls -l /proc/self/fd'...
total 0
lr-x------ 1 abir abir 64 Sep 11 03:49 0 -> pipe:[38018]
l-wx------ 1 abir abir 64 Sep 11 03:49 1 -> pipe:[38019]
l-wx------ 1 abir abir 64 Sep 11 03:49 2 -> pipe:[38020]
lrwx------ 1 abir abir 64 Sep 11 03:49 3 -> /tmp/leaked_secret.txt
lr-x------ 1 abir abir 64 Sep 11 03:49 4 -> /proc/5751/fd
```
Look at that output: **FD 3 survived the `execve()` brain wipe!** FD 4 was safely closed. That's `O_CLOEXEC` in action.

---

## 10. Quick Engineering Cheat Sheet

| Command | What it does |
| :--- | :--- |
| `pstree -p -u` | Visual tree of all parent-child relationships and PIDs |
| `ps -eo pid,ppid,stat,comm` | List all processes with their states (`R`, `S`, `Z`) |
| `ps -eo pid,ppid,stat,comm \| grep -w 'Z'` | Find every zombie process on the host |
| `cat /proc/sys/kernel/pid_max` | Check your system's global PID ceiling |
| `ls -la /proc/<PID>/fd/` | View every open file descriptor for a process |
| `tr '\0' ' ' < /proc/<PID>/cmdline` | Inspect the exact arguments used to launch any process |

---

## Summary & What's Next
Understanding processes, virtual memory isolation, and PID 1 isn't just academic theory—it is the bedrock of container security, troubleshooting memory leaks, and building bulletproof production systems.

On **Day 2**, we'll dive deeper into Linux signals, IPC (Inter-Process Communication), and memory allocation mechanics.

*Got thoughts or questions? Check out the repo and run the labs yourself!*  
👉 **GitHub:** [isswansalty-tech/day-01-linux-processes](https://github.com/isswansalty-tech/day-01-linux-processes)
