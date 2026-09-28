# Phase 1 Audit — Current State of ShreeOS

Audit date: 2026-09-28
Commit: `d2726fb` (master)

This document records what ShreeOS **actually is today**, verified from the
implementation and from measurements of a real built image — not from the
README. Every claim below was checked against code or a measured number.

Reproduce with:

```sh
make audit                       # source-tree report (JSON + text)
make audit-iso ISO=path.iso      # full image report
make test-audit                  # the audit tool's own test suite
```

---

## 1. What actually goes inside the current ISO

Measured from the released `shreeos-0.2.1-dev-desktop.iso`
(`build/audit/iso-report.txt`, `build/audit/rootfs-files.txt`):

| Component | Measured size | Notes |
|---|---:|---|
| ISO image | ~237 MB | single profile image |
| `/boot/bzImage` | ~12 MiB | kernel 6.18 |
| `/boot/initramfs.cpio.gz` | ~205 MiB | **the entire operating system** |
| ├ uncompressed cpio | ~560 MiB | 12,000+ files |
| └ `/lib/modules/6.18/` | ~60 MiB | kernel modules |
| `/boot/grub/` + EFI images | ~1 MiB | GRUB2, i386-pc + x86_64-efi |

**There is no SquashFS image and no overlayfs layer.** The live filesystem
*is* the initramfs. `init.c` performs `switch_root` directly into the cpio
tree. This is the single most consequential architectural fact in the project.

### Why the ISO is ~237 MB rather than several GB

Three independent reasons, all measured:

1. **Development artifacts are shipped.** The rootfs contains static archives
   that no distribution ever ships to users:

   | File | Size |
   |---|---:|
   | `libstdc++.a` (×2 copies) | ~66 MiB |
   | `libc.a` | ~23 MiB |
   | `libcrypto.a` | ~11 MiB |

   That is **~100 MiB of linker-only input** — roughly 40% of the compressed
   image — that should be deleted before packaging, not shipped.

2. **Non-runtime data dominates what remains.** ~38 MiB of compiled locale
   catalogues, ~15 MiB of man pages and documentation. This is appropriate for
   a *source* tarball or a `-dbg` image, not for a live desktop.

3. **There is almost no software to ship.** With ~100 MiB of genuinely
   runtime-relevant content after removing the above, and ~60 MiB of that
   being kernel modules, the remainder is a minimal C userspace plus X11.
   There are **0 bytes of Linux firmware**, **0 application packages**,
   **0 non-kernel drivers**, and every "application" is a shell or Tcl
   script rather than a program.

A correctly packaged image of the *current* component set would be roughly
**80–120 MB**. The image is ~237 MB only because of items 1 and 2. Growth
toward a complete desktop must come from real content (firmware, drivers,
Mesa, browsers, fonts, applications), never from padding.

---

## 2. Architecture as implemented

### Build pipeline

`scripts/build.sh` runs seven ordered, individually cached stages:

```
toolchain → kernel → base-system → packages → desktop → rootfs → iso
```

Each stage has a `verify-stage.sh` postcondition check, so a stale cache
marker cannot mask a missing output. Source pinning is enforced by
`scripts/verify-sources.sh` (SHA-256, HTTPS-only, no all-zero placeholders).

### Toolchain

| Item | Value |
|---|---|
| Target triplet | `x86_64-shreeos-linux-gnu` |
| GCC | 14.2.0 |
| binutils | 2.43.1 |
| glibc | 2.40 |
| Kernel | 6.18 |

A genuine cross-toolchain is built from source; the target sysroot contains no
host Ubuntu binaries. Host contamination is not currently a problem.

### Boot path

```
GRUB2 (BIOS El Torito + UEFI removable-media path)
  → /boot/bzImage  (kernel 6.18)
  → /boot/initramfs.cpio.gz   (≈205 MiB — whole OS)
       → init.c: mount pseudo-filesystems, load modules, switch_root
  → /sbin/init  (custom C PID 1, init/src/init.c)
  → Xorg → dwm + picom + ShreeOS shell desktop
```

