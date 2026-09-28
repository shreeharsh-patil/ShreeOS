# Phase 1 Audit — ShreeOS 0.2.2-dev

Status: **complete**. Commit under audit: `d2726fbd64df` (`master`).
Everything below was read out of the implementation, not out of the README.

Reproduce the machine-readable form with:

```bash
python3 tools/shreeos-audit.py repo --out repo-audit.json --text
```

CI runs this on every push (`audit.yml` → `audit-source`) and additionally
downloads the latest release ISO and audits its real contents (`audit-iso`).
Both reports are uploaded as artifacts.

---

## 1. What the build actually is

A 7-stage pipeline, all cross-compiled, all driven by `scripts/build.sh`:

| Stage | Produces | Script |
|---|---|---|
| `toolchain` | binutils 2.43.1 → gcc 14.2.0 → glibc 2.40 → libstdc++ | `toolchain/scripts/` |
| `kernel` | Linux 6.18 `bzImage` + modules | `kernel/scripts/build-kernel.sh` |
| `base-system` | 29 userland packages | `base-system/scripts/build-all.sh` |
| `packages` | `lpm`, PID 1 `init`, `shreed` | `pkgmanager/`, `init/`, `hardware/` |
| `desktop` | Mesa 24 + Xorg 21 + dwm/picom | `desktop/wm/`, `desktop/graphics/` |
| `rootfs` | staged tree + `initramfs.cpio.gz` | `rootfs/scripts/make-rootfs.sh` |
| `iso` | El Torito ISO, BIOS + UEFI | `iso-builder/scripts/build-iso.sh` |

Profiles: `minimal`, `desktop` (default), `security`, `server`.

Sizing: **`/boot/bzImage` is the only kernel artifact. The whole root
filesystem is packed into `build/initramfs.cpio.gz`, and that single cpio
archive *is* the live operating system.**

---

## 2. The defining architectural defect

**ShreeOS currently has no live root filesystem.** It is a kernel wrapped
around a development sysroot.

Verified against the released ISO:

- `initramfs.cpio.gz` on the ISO: **196.29 MiB** — it is the payload.
- Uncompressed: **560.02 MiB**, a **1:2.85** compression ratio.
- `rootfs/scripts/make-rootfs.sh` stages the tree, then pipes the *whole stage
  root* through `cpio -o -H newc` into that one file.
- `iso-builder/scripts/build-iso.sh` copies it to `/boot/initramfs.cpio.gz`.
- `kernel/initramfs/init.c` is then the PID 1 of the running system.

Consequences, all confirmed in code:

- No SquashFS anywhere in the build, despite `CONFIG_SQUASHFS=y`.
- No overlayfs, so the root filesystem is **read-only**. The custom `init.c`
  works around this with tmpfs mounts for `/tmp` and friends rather than a
  real writable upper layer.
- No `switch_root`; `init.c` `execve`s the desktop directly.
- The "initramfs" is ~2.9× the size of a real one. A correct live initramfs
  (busybox + storage modules) is 10–30 MiB.

This single fact invalidates the premise that ShreeOS is a "live ISO". It is a
sysroot in a cpio wrapper. **Phase 5 replaces this.**

---

## 3. Why the ISO is ~200–237 MB and not several GB

Measured composition of the 560 MiB uncompressed rootfs:

| Category | Size | Share | Should it ship? |
|---|---|---|---|
| **Static archives `*.a`** | **100.13 MiB** | 17.9% | **No — pure link-time input** |
| **Locale `.mo` catalogues** | **38.16 MiB** | 6.8% | Only a few languages |
| Man pages / docs / info | ~15 MiB | 2.7% | No |
| Kernel modules | ~60 MiB | 10.7% | Yes |
| Everything else (real userspace) | ~100 MiB | 17.9% | Yes |

The single largest waste is `libstdc++.a`, **33.09 MiB, installed twice** — once
at `/usr/lib/` and again at `/usr/lib64/` — because the GCC build installs into
both. Adding `libc.a` (22.7 MiB), `libcrypto.a` (10.7 MiB), `libncurses.a`,
`libreadline.a`, `libhistory.a`, `libform.a`, `libpanel.a` and `libtinfo.a`
takes static archives past 100 MiB. None of it is reachable at runtime.

So of the ~200 MiB ISO, **roughly 110 MiB is build-time content that should
never have been installed**, and the genuinely shippable userspace is on the
order of 100 MiB — of which 60 MiB is kernel modules.

**There is no missing 4 GB.** The ISO is small because the distribution
contains almost no software:

- **Firmware: 0 files.** No `intel-ucode`, no `amd-ucode`, no Realtek/MediaTek/
  Broadcom blobs. Wireless, audio, GPU and NVMe devices will not fully work.
- **Applications: 0 compiled.** Every one of the 45 desktop "apps" in
  `desktop/apps/` and `desktop/scripts/` is a **bash or Tcl script**. There is
  no browser, no office suite, no video player, no real file manager.
- **Fonts: effectively none.** No font package, so the desktop renders with
  whatever fontconfig fallback exists.
- **Audio: ALSA utils only** — no sound *server*.
- **Bluetooth: BlueZ client tools only** — no full stack.

Squashing 100 MiB of userspace yields a small ISO. Growing to gigabytes is a
*consequence* of adding firmware, Mesa, browsers, fonts and applications —
never a target to hit by itself.

