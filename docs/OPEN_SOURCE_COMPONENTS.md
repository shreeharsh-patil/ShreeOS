# Open-source components

The entries below describe the intended Debian Live Plasma profile. The exact
versions in a built image are recorded in its package manifest. Each package
retains its Debian copyright and license record under `/usr/share/doc/`.

| Component | Upstream | License | ShreeOS usage |
|---|---|---|---|
| KDE Plasma (`kde-plasma-desktop`, `plasma-desktop`, `plasma-workspace`) | [KDE](https://invent.kde.org/plasma) | GPL-2.0-or-later and LGPL-2.1-or-later components; file-specific notices apply | Official desktop and workspace packages |
| KWin (`kwin-x11`) | [KDE KWin](https://invent.kde.org/plasma/kwin) | GPL-2.0-or-later; package record governs | Official X11 window manager and compositor |
| SDDM | [SDDM](https://github.com/sddm/sddm) | GPL-2.0-or-later; package record governs | Official display manager with Breeze theme |
| Dolphin | [KDE Dolphin](https://invent.kde.org/system/dolphin) | GPL-2.0-or-later; package record governs | Official file manager |
| Konsole | [KDE Konsole](https://invent.kde.org/utilities/konsole) | GPL-2.0-or-later; package record governs | Official terminal |
| Ark | [KDE Ark](https://invent.kde.org/utilities/ark) | GPL-2.0-or-later; package record governs | Official archive manager |
| KDE Spectacle (`kde-spectacle`) | [KDE Spectacle](https://invent.kde.org/graphics/spectacle) | GPL-2.0-or-later; package record governs | Official screenshot tool |
| Plasma NetworkManager | [KDE plasma-nm](https://invent.kde.org/plasma/plasma-nm) | GPL-2.0-or-later; package record governs | NetworkManager UI and tray integration |
| Plasma Audio | [KDE plasma-pa](https://invent.kde.org/plasma/plasma-pa) | GPL-2.0-or-later; package record governs | Audio controls |
| PowerDevil | [KDE PowerDevil](https://invent.kde.org/plasma/powerdevil) | GPL-2.0-or-later; package record governs | Power and battery management |
| BlueDevil | [KDE BlueDevil](https://invent.kde.org/plasma/bluedevil) | GPL-2.0-or-later; package record governs | Bluetooth integration |
| Linux, systemd, NetworkManager, PipeWire, BlueZ | Respective upstream projects | Multiple licenses by package and file | Kernel, session/services, network, audio, Bluetooth |
| ShreeOS logo and wallpapers | ShreeOS | See repository `LICENSE` and asset notices | Original distribution branding |

This is a component map, not a complete notice bundle. Before redistributing
an image, inspect the exact package manifest and preserve all corresponding
Debian copyright and license files. See [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md).
