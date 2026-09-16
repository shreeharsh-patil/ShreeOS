# ShreeOS

## What This Is

A from-scratch Linux distribution built entirely from source — custom cross-compilation toolchain, mainline Linux kernel, custom init system, custom package manager, guided installer, and minimal desktop environment — assembled into a bootable hybrid BIOS/UEFI ISO and released through CI.

## Core Value

A complete, bootable, self-built Linux distribution that boots to a desktop environment, installable to real hardware via a guided installer.

## Context

ShreeOS is the successor to the Lumen Linux scaffold. The repo contains all the infrastructure for building every component from source: toolchain scripts, kernel configs, init system source, package manager code, installer, desktop environment, and ISO builder. Currently at Milestone 1 (repository scaffold) — all component directories exist but are empty placeholders. The build system is driven by `build.conf` at the repo root, which is the single source of truth for arch, versions, and paths.

## Constraints

- **Architecture**: x86_64 only for v1.0
- **Libc**: glibc (chosen over musl for compatibility)
- **Firmware**: BIOS + UEFI via GRUB2
- **Init**: Custom C-based init (PID 1)
- **Build**: Cross-compiled via 2-pass LFS-style toolchain — never touches host system
- **Desktop**: X11 + lightweight window manager
- **CI**: GitHub Actions for full builds (local dev for quick smoke tests)
- **Sources**: All upstream components pinned to exact versions with SHA-256 checksums

## Requirements

### Validated

- ✓ Repository scaffold with directory structure, docs, `build.conf`, git history — Milestone 1

### Active

- [ ] Cross-compilation toolchain (binutils, gcc, glibc) — 2-pass LFS method
- [ ] Core userland compiled against new toolchain
- [ ] Linux kernel configured and compiled
- [ ] Root filesystem with custom init
- [ ] Bootable hybrid ISO (BIOS + UEFI)
- [ ] Custom package manager (`lpm`) with `.lpkg` format
- [ ] Guided disk installer
- [ ] X11 + lightweight window manager desktop
- [ ] End-to-end automated build scripts
- [ ] CI/CD pipelines and v1.0 release

### Out of Scope

- aarch64 support — post-v1.0
- Wayland compositor — post-v1.0
- Heavy desktop environment (XFCE-class) — post-v1.0
- Binary package mirroring / CDN — post-v1.0
- Signed package repository with trust chain — post-v1.0

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| glibc over musl | Maximum compatibility with existing software | ✓ Good |
| Custom init over systemd/openrc | Educational value, minimal footprint | — Pending |
| `.lpkg` format (tar+zstd+JSON) | Custom format tailored to distro needs | — Pending |
| 2-pass LFS toolchain build | Proven method for cross-compilation bootstrap | — Pending |
| Cross-compilation from Linux host | Enables CI builds without target hardware | ✓ Good |
| GRUB2 for BIOS+UEFI | Industry standard, well-documented | — Pending |
| X11 over Wayland | Simpler v1.0 target, wider driver support | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone:**
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-20 after initialization*
