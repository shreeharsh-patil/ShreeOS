# ShreeOS

ShreeOS is an independent Linux distribution project. Its current product path
is a small x86-64 image assembled from pinned upstream source packages. A
separate Debian 13 (Trixie) Live prototype is being evaluated as the future
desktop base. Its default profile targets a text console; optional XFCE and KDE
Plasma profiles are early integration work, not daily-use desktop releases.

ShreeOS has its own name and artwork. It is not an Ubuntu image, and it does
not include Ubuntu or Canonical branding. The prototype uses Debian's signed
package repositories and identifies Debian as its upstream through
`ID_LIKE=debian`.

## Current status

The repository contains two distinct build paths:

| Path | What it currently provides | Status |
|---|---|---|
| Existing source-built image | Custom cross-build pipeline, Linux kernel, BusyBox-oriented early userspace, custom ShreeOS init and package tooling, and a small X11/dwm graphical stack | Existing experimental path; its README-era claims are not a substitute for testing the generated image |
| Debian Live prototype | Debian Trixie userspace, apt/dpkg, systemd, live-boot, NetworkManager, common storage/diagnostic tools, SquashFS, and hybrid BIOS/UEFI boot configuration | Console BIOS/UEFI boot passes in CI; XFCE screenshot gate is failing; Plasma package/session profile is newly added and awaits Linux CI |

Native desktop development ISOs are available from
[GitHub Releases](https://github.com/shreeharsh-patil/ShreeOS/releases).
The current native version is `4.0.0-dev`; these are development prereleases,
and a supported production desktop release has not been certified.
CI has built the optional XFCE profile and started its session, but the
QEMU screenshot is still black after first-login setup completes; the screenshot
gate and visual acceptance remain open. The desktop includes a ShreeOS XFCE
appearance configuration: original
wallpapers and logo, a compact top panel, a centered Plank dock, four
workspaces, a dark Arc GTK theme, Papirus icons, Inter UI text, and ShreeOS
accent styling. This is an early desktop pass, not the complete shell described
in the roadmap. The ShreeOS Control Center provides Wi-Fi, Bluetooth, and
airplane-mode controls; audio mute, dark/light appearance, focus mode,
brightness when supported, and battery state on supported laptops; and links to
XFCE settings tools. ShreeOS Software searches the APT catalog and delegates
package changes to `apt-get` with administrator authorization. Changes are
disabled in the temporary live session and removal of essential packages is
blocked. These interfaces still need interactive Linux review. Dock
preferences open Plank's configuration for size, position, and hide behavior.
A graphical installer, broader hardware support, animated window overview,
and installed-system workflow remain open.
`Super+Space` opens Shree Search for applications, files in common user
folders, and safe calculator expressions; `Super+Up` opens Workspace Overview
to switch workspaces, activate, move, or close listed windows. Animated window
thumbnails, workspace creation, and touchpad gestures are not implemented yet.
The dock includes ShreeOS search, overview, and quick controls, while Thunar's
sidebar starts with standard personal folders and system locations.
The top panel also includes XFCE's notification history dropdown.
Keyboard navigation supports Ctrl+Alt+Left/Right to switch workspaces,
Ctrl+Alt+Shift+Left/Right to move windows, and Super+1â€“4 to select a workspace.
The target direction and exit criteria are in
[`docs/IMPLEMENTATION-PLAN.md`](docs/IMPLEMENTATION-PLAN.md).

## Current desktop hardening pass

The Plasma profile now selects office/media applications, printing/scanning,
accessibility, common PC firmware, power profiles and compressed swap. Native
KDE effects provide Mac-style motion, with performance and reduced-motion
choices. Optional developer, security and creative toolsets use Debian APT.
The installer launch, dock paths, shortcuts and repository provisioning have
received fixes; Linux installation and hardware acceptance remain open.
See [system readiness](docs/SYSTEM-READINESS.md) and
[feature commands](prototype/debian-live/features/README.md).
The current source audit is in [docs/audit/2026-10-09-AUDIT.md](docs/audit/2026-10-09-AUDIT.md).

## Architecture direction

The prototype tests a Debian-derived x86-64 base assembled with Debian Live.
The intent is to use Debian's maintained packages for the base operating
system, including systemd, udev, apt/dpkg and the live SquashFS boot path, then
add ShreeOS-owned configuration, branding, desktop defaults and packages. The
existing source-built path remains available while the prototype is evaluated.
No migration decision has been made yet.

Prototype inputs are pinned to a Debian snapshot and a specific `live-build`
version in [`prototype/debian-live/versions.conf`](prototype/debian-live/versions.conf).
The resulting installed system is configured to use Debian's signed Trixie
and security repositories. The package manifest and build metadata are
generated with the image. Upstream packages retain their own licenses; see
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) and
[`SOURCE_INFORMATION.md`](SOURCE_INFORMATION.md).

