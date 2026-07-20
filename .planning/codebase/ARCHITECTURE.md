# ShreeOS Architecture

Date: 2026-07-20
Status: Phase 0 complete (repository scaffold), Phase 1 in progress

---

## 1. Project Philosophy

ShreeOS is a Linux distribution built entirely from source. It follows the
Linux From Scratch (LFS) methodology but treats the build as a reproducible,
scripted, CI-driven engineering project rather than a manual walkthrough.
Every artifact is built by scripts under version control; nothing is expected
to exist on the host system beyond the bare essentials needed to bootstrap the
cross-compiler.

The project is organized as a directed acyclic graph (DAG) of 12 milestones
(see `docs/ROADMAP.md`). Each milestone produces a testable artifact that the
next milestone consumes. No milestone begins until the previous one is verified
working.

---

## 2. Seven-Stage Build Pipeline

The canonical build flows through seven sequential stages:

```
  1. Cross-compilation toolchain   (binutils, gcc, glibc)   ─┐
               │                                              │
  2. Base system userland          (coreutils, bash, etc.)   ─┤
               │                                              │  compiled
  3. Linux kernel                  (bzImage + modules)       ─┤  with the
               │                                              │  cross-
  4. Root filesystem               (skeleton + init + kernel ├─ compiler
               │                     modules + base)         ┘
  5. Bootloader + ISO              (GRUB2 + xorriso hybrid)
               │
  6. Package manager + repo tools  (lpm, .lpkg format)
               │
  7. Installer + desktop           (disk installer, X11 + WM)
```

Stages 1-4 produce a bootable live ISO. Stages 5-6 add the tooling to manage
software on the running system. Stage 7 adds the guided installer and a
graphical desktop.

---

## 3. Configuration and Build Paths

### 3.1. Central Configuration

`build.conf` (`build.conf`) is the single source of truth. Every build script
sources this file. It defines:

| Variable | Purpose | Default |
|---|---|---|
| `DISTRO_NAME` | Distro display name | `ShreeOS` |
| `DISTRO_CODENAME` | Short identifier | `shreeos` |
| `DISTRO_VERSION` | Version string | `0.1.0-dev` |
| `LUMEN_ARCH` | Target CPU architecture | `x86_64` |
| `LUMEN_TARGET_TRIPLET` | Full GNU target triple | `x86_64-shreeos-linux-gnu` |
| `LUMEN_ROOT_DIR` | Repository root | auto-detected |
| `LUMEN_BUILD_DIR` | Scratch/build artifacts | `<root>/build` |
| `LUMEN_TOOLS` | Cross-toolchain install prefix | `<build>/tools` |
| `LUMEN_SYSROOT` | Target headers/libs for compiler | `<build>/sysroot` |
| `LUMEN_STAGE_ROOT` | Assembled target rootfs | `<build>/rootfs` |
| `LUMEN_SOURCES` | Downloaded upstream tarballs | `<build>/sources` |
| `LUMEN_OUT` | Final artifacts (ISOs, packages) | `<root>/out` |
| `VER_BINUTILS` | Pinned binutils version | (populated per milestone) |
| `VER_GCC` | Pinned GCC version | (populated per milestone) |
| `VER_GLIBC` | Pinned glibc version | (populated per milestone) |
| `VER_LINUX_KERNEL` | Pinned kernel version | (populated per milestone) |
| `LUMEN_MAKE_JOBS` | Build parallelism | `nproc` output |

### 3.2. Gitignore Strategy

`.gitignore` (`gitignore`) excludes:
- `/build/` — all scratch/build artifacts (reproducible from scripts)
- `/out/` — final generated artifacts (ISOs, packages)
- All tarball patterns (`*.tar.gz`, `*.tar.xz`, etc.) — sources are re-fetched
  and checksum-verified
- Editor/IDE artifacts (`.vscode/`, `.idea/`, `*.swp`, `.DS_Store`)
- Log files (`*.log`)

---

## 4. Stage-by-Stage Architecture

### 4.1. Phase 0 — Repository Scaffold (✅ complete)

