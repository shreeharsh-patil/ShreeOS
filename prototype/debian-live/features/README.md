# System features

Shared payloads for the Debian Live profiles. The builder copies
`includes.chroot` and installs each toolset manifest under
`/usr/share/shreeos/toolsets`. Firmware and optional tool dependencies are
resolved by signed APT using the image's pinned Debian snapshot.

## Firmware

Graphical builds default to `SHREEOS_FIRMWARE=standard`: common AMD/Intel GPU,
Intel/Realtek/Atheros/Broadcom Wi-Fi, audio firmware, and CPU microcode from
Debian's `non-free-firmware` component. These contain proprietary firmware
under their respective redistribution licenses; retain the Debian packages'
copyright notices. This is broader coverage, not a hardware certification.
The console base defaults to `free`. Set `SHREEOS_FIRMWARE=free` on any profile
to keep only `main` and omit this package list.

## Optional software

```sh
# Build an image with these applications already installed (Debian 13 host).
sudo SHREEOS_LIVE_PROFILE=plasma SHREEOS_TOOLSETS=developer,security \
  bash scripts/build-debian-prototype.sh

# On an installed ShreeOS system, inspect and install a bundle using APT.
shreeos-software list
shreeos-software show security
shreeos-software install security
```

Developer: compilers, Git, CMake, Python environments, debugging.
Security: Nmap, Wireshark, tcpdump, tshark, Aircrack-ng, John, Hydra,
sqlmap, YARA, Lynis. Creative: GIMP, Inkscape, Kdenlive, Audacity, Blender.
These are selected Debian tools; no Ubuntu or Kali repository is mixed into
the system. Installation requires administrator authorization, refreshes
metadata, and preserves APT's confirmation and signature checks. Live-session
installation is refused because it would be lost at restart; use build-time
toolsets for live media. Bundles add no ShreeOS autostart entries or listeners.

## Installed update sources

The `shreeos-sources` Calamares Python job uses `rootMountPoint`, validates
paths and the Debian keyring, backs up image/media sources, and writes an
explicit HTTPS `debian.sources` with stable, updates and security suites.
Firmware policy determines its components. Backports and third-party sources
are not enabled by this module. It runs only during a fresh installation;
it is not an updater for existing users' repository settings.

`99-shreeos-security` enables freshness and signature enforcement at runtime.
The build script passes its snapshot expiry exception on APT's command line.
Discover and standard APT can update Debian applications without another ISO.
ShreeOS desktop files still require a versioned `.deb` and signed ShreeOS
repository before those customizations can be shipped through APT.

## Desktop performance and motion

Plasma selects its own graphics backend and retains driver safety checks.
`shreeos-motion` or the Desktop Motion settings entry offers:

| Choice | Behavior |
| --- | --- |
| balanced | Blur, Magic Lamp minimize, Scale opening, sliding workspaces, dock zoom |
| performance | Blur and Magic Lamp off; shorter transitions; dock zoom off |
| reduced | Animation factor zero; Scale, Slide, Magic Lamp and dock zoom off |

Overview remains available in every mode. Global application animation speed
may require reopening applications. The script changes effect preferences,
not CPU/GPU power policy or window layout. Applications may implement their
own animations; these settings cannot suppress every third-party animation.
These are native KDE equivalents of familiar Mac interactions.

Plasma includes `power-profiles-daemon` for supported hardware through KDE's
battery settings, and `systemd-zram-generator` for on-demand LZ4 compressed
swap, half of RAM capped at 2 GiB. It neither preallocates 2 GiB nor replaces
disk swap or sets up hibernation. Administrator overrides belong in
`/etc/systemd/zram-generator.conf.d/50-shreeos.conf`. Boot with
`systemd.zram=0` to diagnose without compressed swap. Benefits depend on load;
there are no measured boot, memory or frame-time improvements yet.

## Checks

```sh
bash tests/prototype/test-config.sh
python3 tests/prototype/test-system-features.py
python3 tests/prototype/test-plasma-config.py
```

The ISO test additionally checks the declared firmware policy, desktop
packages and feature assets. Full installation, update, graphics, printing,
accessibility, suspend/resume, and zram acceptance require a Linux VM or PC.

Sources used to check interfaces:

- [Calamares Python job API](https://github.com/calamares/calamares/blob/v3.3.14/src/modules/dummypython/main.py)
- [Polkit GUI environment and argument handling](https://github.com/polkit-org/polkit/blob/126/docs/man/pkexec.xml)
- [KDE effects](https://docs.kde.org/stable_kf6/en/kwin/kcontrol/kwineffects/)
- [zram-generator configuration](https://github.com/systemd/zram-generator/blob/v1.2.1/man/zram-generator.conf.md)
- [Debian firmware policy](https://www.debian.org/releases/trixie/amd64/ch02s02.en.html)