## Supported architecture and hardware

The prototype targets amd64 (x86-64) PCs and virtual machines. BIOS and UEFI
boot are configured; the console image passes both QEMU paths, while desktop
visual output and capture are still being debugged. Physical hardware
coverage, Secure Boot, Wi-Fi, Bluetooth, audio, suspend/resume, and graphics
acceleration have not yet been certified. The current source-built image has
its own kernel and hardware limitations; consult the phase plan before using it
as an installed system.

## Build the Debian Live prototype

Use a Debian 13 Trixie Linux host or a disposable Debian 13 VM with root access.
The build uses `live-build`, `debootstrap`, GRUB, xorriso, SquashFS tools and
other packages listed in
[`.github/workflows/debian-prototype.yml`](.github/workflows/debian-prototype.yml).
The repository checkout should have enough free space for package downloads,
the unpacked live root, and the ISO; allow at least 20 GB. Native Windows is
not a build host. WSL is suitable only when a working Linux distribution,
system services required by the build, and root filesystem support are
available.

```sh
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
git switch master
make test-prototype-config
make prototype-debian
make test-prototype ISO=out/shreeos-0.3.0-prototype-amd64.iso

# Optional desktop build and its stronger QEMU login check.
make prototype-debian SHREEOS_LIVE_PROFILE=desktop
make test-prototype SHREEOS_LIVE_PROFILE=desktop \
  ISO=out/shreeos-0.3.0-prototype-desktop-amd64.iso

# Experimental KDE Plasma profile (SDDM and Plasma X11 session).
make prototype-debian SHREEOS_LIVE_PROFILE=plasma
make test-prototype SHREEOS_LIVE_PROFILE=plasma \
  ISO=out/shreeos-0.3.0-prototype-plasma-amd64.iso
```

The build target refuses to run without root and removes only its dedicated
`build/debian-live-prototype` scratch directory before rebuilding. Generated
files are placed under ignored `build/` and `out/` directories. The prototype
CI workflow builds the same image path, checks its package manifest and
SquashFS, then attempts BIOS and UEFI QEMU boots. CI artifacts are short-lived
development artifacts, not releases. Because this workspace is Windows, the
first complete image build and QEMU results must come from Linux CI.

The previous source-built path has separate host requirements and commands;
consult [`docs/BUILD_GUIDE.md`](docs/BUILD_GUIDE.md) and the relevant Makefile
targets before running it. It is not currently the recommended way to obtain a
desktop distribution.

## Live media and installation

The base profile is a Live ISO with a compressed SquashFS root that boots to a
console. The optional XFCE profile adds XFCE, LightDM, ShreeOS wallpapers
and greeter branding, a configured top panel and dock, and coordinated GTK,
icon, and font defaults. CI confirms the desktop session, panel, and dock
processes start and the boot marker passes, but its QEMU screen capture is black.
The new Plasma profile installs Debian's KDE packages, SDDM, and ShreeOS-owned
session defaults. Its current source layout uses a slim translucent menu bar,
an original mountain sunrise wallpaper, ShreeOS Light surfaces, and a centered
Plank dock with hover magnification and real application launchers. It has a
QEMU check for the SDDM/Plasma session, Plank process, and visible
screen output, but this layout has not yet run in Linux CI. Live rendering and
visual acceptance remain open. Neither desktop profile has a supported disk
installation procedure. Do not use it to install on a physical computer.

