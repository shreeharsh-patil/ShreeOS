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
The desktop is experimental and has not yet been built, booted, or visually
verified in this workspace. Neither profile is a supported desktop release.
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
it passes; visual appearance still requires manual review.
