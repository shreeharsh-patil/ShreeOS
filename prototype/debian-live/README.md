# Debian Live base prototype

This is an isolated Phase 2/3 build path. It uses Debian Live's maintained
`live-build`, `live-boot` and `live-config` stack to create an amd64 hybrid ISO
with a SquashFS root, systemd, apt/dpkg, a temporary ShreeOS live user, and a
serial-visible boot marker. The existing source-built ISO target is unchanged.

The base is deliberately console-only at this milestone. It does not claim to
be the requested desktop distribution. Desktop packages, redistributable
firmware selection, graphical installer and installed-system tests are later
gates. The image identifies itself as a Debian-derived ShreeOS prototype and
uses Debian's signed repositories for installed-system updates.

## Build host

Build in Debian 13 (Trixie) as root. Required tools are `live-build`,
`debootstrap`, `xorriso`, `squashfs-tools`, `grub-pc-bin`,
`grub-efi-amd64-bin`, `mtools`, `dosfstools` and `qemu-system-x86` for boot
validation. CI installs these in a Debian Trixie container and pins
`live-build` to the version in `versions.conf`.

```sh
make prototype-debian
make test-prototype ISO=out/shreeos-0.3.0-prototype-amd64.iso
```

The image is built from the Debian Trixie snapshot in `versions.conf`; live-build
configures the running system to use Debian's normal signed Trixie and security
repositories. Build output and package inventory are written under ignored
`build/` and `out/` directories.

The build script refuses to run without root because live-build must debootstrap
and configure a target root filesystem. Use a disposable Linux VM or CI; native
Windows and WSL without a working Linux distribution are not supported build
hosts.
