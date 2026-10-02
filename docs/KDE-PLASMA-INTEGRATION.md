# KDE Plasma integration audit and first slice

## Repository audit

ShreeOS currently has two intentionally separate build systems. The legacy
source-built ISO compiles its own x86-64 toolchain, Linux kernel, BusyBox-based
early userspace and custom init, and assembles an initramfs CPIO plus GRUB ISO.
Its native package tool is `lpm`; its optional X11 desktop is dwm/st/dmenu with
ShreeOS shell scripts. That stack is not apt-compatible and does not yet have
the session services needed for a full Plasma desktop.

The experimental Debian Live path under `prototype/debian-live/` uses Debian
13 Trixie packages through `apt`/`dpkg`, `systemd`, `live-boot`, a SquashFS
root filesystem, and hybrid GRUB BIOS/UEFI media. `scripts/build-debian-prototype.sh`
drives `live-build`; `tests/prototype/test-iso.sh` checks the ISO and boots it
under QEMU; `.github/workflows/debian-prototype.yml` performs those builds and
boot checks. Its existing `desktop` profile is XFCE + LightDM and has its own
configuration, applications, installer branding, and first-login tools.

The Debian Live profile is the right integration point for Plasma: it already
uses the package manager and service manager expected by upstream KDE. The
legacy path remains independent and unchanged. Neither path is a supported
release; the XFCE profile's screenshot gate is still under investigation.

| Area | Existing implementation | Plasma integration strategy |
|---|---|---|
| Linux base and kernel | Custom cross-built kernel in legacy path; Debian kernel in prototype | Keep both; Plasma lives only in the Debian prototype |
| Init and services | Custom init / BusyBox in legacy; systemd in prototype | Use systemd for SDDM, NetworkManager, audio and user sessions |
| Package manager | `lpm` in legacy; apt/dpkg in prototype | Install Debian KDE packages from the pinned Debian snapshot |
| Root filesystem | CPIO initramfs in legacy; live-build SquashFS in prototype | Extend the prototype package list and chroot includes |
| ISO and boot | GRUB hybrid ISO in legacy; live-build GRUB BIOS/UEFI in prototype | Keep existing prototype boot pipeline and add a `plasma` profile |
| Existing GUI | X11/dwm and custom scripts; separate XFCE desktop prototype | Preserve both; add a separate SDDM/Plasma profile |
| Login | No full legacy desktop login; LightDM for XFCE prototype | SDDM with upstream Breeze greeter and ShreeOS-owned defaults |
| Panel and dock | dwm bar in legacy; XFCE panel + Plank in prototype | Start with Plasma defaults/configuration; custom shell work is later |
| Networking, audio, Bluetooth, power | Basic custom tools in legacy; NM/PipeWire/BlueZ in prototype | Use plasma-nm, plasma-pa, BlueDevil, PowerDevil and their services |
| Installer | Shell installer in legacy; Calamares config in prototype | Retain upstream Calamares dependency/config; validate install flow later |
| CI | Multiple legacy workflows; Debian prototype build/QEMU workflow | Extend prototype validation to package manifest and Plasma session |

## First integration slice

The new `plasma` profile installs Debian's `kde-plasma-desktop`, SDDM, Dolphin,
Konsole, Ark, Spectacle, Plasma network/audio widgets, PowerDevil and BlueDevil.
It uses ShreeOS's existing original logo and wallpapers, dark Breeze color
defaults, Papirus icons, four virtual desktops, KRunner's Meta+Space shortcut,
and an SDDM autologin for the locked-password temporary live user. No KDE source
is vendored or forked.

Discover does not have a configured package source in this profile yet. Debian's
prototype has apt/dpkg, but Discover's usable Debian backend has not been
established here, and no Flatpak remote is configured. Do not treat Discover
as a working software center until a supported backend and source are added
and tested.

This slice is a package-and-session foundation, not the finished ShreeOS shell.
It does not yet implement the custom floating dock, top-panel arrangement,
original light/dark theme packages, custom SDDM/lock-screen artwork, quick
settings, custom KWin effects, or an installed-system acceptance run. The
first QEMU gate checks the package manifest and that SDDM starts Plasma; visual
and functional hardware acceptance remains required.

## Upstream-code provenance

No upstream source files have been copied or adapted in this integration
slice. `docs/UPSTREAM_CODE.md` is the tracking table for any future copied
component. Before each copy, record the exact upstream path and revision,
inspect its license and notices, preserve required text, and document ShreeOS
changes. For this profile, KDE applications and components remain Debian
package dependencies.