**Entry point:** `tests/smoke/run-all.sh` (`tests/smoke/run-all.sh`)

**Artifacts:** The directory structure itself, plus:
- `build.conf` — central configuration
- `scripts/common.sh` (`scripts/common.sh`) — shared Bash helpers:
  - `lumen_log`, `lumen_ok`, `lumen_warn`, `lumen_die` — colored logging
  - `lumen_fetch <url> <dest> <sha256>` — download with checksum verification
  - `lumen_step <desc>` — labeled build step logging
  - `lumen_require_cmd <cmd>...` — fail-fast missing-dependency check
- All README.md stubs across 14 component directories
- `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/README.md`
- `.github/workflows/lint.yml` — shellcheck + structure enforcement in CI

**Testing pattern (used throughout):**
```
check "description" condition
```
All smoke tests follow this pattern from `tests/smoke/run-all.sh`.

### 4.2. Phase 1 — Cross-Compilation Toolchain (⏳ in progress)

**Entry point:** `toolchain/scripts/build-all.sh` (to be created)

**Output directory:** `$LUMEN_TOOLS/bin/` — cross-compiler binaries
**Output directory:** `$LUMEN_SYSROOT/` — target headers and startup files

**Algorithm (LFS two-pass method):**

1. **binutils pass 1:**
   - Cross-assembler/linker only, no libc needed.
   - `toolchain/scripts/01-binutils-pass1.sh`
   - Configured with `--target=$LUMEN_TARGET_TRIPLET --disable-nls`

2. **gcc pass 1 (minimal):**
   - C-only compiler with `--without-headers`, enough to build glibc.
   - `toolchain/scripts/02-gcc-pass1.sh`
   - Builds `libgcc.a` (static startup code needed by glibc).

3. **Linux API headers:**
   - Extracted from pinned kernel source, installed to `$LUMEN_SYSROOT/usr/include`.
   - `toolchain/scripts/03-linux-headers.sh`
   - Uses `make headers_install` from kernel source.

4. **glibc:**
   - Full C library, built using the pass-1 compiler, installed to `$LUMEN_SYSROOT`.
   - `toolchain/scripts/04-glibc.sh`
   - Most time-intensive single step (~30-60 minutes).

5. **libstdc++ pass 1:**
   - C++ standard library built against the new glibc.
   - `toolchain/scripts/05-libstdcpp-pass1.sh`

6. **binutils pass 2:**
   - Full rebuild with the sysroot, producing the final linker/assembler.
   - `toolchain/scripts/06-binutils-pass2.sh`

7. **gcc pass 2:**
   - Full C/C++ compiler against the complete sysroot.
   - `toolchain/scripts/07-gcc-pass2.sh`
   - This is the final, self-hosting cross-compiler.

**Source pinning:** `toolchain/sources.list` (to be created) records exact
URLs and SHA-256 checksums for binutils, gcc, glibc, and kernel headers.

**Testing:**
- `${LUMEN_TOOLS}/bin/x86_64-shreeos-linux-gnu-gcc --version` runs
- A trivial static C program cross-compiles and executes under `qemu-x86_64`
- `toolchain/tests/` test script (to be created)

### 4.3. Phase 2 — Base System (📅 planned for Milestone 3)

**Entry point:** `base-system/scripts/build-all.sh` (to be created)

**Input dependency:** Phase 1 cross-compiler at `$LUMEN_TOOLS`
**Output directory:** `$LUMEN_STAGE_ROOT/` — staging root for the target

**Components built (per LFS/BLFS baseline):**
- `coreutils` — base file/shell utilities
- `bash` — shell (chosen over busybox for scripting compatibility)
- `util-linux` — mount, fdisk, etc.
- Supporting libraries: `ncurses`, `zlib`, `readline`, `m4`, `bison`, `file`
  (as build dependencies of the above)

**Package specification:** `base-system/packages.list` (to be created) mirrors
`toolchain/sources.list` — pinned versions + checksums.

**Testing:**
- `chroot $LUMEN_STAGE_ROOT /bin/bash -c 'echo hello'` succeeds under QEMU
- Core utilities (`ls`, `cat`, `mount`, `ps`) run inside the chroot

