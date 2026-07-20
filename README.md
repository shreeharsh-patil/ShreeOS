# Lumen Linux

Lumen Linux is a Linux distribution built from source: a custom cross-compilation
toolchain, mainline Linux kernel, from-scratch root filesystem, custom init
system, custom package manager, installer, and a minimal desktop environment —
assembled into a bootable ISO and released through CI.

> **Status:** early scaffold. See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the
> milestone plan and current progress.

`Lumen` is a placeholder codename — every reference to it lives behind the
`DISTRO_NAME` variable in [`build.conf`](build.conf), so renaming the project
is a one-line change.

## Why build a distro from source

Package-manager-based distros (Debian, Fedora, Arch) assemble prebuilt
components. Lumen instead builds its own toolchain, compiles its own kernel,
and writes its own init and package manager — closer in spirit to
[Linux From Scratch](https://www.linuxfromscratch.org/), but organized as a
reproducible, scripted, CI-driven engineering project rather than a manual
walkthrough.

## Repository layout

| Directory | Purpose |
|---|---|
| `toolchain/` | Cross-compilation toolchain (binutils, gcc, glibc) build scripts |
| `base-system/` | Core userland (coreutils, bash, util-linux, etc.) |
| `kernel/` | Kernel configs and build scripts |
| `rootfs/` | Root filesystem skeleton and assembly scripts |
| `init/` | Custom PID 1 init system and service definitions |
| `bootloader/` | GRUB2 configuration and installation scripts |
| `pkgmanager/` | Custom package manager (`lpm`) source and package spec |
| `repo-tools/` | Tools for building and serving the software repository |
| `installer/` | Guided installer for target disks |
| `iso-builder/` | Hybrid BIOS/UEFI ISO image builder |
| `desktop/` | Desktop environment (window manager + configs) |
| `branding/` | Distro name, logo, wallpapers, theme placeholders |
| `update/` | System update mechanism |
| `tests/` | Smoke tests, QEMU boot tests, unit tests |
| `.github/workflows/` | CI/CD pipelines |
| `docs/` | Architecture, roadmap, and design-decision records |
| `scripts/` | Shared shell helpers used across all build stages |

Every directory above has (or will have, per the roadmap) its own `README.md`
documenting what it does and how to build/test it in isolation.

## Build requirements

- Linux host (Ubuntu 22.04/24.04 recommended) or the provided CI containers
- `git`, `make`, `bash`, `wget`/`curl`
- ~30 GB free disk, 4+ CPU cores recommended for full toolchain builds
- See [`docs/BUILD_GUIDE.md`](docs/BUILD_GUIDE.md) *(added once the toolchain
  milestone lands)* for the full dependency list

## Quick start

```bash
git clone <this-repo> lumen-linux
cd lumen-linux
cat build.conf        # review target arch, versions, paths
make help             # list available build targets (added in Milestone 2)
```

## Development process

This project is built milestone by milestone, matching `docs/ROADMAP.md`.
Each milestone must compile/run and include tests before the next begins —
no milestone is started until the previous one is verified working.

## License

MIT — see [`LICENSE`](LICENSE). Third-party components (Linux kernel, GNU
toolchain, etc.) retain their own upstream licenses; see
`docs/design-decisions/` for attribution notes as they're added.
