# Debian Live base prototype

This is an isolated Phase 2/3 build path. It uses Debian Live's maintained
`live-build`, `live-boot` and `live-config` stack to create an amd64 hybrid ISO
with a SquashFS root, systemd, apt/dpkg, a temporary ShreeOS account whose
password is locked during boot, and a serial-visible boot marker. It has no
default login password and does not grant the live account sudo access. The
existing source-built ISO target is unchanged.

The default `base` profile is deliberately console-only. An optional
`desktop` profile adds Debian's XFCE task, LightDM autologin, PipeWire,
BlueZ/Blueman, common desktop applications, ShreeOS wallpaper and greeter
branding, and the DFSG-compliant `firmware-linux-free` package from `main`.
It also configures an XFCE top panel, four workspaces, left-aligned window
controls, a centered translucent Plank dock with magnification, original dark
and light wallpapers, and Arc/Papirus/Inter appearance defaults. The desktop
is experimental and has not yet been built, booted, or visually verified in
this workspace. Its XFCE session is a staged desktop composition, not yet a
custom shell with a ShreeOS control center, overview, notification center, or
installer. An initial GTK Control Center offers Wi-Fi, Bluetooth, audio and
dark/light appearance switches, a hardware backlight slider when available,
and notification focus mode with links to existing XFCE tools; its interactive
behavior still needs Linux desktop validation. Airplane mode and power-profile
controls are still missing. Neither profile is a supported desktop release.
`Super+Space` opens Shree Search for applications, files in common user
folders, and bounded calculator expressions; the GUI still needs Linux review.
`Super+Up` opens a text-based Workspace Overview for switching desktops and
activating, moving, or closing windows. It has no window thumbnails or gesture
support yet. Thunar's sidebar includes common personal folders, Computer,
Network, and Trash; the dock includes ShreeOS search and quick controls, and
the top panel has a recent-notifications dropdown.
Ctrl+Alt+Left/Right switches workspaces; Ctrl+Alt+Shift+Left/Right moves the
focused window, and Super+1–4 selects a workspace directly.
The image identifies itself as a Debian-derived ShreeOS prototype and uses
Debian's signed repositories for installed-system updates.

## Build host

Build in Debian 13 (Trixie) as root. Required tools are `live-build`,
`debootstrap`, `xorriso`, `squashfs-tools`, `grub-pc-bin`,
`grub-efi-amd64-bin`, `mtools`, `dosfstools` and `qemu-system-x86` for boot
validation. CI installs these in a Debian Trixie container and pins
`live-build` to the version in `versions.conf`.

```sh
make prototype-debian
make test-prototype ISO=out/shreeos-0.3.0-prototype-amd64.iso

# Optional desktop profile.
make prototype-debian SHREEOS_LIVE_PROFILE=desktop
make test-prototype SHREEOS_LIVE_PROFILE=desktop \
  ISO=out/shreeos-0.3.0-prototype-desktop-amd64.iso
```

Images are built from the Debian Trixie snapshot in `versions.conf`; live-build
configures the running system to use Debian's signed Trixie and security
repositories. The desktop profile uses Debian's XFCE task and its standard
recommended applications, including a graphical package manager. Build output,
exact package manifests, checksums and metadata are written under ignored
`build/` and `out/` directories.

The build script refuses to run without root because live-build must debootstrap
and configure a target root filesystem. Use a disposable Linux VM or CI; native
Windows and WSL without a working Linux distribution are not supported build
hosts. Both profiles lock the live account's default password and withhold
sudo access. The desktop QEMU test requires the XFCE session to start before
it passes, and now also requires the panel and dock processes. Static CI checks
validate the XML, menu, wallpaper, theme, and dock launcher contracts. The
appearance and interactive behavior still require a graphical Linux review.