### 4.4. Phase 3 — Kernel (📅 planned for Milestone 4)

**Entry point:** `kernel/scripts/build-kernel.sh` (to be created)

**Input dependency:** Phase 1 cross-compiler at `$LUMEN_TOOLS`
**Output:** `$LUMEN_STAGE_ROOT/boot/vmlinuz-*` (bzImage), modules in
`$LUMEN_STAGE_ROOT/lib/modules/`

**Config strategy:**
- `kernel/configs/x86_64-minimal.config` — minimal boot-capable config
  (PC platform, ext4/virtio block+net, serial console, for QEMU dev/testing)
- `kernel/configs/x86_64-generic.config` — broader hardware support for
  production installs
- Generated via `make ARCH=x86_64 CROSS_COMPILE=... olddefconfig`
  from documented baselines

**Kernel version:** Pinned in `build.conf` as `VER_LINUX_KERNEL`, sourced from
`torvalds/linux` GitHub mirror (specific LTS tag).

**Testing:**
- QEMU boots minimal kernel + trivial initramfs to a shell
- `tests/qemu/boot-kernel-only.sh` automates and checks serial output

### 4.5. Phase 4 — Root Filesystem + Init (📅 planned for Milestone 5)

**Entry point:** `rootfs/scripts/make-rootfs.sh` (to be created)

**Inputs:**
- Phase 2 base system at `$LUMEN_STAGE_ROOT`
- Phase 3 kernel + modules at `$LUMEN_STAGE_ROOT`
- Phase 4 init binary (compiled from `init/src/`)

**Output:** Complete `$LUMEN_STAGE_ROOT` ready for ISO packaging

**`rootfs/skeleton/` (to be created) — static filesystem layout:**
```
skeleton/
├── etc/
│   ├── os-release          # templated from build.conf DISTRO_* vars
│   ├── fstab               # default mount table
│   ├── inittab             # init configuration
│   ├── hostname
│   ├── resolv.conf         # DNS (populated at runtime)
│   └── shadow|passwd|group # root account
├── var/
│   ├── log/
│   └── cache/
└── dev/                    # device node manifest
```

**Custom init system (`init/`):**
- Written in C (source to be created in `init/src/init.c`)
- Responsibilities at boot:
  1. Mount `/proc`, `/sys`, `/devtmpfs`
  2. Parse `init/services/*` service definitions
  3. Execute services in dependency order
  4. Spawn shell on console
  5. Handle reboot/poweroff/halt via direct syscalls
- Service definitions: `init/services/*` (to be created), format TBD but
  expected to be declarative (e.g., `.service`-like or simple config)

**Testing:**
- `init/tests/` unit tests for service-parsing logic (no QEMU needed)
- `tests/qemu/boot-full-rootfs.sh` — boots rootfs + kernel to custom init shell

### 4.6. Phase 5 — Bootloader + Bootable ISO (📅 planned for Milestone 6)

**Entry point:** `iso-builder/scripts/build-iso.sh` (to be created)

**Inputs:**
- Phase 4 assembled rootfs at `$LUMEN_STAGE_ROOT`
- Phase 3 kernel bzImage
- GRUB2 config from `bootloader/grub/grub.cfg.template`

**Output:** Hybrid BIOS/UEFI ISO at `$LUMEN_OUT/shreeos-<version>.iso`

**Components:**

1. **`bootloader/grub/grub.cfg.template`:**
   - Templated with `DISTRO_NAME`/`DISTRO_VERSION`
   - Menu entries for normal boot, recovery/single-user mode
   - Separate BIOS (`core.img`) and UEFI (`BOOTX64.EFI`) paths

2. **`bootloader/scripts/install-grub.sh`:**
   - Installs GRUB2 to target (disk or ISO staging directory)
   - Dual BIOS + UEFI support
   - For ISO mode, sets up loopback-compatible GRUB

3. **`iso-builder/scripts/build-iso.sh`:**
   - Creates staging directory with `/boot`, kernel, initramfs, rootfs
   - Options: squashfs rootfs for live mode, or plain filesystem
   - Runs `grub-mkrescue` or `xorriso` for final hybrid ISO

