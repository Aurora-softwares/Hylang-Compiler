# Roadmap to GUI

`🟢` Implemented, `🟡` Partial implementation, `🔴` Absent.

## Phase 1: Kernel reliability

- 🔴 Define and document kernel invariants and ownership rules
- 🔴 Audit physical memory allocation, alignment and bounds checks
- 🔴 Implement reliable exception handling and fault classification
- 🔴 Strengthen interrupt handling, timers and locking
- 🔴 Add serial crash diagnostics and reproducible panic reports

### Completion: Kernel survives controlled faults and reports actionable diagnostics.

## Phase 2: Memory protection

- 🔴 Implement or complete virtual memory management
- 🔴 Separate kernel and user page tables with supervisor/user permissions
- 🔴 Enforce writable-versus-executable memory permissions
- 🔴 Implement guarded user stacks and safe address-space switching
- 🔴 Add page fault recovery and malicious pointer tests

### Completion: A user process cannot read or modify kernel memory.

## Phase 3: Processes and scheduling

- 🔴 Define process and thread structures, states and ownership
- 🔴 Implement native ring-3 process entry and return
- 🔴 Build context switching and preemptive scheduling
- 🔴 Add process termination, cleanup and resource limits
- 🔴 Implement safe wait, exit and parent/child lifecycle handling

### Completion: Multiple independent processes run and fail without crashing each other.

## Phase 4: System calls and IPC

- 🔴 Define a versioned syscall ABI and error conventions
- 🔴 Implement validated user/kernel data copying
- 🔴 Introduce per-process handle tables and access rights
- 🔴 Implement bounded IPC messages and synchronization
- 🔴 Add capability-based authorization and service isolation

### Completion: Applications access privileged resources only through validated interfaces.

## Phase 5: Storage and filesystem safety

- 🔴 Harden AHCI, NVMe, USB and GPT input validation
- 🔴 Define VFS permissions and per-process file handles
- 🔴 Introduce a writable filesystem with a recovery strategy
- 🔴 Add write ordering, flush semantics and power-loss tests
- 🔴 Implement atomic file replacement and filesystem integrity checking

### Completion: Unexpected shutdowns do not routinely destroy stored data.

## Phase 6: Driver and hardware stability

- 🔴 Improve device discovery, resource allocation and driver lifecycles
- 🔴 Implement safe keyboard and mouse event delivery
- 🔴 Provide a framebuffer/display interface and mode handling
- 🔴 Add driver timeouts, reset paths and failure recovery
- 🔴 Establish a hardware compatibility and regression test matrix

### Completion: Supported devices behave predictably and recover from errors.

## Phase 7: Graphics and window management

- 🔴 Build a 2D graphics library and surface abstraction
- 🔴 Create a user-space display server/compositor
- 🔴 Implement isolated application windows and ownership
- 🔴 Add input focus, hit testing, clipping and damage tracking
- 🔴 Build window decoration, movement, resizing and stacking

### Completion: Two applications can display independent windows without interfering.

## Phase 8: Desktop and applications

- 🔴 Implement a graphical login/session manager
- 🔴 Build desktop shell, launcher, taskbar and basic settings
- 🔴 Create a terminal application using the new APIs
- 🔴 Add a file manager, text editor and basic utilities
- 🔴 Define application lifecycle, packaging and permissions UX

### Completion: A user can log in, launch programs, work with files and log out.

## Phase 9: Security hardening

- 🔴 Define trust boundaries and threat models for the OS
- 🔴 Implement privilege separation and least-privilege service accounts
- 🔴 Add secure randomness and cryptographic primitives
- 🔴 Design verified boot, signed packages and trusted updates
- 🔴 Audit parsers, permissions, IPC and memory-safety boundaries

### Completion: Untrusted programs cannot gain unrestricted system access through intended APIs.

## Phase 10: Release engineering

- 🔴 Build automated CI for compiler, kernel, drivers and apps
- 🔴 Add fuzzing, stress tests and fault injection
- 🔴 Create installation, recovery and rollback mechanisms
- 🔴 Run prolonged stability tests on QEMU and real hardware
- 🔴 Publish release criteria, supported hardware and security policy

### Completion: A release candidate passes defined security, data-integrity and stability tests.
