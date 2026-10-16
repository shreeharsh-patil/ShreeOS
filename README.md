# ShreeOS

The unified ShreeOS desktop image uses Debian 13 (Trixie) + KDE Plasma.
The canonical command is `make shreeos`; it assembles one live and installable
system with Debian's kernel, systemd, glibc, APT, GRUB, and Calamares, plus
ShreeOS desktop configuration and a small Debian-packaged set of native tools.
The older source-built system remains experimental and is not the release path.

ShreeOS has its own name and artwork. It is not an Ubuntu image, and it does
not include Ubuntu or Canonical branding. The desktop image uses Debian's signed
package repositories and identifies Debian as its upstream through
`ID_LIKE=debian`.

## Current status

The repository retains two distinct build paths:

| Path | What it provides | Status |
|---|---|---|
| Unified Debian + Plasma image | Debian Trixie, systemd, APT/dpkg, KDE Plasma, ShreeOS branding, packaged native utilities, and Calamares | Canonical product; release gates remain open until current BIOS/UEFI, performance, and recorded install acceptance pass |
| Source-built native image | Custom kernel, early userspace, init, LPM package tooling, and X11 desktop | Experimental research path; not included as a second root filesystem in the unified ISO |

`make shreeos` writes exactly one primary artifact,
`out/shreeos(VERSION).iso`; its version comes from the repository-root
`VERSION` file and every other version reference derives from it. A supported
production desktop release has not been certified yet: see
[`docs/UNIFIED-ARCHITECTURE.md`](docs/UNIFIED-ARCHITECTURE.md) for what is
integrated into the image and
[`docs/SYSTEM-READINESS.md`](docs/SYSTEM-READINESS.md) for the open release gates.
The live desktop uses Plasma on X11, a ShreeOS top panel, a centered Plank dock,
KRunner, ShreeOS themes and artwork, and Debian applications. Live ISO boots,
interactive use, installation, installed-system updates, and hardware coverage
are separate validation gates; a configured package or service is not proof
that the feature works on physical hardware.

## Desktop and integration

The default image uses KDE Plasma on X11, SDDM, KWin, Dolphin, Konsole,
Discover, a ShreeOS top panel, and a centered Plank dock. ShreeOS supplies the
layout, themes, artwork, power and motion controls, software launcher, and
installer integration. Compatible native commands are delivered in the
versioned `shreeos-tools` Debian package. The native `lpm`, custom init, and
source-built root filesystem remain experimental and are not installed into
the unified image.

Printing, scanning, accessibility tools, power profiles, firmware support, and
compressed swap are part of the desktop package selection. Office and
multimedia applications are optional bundles, as are developer, security, and
creative toolsets. Static configuration checks cover those choices; live
hardware and interactive use still require acceptance testing.

See [system readiness](docs/SYSTEM-READINESS.md), the
[feature commands](prototype/debian-live/features/README.md), and the
[2026-10-09 historical audit](docs/audit/2026-10-09-AUDIT.md).

## Architecture

The release product is one Debian 13 Trixie system with systemd, glibc,
APT/dpkg, Debian's kernel and drivers, GRUB, Plasma, and Calamares. The same
root filesystem provides live and installed modes. Native source-built code is
retained for research; incompatible init and package-management components do
not replace Debian's system services or package database.

Package inputs are pinned to a Debian snapshot and a specific `live-build`
version in [`prototype/debian-live/versions.conf`](prototype/debian-live/versions.conf).
The installed system uses Debian's signed Trixie and security repositories.
The image includes package and build manifests. Upstream packages retain their
own licenses; see [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) and
[`SOURCE_INFORMATION.md`](SOURCE_INFORMATION.md).

## Supported architecture and hardware

The image targets amd64 (x86-64) PCs and virtual machines, with BIOS and UEFI
boot paths. QEMU live-boot checks do not prove installed-disk boot or physical
hardware support. Secure Boot, Wi-Fi, Bluetooth, audio, printers, suspend and
resume, multi-monitor graphics, and representative Intel/AMD/NVIDIA hardware
remain uncertified.

## Build the ShreeOS desktop image

Use a Debian 13 Trixie Linux host or a disposable Debian 13 VM with root access.
The build uses `live-build`, `debootstrap`, GRUB, xorriso, SquashFS tools and
other packages; `scripts/build-shreeos.sh` validates all of them, the pinned
`live-build` version and the version contract before it starts, and fails
instead of building a partial image.
The repository checkout should have enough free space for package downloads,
the unpacked live root, and the ISO; allow at least 20 GB. Native Windows is
not a build host. WSL is suitable only when a working Linux distribution,
system services required by the build, and root filesystem support are
available.

