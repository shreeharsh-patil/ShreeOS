# STACK.md — ShreeOS Technology Stack

> Generated: 2026-07-20 | Branch: `main` (single commit `1564a4c`)
> Status: **Milestone 1 — Repository Scaffold (complete)**
> All subsequent milestones (toolchain, kernel, rootfs, ISO, etc.) are
> **planned but not yet implemented** — directories exist but are empty
> placeholders.

---

## 1. Project Identity

| Field | Value | Source |
|---|---|---|
| Distro name | `ShreeOS` | `build.conf:8` |
| Codename | `shreeos` | `build.conf:9` |
| Version | `0.1.0-dev` | `build.conf:10`, `VERSION:1` |
| OS ID | `shreeos` | `build.conf:11` |
| License | MIT (original code); GPL-2.0/LGPL (upstream kernel/toolchain) | `LICENSE:1-30` |
| Repository | Git, single-root monorepo | `.git/` |

---

## 2. Target Platform

| Property | Value | Source |
|---|---|---|
| Architecture | `x86_64` | `build.conf:14` |
| Target triplet | `x86_64-shreeos-linux-gnu` | `build.conf:15` |
| Firmware targets | BIOS (legacy) + UEFI, via GRUB2 | `ARCHITECTURE.md:49` |
| C library | glibc | `ARCHITECTURE.md:51` |
| Init system | Custom PID 1 in C (not systemd) | `ARCHITECTURE.md:52`, `init/README.md:7` |
| Package format | `.lpkg` (tar + zstd + JSON manifest) | `ARCHITECTURE.md:53` |
| Desktop | X11 + lightweight WM (v1.0 scope) | `ARCHITECTURE.md:54-55` |

---

## 3. Languages

| Language | Where Used | Current Files | Notes |
|---|---|---|---|
| **Bash** (POSIX + Bashisms) | All build scripts, CI workflows, smoke tests, orchestration | `scripts/common.sh`, `build.conf`, `tests/smoke/run-all.sh`, `.github/workflows/lint.yml` | Only language with real code so far. Uses `set -euo pipefail`, `[[ ]]`, `printf` for logging |
| **C** | Planned: custom init (`init/src/`), package manager `lpm` (`pkgmanager/src/`), installer (`installer/src/`) | No `.c` files yet | Init: small PID 1 handling `/proc`/`/sys`/`/dev` mounts, service definitions. `lpm`: statically linkable |
| **Make** (GNU Make) | Planned: top-level `Makefile` + per-component `Makefile`s | No `Makefile` yet | Phase 9 will add orchestration targets (`make toolchain`, `make kernel`, `make iso`, `make all`) |

---

## 4. Runtime & Execution Environment

### Host build requirements
| Requirement | Version / Notes | Source |
|---|---|---|
| Host OS | Linux (Ubuntu 22.04/24.04 recommended) | `README.md:51` |
| Bash | Any modern bash (scripts use `set -euo pipefail`) | `scripts/common.sh:9` |
| `curl` | HTTPS downloads with `--retry 3` | `scripts/common.sh:25` |
| `sha256sum` | Checksum verification | `scripts/common.sh:29` |
| `nproc` | Build parallelism detection | `build.conf:35` |
| `shellcheck` | Static analysis of shell scripts (CI) | `.github/workflows/lint.yml:16` |
| cross-compiler prerequisites | `build-essential` (host gcc, make, etc.) | `CONTRIBUTING.md:22-24` |
| QEMU | `qemu-system-x86_64`, `qemu-x86_64` (user mode) for boot tests | `IMPLEMENTATION_PLAN.md:63-64` |
| `xorriso` | Hybrid ISO creation (Phase 5) | `IMPLEMENTATION_PLAN.md:191` |
| `ovmf` | UEFI firmware for QEMU boot tests | `IMPLEMENTATION_PLAN.md:205` |

### Target runtime
| Component | Role | Status |
|---|---|---|
| **Linux kernel** | Mainline LTS, x86_64, compiled with custom cross-compiler | Planned (Phase 3) |
| **glibc** | Target C library | Planned (Phase 1) |
| **Custom init** | PID 1 — mounts `/proc`/`/sys`/`/dev`, reads service definitions, handles reboot/poweroff | Planned (Phase 4) |
| **GRUB2** | Bootloader — BIOS + UEFI | Planned (Phase 5) |
| **X11** | Display server for desktop | Planned (Phase 8) |
| **Lightweight WM** | Window manager (dwm-style or equivalent) | Planned (Phase 8) |

---

## 5. Build System & Toolchain

