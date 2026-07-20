# Architecture

## Overview

ShreeOS is built in seven sequential stages. Each stage consumes the
output of the previous one and produces an artifact that is independently
testable.

```
1. Cross-compilation toolchain   (binutils, gcc, glibc)
        |
2. Linux kernel                  (config, compile, modules)
        |
3. Root filesystem               (base userland, custom init)
        |
4. Bootloader + ISO              (GRUB2, xorriso hybrid image)
        |
5. Package manager + repo tools  (lpm, package format)
        |
6. Installer + desktop           (disk installer, X11 + WM)
        |
7. CI/CD + v1.0 release          (GitHub Actions, ISO artifact)
```

## Design principles

1. **Everything is scripted.** No manual steps that aren't captured in a
   script under version control. If a human has to remember to do something,
   it's a bug in the build system.
2. **Every stage is independently buildable and testable.** You should be
   able to `cd toolchain && make` without having built anything else first
   (aside from documented prerequisites), and a failing test in one stage
   should never be masked by a later stage.
3. **Pinned, checksummed sources.** Every upstream component (kernel, gcc,
   binutils, glibc, busybox equivalents) is pinned to an exact version and
   verified by checksum in `toolchain/sources.list` and `kernel/sources.list`.
   No "latest" builds.
4. **Config lives in one place.** `build.conf` at the repo root is the single
   source of truth for target architecture, distro name/branding, and
   component versions. Scripts read from it; nothing hardcodes these values.
5. **Local dev vs. CI.** Quick iteration and smoke tests happen locally
   (reduced scope where needed — e.g. testing a script's logic against a
   small input). Full multi-hour builds (complete toolchain bootstrap, full
   kernel compile, full ISO assembly) run in GitHub Actions, which has the
   runtime budget for it. This split is documented per-milestone.

## Target platform (v1.0)

- Architecture: x86_64
- Firmware: BIOS (legacy) and UEFI, both via GRUB2
- Libc: glibc
- Init: custom minimal C init (see `init/`)
- Package format: `.lpkg` (tar + zstd + JSON manifest, see `pkgmanager/spec/`)
- Desktop: X11 + lightweight window manager (v1.0 scope; heavier DE support
  is a post-1.0 roadmap item, see `docs/ROADMAP.md`)

## Build pipeline data flow

- `toolchain/` produces a cross-compiler installed to `$LUMEN_TOOLS` (a
  sysroot-style prefix, never touching the host system's own toolchain).
- `kernel/` and `base-system/` are both compiled *with* that cross-compiler,
  targeting `$LUMEN_ROOT` (the staging root filesystem directory).
- `rootfs/` assembles `$LUMEN_ROOT` into a clean filesystem image (skeleton
  `/etc`, `/var`, device nodes, init wiring).
- `bootloader/` and `iso-builder/` package `$LUMEN_ROOT` plus the compiled
  kernel into a bootable hybrid ISO.
- `pkgmanager/` and `repo-tools/` are built for *both* the host (to build
  and sign packages) and the target (to install them at runtime).
- `installer/` runs on the live ISO and writes the rootfs to a target disk.
- `desktop/` layers on top of the base rootfs as an optional package set.
- `update/` reuses the package manager's package format for atomic upgrades.

## Why these specific technology choices

See `docs/design-decisions/` for a written rationale per major choice
(libc, init, package format, etc.) as each is finalized in its milestone.