```sh
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
git switch master

# Validate the environment and the version contract without building.
make shreeos-check

# Build the one unified desktop image: out/shreeos(VERSION).iso.
make shreeos

# Equivalent direct entry point, with more control.
bash scripts/build-shreeos.sh
bash scripts/build-shreeos.sh --force        # ignore the reusable-input cache
bash scripts/build-shreeos.sh --verify-only  # re-verify an existing image
```

The build refuses to run without root, and removes only this image's own prior
outputs plus its dedicated `build/debian-live-prototype` scratch directory.
Generated files stay under ignored `build/` and `out/` directories. Alongside
the ISO it writes `shreeos(VERSION).iso.sha256`, the exact package manifest, a
`build-info.txt` record and a machine-readable `-manifest.json` containing the
Git commit, base distribution and snapshot, build timestamp, architecture and
kernel/Plasma versions.

Command-line options let the image be built with free-only firmware
(`SHREEOS_FIRMWARE=free`) or with optional software bundles
(`SHREEOS_TOOLSETS=developer,security,creative`). The console and XFCE images
remain buildable as experiments with
`SHREEOS_LIVE_PROFILE=base|desktop bash scripts/build-debian-prototype.sh`.
They emit suffixed throwaway names and are never published.

The authoritative pipeline is
[`.github/workflows/shreeos-release.yml`](.github/workflows/shreeos-release.yml):
static checks, build, BIOS/UEFI boot verification with real desktop screenshots,
installation verification, performance measurement, and release. Because this
workspace is Windows, the image build and QEMU results must come from Linux CI.

The previous source-built path has separate host requirements and commands;
consult [`docs/BUILD_GUIDE.md`](docs/BUILD_GUIDE.md) and the relevant Makefile
targets before running it. It is not currently the recommended way to obtain a
desktop distribution.

## Live media and installation

`make shreeos` creates the single Plasma live ISO and includes the Calamares
graphical installer. The release workflow checks the installer payload and
safety boundaries, but those checks do not prove that an installation succeeds.
The interactive acceptance record in
[`release/INSTALL-ACCEPTANCE.md`](release/INSTALL-ACCEPTANCE.md) is still
`NOT ACCEPTED`; a disposable-disk install, detached-media reboot, account
login, and installed APT update must be recorded before a stable release.
Do not use the current image to install on physical disks.

## Downloads and checksums

No stable 0.4.0 ISO has been published yet. When a release is published, its page
will provide the exact image, SHA-256 checksum, package manifest, build
metadata, and release notes. Verify a downloaded checksum from the directory
containing the ISO with:

```sh
sha256sum -c 'shreeos(0.4.0).iso.sha256'
```

To create bootable USB media from a future release, follow that release's
instructions and verify the target device carefully: writing an image erases
the selected USB drive.

## Packages and updates

APT and dpkg are the package-management system in the unified image, using
Debian's signed Trixie and security repositories. The ShreeOS software entry
point delegates system changes to APT. The versioned `shreeos-tools` package
provides Debian-aware ShreeOS commands; the native `lpm` package manager is
not installed alongside APT. A signed repository for ShreeOS-authored package
updates has not been deployed.

## CI and validation

[`.github/workflows/shreeos-release.yml`](.github/workflows/shreeos-release.yml)
is the authoritative pipeline for the unified image. It runs source and version
checks, builds the ISO, verifies its contents, boots it in BIOS and UEFI QEMU,
checks installer payload and safety, evaluates performance, and publishes only
when every required release gate passes. Recorded interactive install
acceptance and an untouched-build performance baseline are mandatory release
gates. Separate workflows cover the experimental native pipeline and other
regression checks; those results do not substitute for the unified ISO gates.

Useful local checks include:

```sh
python3 tests/audit/test-shreeos-audit.py
make test-prototype-config
bash tests/release/test-version-contract.sh
bash tests/prototype/test-iso-squashfs.sh "out/shreeos($(tr -d '[:space:]' < VERSION)).iso"
```

## Security and firmware

The default image uses Debian's `main` and `non-free-firmware` components for
ordinary PC firmware; `SHREEOS_FIRMWARE=free` selects the free-firmware-only
variant. The installed system uses signed Debian repositories. Firmware and
service package presence does not establish physical device support or a
complete firewall policy. Wi-Fi, Bluetooth, audio, suspend/resume, Secure Boot,
and service exposure need representative acceptance tests.

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

ShreeOS is under development. Debian 13 is the foundation of its unified
desktop image; the source-built native pipeline remains experimental.
