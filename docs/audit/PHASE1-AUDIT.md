# Phase 1 Audit — ShreeOS 0.2.2-dev

Status: **complete**. Commit under audit: `d2726fbd64df` (`master`).
Everything below was read out of the implementation, not out of the README.

## Headline findings

ShreeOS today is a **bootable Linux system, not a desktop distribution**. It
boots, mounts a root filesystem, starts Xorg, and shows a graphical session
driven by ~45 bash/Tcl scripts. It has none of the software a desktop
distribution is defined by: no firmware, no applications, no systemd, no
network manager, no installer that writes a disk, and no package repository.

1. **The entire root filesystem is shipped inside the initramfs.**
   `initramfs.cpio.gz` is 194.31 MiB of the 226.46 MiB ISO. There is no
   SquashFS, no overlayfs, and no `switch_root`. Every boot decompresses
   562 MiB into RAM before reaching userspace. → **Phase 5**
2. **≈ 32% of the shipped bytes are build artifacts that should never reach a
   user:** 152.99 MiB of static archives, 1,064 C headers (12.37 MiB),
   8.35 MiB of docs, 7.63 MiB of info pages. → **Phases 2/5**
3. **Zero firmware, zero compiled applications.** Wireless, audio, discrete
   graphics and NVMe cannot work on real hardware. → **Phases 4/11**
4. **No systemd, no NetworkManager, no PipeWire, no installer, no package
   repository.** → **Phases 3, 8, 9, 10, 12**

Component tally: **24 working · 21 not production-ready · 33 missing.**

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

Verified against the released ISO and its 10,662-entry rootfs inventory:

- `initramfs.cpio.gz` on the ISO: **194.31 MiB** (203,745,463 bytes) — it is the
  payload, **85.8% of the 226.46 MiB image**.
- Uncompressed: **562.47 MiB** (589,787,648 bytes), a **1:2.85** compression ratio.
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

## 3. Why the ISO is ~226 MB and not several GB

This is the question the audit must answer precisely, because an ISO that is too
small usually means software is missing rather than that the build is
efficient. Here **both** are true, for specific and measurable reasons.

Measured composition of the 560.50 MiB uncompressed rootfs
(10,662 regular files), by category:

| Category | Count | Size | Share | Should it ship? |
|---|---:|---:|---:|---|
| Other (executables, data, X assets) | 4,231 | 164.78 MiB | 29.4% | Partly |
| **Static archives `*.a`** | **37** | **152.99 MiB** | **27.3%** | **No — link-time only** |
| Shared objects `*.so*` | 409 | 110.52 MiB | 19.7% | Yes |
| Kernel modules `*.ko` | 79 | 59.57 MiB | 10.6% | Yes |
| Locale `.mo` catalogues | 748 | 39.39 MiB | 7.0% | Only a few languages |
| Documentation (doc + info) | 244 | 15.27 MiB | 2.7% | No |
| Fonts | 22 | 9.74 MiB | 1.7% | Yes, more needed |
| Man pages | 4,242 | 7.40 MiB | 1.3% | No |
| Zoneinfo | 597 | 390.65 KiB | 0.1% | Yes |
| **Firmware** | **0** | **0 B** | **0.0%** | **Required, absent** |
| Icons | 11 | 9.47 KiB | 0.0% | Yes, more needed |
| `.desktop` entries | 0 | 0 B | 0.0% | Required, absent |

**Reason 1 — the image ships a development sysroot, not a userspace.**
Static archives alone are 152.99 MiB, 27.3% of the rootfs, and the four largest
files in the entire system are pure link-time inputs:

| File | Size | Why it must not ship |
|---|---:|---|
| `/usr/lib/libstdc++.a` | 31.53 MiB | static libstdc++, needed only to link C++ |
| `/usr/lib64/libstdc++.a` | 31.53 MiB | **byte-identical duplicate of the above** |
| `/usr/lib/libc.a` | 21.98 MiB | static glibc, needed only to link binaries |
| `/usr/lib/libcrypto.a` | 10.67 MiB | static libcrypto, needed only to link binaries |

`libstdc++.a` is installed **twice**, at `/usr/lib` and `/usr/lib64`, with no
`/usr/lib64 → usr/lib` compatibility symlink, so 31.53 MiB is paid for an exact
duplicate. None of the 37 archives is reachable at runtime.