GRUB2, El Torito for BIOS, and a removable-media EFI path are all present and
CI-verified on both BIOS and UEFI.

### What is real and working

These were verified by reading the code and by passing CI, and should be
preserved deliberately through every later phase:

- Cross-compiled toolchain and glibc.
- Linux 6.18 with a maintained, desktop-oriented config.
- 26 base-system packages built from pinned upstream sources.
- A 45-package X11/graphics stack (libdrm, Mesa/swrast, Xorg, libinput, …).
- BIOS **and** UEFI boot, verified in QEMU on every build.
- A working `lpm` package manager in C with a documented `.lpkg` format.
- A non-trivial desktop session (dock, launcher, panel, notifications, file
  manager, settings) that boots to a usable graphical screen.
- Checksum enforcement, staging, and licence/provenance documentation.

---

## 3. Component gap analysis

| Component | Current state | Working | Prod. ready | Missing | Required action |
|---|---|:-:|:-:|---|---|
| **Init system** | Custom C `init.c` as PID 1 | ✅ | ❌ | systemd, udev, logind, journald, ordered units, `systemctl` | Phase 3 |
| **Live filesystem** | Whole OS inside initramfs; no SquashFS, no overlayfs | ✅ | ❌ | `filesystem.squashfs`, overlay upperdir, `switch_root` from a small initramfs | Phase 5 |
| **Base userspace** | 26 packages, C-only | ✅ | ❌ | systemd, dbus, PAM, shadow, sudo, kmod, iproute2, ACL/attr, bzip2/zstd, findutils, locale generation | Phase 2 |
| **Account database** | `passwd`/`group`/`shadow` written; no PAM, no `sudo`, no `sysusers` | ⚠️ | ❌ | PAM stack, `sudo` policy, `useradd`, real groups, per-user homes | Phase 2 |
| **Firmware** | **None** | ❌ | ❌ | All of it: iwlwifi, `iwlwifi-ucode`, `ath10k`, Broadcom, Realtek, AMD GPU, Intel, MediaTek, Qualcomm | Phase 4 |
| **Kernel config** | Desktop-oriented, not broad-hardware modern | ⚠️ | ❌ | exFAT, NTFS3, Btrfs, XFS, NVMe, Realtek, Broadcom, touchpad, BT, webcam, modern DRM | Phase 4 |
| **Graphics** | Mesa **swrast only** | ⚠️ | ❌ | Hardware DRM drivers (iris, amdgpu, nouveau), Vulkan drivers, `zink` | Phase 6 |
| **Desktop shell** | Bash/Tcl + dwm; no native compiled apps | ⚠️ | ❌ | Real login manager, lock screen, portal, native settings backend | Phase 7 |
| **Networking** | BusyBox `udhcpc` + `wpa_supplicant` | ⚠️ | ❌ | NetworkManager, `systemd-resolved`, IPv6, hotspot, VPN, reconnection | Phase 8 |
| **Bluetooth** | BlueZ built; not integrated | ⚠️ | ❌ | `bluetoothd` service, pairing UI, audio routing | Phase 8 |
| **Firewall** | None | ❌ | ❌ | nftables, safe default policy | Phase 8 |
| **Audio** | ALSA utilities only | ⚠️ | ❌ | PipeWire + WirePlumber, per-app volume, Bluetooth audio | Phase 9 |
| **Package manager** | Real C `lpm`, real `.lpkg` format, real DB | ✅ | ❌ | `update`/`upgrade`/`search`/`info`/`files`/`verify`, dependency resolution, signatures, repos | Phase 10 |
| **Applications** | Scripts only | ❌ | ❌ | Browser, terminal, text editor, PDF/image viewer, media player, archiver, monitor | Phase 11 |
| **Installer** | `install-shreeos` launcher exists | ⚠️ | ❌ | Real graphical installer, partitioning, user creation, bootloader install | Phase 12 |
| **Updates** | Partial | ⚠️ | ❌ | Signed repos, kernel/firmware updates, GUI updater | Phase 13 |
| **Security hardening** | No PAM, no sudo policy, no signing | ❌ | ❌ | PAM, sudoers, signed metadata, Secure Boot architecture, nftables | Phase 13 |
| **Recovery** | None | ❌ | ❌ | Rescue target, fsck, package repair, protected shell | Phase 13 |
| **i18n / a11y / printing** | tzdata only | ❌ | ❌ | locale-gen, keyboard layouts, CUPS, SANE, accessibility | Phase 14 |
| **Branding** | GRUB/Plymouth assets exist | ⚠️ | ❌ | Consistent boot→login→desktop identity | Phase 15 |
| **CI/CD** | 7 workflows, real QEMU boot tests, no suppressed failures | ✅ | ⚠️ | Missing stages: firmware, packages, initramfs, SquashFS, ISO validation, desktop, installer, recovery, release gate | Phase 17 |