### Source of truth
- **`build.conf`** (`build.conf:1-39`) — single sourced configuration file (Bash `export` variables). Every script reads it.
- **`scripts/common.sh`** (`scripts/common.sh:1-50`) — shared logging (`lumen_log`, `lumen_ok`, `lumen_warn`, `lumen_die`), checksummed fetch (`lumen_fetch`), step helpers, command prerequisites (`lumen_require_cmd`).

### Cross-compilation toolchain (planned, Phase 1)
| Component | Version Var | Approach |
|---|---|---|
| **binutils** | `VER_BINUTILS` (currently empty) | LFS two-pass: pass 1 cross-assembler/linker, pass 2 full rebuild |
| **GCC** | `VER_GCC` (currently empty) | Pass 1: `--without-headers`, minimal C only. Pass 2: full C/C++ against sysroot |
| **glibc** | `VER_GLIBC` (currently empty) | Built into `$LUMEN_SYSROOT` using pass-1 compiler |
| **Linux kernel headers** | `VER_LINUX_KERNEL` (currently empty) | Exported into `$LUMEN_SYSROOT/usr/include` |

### Build directories (all `build.conf` defined)
| Path Variable | Default | Purpose |
|---|---|---|
| `$LUMEN_ROOT_DIR` | Repo root | Auto-detected |
| `$LUMEN_BUILD_DIR` | `build/` | Scratch/build artifacts (gitignored) |
| `$LUMEN_TOOLS` | `build/tools/` | Cross-toolchain install prefix |
| `$LUMEN_SYSROOT` | `build/sysroot/` | Target headers/libs for cross-compiler |
| `$LUMEN_STAGE_ROOT` | `build/rootfs/` | Assembled target root filesystem |
| `$LUMEN_SOURCES` | `build/sources/` | Downloaded upstream tarballs |
| `$LUMEN_OUT` | `out/` | Final artifacts (ISOs, packages) |

---

## 6. Package Management

| Aspect | Detail | Source |
|---|---|---|
| Format name | `.lpkg` | `ARCHITECTURE.md:53` |
| Payload | tar + zstd compression | `pkgmanager/README.md:7` |
| Metadata | JSON manifest (name, version, deps, file list, hooks, per-file checksums) | `IMPLEMENTATION_PLAN.md:217-218` |
| CLI tool | `lpm` (custom C application) | `pkgmanager/README.md:7` |
| Operations (v1) | `install`, `remove`, `query`, `list` | `IMPLEMENTATION_PLAN.md:220` |
| Dependency resolution | Topological, exact/minimum version match (no SAT solving for v1) | `IMPLEMENTATION_PLAN.md:221-222` |
| Repository tooling | `repo-tools/scripts/build-repo.sh` — packages directory tree into `.lpkg`s + writes JSON repo index | `IMPLEMENTATION_PLAN.md:223-224` |

---

## 7. Kernel Configuration Strategy

| Aspect | Detail | Source |
|---|---|---|
| Source | Mainline Linux LTS tag from `torvalds/linux` GitHub mirror | `IMPLEMENTATION_PLAN.md:116` |
| Build approach | `make ARCH=x86_64 CROSS_COMPILE=... olddefconfig` from documented baseline | `IMPLEMENTATION_PLAN.md:120-121` |
| Config fragments | `kernel/configs/x86_64-minimal.config` (QEMU bootstrap: ext4, virtio, serial console) + `x86_64-generic.config` (broader hardware) | `IMPLEMENTATION_PLAN.md:117-120` |
| Version tracking | Via `VER_LINUX_KERNEL` in `build.conf` | `IMPLEMENTATION_PLAN.md:115` |

---

## 8. Init System Architecture

| Aspect | Detail | Source |
|---|---|---|
| Language | C (minimal, auditable) | `init/README.md:7` |
| Responsibilities | Mount `/proc`/`/sys`/`/dev`, read `init/services/*` service definitions, exec shell or launch services, handle reboot/poweroff | `IMPLEMENTATION_PLAN.md:154-157` |
| Service definitions | Files under `init/services/` | `init/README.md` |

---

## 9. Desktop Environment (Planned)

| Aspect | Detail | Source |
|---|---|---|
| Display server | X11 | `ARCHITECTURE.md:54` |
| Window manager | Lightweight (evaluating dwm-style suckless WM vs independent WM) | `IMPLEMENTATION_PLAN.md:281-282` |
| Packaging | As `.lpkg` package set — `lpm install lumen-desktop-minimal` | `IMPLEMENTATION_PLAN.md:288` |
| Branding | Wallpaper, theme colors from `branding/` | `IMPLEMENTATION_PLAN.md:286` |
| Post-1.0 | Wayland compositor, heavier DE support (XFCE-class) | `ROADMAP.md:35-37` |