**Testing:**
- `tests/qemu/boot-iso-bios.sh` — boots ISO in legacy BIOS mode
- `tests/qemu/boot-iso-uefi.sh` — boots ISO in UEFI mode (via OVMF)

### 4.7. Phase 6 — Package Manager + Repository Tools (📅 planned for Milestone 7)

**Component:** `pkgmanager/` — `lpm` (Lumen Package Manager)

**Language:** C, statically linkable
**Source layout:** `pkgmanager/src/*.c` (to be created)

**Package format (`.lpkg`):**
- tar archive + zstd compression + JSON manifest
- Manifest fields: name, version, dependencies, file list, pre/post install
  hooks, per-file checksums
- Spec: `pkgmanager/spec/lpkg-format.md` (to be created)

**`lpm` CLI commands (v1 scope):**
| Command | Description |
|---|---|
| `lpm install <pkg>` | Install package to root |
| `lpm remove <pkg>` | Remove package (full reversal) |
| `lpm query <pkg>` | Show package metadata |
| `lpm list` | List installed packages |

**Dependency resolution (v1):**
- Topological sort, exact version match only
- No SAT/solver or version-range matching (documented limitation)

**Repository tools (`repo-tools/`):**
- `repo-tools/scripts/build-repo.sh`:
  - Scans a directory tree of built software
  - Produces `.lpkg` packages
  - Writes repo index JSON for `lpm` to consume

**Testing:**
- `pkgmanager/tests/` — unit tests for manifest parsing, dependency resolution,
  install/remove against scratch root
- 3-package chain test (A → B → C) verifies topological install order

### 4.8. Phase 7 — Installer (📅 planned for Milestone 8)

**Component:** `installer/`

**Source:** `installer/src/` (to be created, language TBD — C or shell with
ncurses)

**Workflow:**
1. Disk selection — enumerate available block devices
2. Partitioning — call `sfdisk`/`parted`
3. Filesystem creation — `mkfs.ext4`
4. Rootfs copy — extract rootfs archive to target disk
5. Bootloader install — invoke `bootloader/scripts/install-grub.sh`
6. First-boot config — hostname, user creation, network setup

**Key design property:** Scriptable/non-interactive mode via
`--answer-file=<json>` for automated testing and headless installs.

**Testing:**
- Non-interactive install to QEMU virtual disk
- Boot that disk in QEMU to custom init shell

### 4.9. Phase 8 — Desktop Environment (📅 planned for Milestone 9)

**Component:** `desktop/`

**Stack:** X11 + lightweight window manager
**Package model:** Optional package set (`lumen-desktop-minimal`) installed via
`lpm`

**Source layout:**
- `desktop/wm/` — WM build scripts (evaluating dwm-style suckless WM or small
  independent WM)
- `desktop/configs/` — default configs (keybindings, autostart), templated
  with `branding/` assets

**Branding (`branding/`):**
- `branding/logo/` — distro logo assets
- `branding/theme/` — color theme, cursor theme
- `branding/wallpapers/` — default wallpaper(s)

**Testing:**
- Boot ISO with desktop package → X11 session with WM running
- QEMU + VNC/screenshot or process-alive check

### 4.10. Phase 9 — Build Orchestration (📅 planned for Milestone 10)

**Planned:** Top-level `Makefile` with targets:
| Target | Runs |
|---|---|
| `make toolchain` | Phase 1 |
| `make base-system` | Phase 2 |
| `make kernel` | Phase 3 |
| `make rootfs` | Phase 4 |
| `make iso` | Phases 3→4→5 (kernel + rootfs + ISO) |
| `make packages` | Phases 1→2→6 (toolchain + base + lpm) |
| `make all` | Phases 1→8 end-to-end |
| `make clean` | Remove build artifacts |
| `make distclean` | Full reset |

Each target idempotent via marker files under `$LUMEN_BUILD_DIR/.markers/`.

### 4.11. Phase 10-11 — CI/CD and Release (📅 planned for Milestones 11-12)

