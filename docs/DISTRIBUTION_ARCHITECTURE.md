# ShreeOS Distribution Architecture

ShreeOS now has two deliberately separate engineering tracks.

## 1. Production desktop distribution

The production image is a **Debian 13 (Trixie) derivative** built with Debian Live. Debian explicitly supports derivative distributions and is the common upstream family behind both Ubuntu and Kali Linux. The goal is to provide the reliability and familiarity users expect from a mainstream desktop distribution while maintaining a distinct ShreeOS identity.

The production stack includes:

- Linux kernel and firmware from Debian stable
- systemd and the standard Linux boot/userspace stack
- APT package management and Debian security updates
- NetworkManager, PipeWire, Bluetooth and fwupd
- GNOME desktop with Yaru packages, Dash-to-Dock and AppIndicator support for an Ubuntu-like workflow
- Firefox ESR, LibreOffice, Thunderbird, Flatpak and common workstation utilities
- Debian Installer in live-installer mode so the live system can be installed to disk
- a curated security and diagnostics profile inspired by Kali categories, using packages from Debian stable
- hybrid ISO support for normal optical/USB boot paths, including BIOS and UEFI bootloaders

### Why ShreeOS does not mix Kali and Ubuntu repositories

Mixing repositories from independent distributions is not a valid way to combine them. Their package versions, dependency graphs, patches and release policies differ. A mixed system can silently replace core libraries and become un-upgradable. ShreeOS instead selects compatible security tools from the same Debian base and will package additional tools in its own repository when needed.

### Why the public image is not a modified Ubuntu binary image

ShreeOS can copy and adapt software whose licenses permit it, but project branding and redistribution terms still matter. A public ShreeOS release must not present itself as Ubuntu or Kali, reuse their protected logos as ShreeOS branding, or imply endorsement. ShreeOS therefore has its own `os-release`, hostname, wallpaper, installer label and project identity.

## 2. Independent source-built research track

The existing cross-toolchain, custom init, `lpm`, native desktop and source-built root filesystem remain valuable ShreeOS research. They are preserved as the independent/experimental track instead of being deleted. Components can graduate into the production distribution when they are sufficiently compatible, secure and tested.

## Release gates

A production desktop ISO must pass automated checks before it can be treated as a release candidate:

1. the image is a full desktop-sized artifact rather than a tiny/headless placeholder;
2. El Torito boot metadata exists;
3. a live SquashFS root filesystem exists;
4. installer payload is present;
5. `/etc/os-release` identifies the system as ShreeOS;
6. GNOME, Firefox, the ShreeOS wallpaper and representative security tools exist in the root filesystem;
7. SHA-256 integrity metadata verifies.

Future release gates should add automated QEMU BIOS/UEFI boot tests, installer-to-virtual-disk tests, Secure Boot signing, upgrade tests and hardware smoke testing.

## Licensing and attribution

ShreeOS source code in this repository follows the repository license. Third-party packages retain their own licenses and notices. Debian, Ubuntu, Kali Linux, Canonical and OffSec names and trademarks remain the property of their respective owners. ShreeOS is an independent project and is not endorsed by those projects or companies.
