# Historical ShreeOS Phase 1 Audit

> **Historical baseline, not a current inventory.** This report describes
> commit `53e9371`. The repository and build manifests have changed since then.
> See [the implementation plan](../IMPLEMENTATION-PLAN.md) for current
> observations and regenerate an audit from the current ISO before relying on
> package counts, sizes or runtime capabilities.

Verified against commit `53e9371` on `master`. Every claim below was read out of
the source, not out of the README. The machine-readable form of this audit is
produced by `tools/shreeos-audit.py` and runs in CI as the **Distribution Audit**
workflow.

Reproduce with:

```sh
python3 tools/shreeos-audit.py repo --root . --out build/audit/repo-audit.json --text
python3 tools/shreeos-audit.py iso out/shreeos-0.2.2-dev-desktop.iso --text
```

## 1. What the current ISO actually contains

The ISO is **not** a live distribution. It is a kernel plus a single large cpio
archive that contains the entire userspace.

```
shreeos-0.2.2-dev-desktop.iso          ~237 MiB
├── /boot/bzImage                     kernel 6.18, 12 MiB
├── /boot/initramfs.cpio.gz           ~215 MiB  <-- the whole operating system
├── /boot/grub/grub.cfg               BIOS + UEFI entries
├── /boot/grub/i386-pc/eltorito.img   El Torito BIOS image
├── /boot/grub/x86_64-efi/efi.img     El Torito UEFI image
└── /EFI/BOOT/BOOTX64.EFI              UEFI fallback
```

`rootfs/scripts/make-rootfs.sh` walks the staging tree and writes it to
`build/initramfs.cpio.gz`. The ISO builder copies that one file to `/boot` and
GRUB boots it as `initrd`. There is no `filesystem.squashfs`, no `/live/`
directory, no overlayfs, and no `switch_root`.

Consequences that matter for every later phase:

- The "initramfs" is a full userspace, so it is unpacked into RAM on every boot.
  A 2 GiB rootfs in RAM is not viable; this caps how large the desktop can grow.
- Read-only live media is not available, so the root filesystem is a tmpfs-like
  copy and writes are not persisted.
- Nothing in the boot path is a *boot* path. It is a full system load wearing a
  boot image's filename.

## 2. Why the ISO is a few hundred MB instead of several GB

Measured on the released 0.2.1 image (`build/audit/released-rootfs-report.txt`),
the ~562 MiB uncompressed rootfs breaks down as:

| Category | Size | Share | Belongs in a shipped ISO? |
|---|---:|---:|---|
| `libstdc++.a` (two copies) | 66 MiB | 12% | **No** — static C++ dev archive |
| `libc.a` | 23 MiB | 4% | **No** — static libc dev archive |
| Locale catalogs | 38 MiB | 7% | Partly — all locales, no pruning |
| `libcrypto.a` | 11 MiB | 2% | **No** — static dev archive |
| Man pages and docs | 15 MiB | 3% | No — not needed on a live image |
| Kernel modules | ~60 MiB | 11% | Yes, but no firmware accompanies them |
| Everything else | ~350 MiB | 63% | Real userspace |

**Roughly 100 MiB of the payload is development artifacts that should never
ship.** The ISO is small not because the system is complete, but because almost
nothing has been added yet:

- **0 bytes of firmware.** No `/lib/firmware`. The kernel ships ~60 MiB of
  modules with no blobs to feed them, so no Wi-Fi, Bluetooth, GPU, or audio
  device will initialise on real hardware.
- **0 application software.** No browser, no office suite, no media player.
- **0 NetworkManager, 0 systemd, 0 PipeWire, 0 BlueZ daemon, 0 nftables.**

The static archives are the clearest symptom. They are left in the staging tree
because no packaging step strips `*.a` and `*.la` files, and a distribution
whose payload is 19% static link libraries is a development sysroot, not a
desktop.

## 3. Component status