**Workflow topology (`.github/workflows/`):**

| Workflow | Trigger | Scope |
|---|---|---|
| `lint.yml` | every push/PR | shellcheck + directory structure |
| `toolchain.yml` | push to main | Phase 1 full build, cache artifacts |
| `kernel.yml` | push to main | Phase 3 build against cached toolchain |
| `iso.yml` | push to main, tags | Full make all, upload ISO artifact |
| `release.yml` | v* tags | ISO → GitHub Release with SHA256SUMS |

**Test categories (in `tests/`):**
| Directory | Speed | Scope |
|---|---|---|
| `tests/smoke/` | fast (seconds) | Structure, config syntax, README presence |
| `tests/unit/` | fast (seconds) | Logic tests (init parser, lpm resolver) |
| `tests/qemu/` | slow (minutes) | Full boot tests with QEMU |

---

## 5. Data Flow Between Stages

```
build.conf  ───────────────────────────────────────────────────────┐
                                                                    │
                    ┌───────────────────────────────────────────────┤
                    │                                               │
                    v                                               │
 Phase 1: toolchain/                                                │
    01-binutils-p1.sh ──┐                                           │
    02-gcc-p1.sh ───────┤                                           │
    03-linux-headers.sh ─┤  produces: $LUMEN_TOOLS/bin/*            │
    04-glibc.sh ────────┤            $LUMEN_SYSROOT/*               │
    05-libstdcpp-p1.sh ─┤                                           │
    06-binutils-p2.sh ──┤                                           │
    07-gcc-p2.sh ───────┘                                           │
                    │                                               │
                    v                                               │
 Phase 2: base-system/                                              │
    packages.list ──┐                                               │
    build-all.sh ───┤  produces: $LUMEN_STAGE_ROOT/{bin,lib,...}    │
                    │                                               │
                    v                                               │
 Phase 3: kernel/          ┌────────────────────────────────────────┘
    build-kernel.sh ───────┤  produces: bzImage, modules
                    │      │
                    v      v
 Phase 4: rootfs/ + init/
    skeleton/ ─────────────┐
    init/src/init.c ───────┤  produces: $LUMEN_STAGE_ROOT (complete)
    make-rootfs.sh ────────┘
                    │
                    v
 Phase 5: bootloader/ + iso-builder/
    grub.cfg.template ─────┐
    install-grub.sh ───────┤  produces: $LUMEN_OUT/*.iso
    build-iso.sh ──────────┘
                    │
                    v
 Phase 6: pkgmanager/ + repo-tools/
    src/lpm.c ──────────────┐
    spec/lpkg-format.md ────┤  produces: lpm binary + .lpkg packages
    build-repo.sh ──────────┘
                    │
                    v
 Phase 7: installer/
    src/installer.c ────────┐
    answer-file.json ───────┤  produces: installer binary
```

---

## 6. Cross-Cutting Patterns

### 6.1. Script Convention

Every build script:
1. Sources `build.conf` for variables
2. Sources `scripts/common.sh` for logging + helpers
3. Uses `lumen_fetch` for every download (with SHA-256 verification)
4. Uses `lumen_step` for labeled output
5. Uses `lumen_die` for fatal errors
6. Is idempotent: skips completed steps via existence/checksum checks
7. Is tested by `bash -n` in CI (syntax check)

### 6.2. Source Pinning

Every upstream component is pinned to an exact version via:
- Variable in `build.conf` (e.g., `VER_BINUTILS`)
- URL + SHA-256 in a `sources.list` file per component directory
- No `latest` or floating tags

### 6.3. Host vs. Target Split

| Component | Runs on host | Runs on target |
|---|---|---|
| `toolchain/` scripts | ✅ build-time only | ❌ |
| `base-system/` scripts | ✅ build-time only | ❌ |
| `kernel/` scripts | ✅ build-time only | ❌ |
| `lpm` (package manager) | ✅ (for packaging) | ✅ (runtime) |
| `repo-tools/` | ✅ (for building repos) | ❌ |
| `installer/` | ✅ (from live ISO) | ❌ |
| `init` (PID 1) | ❌ | ✅ |
| `update/` | ❌ | ✅ |

