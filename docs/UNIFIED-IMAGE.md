# ShreeOS unified Plasma desktop ISO (development)

The unified image extends the Debian 13 Live KDE Plasma prototype with
selected native ShreeOS utilities, using normal Debian package management.
It is NOT a binary concatenation of two incompatible operating systems.

## Safe integration boundaries

- Debian Linux kernel packages, glibc, systemd (PID 1), GRUB, SDDM, Calamares,
  drivers, NetworkManager, apt and dpkg remain authoritative.
- ShreeOS owns branding, its Plasma layout, read-only `shreeinfo` from the
  `shreeos-tools` package, original terminal system monitor, native `shreed` C
  daemon, the `shreedctl` client, and integration diagnostics. The daemon runs
  as a distinct systemd service (not a replacement for systemd or NetworkManager).
- LPM code and the .lpkg specification are distributed as **reference sources**
  in /usr/share/doc/shreeos-native-tools/lpm, not as an active root-level
  package manager. Native LPM uses different paths and ownership rules from dpkg.
- The experimental native init/kernel/BusyBox/dwm pipeline remains independently
  buildable and is not installed over Debian's boot-critical components.
- Native utilities are installed as versioned `shreeos-tools` and
  `shreeos-native-tools` packages and persist from the live image to a disk
  installation via the SquashFS root.
- The hardware daemon runs as the unprivileged `shreed` system account with an
  empty capability set and a read-only systemd filesystem sandbox. Its IPC
  socket is mode `0660` in `shree-hardware`; the live user and Calamares-created
  users receive that group through their supported account setup paths.

## Build on Debian 13

Install dependencies listed in .github/workflows/unified-iso.yml, then run
as root in a disposable Debian 13 VM or container:

    make unified-iso

Expected outputs:
    out/shreeos(VERSION).iso
    out/shreeos(VERSION).iso.sha256
    out/shreeos(VERSION)-packages.txt
    out/shreeos(VERSION)-build-info.txt
    out/shreeos(VERSION)-manifest.json

The release candidate build enforces an ISO size below 1,900,000,000 bytes.
The manifest records the source commit, image profile, pinned Debian snapshot,
component versions, byte size and SHA-256 of the exact ISO.

Check:
    iso="out/shreeos($(tr -d '[:space:]' < VERSION)).iso"
    bash tests/prototype/test-iso.sh "$iso" plasma
    bash tests/unified/test-iso-contents.sh "$iso"

## No unverified release claims

QEMU BIOS/UEFI Live boot and screenshot checks do not prove that Calamares
can install onto a virtual disk. Before labelling this ISO installable,
install through Calamares in a disposable VM, power off, detach the ISO, boot
from disk, log in and use the Plasma desktop; verify the native tools,
NetworkManager, signed APT updates, reboot/shutdown and filesystem integrity.
Save the evidence and fix failures.

The CI workflow uploads development artifacts only. Publishing to GitHub
Releases must remain blocked until the above acceptance checks pass.

## Installed VM acceptance

Use a separate 25 GB disposable GPT disk for each Calamares path. Boot the
installer in UEFI mode for both runs. The guided erase-disk layout is
configured with a 2 MiB unformatted GPT BIOS Boot Partition and Calamares
prepends a 512 MiB EFI System Partition mounted at `/boot/efi`. For manual
partitioning, create an unformatted 2 MiB BIOS Boot Partition (type
`21686148-6449-6e6f-744e-656564454649`), a 512 MiB FAT32 EFI System Partition
(type `c12a7328-f81f-11d2-ba4b-00a0c93ec93b`) mounted at `/boot/efi`, and an
ext4 root partition. Calamares 3.3.14 creates the guided ESP only when started
in UEFI mode; the ShreeOS installer then installs BIOS GRUB to the same
validated GPT target disk. Do not start the installer in BIOS mode. For each
installation, shut down, eject the ISO, then boot the same installed disk in
both UEFI and legacy BIOS modes. Log in to Plasma and run
`shreeos-verify-installed`; it must print `SHREEOS_INSTALLED_OK`. Check that
the ShreeOS native system monitor launches, and verify network connectivity
and signed APT updates. Capture installation, cross-firmware boot and desktop
screenshots. This is not automated by the current CI and must pass before
publishing a public release.
