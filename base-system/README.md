# Base System & System Profiles

**Status:** implemented — Phase 2 of the implementation plan.  
**Packages:** 19 packages from the LFS 12.3 stable release  

## Purpose

Compiles the core userland (bash, coreutils, util-linux, and build tools)
against the cross-compiler from Phase 1, producing a minimal chroot-able
base system at `$SHREEOS_STAGE_ROOT` (`build/rootfs/`).

## System Profiles

ShreeOS defines 3 tiered installation profiles:

1. **`minimal`** (`base-system/profiles/minimal.list`):
   - Pure bootable core: init, bash, coreutils, sed, grep, tar, util-linux, and `lpm` package manager.
   - Ideal for embedded environments, containers, and hypervisor appliances.

2. **`server`** (`base-system/profiles/server.list`):
   - Extends `minimal` with networking (`iproute2`, `dhcpcd`), TLS (`openssl`, `ca-certificates`), remote management (`openssh`), time synchronization (`chrony`), and storage tooling (`e2fsprogs`, `kmod`).
   - Standard profile for headless server deployments.

3. **`desktop`** (`base-system/profiles/desktop.list`):
   - Extends `server` with lightweight graphical stack (`dwm`, `st`, `dmenu`, `Xorg`, `Mesa`, `libinput`, DejaVu fonts).
   - Low-footprint, high-performance desktop workstation environment.

## Package List

| # | Package | Version | Purpose |
|---|---------|---------|---------|
| 01 | m4 | 1.4.19 | Macro processor (build tool) |
| 02 | ncurses | 6.5 | Terminal handling library |
| 03 | zlib | 1.3.1 | Compression library |
| 04 | bison | 3.8.2 | Parser generator |
| 05 | flex | 2.6.4 | Lexer generator |
| 06 | readline | 8.2.13 | Line editing library |
| 07 | bash | 5.2.37 | Bourne-Again SHell |
| 08 | coreutils | 9.6 | Core Unix utilities |
| 09 | diffutils | 3.11 | diff, cmp |
| 10 | file | 5.46 | File type detection |
| 11 | gawk | 5.3.1 | GNU awk |
| 12 | grep | 3.11 | Text search |
| 13 | gzip | 1.13 | Compression |
| 14 | make | 4.4.1 | Build tool |
| 15 | patch | 2.7.6 | Source patching |
| 16 | sed | 4.9 | Stream editor |
| 17 | tar | 1.35 | Archiving |
| 18 | xz | 5.6.4 | LZMA compression |
| 19 | util-linux | 2.40.4 | System utilities (mount, ps, etc.) |

## Building

```bash
# Prerequisites: Phase 1 cross-compiler in $SHREEOS_TOOLS/bin/
bash base-system/scripts/build-all.sh
```

**Options:**
- `--resume N`: Resume from package number N
- `--skip-tests`: Skip the final smoke test
- `--list`: List all packages and exit

## Outputs

All packages are installed to `$SHREEOS_STAGE_ROOT/usr/`:
```
build/rootfs/
├── usr/
│   ├── bin/          # bash, ls, cat, grep, sed, etc.
│   ├── lib/          # libncursesw.so, libreadline.so, libz.so
│   ├── include/      # Header files
│   └── share/        # Man pages, documentation
└── bin/
    ├── bash          # Symlink to /usr/bin/bash
    └── sh            # Symlink to bash
```