---

## 10. Installer Architecture (Planned)

| Aspect | Detail | Source |
|---|---|---|
| Language | C (likely with ncurses or plain-line interface) | `IMPLEMENTATION_PLAN.md:252` |
| Disk operations | Calls `sfdisk`/`parted`, `mkfs.ext4` | `IMPLEMENTATION_PLAN.md:253-254` |
| Bootloader install | Invokes `bootloader/scripts/install-grub.sh` | `IMPLEMENTATION_PLAN.md:254-255` |
| First-boot config | Hostname, user creation | `IMPLEMENTATION_PLAN.md:255-256` |
| Non-interactive mode | `installer --answer-file=...` for automated testing | `IMPLEMENTATION_PLAN.md:257` |

---

## 11. Development & CI Tooling

| Tool | Version / Config | Source |
|---|---|---|
| Git | Single-commit repo (SHA `1564a4c`) | Git log |
| GitHub Actions | CI/CD platform — `.github/workflows/lint.yml` | `.github/workflows/lint.yml:14-42` |
| `actions/checkout@v4` | GitHub Action for checkout | `.github/workflows/lint.yml:14` |
| `shellcheck` | On `ubuntu-latest`, `apt-get install shellcheck` | `.github/workflows/lint.yml:16-20` |
| QEMU (planned) | `qemu-system-x86_64` for boot tests | Planned (Phase 3+) |
| Test framework (planned) | Custom shell-based tests + QEMU boot tests + unit tests for C components | `tests/` directory structure |

---

## 12. Filesystem Layout Conventions

| Path | Purpose | Source |
|---|---|---|
| `build/` | Scratch/build artifacts (gitignored) | `.gitignore:3` |
| `out/` | Final artifacts (ISOs, packages) (gitignored) | `.gitignore:4` |
| `kernel/configs/*.config` | Kernel configuration fragments | `ARCHITECTURE.md`, `kernel/README.md` |
| `rootfs/skeleton/` | Static root filesystem layout (`/etc`, `/var`, `/dev` manifest, `/etc/os-release` template) | `IMPLEMENTATION_PLAN.md:150-153` |
| `pkgmanager/spec/` | `.lpkg` package format specification | `IMPLEMENTATION_PLAN.md:218` |
| `desktop/wm/` | Window manager build scripts | `IMPLEMENTATION_PLAN.md:281` |
| `desktop/configs/` | Default desktop configuration files | `IMPLEMENTATION_PLAN.md:285` |
| `branding/logo/`, `branding/wallpapers/`, `branding/theme/` | Distro branding assets | `ARCHITECTURE.md`, `branding/README.md` |
| `tests/unit/` | Fast, no-build logic tests (init parsing, lpm dependency resolution) | `IMPLEMENTATION_PLAN.md:343` |
| `tests/smoke/` | Structure/config sanity checks | `IMPLEMENTATION_PLAN.md:345-346` |
| `tests/qemu/` | QEMU-based boot tests (kernel, rootfs, ISO) | `IMPLEMENTATION_PLAN.md:347-348` |
| `docs/design-decisions/` | Written rationale for major technical choices | `ARCHITECTURE.md:75` |

---

## 13. Upstream Component Licensing

| Component | License | Notes |
|---|---|---|
| Original ShreeOS code (scripts, init, lpm, installer) | MIT | `LICENSE:1-30` |
| Linux kernel | GPL-2.0 | Distributed per upstream terms |
| GNU binutils | GPL | Linked/distributed per upstream terms |
| GNU GCC | GPL | Linked/distributed per upstream terms |
| glibc | LGPL | Linked/distributed per upstream terms |

---

## 14. Testing Strategy

| Layer | Scope | When Run | Tooling |
|---|---|---|---|
| Smoke tests | Structure, config sanity, script syntax | Every push | `tests/smoke/run-all.sh` (Bash) |
| Unit tests | Logic-only (init service parsing, lpm dependency resolution) | Every push | Custom shell/C test runners |
| QEMU boot tests | Kernel boots, rootfs reaches PID 1, ISO boots (BIOS+UEFI) | Schedule/release branches | `qemu-system-x86_64` + serial output assertion |
| Full-chain build | `make all` from clean checkout → bootable ISO | CI only (scheduled/tag) | GitHub Actions |

---

*This document was generated by exploring the repository at commit `1564a4c`. The project is in early scaffold stage — many version variables and directories are declared but empty. They will be populated as each roadmap milestone is implemented.*
