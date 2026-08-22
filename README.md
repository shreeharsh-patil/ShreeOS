<div align="center">

# 🐧 ShreeOS

### Experimental Independent Source-Built Linux Distribution with Custom Init, LPM Package Manager & Desktop Suite

**ShreeOS** is an independent, source-built x86_64 Linux operating system engineered from the ground up without relying on prebuilt binary distributions. It automates the compilation of a cross-toolchain, mainline Linux kernel, custom PID 1 init system with Unix socket IPC, and native package manager (`lpm`), providing a unified desktop environment and bootable hybrid BIOS/UEFI ISO.

<p align="center">
  <img src="https://img.shields.io/badge/Linux_Kernel-Mainline-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux Kernel" />
  <img src="https://img.shields.io/badge/Toolchain-GCC_/_Glibc-A42E2B?style=for-the-badge&logo=gnu&logoColor=white" alt="GNU Toolchain" />
  <img src="https://img.shields.io/badge/Package_Manager-lpm-4169E1?style=for-the-badge" alt="lpm Package Manager" />
  <img src="https://img.shields.io/badge/Init_System-Custom_PID_1-20B2AA?style=for-the-badge" alt="Custom Init" />
  <img src="https://img.shields.io/badge/Architecture-x86__64-000000?style=for-the-badge" alt="x86_64 Architecture" />
</p>

<p align="center">
  <a href="https://github.com/shreeharsh-patil/shreeos/stargazers"><img alt="Stars" src="https://badgen.net/github/stars/shreeharsh-patil/shreeos?color=FCC624&icon=github"></a>
  <a href="https://github.com/shreeharsh-patil/shreeos/issues"><img alt="Issues" src="https://badgen.net/github/issues/shreeharsh-patil/shreeos?color=FCC624&icon=github"></a>
  <a href="LICENSE"><img alt="License" src="https://badgen.net/badge/license/MIT/FCC624"></a>
</p>

</div>

---

## 🏛️ Operating System Architecture & Compilation Topology

Building ShreeOS from source uses a three-stage bootstrap process:

1. **Stage 1 (Cross-Toolchain):** Compiles cross-binutils, cross-GCC, and Linux kernel headers targeting `x86_64-shreeos-linux-gnu`.
2. **Stage 2 (Base Userland):** Compiles base packages (Coreutils, Bash, Util-Linux, Glibc runtime) inside an isolated build staging root.
3. **Stage 3 (Desktop, Init & Packaging):** Compiles the mainline Linux kernel, PID 1 supervisor, `lpm` package manager, desktop suite, and hybrid BIOS/UEFI bootloader image.

```mermaid
graph TD
    subgraph Host Infrastructure Layer
        A["💻 Linux Host System <br><i>(Ubuntu 22.04 / 24.04 LTS / CI)</i>"]
        B["⚙️ Global Config Manager <br><i>(build.conf / Global Vars)</i>"]
    end

    subgraph Stage 1: Cross-Toolchain Compilation
        C["🛠️ Cross-Binutils & GCC <br><i>(x86_64 Target Cross-Compilers)</i>"]
        D["📚 Kernel Headers & Glibc <br><i>(Target System C Runtime)</i>"]
    end

    subgraph Stage 2: Base System Assembly
        E["📦 Core Userland Assembly <br><i>(Coreutils, Bash, Util-Linux)</i>"]
        F["🧠 Custom Init System <br><i>(PID 1 Service Supervisor)</i>"]
        G["⚡ Package Manager Engine <br><i>(lpm / lpm-build Suite)</i>"]
    end

    subgraph Stage 3: System Packaging & Deployment
        H["🐧 Mainline Linux Kernel <br><i>(Custom Kconfig Module Drivers)</i>"]
        I["💽 Hybrid Bootloader Engine <br><i>(GRUB2 BIOS/UEFI Isohybrid)</i>"]
        J["💿 Bootable ISO Artifact <br><i>(Target Disk Installer Execution)</i>"]
    end

    A <-->|Inject Config Parameters| B
    B --> C
    C --> D
    D -->|Mount Clean Staging Environment| E
    E --> F & G
    F & G --> H
    H --> I
    I --> J

    style A fill:#000000,stroke:#333,stroke-width:2px,color:#fff
    style B fill:#34B7F1,stroke:#209CEE,stroke-width:2px,color:#fff
    style C fill:#A42E2B,stroke:#800000,stroke-width:2px,color:#fff
    style D fill:#9b59b6,stroke:#8e44ad,stroke-width:2px,color:#fff
    style E fill:#4169E1,stroke:#27ae60,stroke-width:2px,color:#fff
    style F fill:#20B2AA,stroke:#008b8b,stroke-width:2px,color:#fff
    style G fill:#f1c40f,stroke:#f39c12,stroke-width:2px,color:#333
    style H fill:#FCC624,stroke:#d4a017,stroke-width:2px,color:#333
    style I fill:#e74c3c,stroke:#c0392b,stroke-width:2px,color:#fff
    style J fill:#2ecc71,stroke:#27ae60,stroke-width:2px,color:#fff
```