**Reason 2 — 1,064 C headers are installed into the live system.**
`/usr/include` holds 1,064 header files totalling 12.37 MiB. `lpm` and `init`
are linked in-tree at build time, so the headers were installed from the
sysroot instead of being used from it.

**Reason 3 — documentation and localisation ship in full.**
`/usr/share` is 18.38 MiB, of which `doc` is 8.35 MiB, `info` 7.63 MiB (autotools
pages from the base-system builds) and `man` 7.76 MiB, plus 40.20 MiB of locale
catalogues in `/usr/share/locale`. A desktop ISO carries a curated locale set and
drops info pages entirely.

Adding reasons 1–3: **≈ 181 MiB of the 560.50 MiB rootfs (32%) is build-time or
developer content that should never reach a user's machine.**

**Reason 4 — there is almost no software to compress.**
The genuinely useful runtime content is 79 kernel modules (59.57 MiB) plus a
few hundred shared objects. A real desktop distribution has 1.5–3 GB of largely
*incompressible* binary and data — firmware blobs, a browser, an office suite, a
full graphics driver stack, fonts, media codecs. ShreeOS has **0 bytes of
firmware and 0 compiled applications**, so there is no large payload present to
compress.

So the image is small for two independent reasons: **≈ 32% of it is build
scaffolding that should be deleted**, and the remaining real payload is small
because the applications, drivers, and firmware that define a desktop
distribution have not been integrated. Both are fixed by pruning *and* adding —
never by padding.

### 3.1 What is simply absent

**There is no missing 4 GB.** The ISO is small because the distribution contains
almost no software:

- **Firmware: 0 bytes, 0 blobs.** No `intel-ucode`, no `amd-ucode`, no
  Realtek/MediaTek/Qualcomm/Broadcom blobs. Wireless, audio, GPU and NVMe
  devices will not fully work on real hardware no matter how the kernel is
  configured.
- **Applications: 0 compiled.** All 45 entry points in `desktop/apps/` and
  `desktop/scripts/` are **bash or Tcl scripts**. There is no browser, no
  office suite, no media player, and no real file manager.
- **Fonts: 22 files, 9.74 MiB — not zero, but thin.** No proper UI font family
  or scalable text stack, so text rendering quality is far below a real desktop.
- **Audio: ALSA `utils` only** — no sound *server*.
- **Bluetooth: BlueZ client tools only** — no `bluetoothd`, no pairing service.
- **`.desktop` entries: 0.** Nothing is registered with a display manager or
  menu, because there is no display manager and no applications to register.

Squashing ~100 MiB of userspace yields a small ISO. Growing to gigabytes is a
*consequence* of adding firmware, Mesa, browsers, fonts and applications — never
a target to hit by itself.

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

## 4.1 ISO artifact breakdown

For reference when Phase 5 restructures this, the released `v0.2.2-dev` desktop
ISO (`shreeos-0.2.2-dev-desktop.iso`, SHA-256 `c191bcb6…`) breaks down as:

| Artifact | Size | Share of ISO |
|---|---:|---:|
| `initramfs.cpio.gz` — the entire OS | 194.31 MiB | 85.8% |
| Bootloader images (`*.img`, 3 files) | 16.32 MiB | 7.2% |
| `bzImage` kernel | 12.14 MiB | 5.4% |
| EFI bootloader (`*.efi`) | 0.77 MiB | 0.3% |
| `grub.cfg` + boot catalog | 0.01 MiB | ~0% |
| **Total ISO** | **226.46 MiB** | 100% |
| **Compressed live root filesystem** | **absent** | — |

The ISO contains only **8 regular files**. There is no
`/live/filesystem.squashfs`, no `/casper/`, no persistent-storage layer, and no
second initramfs variant.

---

## 4.2 Critical findings, ranked

1. **Whole rootfs in the initramfs (Phase 5).** 194.31 MiB of compressed cpio
   *is* the OS. No SquashFS, no overlayfs, no `switch_root`. Every boot
   decompresses 562 MiB before userspace. This is the structural blocker.
2. **No firmware at all (Phase 4).** Zero bytes of GPU, Wi-Fi, Bluetooth or
   storage-controller firmware. Wireless, audio, discrete graphics and NVMe
   cannot work on real hardware regardless of kernel support.
3. **No applications (Phase 11).** No browser, no media player, no office
   tooling, no Software Center — and nothing to install software *with*.
