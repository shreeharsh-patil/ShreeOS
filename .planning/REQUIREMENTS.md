# Requirements: ShreeOS

**Defined:** 2026-07-20
**Core Value:** A complete, bootable, self-built Linux distribution that boots to a desktop environment, installable to real hardware via a guided installer.

## v1 Requirements

### Toolchain

- [ ] **TOOL-01**: binutils cross-compiled for x86_64-lumen-linux-gnu target
- [ ] **TOOL-02**: GCC (C and C++) cross-compiled in 2-pass bootstrap
- [ ] **TOOL-03**: glibc cross-compiled for target sysroot
- [ ] **TOOL-04**: Cross-compiler produces static hello-world binary that runs on target
- [ ] **TOOL-05**: All upstream sources pinned with SHA-256 checksums
- [ ] **TOOL-06**: Toolchain is self-contained under `$LUMEN_TOOLS`, never touches host

### Base System

- [ ] **BASE-01**: Coreutils compiled and installed to rootfs
- [ ] **BASE-02**: Bash shell compiled and installed
- [ ] **BASE-03**: util-linux essentials compiled
- [ ] **BASE-04**: Basic device nodes and filesystem layout
- [ ] **BASE-05**: chroot-able base rootfs

### Kernel

- [ ] **KERN-01**: Kernel config for x86_64 (minimal + required drivers)
- [ ] **KERN-02**: Kernel compiled as bzImage with modules
- [ ] **KERN-03**: Kernel boots in QEMU to a shell

### Init System

- [ ] **INIT-01**: Custom C init (PID 1) handles system boot
- [ ] **INIT-02**: Service definitions and management
- [ ] **INIT-03**: Init reaches PID 1 successfully in QEMU

### Root Filesystem

- [ ] **ROOT-01**: Skeleton /etc, /var, /tmp, /dev structure
- [ ] **ROOT-02**: Init wired as PID 1
- [ ] **ROOT-03**: Networking configured (DHCP)

### Bootable ISO

- [ ] **ISO-01**: GRUB2 configured for BIOS boot
- [ ] **ISO-02**: GRUB2 configured for UEFI boot
- [ ] **ISO-03**: Hybrid ISO image built with xorriso
- [ ] **ISO-04**: ISO boots in QEMU (BIOS + UEFI)

### Package Manager

- [ ] **PKG-01**: `lpm` CLI with install/remove/query commands
- [ ] **PKG-02**: `.lpkg` package format spec (tar + zstd + JSON manifest)
- [ ] **PKG-03**: Tools for building and signing packages
- [ ] **PKG-04**: Package repository indexing and serving

### Installer

- [ ] **INST-01**: Guided disk partitioning
- [ ] **INST-02**: Root filesystem write to target disk
- [ ] **INST-03**: Bootloader install to target
- [ ] **INST-04**: Post-install configuration

### Desktop

- [ ] **DSK-01**: X11 server configured and running
- [ ] **DSK-02**: Lightweight window manager installed
- [ ] **DSK-03**: Distro branding (logo, wallpapers, theme)
- [ ] **DSK-04**: Desktop boots automatically on live ISO

### Build & Release

- [ ] **BLD-01**: Top-level Makefile/orchestration script
- [ ] **BLD-02**: All stages chain end-to-end in CI
- [ ] **BLD-03**: Smoke tests pass (unit + QEMU boot)
- [ ] **BLD-04**: v1.0 tagged release with published ISO artifact

## v2 Requirements

### Architecture

- **ARCH-01**: aarch64 target support
- **ARCH-02**: Wayland compositor option alongside X11

### Desktop

- **DSK2-01**: Heavier desktop environment (XFCE-class)

### Infrastructure

- **INF-01**: Binary package mirroring / CDN
- **INF-02**: Signed package repository with trust chain
- **INF-03**: Atomic system updates via package manager

## Out of Scope

| Feature | Reason |
|---------|--------|
| Real-time kernel | Not a target use case |
| Container/orchestration support | Not a distro goal for v1.0 |
| Default Wayland | Defer to post-v1.0 for stability |
| Non-x86 architectures | aarch64 is v2, others not planned |
| Package manager from another distro | Custom `lpm` is a design goal |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TOOL-01–06 | Phase 1 | Pending |
| BASE-01–05 | Phase 2 | Pending |
| KERN-01–03 | Phase 3 | Pending |
| INIT-01–03 | Phase 4 | Pending |
| ROOT-01–03 | Phase 4 | Pending |
| ISO-01–04 | Phase 5 | Pending |
| PKG-01–04 | Phase 6 | Pending |
| INST-01–04 | Phase 7 | Pending |
| DSK-01–04 | Phase 7 | Pending |
| BLD-01–04 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 38 total
- Mapped to phases: 38
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-20*
*Last updated: 2026-07-20 after initialization*
