# ShreeOS 0.4.0 unified Plasma desktop ISO (development)

The unified image extends the Debian 13 Live KDE Plasma prototype with
selected native ShreeOS utilities, using normal Debian package management.
It is NOT a binary concatenation of two incompatible operating systems.

## Safe integration boundaries

- Debian Linux kernel packages, glibc, systemd (PID 1), GRUB, SDDM, Calamares,
  drivers, NetworkManager, apt and dpkg remain authoritative.
- ShreeOS owns branding, its Plasma layout, read-only native "shreeinfo",
  original terminal system monitor, native `shreed` C daemon, the `shreedctl`
  client, and integration diagnostics. The daemon runs as a distinct systemd
  service (not a replacement for systemd or NetworkManager).
- LPM code and the .lpkg specification are distributed as **reference sources**
  in /usr/share/doc/shreeos-native-tools/lpm, not as an active root-level
  package manager. Native LPM uses different paths and ownership rules from dpkg.
- The experimental native init/kernel/BusyBox/dwm pipeline remains independently
  buildable and is not installed over Debian's boot-critical components.
- Native utilities are installed as shreeos-native-tools_0.4.0_amd64.deb and
  persist from the live image to a disk installation via the SquashFS root.

## Build on Debian 13

Install dependencies listed in .github/workflows/unified-iso.yml, then run
as root in a disposable Debian 13 VM or container:

    make unified-iso

Expected outputs:
    out/ShreeOS-0.4.0-amd64.iso
    out/ShreeOS-0.4.0-amd64.iso.sha256
    out/ShreeOS-0.4.0-packages.txt
    out/ShreeOS-0.4.0-build-info.txt

Check:
    bash tests/prototype/test-iso.sh out/ShreeOS-0.4.0-amd64.iso plasma
    bash tests/unified/test-iso-contents.sh out/ShreeOS-0.4.0-amd64.iso

## No unverified release claims

QEMU BIOS/UEFI Live boot and screenshot checks do not prove that Calamares
can install onto a virtual disk. Before labelling this ISO installable,
install through Calamares in a disposable VM for BIOS and UEFI, power off,
detach the ISO, boot from disk, login and use the Plasma desktop; verify
the native tools, NetworkManager, signed APT updates, reboot/shutdown and
filesystem integrity. Save the evidence and fix failures.

The CI workflow uploads development artifacts only. Publishing to GitHub
Releases must remain blocked until the above acceptance checks pass.

## Installed VM acceptance

In separate BIOS and UEFI disposable VMs, install the unified image using
Calamares to a 25 GB virtual disk. Shut down, eject the ISO, cold-boot from
the installed disk, log in to Plasma and run `shreeos-verify-installed`.
It must print `SHREEOS_INSTALLED_OK`. Check that the ShreeOS native system
monitor launches, and verify network connectivity and signed APT updates.
Capture installation, boot and desktop screenshots. This is not automated
by the current CI and must pass before publishing a public release.