### 🔄 System Initialization & Service Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor User as Hardware / QEMU
    participant Boot as GRUB2 Bootloader
    participant Kernel as Linux Kernel Matrix
    participant Init as Custom Init (PID 1)
    participant Service as Service Supervisor
    participant Desktop as Window Manager Shell

    User->>Boot: Power On / Select ShreeOS Entry
    Boot->>Kernel: Load bzImage & Initramfs Payload
    Kernel->>Kernel: Initialize Hardware Drivers & Mount RootFS
    Kernel->>Init: Execute PID 1 Handoff (/sbin/init)
    
    rect rgb(20, 30, 20)
        note over Init,Service: System Initialization Lifecycle
        Init->>Init: Mount /proc, /sys, /dev Pseudo Filesystems
        Init->>Service: Parse Service Descriptors (/etc/services.d/*.conf)
        Service->>Service: Start Daemons & Open Socket IPC (/run/init.sock)
    end

    rect rgb(30, 20, 40)
        note over Service,Desktop: Userland Presentation Layer
        Service->>Desktop: Authenticate User (shree-auth) & Start Session
        Desktop-->>User: Present Restrained Desktop Environment
    end
```

## 🛠️ Subsystems & Specifications

| Subsystem Component | Architecture & Purpose |
|---|---|
| 🛠️ Native Toolchain | Cross-compiled GNU Binutils and GCC targeting `x86_64-shreeos-linux-gnu` with isolated search paths. |
| 🧠 Custom Init (PID 1) | C-based init daemon with non-blocking zombie reaping (`waitpid`), process group signal routing, service logging (`/var/log/shreeos/services/`), and Unix socket IPC (`/run/init.sock`). |
| 📦 lpm Package Manager | Custom package manager with SHA-256 integrity verification, transactional staging, file conflict detection, and `/var/lib/lpm/lock` locking. |
| 💿 Hybrid ISO Builder | Isohybrid image with dual GRUB2 boot paths (`i386-pc` for BIOS and `x86_64-efi` for UEFI). |

## 🚀 Build Guide & Local Execution

### Prerequisites

- **Host System:** Linux (Ubuntu 22.04 / 24.04 LTS or equivalent)
- **Core Dependencies:** `git`, `make`, `gcc`, `g++`, `bash`, `bison`, `flex`, `gawk`, `texinfo`, `wget`, `curl`, `xorriso`, `qemu-system-x86_64`
- **Storage:** ~30 GB free disk space.

### Building ShreeOS

```bash
git clone https://github.com/shreeharsh-patil/shreeos.git
cd shreeos

# Build full desktop ISO profile
make PROFILE=desktop iso

# Or build minimal headless profile
make PROFILE=minimal iso
```

### Testing & Validation

```bash
# Run all test suites (unit tests + security + auth + installer + desktop)
make test-all

# Launch built ISO in QEMU (UEFI mode)
make qemu

# Launch built ISO in QEMU (BIOS mode)
make qemu-bios
```

## 📁 Repository Directory Architecture

```
shreeos/
├─ build.conf                       (Central Configuration File)
├─ Makefile                         (Root Build Script Orchestration)
├─ toolchain/                       (Cross-compilation toolchain: binutils, gcc, glibc)
├─ base-system/                     (Core userland: coreutils, bash, util-linux)
├─ kernel/                          (Linux kernel configs, patches, and build scripts)
├─ rootfs/                          (Root filesystem assembly and skeleton scripts)
├─ init/                            (Custom C-based PID 1 init system and service configs)
├─ pkgmanager/                      (Native lpm package manager source and test suites)
├─ repo-tools/                      (Package indexing & archive tooling)
├─ installer/                       (Target disk installer and partitioning safeguards)
├─ iso-builder/                     (Hybrid BIOS/UEFI ISO generation framework)
├─ desktop/                         (Window manager, control center, launcher, file manager)
├─ branding/                        (Design system tokens, vector icons, wallpapers)
├─ tests/                           (Security, authentication, installer, and smoke tests)
└─ scripts/                         (shreectl, shree-doctor, shreeinfo utilities)
```

## ⚖️ License & Attribution

Distributed under the terms of the MIT License. Third-party components built from source (Linux kernel, GNU toolchain, core libraries) retain their respective upstream software licenses (GPLv2, GPLv3, LGPL, etc.).

## 👤 Project Author

**Developed and Maintained by Shreeharsh Patil.**
- **GitHub:** [github.com/shreeharsh-patil](https://github.com/shreeharsh-patil)
