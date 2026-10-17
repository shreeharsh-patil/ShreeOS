# ShreeOS unified architecture

ShreeOS is one operating system with one build and one release artifact. This
document records what the repository actually contains, what was integrated into
the unified image, what is deliberately left out, and what is still missing.

## The one product

```
make shreeos   ->   out/shreeos(VERSION).iso
```

- **Foundation**: Debian 13 (Trixie), amd64, from the pinned snapshot in
  `prototype/debian-live/versions.conf`.
- **Desktop**: KDE Plasma with X11 and Wayland sessions, SDDM, KWin, Dolphin,
  Konsole and Discover. The live desktop starts X11 so Plank is available.
- **One image, two modes**: the same SquashFS is the live desktop *and*, via
  Calamares, the installed system. There is no separate live and install media.
- **One root filesystem, one desktop environment.** No second Linux userspace,
  no dual install, no competing session.

`VERSION` in the repository root is the single authoritative version source.
`build.conf`, `prototype/debian-live/versions.conf`, the generated
`/etc/os-release`, the ISO filename and the release tag all derive from it, and
`scripts/verify-version.sh` fails the build when any of them drifts.

## Integration matrix

### Reused directly

Components taken from Debian unchanged, because replacing them with a
source-built counterpart would trade a working system for a worse one.

| Component | Why it is reused |
|---|---|
| Linux kernel, initramfs, firmware | `linux-image-amd64` plus the standard firmware set; Debian's driver and hardware coverage is the point |
| systemd and udev | Required by Plasma, Calamares, NetworkManager and PipeWire; a custom init here would break all four |
| glibc and shared libraries | Binary compatibility for every packaged application |
| APT, dpkg, Debian signed repositories and security updates | Software Center, installer source provisioning and update management all rest on it |
| GRUB, xorriso, live-boot | Hybrid BIOS/UEFI boot and the live medium |
| NetworkManager, BlueZ, PipeWire/WirePlumber | Wi-Fi, Bluetooth and audio, including the Plasma tray applets wired to them |
| KDE Plasma, KWin, SDDM, KDE applications | The shell; ShreeOS configures it rather than reimplementing it |
| Calamares | The graphical installer |
| Mesa and the X11 stack | Graphics and X11 support; the live desktop starts X11 so Plank is available |

### Adapted or packaged for ShreeOS

| Component | How it is integrated |
|---|---|
| Desktop layout | `desktop/plasma/layout.js` builds the top panel from installed Plasma widgets and writes ShreeOS defaults once per user |
| Look and feel | `themes/plasma/` color schemes and the `shreeos-glass` desktop theme, installed into `/usr/share/plasma` |
| Branding | `branding/` logos, wallpapers, icons and the generated PNG exports, used by the desktop, SDDM, Calamares, Plymouth and GRUB |
| SDDM greeter | Original QML theme in `prototype/debian-live/profiles/plasma/.../usr/share/sddm/themes/shreeos` |
| Dock | Plank, pinned and themed by ShreeOS, with a ShreeOS Glass dock theme |
| Search | KRunner plus the ShreeOS launcher entries, bound to `Meta+Space` |
| Motion | `shreeos-motion` maps balanced/performance/reduced onto native KWin effect settings |
| Power | `shreeos-power` maps Performance/Balanced/Battery Saver onto power-profiles-daemon plus the motion profile |
| Software Center | `shreeos-software` drives APT for system packages, with Discover for the GUI |
| Installer integration | `shreeos-installer` wrapper, privileged helper, scoped polkit action, and the `shreeos-sources` Calamares module that provisions signed target repositories |
| Native ShreeOS utilities | The versioned `shreeos-tools` Debian package provides Debian-aware `shreeinfo` and `shree-doctor` commands |
| Boot checking and measurement | `shreeos-live-boot-check` and `shreeos-perf-probe`, live-media only |
| Compressed swap | Bounded zram (`min(ram / 2, 2048)`, lz4) via `systemd-zram-generator` |

### Optional, not in the default image

| Component | How it is available |
|---|---|
| Developer, security and creative tool sets | Build-time `SHREEOS_TOOLSETS=developer,security,creative`, installed through the ShreeOS software entry point |
| Flatpak applications | Flathub remote is configured; no Flatpak apps are bundled |
| Free-firmware-only image | `SHREEOS_FIRMWARE=free` |
| Office and multimedia applications | The `office` and `multimedia` bundles can be installed through `shreeos-software`; neither suite is in the default image |

Keeping these out is what holds the image size and the boot-time package graph
down. They are installable, not shipped.

### Cannot safely coexist (and is therefore excluded)

| Component | Why |
|---|---|
| A second desktop environment (GNOME, XFCE, Budgie) | Doubles the session process tree and the settings stack. `tests/prototype/test-performance-config.py` fails if one is added to the desktop manifest |
| A second dock provider alongside Plank | Two docks claim the same screen edge and both keep a window-tracking service resident |
| The native `lpm` package manager alongside APT | It would compete with APT over Debian-managed files. It stays in the tree as experimental source and is not installed into the image |
| The native source-built root filesystem as a second userspace | Two inits, two libc lineages and two boot paths in one ISO is a dual-boot arrangement, not a distribution |
| Wayland in the live session | Plank is X11-only, so the live desktop starts X11. The installed image includes both sessions; users can choose at the SDDM login screen |

