# ShreeOS Repository Structure

Date: 2026-07-20
Status: Phase 0 complete, Phase 1 in progress

---

## 1. Top-Level Directory Layout

```
D:\lumen-linux\
├── .git/                          # Git repository data
├── .github/                       # CI/CD configuration
├── .gitignore                     # Build/output/tarball exclusion rules
├── .planning/                     # Planning and architecture artifacts (this file)
├── base-system/                   # Core userland build scripts
├── bootloader/                    # GRUB2 configuration + installation
├── branding/                      # Distro name, logo, wallpapers, theme
├── build.conf                     # Single source of truth for all build vars
├── CHANGELOG.md                   # Release changelog
├── CONTRIBUTING.md                # Contribution guide
├── desktop/                       # X11 + WM build scripts and configs
├── docs/                          # Architecture, roadmap, design documents
├── IMPLEMENTATION_PLAN.md         # Detailed 12-phase execution plan
├── init/                          # Custom PID 1 init system (C source)
├── installer/                     # Guided disk installer
├── iso-builder/                   # Hybrid BIOS/UEFI ISO assembler
├── kernel/                        # Linux kernel configs + build scripts
├── LICENSE                        # MIT license for original code
├── pkgmanager/                    # lpm package manager source + spec
├── README.md                      # Project overview
├── repo-tools/                    # Package repository build tools
├── rootfs/                        # Root filesystem skeleton + assembly
├── scripts/                       # Shared shell helpers (common.sh)
├── tests/                         # Unit, smoke, and QEMU boot tests
├── toolchain/                     # Cross-compilation toolchain build scripts
├── update/                        # System update mechanism
└── VERSION                        # Current version: 0.1.0-dev
```

---

## 2. Component Directory Breakdown

### 2.1. `toolchain/` — Cross-Compilation Toolchain

**Purpose:** Builds binutils, gcc, and glibc for `x86_64-shreeos-linux-gnu`
using the LFS two-pass method. Output is a self-contained cross-compiler in
`$LUMEN_TOOLS`.

```
toolchain/
├── README.md                  # Status (scaffolded), purpose, build instructions
└── scripts/
    ├── sources.list           # (TODO) Pinned URLs + SHA-256 for all upstream sources
    ├── build-all.sh           # (TODO) Orchestrates steps 01→07, idempotent
    ├── 01-binutils-pass1.sh   # (TODO) Initial binutils (assembler/linker only)
    ├── 02-gcc-pass1.sh        # (TODO) Minimal gcc (--without-headers)
    ├── 03-linux-headers.sh    # (TODO) Export Linux API headers to sysroot
    ├── 04-glibc.sh            # (TODO) Full C library build
    ├── 05-libstdcpp-pass1.sh  # (TODO) libstdc++ pass 1
    ├── 06-binutils-pass2.sh   # (TODO) Full binutils rebuild against sysroot
    └── 07-gcc-pass2.sh        # (TODO) Final self-hosting cross-compiler
```

**Status notes:** All subdirectories are empty; scripts will be created during
Milestone 2. The script directory exists to receive numbered build scripts
following the 7-step two-pass algorithm.

---

### 2.2. `base-system/` — Core Userland

**Purpose:** Compiles coreutils, bash, util-linux, ncurses, zlib, and other
LFS-mandatory packages against the Phase 1 cross-compiler. Produces a minimal
chroot-able base system installed to `$LUMEN_STAGE_ROOT`.

```
base-system/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── packages.list              # (TODO) Pinned versions and checksums per package
└── scripts/
    ├── build-all.sh           # (TODO) Orchestrate per-package scripts in order
    ├── 01-coreutils.sh        # (TODO) coreutils build
    ├── 02-bash.sh             # (TODO) bash build
    ├── 03-util-linux.sh       # (TODO) util-linux build
    ├── ...                    # Additional packages per LFS/BLFS baseline
    └── XX-ncurses.sh          # (TODO) ncurses (build dep for many packages)
```

**Status notes:** Empty directory. Planned for Milestone 3. Will mirror the
`toolchain/scripts/` convention: one numbered script per package, plus an
orchestrator.

---

### 2.3. `kernel/` — Linux Kernel

**Purpose:** Mainline Linux kernel configuration and cross-compilation.
Produces `bzImage` and kernel modules for `x86_64`.

```
kernel/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── configs/
│   ├── x86_64-minimal.config  # (TODO) Minimal boot config (QEMU dev)
│   └── x86_64-generic.config  # (TODO) Broad hardware support
└── scripts/
    └── build-kernel.sh        # (TODO) Cross-compile kernel + modules
```