### 6.4. Testing Discipline

- Every milestone adds tests before it is considered complete
- Unit tests: pure logic, no system dependencies, fast
- Smoke tests: structure checks, config validation
- QEMU boot tests: full-system integration, slow, run in CI
- No manual steps — if a test requires a human to verify, it's a bug

### 6.5. CI Architecture

The CI system uses GitHub Actions with a layered approach:
- **Lint layer** (every push): shellcheck, structure, Bash syntax
- **Build layer** (main branch): full toolchain bootstraps, kernel compiles,
  ISO assembly, cached between runs
- **Release layer** (tags): final produce-and-publish

Artifact caching is critical: the toolchain build (~hours) is cached so that
kernel and ISO workflows don't repeat it.

---

## 7. Naming Conventions

| Convention | Rule | Example |
|---|---|---|
| Directory names | kebab-case | `iso-builder/`, `repo-tools/` |
| Script names | kebab-case, numbered for ordered steps | `01-binutils-pass1.sh` |
| Variables | `UPPER_SNAKE_CASE` with `LUMEN_` prefix | `$LUMEN_TOOLS` |
| Functions | `lower_snake_case` with `lumen_` prefix | `lumen_fetch` |
| Package format | `.lpkg` | `coreutils-9.4-1.lpkg` |
| CI workflows | descriptive kebab-case | `toolchain.yml` |
| Test files | descriptive kebab-case | `boot-kernel-only.sh` |

---

## 8. Key Dependencies and Relationships

```
toolchain/  ──provides CC──▶  base-system/  ──provides userland──▶  rootfs/
toolchain/  ──provides CC──▶  kernel/       ──provides bzImage──▶  rootfs/
rootfs/     ──provides root──▶ iso-builder/  ──provides ISO──────▶  installer/
pkgmanager/ ──provides lpm──▶  repo-tools/  ──provides repo──────▶  update/
branding/   ──provides assets▶  desktop/     ──provides packages──▶  repo-tools/
```

The update system (`update/`) reuses the package format (`pkgmanager/`) for
atomic upgrades — it is not a separate pipeline, but a runtime mode of lpm.

---

## 9. File Manifest (Phase 0 — Committed Files)

```
.github/workflows/lint.yml     # CI — shellcheck + structure checks
.gitignore                     # Excludes build/, out/, tarballs, editor cruft
CHANGELOG.md                   # Release notes
CONTRIBUTING.md                # Contribution guide
IMPLEMENTATION_PLAN.md         # Detailed 12-phase execution plan
LICENSE                        # MIT (original code), GPL/LGPL (upstream)
README.md                      # Project overview
VERSION                        # 0.1.0-dev
build.conf                     # Central configuration (single source of truth)
scripts/common.sh              # Shared shell helpers (logging, fetch, guards)
tests/smoke/run-all.sh         # 21 smoke tests for Phase 0

14 README.md stubs (one per component):
  base-system/README.md
  bootloader/README.md
  branding/README.md
  desktop/README.md
  init/README.md
  installer/README.md
  iso-builder/README.md
  kernel/README.md
  pkgmanager/README.md
  repo-tools/README.md
  rootfs/README.md
  tests/README.md
  toolchain/README.md
  update/README.md

3 docs/ files:
  docs/ARCHITECTURE.md
  docs/README.md
  docs/ROADMAP.md
```

---

## 10. Risk Areas

| Risk | Mitigation |
|---|---|
| binutils/gcc/glibc version incompatibility | Versions pinned and tested as a set |
| Host toolchain contamination | Cross-compiler installed to isolated `$LUMEN_TOOLS` prefix |
| CI runtime limits | Two-pass toolchain split: pass-1 local, pass-2 in CI |
| Unreproducible builds | Every source pinned + checksummed; no `latest` |
| Missing host dependencies | `lumen_require_cmd` fail-fast in every entry script |
| Slow QEMU boot tests | Run on schedule/release only; fast unit tests run every push |
