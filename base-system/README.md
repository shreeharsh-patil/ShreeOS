# Base System & Distribution Profiles

**Status:** implemented and source-built for ShreeOS.  
**Default edition:** `desktop`.

## Purpose

The base-system stage cross-compiles the core ShreeOS userland against the ShreeOS toolchain and stages it in `$SHREEOS_STAGE_ROOT` (`build/rootfs/`). ShreeOS does not use Ubuntu or Kali as its runtime base.

The current source build includes the GNU/POSIX core needed by the system plus BusyBox networking/device helpers, OpenSSL, libnl + wpa_supplicant, ALSA, timezone data, and the supporting libraries used by the native ShreeOS desktop stack. LPM, ShreeOS init, `shreed`, desktop applications and the updater are built in later stages.

## System profiles

ShreeOS defines four installation/build profiles:

1. **`minimal`** (`base-system/profiles/minimal.list`)
   - Small bootable core for recovery, CI and constrained environments.
   - Bash/GNU core utilities, util-linux, BusyBox, init and LPM are the foundation.

2. **`server`** (`base-system/profiles/server.list`)
   - Headless profile using the same native base with ShreeOS networking and administration helpers.
   - The project must not claim optional services such as OpenSSH or chrony as installed until they have a pinned ShreeOS package/build recipe.

3. **`desktop`** (`base-system/profiles/desktop.list`)
   - Primary general-purpose edition.
   - Native Xorg/X11/Mesa software graphics stack, dwm/st/dmenu, ShreeOS dock, settings, files, editor, package manager UI, system monitor, networking/audio/Bluetooth helpers, wallpapers and fonts.
   - Uses the broad desktop kernel profile for laptops, desktops, VMs and removable media.

4. **`security`** (`base-system/profiles/security.list`)
   - Graphical security/administration workstation built on the desktop edition.
   - Adds `shree-audit` and `shree-netdiag` and retains LPM/SafeUpdate verification and rollback.
   - Intended for defensive administration, labs and authorized security testing. Additional security packages should be distributed through LPM instead of copying Kali packages into the base image.

## Base-system build order

The build scripts currently cover:

- m4, ncurses, zlib, bison, flex, readline and bash
- coreutils, diffutils, file, gawk, grep, gzip, make, patch, sed, tar and xz
- util-linux and libxcrypt
- OpenSSL
- libnl + wpa_supplicant
- ALSA libraries/utilities
- BlueZ integration where its target dependencies are available
- IANA timezone data
- BusyBox networking/device-management fallback commands

All upstream source URLs and SHA-256 pins live in `base-system/packages.list`; builds install into the target root rather than linking the runtime against host Ubuntu libraries.

## Building

```bash
# Primary desktop
make PROFILE=desktop iso

# Security workstation
make PROFILE=security security-release-check

# Headless alternatives
make PROFILE=server iso
make PROFILE=minimal iso
```

For direct base-system work:

```bash
bash base-system/scripts/build-all.sh
```

Options include `--resume N`, `--skip-tests` and `--list`.

## Outputs

The staged target filesystem is produced under `build/rootfs/`, with target executables under `/usr/bin`, target libraries under `/usr/lib`, compatibility links under `/bin`/`/lib*`, system configuration under `/etc`, and profile-specific desktop/security commands added by later build stages.