**Status notes:** Empty subdirectories. Milestone 4 deliverable. Uses a
two-config strategy: a minimal fragment for fast development iteration and
a generic config for production.

---

### 2.4. `rootfs/` — Root Filesystem Assembly

**Purpose:** Combines base userland, kernel modules, custom init, and a static
filesystem skeleton into a complete `$LUMEN_STAGE_ROOT` suitable for
ISO-building or disk installation.

```
rootfs/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── skeleton/                  # (TODO) Static filesystem layout
│   ├── etc/
│   │   ├── os-release         # (TODO) DISTRO_NAME/DISTRO_VERSION templated
│   │   ├── fstab
│   │   ├── hostname
│   │   ├── resolv.conf
│   │   ├── passwd
│   │   ├── shadow
│   │   └── inittab
│   └── var/
│       ├── log/
│       └── cache/
└── scripts/
    └── make-rootfs.sh         # (TODO) Assemble skeleton + base + modules + init
```

**Status notes:** Empty subdirectories. Milestone 5 deliverable. The skeleton
provides the `/etc` and `/var` structure that base-system binaries and the
init process expect.

---

### 2.5. `init/` — Custom Init System

**Purpose:** A minimal PID 1 written in C. Not systemd, not a re-skin — a
small, auditable init tailored to ShreeOS.

```
init/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── src/
│   └── init.c                 # (TODO) Main init source
└── services/                  # (TODO) Service definition files
    ├── default/               # (TODO) Default target services
    └── single/                # (TODO) Single-user/recovery services
```

**Status notes:** Empty subdirectories. Milestone 5 deliverable. The init
process mounts virtual filesystems, parses service definitions in
`init/services/`, launches them in dependency order, and handles
reboot/poweroff via direct syscalls.

---

### 2.6. `bootloader/` — GRUB2 Configuration

**Purpose:** GRUB2 configuration templates and installation scripts for dual
BIOS+UEFI boot.

```
bootloader/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── grub/
│   └── grub.cfg.template      # (TODO) GRUB2 menu config (templated)
└── scripts/
    └── install-grub.sh        # (TODO) Install GRUB2 to target disk/ISO
```

**Status notes:** Empty subdirectories. Milestone 6 deliverable. The template
will be populated with `DISTRO_NAME` and `DISTRO_VERSION` variables from
`build.conf`.

---

### 2.7. `iso-builder/` — Hybrid ISO Builder

**Purpose:** Assembles kernel, rootfs, and GRUB2 into a bootable hybrid
BIOS/UEFI ISO using `grub-mkrescue` / `xorriso`.

```
iso-builder/
├── README.md                  # Status (scaffolded), purpose, build instructions
└── scripts/
    └── build-iso.sh           # (TODO) Stage files + produce hybrid .iso
```

**Status notes:** Empty subdirectory. Milestone 6 deliverable. The script
creates an ISO staging directory, copies kernel + rootfs + GRUB, and runs
xorriso for the final image.

---

### 2.8. `pkgmanager/` — Package Manager

**Purpose:** Source code for `lpm` (Lumen Package Manager), the `.lpkg` package
format specification, and unit tests.

```
pkgmanager/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── spec/
│   └── lpkg-format.md        # (TODO) Package format specification
├── src/
│   ├── main.c                # (TODO) CLI entry point
│   ├── install.c             # (TODO) Install logic
│   ├── remove.c              # (TODO) Remove logic
│   ├── query.c               # (TODO) Query logic
│   ├── resolve.c             # (TODO) Dependency resolution
│   ├── manifest.c            # (TODO) JSON manifest parsing
│   └── Makefile              # (TODO) Build system for lpm
└── tests/
    ├── test-manifest.c        # (TODO) Manifest parser tests
    ├── test-resolve.c         # (TODO) Dependency resolver tests
    └── test-install.c         # (TODO) Install/remove integration tests
```

**Status notes:** Empty subdirectories. Milestone 7 deliverable. The `.lpkg`
format will be tar + zstd + JSON manifest.

---

### 2.9. `repo-tools/` — Repository Build Tools

**Purpose:** Tooling for building, indexing, and serving a ShreeOS package
repository compatible with `lpm`.

```
repo-tools/
├── README.md                  # Status (scaffolded), purpose, build instructions
└── scripts/
    └── build-repo.sh          # (TODO) Package directory tree → .lpkg + index
```