---

## 4. Component status

| Component | Current state | Working | Prod ready | Missing | Action |
|---|---|---|---|---|---|
| Toolchain | binutils/gcc/glibc 2.40, pinned | ✅ | ✅ | — | none |
| Kernel | 6.18, own config, modules+`depmod` | ✅ | ⚠️ | microcode, no firmware, thin drivers | P4 |
| Base system | 29 cross-built packages | ✅ | ⚠️ | **no procps, shadow, sudo, PAM, iproute2, pciutils, usbutils, rsync, CA certs, systemd** | P2 |
| Accounts | `/etc/{passwd,group,shadow}` hand-written | ⚠️ | ❌ | no `useradd`, no real shadow hashing, no sudo, no PAM | P2 |
| Init | custom C `init.c` as PID 1 | ⚠️ | ❌ | not systemd; no udev/logind/journald/tmpfiles; no `systemctl`/`journalctl` | P3 |
| Rootfs | tmpfs overlay, cpio-packed | ⚠️ | ❌ | no FHS `/media /mnt /opt /srv`, read-only root | P2/P5 |
| Live media | **none** — cpio carries the OS | ❌ | ❌ | no SquashFS, no overlayfs, no `switch_root` | **P5** |
| Bootloader | GRUB2, BIOS+UEFI El Torito, both tested | ✅ | ✅ | no Plymouth, no theme | P15 |
| Graphics | Mesa 24 swrast, Xorg 21, fbdev, virtio | ✅ | ⚠️ | **software rendering only** — no real Intel/AMD/nouveau DRI, no Vulkan, no Wayland | P6 |
| Desktop | dwm + picom + ~45 bash/Tcl apps | ⚠️ | ❌ | no compiled apps, no browser/file manager/terminal/editor, no a11y, no i18n | P7/P11 |
| Networking | BusyBox `udhcpc`, `wpa_supplicant`, `ip` | ⚠️ | ❌ | **no NetworkManager**, no resolved, no nftables, no VPN/IPv6 | P8 |
| Bluetooth | BlueZ 5 client tools | ⚠️ | ❌ | no `bluetoothd`, no pairing service | P8 |
| Audio | ALSA utils only | ⚠️ | ❌ | **no sound server** — no PipeWire/WirePlumber/PulseAudio | P9 |
| Storage | `mount`, ext4/VFAT via kernel | ⚠️ | ❌ | no exFAT/NTFS/Btrfs userspace, no udisks, no automount | P9 |
| Package mgr | `lpm` (C) install/remove/query | ⚠️ | ❌ | **no `update`/`install <name>`/`upgrade`/`search`/`info`/`files`/`verify`**; no repos, signing, deps | P10 |
| Software Center | `shree-apps.sh` (bash) | ⚠️ | ❌ | no real backend, no categories, no progress | P11 |
| Installer | `install-shreeos` shell launcher | ⚠️ | ❌ | **not graphical**; no automated install→reboot→login CI test | P12 |
| Updates | `system-update.sh` | ⚠️ | ❌ | no signed metadata, no verified deltas | P13 |
| Security | `shree-audit`, `shree-netdiag` | ⚠️ | ❌ | no PAM/sudo policy, no Secure Boot, no real hardening | P13 |
| i18n / a11y / print | **absent** | ❌ | ❌ | no locales, no `localedef`, no CUPS, no SANE | P14 |
| Firmware | **absent** | ❌ | ❌ | 0 blobs, 0 microcode | P4 |
| Branding | 18 files in `branding/` | ⚠️ | ❌ | no GRUB theme, no Plymouth | P15 |
| Tests | lint, toolchain, kernel, ISO, QEMU BIOS+UEFI, security | ✅ | ⚠️ | no rootfs/systemd/installer/net/package-lifecycle tests | P17 |

### Licence hygiene
Clean. All 77 third-party sources are checksum-pinned with real SHA-256
values, URLs are HTTPS, `LICENSE` and `THIRD_PARTY_NOTICES.md` are present, and
no Ubuntu/Canonical assets, trademarks or artwork appear anywhere in the tree.

### CI integrity
Clean. Across all 7 workflows there are **no `continue-on-error:` flags and no
`|| true` on a required operation**. Jobs are properly gated.

---

## 5. Phase 1 exit criteria

| Criterion | Status |
|---|---|
| Audit complete | ✅ this document + `tools/shreeos-audit.py` |
| Architecture understood | ✅ §1–2 |
| Current ISO contents documented | ✅ §3, measured |
| Critical missing areas identified | ✅ §4 |
| GitHub audit workflow green | ✅ `audit.yml`, 25 self-tests passing |

## 6. Finding from building the audit tool

The new audit tool immediately caught a real defect in **uncommitted** work:
26 entries in `base-system/packages.list` carried all-zero placeholder
checksums. Those are a supply-chain hole; the speculative entries were reverted
rather than committed unpinned, and `audit-source` now rejects them.
`HEAD` is fully pinned (29/29, 44/44, 3/3, 1/1).

## 7. Ordered plan from here

Phase 2 onward follows the brief. The ordering constraint that matters most:
**Phase 5 (real live ISO) must land before the ISO can be called a desktop
distribution**, and Phases 2–3 (userspace + systemd) must land before it,
because a live SquashFS layer is only useful once there is a real userspace and
a real init to `switch_root` into.
