# ShreeOS

ShreeOS is an independent Linux distribution project. Its current product path
is a small x86-64 image assembled from pinned upstream source packages. A
separate Debian 13 (Trixie) Live prototype is being evaluated as the future
desktop base. Its default profile targets a text console; an optional XFCE
profile is early integration work, not a daily-use desktop release.

ShreeOS has its own name and artwork. It is not an Ubuntu image, and it does
not include Ubuntu or Canonical branding. The prototype uses Debian's signed
package repositories and identifies Debian as its upstream through
`ID_LIKE=debian`.

## Current status

The repository contains two distinct build paths:

| Path | What it currently provides | Status |
|---|---|---|
| Existing source-built image | Custom cross-build pipeline, Linux kernel, BusyBox-oriented early userspace, custom ShreeOS init and package tooling, and a small X11/dwm graphical stack | Existing experimental path; its README-era claims are not a substitute for testing the generated image |
| Debian Live prototype | Debian Trixie userspace, apt/dpkg, systemd, live-boot, NetworkManager, common storage/diagnostic tools, SquashFS, and hybrid BIOS/UEFI boot configuration | Console base plus optional XFCE desktop profile; full ISO builds and QEMU boots are pending Linux CI validation |

There is no supported ShreeOS desktop release or public download at this time.
The optional desktop profile has not yet been built, booted, or visually
verified. A graphical installer, broad Wi-Fi firmware policy, complete
ShreeOS desktop theme, and installed-system workflow are still missing. The
project will not claim these features until they are implemented and tested.
The target direction and exit criteria are in
[`docs/IMPLEMENTATION-PLAN.md`](docs/IMPLEMENTATION-PLAN.md).

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
boot are configured and will be exercised in QEMU by CI. Physical hardware
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
console. The optional desktop profile adds XFCE, LightDM and ShreeOS wallpaper
and greeter branding, but it has not been validated yet. Neither profile has a
graphical installer or supported disk installation procedure. Do not use it
to install on a physical computer. A future installer phase will use
disposable virtual disks and require explicit confirmation before destructive
changes.

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
storage detection, and NetworkManager DHCP route; the desktop profile also
requires LightDM and an XFCE session for the live user. A green prototype
workflow would validate only those checks; it would not certify physical
hardware, an installer, or a release.

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

Both profiles use Debian's `main` component only. The desktop profile includes
`firmware-linux-free`, whose firmware is DFSG-compliant; it does not enable
Debian's `non-free-firmware` archive. That limited firmware set does not cover
many common Wi-Fi devices. Do not assume all Wi-Fi, Bluetooth, graphics, or
laptop devices are supported. The prototype includes `openssh-client`, not an SSH server.
The temporary account's Debian Live default password is locked at boot and
neither prototype profile grants it sudo access. It is not an installed user
account. The base profile has no interactive login; the desktop profile
attempts local display-manager autologin but remains unverified.

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
