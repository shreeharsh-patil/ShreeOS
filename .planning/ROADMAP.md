# Roadmap: ShreeOS v1.0

**Defined:** 2026-07-20
**Core Value:** A complete, bootable, self-built Linux distribution that boots to a desktop environment, installable to real hardware via a guided installer.

## Phase 1: Cross-Compilation Toolchain

**Goal:** Produce a working cross-compiler targeting x86_64.

**Key deliverables:**
- `toolchain/scripts/*.sh` (binutils/gcc/glibc, 2-pass LFS method)
- Pinned `sources.list` with SHA-256 checksums
- Smoke test: compile a static hello-world binary

**Requirements:** TOOL-01–06

---

## Phase 2: Base System

**Goal:** Core userland compiled against the new toolchain, creating a chroot-able rootfs.

**Key deliverables:**
- Coreutils, bash, util-linux compiled for target
- Root filesystem skeleton (`/etc`, `/var`, `/dev`, `/tmp`)
- chroot-able base rootfs under `$LUMEN_STAGE_ROOT`

**Requirements:** BASE-01–05

---

## Phase 3: Linux Kernel

**Goal:** Kernel configured, compiled, and booting under QEMU.

**Key deliverables:**
- `kernel/configs/*.config` for x86_64
- `build-kernel.sh` script
- bzImage + modules tree
- Boots to a shell in QEMU (using initramfs or base rootfs)

**Requirements:** KERN-01–03

---

## Phase 4: Init System + Root Filesystem

**Goal:** Custom init reaches PID 1 and boot completes to a shell.

**Key deliverables:**
- Custom C init (`init/src/`) compiled for target
- Service definitions in `init/services/`
- Root filesystem assembled with init wired as PID 1
- Networking configured (DHCP)
- Boots fully in QEMU under the compiled kernel

**Requirements:** INIT-01–03, ROOT-01–03

---

## Phase 5: Bootable ISO

**Goal:** Hybrid BIOS/UEFI ISO that boots in QEMU.

**Key deliverables:**
- GRUB2 config for BIOS + UEFI
- `iso-builder/scripts/build-iso.sh` using xorriso
- Bootable ISO boots in QEMU (both firmware modes)

**Requirements:** ISO-01–04

---

## Phase 6: Package Manager

**Goal:** `lpm` CLI working with `.lpkg` format and repo tools.

**Key deliverables:**
- `pkgmanager/src/` — `lpm` CLI (install, remove, query)
- `pkgmanager/spec/` — `.lpkg` specification
- `repo-tools/` — package building, indexing, serving
- Package repo with at least one test package

**Requirements:** PKG-01–04

---

## Phase 7: Installer + Desktop

**Goal:** Guided disk installer + bootable desktop environment.

**Key deliverables:**
- `installer/src/` — guided partitioning and install
- `desktop/wm/` — lightweight window manager
- `desktop/configs/` — X11 configuration, branding
- Desktop boots automatically on live ISO
- Installer writes rootfs to target disk and installs bootloader

**Requirements:** INST-01–04, DSK-01–04

---

## Phase 8: Automation & Release

**Goal:** End-to-end automation, CI/CD, and v1.0 release.

**Key deliverables:**
- Top-level Makefile/orchestration script chaining all stages
- `.github/workflows/*.yml` — full build + test + release pipeline
- `tests/` — unit, smoke, QEMU boot tests
- v1.0 tagged release with published ISO artifact

**Requirements:** BLD-01–04

---

## Phase Dependency Graph

```
Phase 1 (Toolchain) ──► Phase 2 (Base System)
                                   │
                                   ▼
                            Phase 3 (Kernel) ──► Phase 4 (Init + RootFS)
                                                       │
                                                       ▼
                                                Phase 5 (ISO)
                                                       │
                                                       ▼
                                                Phase 6 (Package Manager)
                                                       │
                                                       ▼
                                          ┌────────────┴────────────┐
                                          ▼                         ▼
                                   Phase 7 (Installer + Desktop)   
                                          │                         
                                          ▼                         
                                   Phase 8 (Automation & Release)   
```

Phases 1–5 are strictly sequential. Phase 6 can begin once Phase 5 produces a bootable ISO. Phase 7 depends on Phase 6 (packages) and Phase 5 (ISO). Phase 8 wraps everything.

---
*Last updated: 2026-07-20 after initialization*