**Status notes:** Empty subdirectory. Milestone 7 deliverable (alongside
pkgmanager). Output is consumed by `lpm` at runtime and `update/` for upgrades.

---

### 2.10. `installer/` — Disk Installer

**Purpose:** Guided text-mode installer that runs from the live ISO. Partitions
disks, writes rootfs, installs bootloader, configures first boot.

```
installer/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── src/
│   ├── main.c                 # (TODO) Installer entry point and TUI
│   ├── partition.c            # (TODO) Disk partitioning logic
│   ├── filesystem.c           # (TODO) mkfs calls
│   ├── deploy.c               # (TODO) Rootfs extraction
│   └── bootloader.c           # (TODO) Bootloader installation
└── tests/
    └── test-install.sh        # (TODO) Non-interactive install to QEMU disk
```

**Status notes:** Empty subdirectories. Milestone 8 deliverable. Supports
`--answer-file=<json>` for scripted/headless operation.

---

### 2.11. `desktop/` — Desktop Environment

**Purpose:** X11 + lightweight window manager, built as an optional package set
layered on top of the base rootfs.

```
desktop/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── wm/
│   └── (TODO) WM build scripts
└── configs/
    ├── xinitrc.template       # (TODO) Default X11 session
    ├── wm-config.template     # (TODO) Window manager configuration
    └── autostart/             # (TODO) Autostart entries
```

**Status notes:** Empty subdirectories. Milestone 9 deliverable. Packages are
built via `repo-tools/` for distribution as `lumen-desktop-minimal`.

---

### 2.12. `branding/` — Disto Branding Assets

**Purpose:** Visual identity assets (logo, wallpapers, theme). Driven by
`DISTRO_NAME` in `build.conf`.

```
branding/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── logo/                      # (TODO) Distro logo (SVG/PNG)
├── wallpapers/                # (TODO) Default desktop backgrounds
└── theme/                     # (TODO) GTK/QT theme colors, cursor theme
```

**Status notes:** Empty directories. Milestone 9 deliverable (alongside
desktop). Currently placeholder structure.

---

### 2.13. `update/` — System Update Mechanism

**Purpose:** Atomic system update tooling that reuses the `lpm` package format.

```
update/
├── README.md                  # Status (scaffolded), purpose, build instructions
└── scripts/
    └── (TODO) Update scripts
```

**Status notes:** Empty subdirectory. Post-1.0 scope. Reuses the `.lpkg`
format defined in `pkgmanager/` for atomic upgrades, not a separate pipeline.

---

### 2.14. `scripts/` — Shared Build Helpers

**Purpose:** Common Bash functions sourced by every build script in the repo.

```
scripts/
└── common.sh                  # Logging, fetch, checksum, guard functions
```

**Contents:** See `ARCHITECTURE.md` §4.1 for the function reference. This is
the only file in the repo that is always sourced (never executed directly).

---

### 2.15. `tests/` — Test Suite

**Purpose:** Three-tier test architecture: smoke, unit, and QEMU boot tests.

```
tests/
├── README.md                  # Status (scaffolded), purpose, build instructions
├── smoke/
│   └── run-all.sh             # 21 structure/config sanity checks (Phase 0)
├── unit/
│   └── (TODO) Per-component unit tests
└── qemu/
    ├── boot-kernel-only.sh   # (TODO) Kernel-only QEMU boot test
    ├── boot-full-rootfs.sh   # (TODO) Full rootfs QEMU boot test
    ├── boot-iso-bios.sh      # (TODO) Hybrid ISO BIOS boot test
    └── boot-iso-uefi.sh      # (TODO) Hybrid ISO UEFI boot test
```

**Status notes:** Currently only `tests/smoke/run-all.sh` exists (21 tests,
all passing). QEMU and unit test directories are empty, awaiting their
respective milestones. The test suite grows incrementally — every milestone
adds tests alongside implementation code.

---

### 2.16. `docs/` — Documentation

**Purpose:** Architecture, roadmap, and design-decision records.

```
docs/
├── README.md                  # Documentation index
├── ARCHITECTURE.md            # Build pipeline, design principles, target platform
├── ROADMAP.md                 # Milestone plan, current status, process rules
├── BUILD_GUIDE.md             # (TODO) Full local build walkthrough (Milestone 2+)
└── design-decisions/          # (TODO) Written rationale per major tech choice
    └── (one file per decision)
```

**Status notes:** Three files exist (README, ARCHITECTURE, ROADMAP). BUILD_GUIDE
and `design-decisions/` are deferred until the relevant milestones produce
concrete choices.

