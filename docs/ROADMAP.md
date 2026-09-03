# Roadmap

Each milestone must have working, compiling/running code and at least a
basic test before the next milestone begins. Status is updated as we go.

| # | Milestone | Key deliverables | Status |
|---|---|---|---|
| 1 | Repository scaffold | Directory structure, docs, `build.conf`, git history | ✅ done |
| 2 | Cross-compilation toolchain | `toolchain/scripts/*.sh` (binutils/gcc/glibc, 2-pass LFS method), pinned `sources.list`, smoke test compiling a static binary | ⏳ next |
| 3 | Base system | Core userland compiled against the new toolchain, chroot-able base | planned |
| 4 | Kernel | `kernel/configs/*.config`, `build-kernel.sh`, boots to a shell under QEMU | planned |
| 5 | Root filesystem | `rootfs/skeleton/`, `make-rootfs.sh`, custom init (`init/`) reaches PID 1 successfully | planned |
| 6 | Bootable ISO | GRUB2 config, `iso-builder/scripts/build-iso.sh`, boots in QEMU (BIOS + UEFI) | planned |
| 7 | Package manager | `lpm` CLI (install/remove/query), `.lpkg` spec, `repo-tools/` for building a repo | planned |
| 8 | Installer | `installer/` guided disk installer, partitioning, bootloader install | planned |
| 9 | Desktop environment | X11 + minimal WM package set under `desktop/`, branding wired in | planned |
| 10 | Automated build scripts | Top-level `Makefile`/orchestration script chaining all stages end-to-end | planned |
| 11 | Testing + CI | `tests/` (unit, smoke, QEMU boot), `.github/workflows/*.yml` | planned |
| 12 | v1.0 release | Tagged release, changelog, published ISO artifact via CI | planned |

## Process rules

- We work one milestone at a time, in order.
- Every milestone ends with: working code, a passing test (however small),
  a README update, and a git commit/tag.
- I (Claude) explain what's being built, generate code/config/tests, and
  wait for your confirmation before starting the next milestone.
- Feasibility notes (execution environment, network access, what runs
  locally vs. in CI) are called out explicitly whenever they affect a
  milestone's scope — see the top-level chat response for the current
  constraints.

## Post-1.0 ideas (not in scope for v1.0)

- Additional architectures (aarch64)
- Wayland compositor option alongside X11
- Heavier desktop environment (XFCE-class)
- Binary package mirroring / CDN
- Signed package repository with a real trust chain