## Downloads and checksums

There is no release ISO available yet. When a release is published, its page
will provide the exact image, SHA-256 checksum, package manifest, build
metadata, and release notes. Verify a downloaded checksum from the directory
containing the ISO with:

```sh
sha256sum -c shreeos-<version>-amd64.iso.sha256
```

To create bootable USB media from a future release, follow that release's
instructions and verify the target device carefully: writing an image erases
the selected USB drive.

## Packages and updates

The current source-built path contains ShreeOS's native `lpm` tooling; it is
not apt-compatible. In the Debian Live prototype, apt and dpkg are real Debian
package-management tools, configured to use Debian's signed Trixie and
security repositories. The prototype has no ShreeOS package repository yet.
It does not silently present Debian packages as ShreeOS-maintained packages.

The long-term plan is to distinguish Debian-provided packages from ShreeOS
packages and document repository trust, update behavior, support lifetime and
source availability before offering upgrades to users.

## CI and validation

GitHub Actions currently has focused workflows for the existing source-built
base-system checks and the experimental Debian Live prototype. The prototype
workflow is restricted to `master` pushes, pull requests targeting `master`,
and manual dispatch. It builds in Debian Trixie, checks the SquashFS and
manifest, then runs BIOS and UEFI QEMU boot checks with virtual block storage
and Ethernet devices and timeouts. The boot marker checks the package database,
storage detection, and NetworkManager DHCP route; the XFCE profile also
requires LightDM, an XFCE session, the panel and dock, and a nonblank screenshot.
The XFCE run currently fails at the nonblank screenshot gate. A green
prototype workflow would validate
only those checks; it would not certify physical hardware, an installer, or a
release.

Useful local checks include:

```sh
python3 tests/audit/test-shreeos-audit.py
make test-rootfs-prune
make test-prototype-config
make test-prototype ISO=path/to/prototype.iso
```

The ISO and installed-system gates are listed in
[`docs/IMPLEMENTATION-PLAN.md`](docs/IMPLEMENTATION-PLAN.md). Release
publishing remains gated on those phases being implemented and validated.

## Security and firmware

All profiles use Debian's `main` component only. The desktop profiles include
`firmware-linux-free`, whose firmware is DFSG-compliant; it does not enable
Debian's `non-free-firmware` archive. That limited firmware set does not cover
many common Wi-Fi devices. Do not assume all Wi-Fi, Bluetooth, graphics, or
laptop devices are supported. The prototype includes `openssh-client`, not an SSH server.
The temporary account's Debian Live default password is locked at boot and
neither prototype profile grants it sudo access. It is not an installed user
account. The base profile has no interactive login; the XFCE and Plasma profiles
attempt local display-manager autologin but remain unverified.

## Branding

ShreeOS owns its logo, wallpaper and design tokens under [`branding/`](branding/).
Do not add Ubuntu/Canonical marks, Ubuntu wallpapers, or other third-party
artwork without a verified license and permission for the intended use.
Upstream software names and notices remain with their respective projects.

## Contributing

Contributions to build reliability, base migration, licensing records,
hardware support, accessibility, desktop usability, installer safety and
documentation are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md), then run
the relevant checks for the files changed. Describe precisely which checks ran
and avoid claiming support that was not tested.

## Licensing

ShreeOS-authored project files are generally provided under the MIT License
unless the file says otherwise. The Linux kernel and every bundled upstream
component retain their own terms. See [`LICENSE`](LICENSE),
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md), and
[`SOURCE_INFORMATION.md`](SOURCE_INFORMATION.md). Package-level notices and
source obligations must be preserved and satisfied for any redistributed
image.

---

ShreeOS is an independent distribution project under development. Debian is
an upstream of the experimental base prototype; Ubuntu is not the base of the
current prototype.