### Still missing

| Gap | Where it is tracked |
|---|---|
| Interactive installer acceptance on real media | `release/INSTALL-ACCEPTANCE.md`, gated by the release job |
| Untouched-build performance comparison | `tests/prototype/performance-baseline.tsv` must record the baseline before Stage E can pass; the candidate must improve idle RAM or CPU by at least 20%, unless the untouched build already meets both limits |
| Real-hardware certification (Wi-Fi, Bluetooth, audio, printers, suspend/resume, GPU) | `docs/SYSTEM-READINESS.md` |
| Encryption and dual-boot install paths | `release/INSTALL-ACCEPTANCE.md` known gaps |
| Signed ShreeOS-authored `.deb`s and a ShreeOS package repository | `docs/SYSTEM-READINESS.md` |
| Wayland session | matrix above |

The untouched comparison source is `9313ebb042cf71bb148441037940b130d49920d1`, the pre-optimization revision used for this change. The baseline workflow builds that source separately, overlays only the identical measurement probe, service, and duration helper, then records three valid QEMU samples. A baseline record must name the untouched source commit, include the measured ISO SHA-256, and use the same 2-vCPU, 4096-MiB, VirtIO, 1280x800, no-network conditions, pinned QEMU/SeaBIOS packages, and BIOS ROM hash. The release job rejects missing or mismatched provenance and evaluates absolute targets and regressions on the candidate median. Every raw sample must report a ready desktop, available PSS instrumentation, and no failed system units. Storage throughput remains informational because hosted-runner backing storage varies.

To collect it, dispatch `.github/workflows/performance-baseline.yml`, inspect all three archived samples and the aggregate summary, then commit the reviewed aggregate as `tests/prototype/performance-baseline.tsv`. Candidate measurements are captured separately, all samples are retained, and the median is compared with that reviewed baseline.

## Build and release paths

| Path | Entry point | Output | Status |
|---|---|---|---|
| **Unified ShreeOS desktop** | `make shreeos` / `scripts/build-shreeos.sh` | `out/shreeos(VERSION).iso` + checksum, package manifest, build info, JSON manifest | The product |
| Console and XFCE Debian Live experiments | `SHREEOS_LIVE_PROFILE=base\|desktop bash scripts/build-debian-prototype.sh` | `out/shreeos-VERSION[-desktop]-amd64.iso` | Experimental, never published |
| Source-built native image | `make iso` (legacy pipeline) | `shreeos-VERSION[-profile].iso` | Experimental research path, no longer published |

One pipeline publishes anything:
`.github/workflows/shreeos-release.yml`, with stages A (static checks), B
(build), C (BIOS/UEFI boot and real desktop screenshots), D (installer payload,
safety checks and recorded interactive acceptance), E (idle RAM, CPU and cold
boot against absolute limits and the untouched-build comparison) and F (release). Stage F refuses to run unless
every earlier stage succeeded.

## Why the dock is Plank, not a Plasma panel widget

`docs/COMPONENT_INTEGRATION_MATRIX.md` records the evaluation. In short: the
session is X11, Plank is an X11 dock with magnification, running-app indicators
and per-user pinned items, and it themes consistently with the ShreeOS Glass
panel. A Plasma `org.kde.plasma.icontasks` panel was the alternative; it was not
selected because a second panel must then own window tracking and compositing
decisions that Plank already owns, and the layout is deliberately a single top
panel so that KWin's floating panel geometry is not reset on first login.
`tests/prototype/test-performance-config.py` fails if a competing dock provider
is added to the package manifest.

## Verification

| Question | Checked by |
|---|---|
| Is the version consistent everywhere? | `scripts/verify-version.sh`, `tests/release/test-version-contract.sh` |
| Is the image structurally complete? | `tests/prototype/test-iso-squashfs.sh` |
| Does it boot on BIOS and UEFI with a real desktop? | `tests/prototype/test-iso.sh` |
| Can the shipped installer actually run? | `tests/prototype/test-installer-payload.sh`, `tests/installer/test-installer-validation.sh` |
| Does an interactive install work? | `release/INSTALL-ACCEPTANCE.md` (recorded acceptance) |
| How much RAM and CPU does it idle at? | `tests/prototype/test-performance-report.sh` against `prototype/debian-live/performance-targets.tsv` |
| Are the idle-cost and power defaults intact? | `tests/prototype/test-performance-config.py` |

## Known limitations of this document

Everything above describes the repository's design and its automated gates. It
does not assert that a current image has been built and booted: the only
environment available while these changes were made was Windows, where
live-build and QEMU cannot run. The Linux pipeline results, not this document,
are the evidence.