---

## 4. The architectural problems that must be fixed, in order

1. **The live filesystem lives in the initramfs.** Until this changes, the
   image cannot grow past RAM-and-compression limits, cannot use overlayfs for
   a writable live session, and does not have the structure of a real
   distribution. This is Phase 5 and it gates meaningful desktop growth.
2. **PID 1 is a custom C program.** It works, but it means there is no
   `systemctl`, no dependency ordering, no journal, no reliable recovery
   mode, and no `loginctl` session management. Phase 3.
3. **No firmware and no hardware drivers.** The system cannot drive real
   Wi-Fi, real GPUs, or real webcams. Everything hardware-related is
   `REQUIRES PHYSICAL HARDWARE VALIDATION` until firmware ships. Phase 4.
4. **Mesa is software-rendered only.** There is no hardware acceleration
   path at all. Phase 6.
5. **No application payload.** There is no browser, no real editor, no real
   media player. The "applications" are scripts. Phase 11.
6. **No installer.** The ISO cannot be installed to disk. Phase 12.
7. **`lpm` cannot manage a system.** No repos, no dependencies, no
   signatures, no upgrades. Phase 10.

---

## 5. Rules this audit establishes for later phases

- **No padding.** ISO size must grow only from real content. If a "desktop"
  image lands in the 200–300 MB range, that is a signal that components were
  omitted — the audit tool reports the category breakdown so the omission is
  visible rather than hidden.
- **No host contamination.** The target sysroot is cross-built. Adding
  debootstrap-style host binary copies would regress this and is prohibited.
- **No suppressed failures.** The audit tool scans every workflow for
  `continue-on-error` and `|| true` and reports violations.
- **No placeholder checksums.** All-zero SHA-256 values are rejected by
  `verify-sources.sh` and reported by the audit tool.
- **Honest hardware claims.** Anything that can only be proven on real silicon
  is labelled `REQUIRES PHYSICAL HARDWARE VALIDATION` and is never reported
  as passing.

---

## 6. Audit tooling

`tools/shreeos-audit.py` produces machine-readable JSON for any source tree,
assembled rootfs, or built ISO, and is covered by 43 self-tests
(`tests/audit/test-shreeos-audit.py`). `.github/workflows/audit.yml` runs it
in CI, uploads the reports as artifacts, and can audit a specific released ISO
via `workflow_dispatch`.

The tool exists because this audit had to answer "what is actually in the
image?" reliably and repeatably. Reading a 12,000-entry cpio listing by hand
is not a process that scales across eighteen phases.

### Phase 1 exit criteria

- [x] Audit complete — every subsystem inspected from source
- [x] Architecture understood — pipeline, boot path, and data flow documented
- [x] Current ISO contents documented with measured sizes
- [x] Critical missing areas identified with required actions
- [x] Machine-readable audit report produced by CI
- [x] Audit tool self-tested (43 tests passing)