---

### 2.17. `.github/workflows/` — CI/CD Pipelines

**Purpose:** GitHub Actions workflows for automation.

```
.github/workflows/
├── lint.yml                   # shellcheck + structure enforcement (active)
├── toolchain.yml              # (TODO) Full toolchain build + cache
├── kernel.yml                 # (TODO) Kernel build against cached toolchain
├── iso.yml                    # (TODO) Full chain: make all → ISO artifact
└── release.yml                # (TODO) Tag-triggered release workflow
```

**Status notes:** Only `lint.yml` is active. It runs on every push/PR to main
and performs shellcheck on all `.sh` files plus syntax checks on `build.conf`
and `scripts/common.sh`. The remaining workflows will be added incrementally
as their components become buildable.

---

## 3. Root-Level Files

| File | Purpose |
|---|---|
| `build.conf` | Central configuration: arch, versions, paths, branding. Sourced by every build script. |
| `VERSION` | Current version string: `0.1.0-dev` |
| `README.md` | Project overview, repo layout table, quick start, dev process |
| `CHANGELOG.md` | Release changelog (unreleased: Milestone 1 scaffold) |
| `CONTRIBUTING.md` | Contribution guide: branch discipline, script quality, test requirements |
| `IMPLEMENTATION_PLAN.md` | Detailed 12-phase plan with technical approach per phase |
| `LICENSE` | MIT (original code), GPL/LGPL (upstream components) |
| `.gitignore` | Excludes build/, out/, tarballs, editor artifacts, logs |

---

## 4. Naming Conventions

### 4.1. Directories

- All component directories are **kebab-case**: `base-system`, `iso-builder`,
  `repo-tools`, `pkgmanager`
- Build-script subdirectories are named `scripts/` (not `bin/` or `build/`)
- Source-code subdirectories are named `src/`
- Configuration subdirectories are named `configs/` (not `conf/`)
- Test subdirectories are named `tests/`
- Static data subdirectories use descriptive names: `skeleton/`, `spec/`,
  `services/`, `grub/`, `logo/`, `wm/`, `theme/`, `wallpapers/`

### 4.2. Files

- Shell scripts: `.sh` — kebab-case with numeric prefixes for ordered steps:
  `01-binutils-pass1.sh`
- C source: `.c`, headers: `.h`
- Kernel configs: `.config` with architecture prefix: `x86_64-minimal.config`
- Package specs: markdown: `lpkg-format.md`
- Test scripts: kebab-case with descriptive names: `boot-kernel-only.sh`
- CI workflows: kebab-case `.yml`: `lint.yml`, `toolchain.yml`
- Templates: `.template` suffix: `grub.cfg.template`

### 4.3. Variables

- Build configuration: `UPPER_SNAKE_CASE` with `LUMEN_` prefix:
  `$LUMEN_TOOLS`, `$LUMEN_STAGE_ROOT`
- Component versions: `VER_` prefix: `VER_BINUTILS`, `VER_GCC`
- Functions: `lower_snake_case` with `lumen_` prefix: `lumen_fetch`

### 4.4. Git

- Commits follow the pattern `<component>: <description>`:
  `toolchain: add pass-1 binutils build script`
- Branches per milestone/feature
- Tags for releases: `v1.0.0`, `v1.1.0`, etc.

---

## 5. Build Path Layout

All build artifacts live outside the repo tree under `$LUMEN_BUILD_DIR` (default:
`<repo-root>/build/`). This directory is gitignored.

```
build/
├── tools/              # $LUMEN_TOOLS — cross-compiler install prefix
│   └── bin/
│       └── x86_64-shreeos-linux-gnu-gcc
├── sysroot/            # $LUMEN_SYSROOT — target headers and libraries
│   └── usr/
│       ├── include/
│       └── lib/
├── rootfs/             # $LUMEN_STAGE_ROOT — assembled target rootfs
│   ├── bin/
│   ├── lib/
│   ├── boot/
│   ├── etc/
│   └── ...
├── sources/            # $LUMEN_SOURCES — downloaded upstream tarballs
│   ├── binutils-*.tar.xz
│   ├── gcc-*.tar.xz
│   └── ...
└── .markers/           # (TODO) Build stage completion markers for idempotence

out/                    # $LUMEN_OUT — final artifacts
├── shreeos-<version>.iso
└── packages/
    └── *.lpkg
```

---

## 6. Empty Directory Inventory

The following directories are **scaffolded but empty** (awaiting implementation):