| Component | Current state | Working | Prod. ready | Missing | Required action |
|---|---|---|---|---|---|
| Toolchain | GCC 14.2, binutils 2.43.1, glibc 2.40, cross-built | Yes | Yes | — | Keep pinned |
| Kernel | 6.18, custom defconfig, builds | Yes | Partly | Broad hardware coverage, microcode | Phase 4 |
| Boot | GRUB2, BIOS + UEFI El Torito, boots in QEMU | Yes | Partly | Theme, splash, recovery entries | Phase 15 |
| **Live architecture** | **Whole OS in `initramfs.cpio.gz`** | **Yes** | **No** | **SquashFS, overlayfs, `switch_root`** | **Phase 5** |
| **Init system** | **Custom C `init` as PID 1** | **Yes** | **No** | **systemd, udev, journald, logind** | **Phase 3** |
| Base userspace | 26 hand-built packages, real glibc/bash/coreutils | Yes | Partly | procps, file, findutils, ACL, attr, libcap, rsync | Phase 2 (in progress) |
| Accounts | passwd/group/shadow generated, sudo policy present | Yes | Partly | PAM-aware login, systemd-homed | Phase 2/3 |
| Filesystem layout | FHS skeleton present | Yes | Partly | tmpfiles, sysusers, `/run` policy | Phase 3 |
| **Firmware** | **absent** | **No** | **No** | **All of it** | **Phase 4** |
| **Applications** | **absent** | **No** | **No** | **All of it** | **Phase 11** |
| Networking | iproute2, wpa_supplicant, `udhcpc` only | Partly | No | NetworkManager, resolved, nftables | Phase 8 |
| Bluetooth | BlueZ *libraries* built, no daemon | No | No | `bluetoothd`, `bluetoothctl` | Phase 8 |
| Audio | ALSA + `amixer` | Partly | No | PipeWire, WirePlumber, per-app volume | Phase 9 |
| Graphics | Xorg, Mesa (swrast), Xlib stack, dwm, picom | Yes | Partly | Vulkan, real DRI drivers, GPU firmware | Phase 6 |
| Desktop shell | 45 bash/Tcl scripts, no compiled apps | Partly | No | Compiled apps, portals, HiDPI | Phase 7 |
| Package manager | `lpm` in C, `.lpkg` format, local only | Partly | No | Repos, signatures, deps, `update`/`upgrade` | Phase 10 |
| Installer | Shell scripts, partition + copy + GRUB | Partly | No | Graphical, automated CI install test | Phase 12 |
| Updates | `system-update.sh` transactional updater | Partly | No | Signed repo metadata | Phase 13 |
| i18n / a11y / printing | Not integrated | No | No | Locales, CUPS, SANE, a11y settings | Phase 14 |
| CI | 8 workflows, ISO builds and boots in QEMU | Yes | Partly | Audit job, size regression guard | Phase 1/17 |
| Branding | 18 files, original | Yes | No | GRUB theme, Plymouth, wallpapers | Phase 15 |

## 4. The five things that most limit ShreeOS today

1. **No firmware.** Nothing works on real hardware. This is the single largest
   gap between "boots in QEMU with virtio" and "boots on a laptop".
2. **The live architecture is wrong.** It must become kernel + small initramfs +
   SquashFS + overlayfs before the system can grow past a few hundred MB.
3. **No applications.** A desktop with no browser or file manager cannot be used
   daily, which is the actual product requirement.
4. **No init system.** A bespoke C init means no service ordering, no journald,
   no `systemctl`, and no way to run a real desktop session's service graph.
5. **Development files ship.** ~100 MiB of static archives and unpruned locale
   data inflate the payload while contributing nothing at runtime.

## 5. Physical hardware status

Everything validated so far has been structural or QEMU-based on GitHub-hosted
runners. The following remain **`REQUIRES PHYSICAL HARDWARE VALIDATION`** and
have *not* been tested:

- Wi-Fi (any chipset), Bluetooth radio pairing and audio routing
- Laptop battery, ACPI lid events, suspend/resume
- Intel / AMD / NVIDIA GPU acceleration, multi-monitor, HDMI audio
- Webcam, microphone, touchpad, touchscreen
- USB 2/3/C peripheral enumeration, USB-C alt-modes
- Secure Boot with a signed shim
- Printing and scanning against real devices

No claim of physical-hardware validation is made anywhere in this document.

## 6. Reproducing the size measurement

The audit tool parses ISO 9660, Rock Ridge, El Torito, cpio `newc` and SquashFS
4.0 directly, so it can describe an image without xorriso or unsquashfs:

```sh
python3 tools/shreeos-audit.py iso out/shreeos-0.2.2-dev-desktop.iso \
  --out build/audit/iso-audit.json --text
```

It reports ISO size, live-rootfs format, compressed and uncompressed rootfs
size, file and module counts, and which desktop components are present or
missing. Its own parsers are covered by `tests/audit/test-shreeos-audit.py`
(43 tests) so the numbers can be trusted.