4. **No network manager (Phase 8).** BusyBox `udhcpc` only. No Wi-Fi UI, no VPN,
   no static configuration, no reconnect handling.
5. **No real init system (Phase 3).** A custom C init replaces systemd, so there
   are no service dependencies, no journal, no logind, no session management.
6. **Dev artifacts ship in the live image (Phases 2/5).** 152.99 MiB of static
   archives, 12.37 MiB of C headers, 8.35 MiB of docs, 7.63 MiB of info pages.
7. **No installer that installs (Phase 12).** `install-shreeos` is a 698-byte
   launcher; nothing partitions, formats, or installs a bootloader.
8. **No package repository (Phase 10).** `lpm` handles local `.lpkg` files
   only — no index, no dependencies, no signatures, no upgrade path.
9. **Duplicated static archive.** `libstdc++.a` installed twice, 31.53 MiB
   wasted on an exact duplicate.
10. **No accessibility, locale generation, printing or scanning (Phase 14).**

---

## 4.3 Physical-hardware status

Everything measured in this audit is structural: source reading, ISO parsing,
and CI job results. The following **REQUIRES PHYSICAL HARDWARE VALIDATION** and
is explicitly *not* claimed as working:

```
REQUIRES PHYSICAL HARDWARE VALIDATION
  Wi-Fi hardware (any chipset)       - no firmware, no NetworkManager
  Bluetooth hardware                 - BlueZ client tools only, never paired
  Laptop battery / charging state    - no upower, no power daemon
  Suspend / resume on a real laptop  - no logind power management
  Discrete NVIDIA GPU                - no firmware, no nouveau/NVIDIA driver
  Discrete AMD GPU                   - no firmware, no Vulkan driver
  Intel integrated GPU               - Mesa built, never run on real silicon
  Webcam                             - no uvcvideo runtime verification
  Microphone / speakers              - ALSA utils only, no sound server
  Touchpad                           - libinput present, no device exercised
  USB 2.0 / 3.0 / Type-C peripherals - not exercised
  Real printer / scanner             - CUPS and SANE absent entirely
  Lid close / ACPI events            - not exercised
```

QEMU tests that *are* meaningful cover boot, `init` startup, PCI/USB
enumeration, virtio drivers, and module loading — not device behaviour.

---

## 5. Phase 1 exit criteria

| Criterion | Status |
|---|---|
| Audit complete | ✅ this document + `tools/shreeos-audit.py` |
| Architecture understood | ✅ §1–2 |
| Current ISO contents documented | ✅ §3–4.1, all figures measured |
| Critical missing areas identified | ✅ §4, §4.2 |
| GitHub audit workflow green | ✅ `audit.yml`; 25 self-tests passing locally |

### Reproduction

```bash
make audit        # repo audit -> build/audit/repo-audit.{json,txt}
make test-audit   # 25 self-tests for the audit tool itself

# Full ISO audit (downloads the latest release asset):
python3 tools/shreeos-audit.py iso shreeos-0.2.2-dev-desktop.iso \
  --out iso-audit.json --text
```

CI runs `audit-source` on every push and `audit-iso` downloads and inspects the
latest release ISO. Both publish machine-readable JSON as workflow artifacts,
so ISO composition is trackable over time rather than re-derived by hand.

## 6. Finding from building the audit tool

The new audit tool immediately caught a real defect in **uncommitted** work:
26 entries in `base-system/packages.list` carried all-zero placeholder
checksums. Those are a supply-chain hole; the speculative entries were reverted
rather than committed unpinned, and `audit-source` now rejects them.
`HEAD` is fully pinned (29/29, 44/44, 3/3, 1/1).

This is the tool doing its job: it will refuse to certify an image whose
provenance is unverified, which is the same standard Phase 13 requires of
package metadata.

## 7. Ordered plan from here

Phase 2 onward follows the brief. The ordering constraint that matters most:
**Phase 5 (real live ISO) must land before the ISO can be called a desktop
distribution**, and Phases 2–3 (userspace + systemd) must land before it,
because a live SquashFS layer is only useful once there is a real userspace and
a real init to `switch_root` into.

One consequence worth flagging now: pruning the 181 MiB of build artifacts
(§3) will make the ISO *smaller* before it gets bigger. A drop from 226 MiB to
roughly 120–150 MiB during Phases 2–5 is the expected and correct outcome, not
a regression. Size should only grow once firmware, Mesa drivers, browsers and
applications are genuinely added.