| Directory | Milestone | Will Contain |
|---|---|---|
| `toolchain/scripts/` | 2 | 7 numbered build scripts + sources.list + build-all.sh |
| `base-system/scripts/` | 3 | Per-package build scripts + packages.list + build-all.sh |
| `kernel/configs/` | 4 | Minimal and generic kernel configs |
| `kernel/scripts/` | 4 | build-kernel.sh |
| `rootfs/skeleton/` | 5 | Static /etc, /var, /dev structure |
| `rootfs/scripts/` | 5 | make-rootfs.sh |
| `init/src/` | 5 | init.c |
| `init/services/` | 5 | Service definition files |
| `bootloader/grub/` | 6 | grub.cfg.template |
| `bootloader/scripts/` | 6 | install-grub.sh |
| `iso-builder/scripts/` | 6 | build-iso.sh |
| `pkgmanager/spec/` | 7 | lpkg-format.md |
| `pkgmanager/src/` | 7 | lpm C source + Makefile |
| `pkgmanager/tests/` | 7 | C unit tests |
| `repo-tools/scripts/` | 7 | build-repo.sh |
| `installer/src/` | 8 | Installer C source |
| `installer/tests/` | 8 | Installer test script |
| `desktop/wm/` | 9 | WM build scripts |
| `desktop/configs/` | 9 | X11/WM configuration templates |
| `branding/logo/` | 9 | Logo assets |
| `branding/theme/` | 9 | Theme assets |
| `branding/wallpapers/` | 9 | Wallpaper images |
| `update/scripts/` | 10+ | Update scripts |
| `tests/unit/` | 2+ | Per-component unit tests |
| `tests/qemu/` | 4+ | QEMU boot test scripts |

Total: **25 empty scaffolded directories** across the repository.

---

## 7. Stage Dependency Graph

```
Phase 1 (toolchain) ─────────────────────────────────┐
    ├── Phase 2 (base-system) ────────────────────────┤──── Phase 6 (pkgmanager)
    └── Phase 3 (kernel) ────────────────────────────┘
                                    │
                                    └── Phase 4 (rootfs + init)
                                                │
                                                └── Phase 5 (bootloader + ISO)
                                                            │
                                            ┌───────────────┘
                                            │
                                        Phase 7 (installer)
                                        Phase 8 (desktop)
                                        Phase 9 (make all orchestration)
                                        Phase 10 (CI/CD)
                                        Phase 11 (v1.0 release)
```

No circular dependencies exist between stages. Each phase produces artifacts
consumed by exactly the next phase in the chain, with the exception of the
toolchain which feeds both base-system and kernel.

---

## 8. Key File Locations Summary

| File | Line Count | Role |
|---|---|---|
| `build.conf` | 39 | Central configuration (sourced by all scripts) |
| `scripts/common.sh` | 50 | Shared bash helpers (logging, fetch, guard) |
| `tests/smoke/run-all.sh` | 41 | Phase 0 smoke tests (21 checks) |
| `.github/workflows/lint.yml` | 42 | CI shellcheck + structure checks |
| `docs/ARCHITECTURE.md` | 76 | Build pipeline and design document |
| `docs/ROADMAP.md` | 39 | Milestone plan and status table |
| `IMPLEMENTATION_PLAN.md` | 405 | Detailed 12-phase execution plan |
| `CONTRIBUTING.md` | 33 | Contribution rules and conventions |
| `CHANGELOG.md` | 11 | Release changelog |
| `LICENSE` | 30 | MIT with upstream licensing notes |
| `VERSION` | 1 | Current version string |
| `.gitignore` | 18 | Build/output/tarball exclusion rules |

---

## 9. Expansion Points

The repository is designed for incremental growth. Each empty subdirectory
represents a bounded work unit that can be implemented independently once its
dependencies exist. The milestone numbering provides a linear ordering:

**Milestone 2** populates: `toolchain/scripts/` + `tests/`
**Milestone 3** populates: `base-system/scripts/`
**Milestone 4** populates: `kernel/configs/`, `kernel/scripts/`
**Milestone 5** populates: `rootfs/`, `init/`
**Milestone 6** populates: `bootloader/`, `iso-builder/`
**Milestone 7** populates: `pkgmanager/`, `repo-tools/`
**Milestone 8** populates: `installer/`
**Milestone 9** populates: `desktop/`, `branding/`
**Milestone 10** populates: root `Makefile`
**Milestones 11-12** populate: `.github/workflows/*.yml`, `tests/`

The `update/` directory is explicitly post-1.0 and has no milestone assigned.
