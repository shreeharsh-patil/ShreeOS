# ShreeOS Desktop Environment

A minimal, high-performance desktop experience combining X11, lightweight window management (dwm), smooth GPU-accelerated compositing (picom), Inter/JetBrains typography, and native system utilities.

## Visual Design Standards

- **Color Harmony:** Neutral dark `#1C1C1E` / light `#F5F5F7` surfaces with restrained cool blue `#2878FF` accents.
- **Typography:** Inter UI and JetBrains Mono monospace with subpixel RGB antialiasing.
- **Window Geometry:** 10px corner radii, crisp 1px borders, and realistic ambient drop shadows.
- **Top System Bar:** Compact 28px height displaying workspace indicators, active window titles, memory, load, network status, battery, and date/clock.
- **Spotlight-Style Launcher:** Centered modal search (`Super + Space`) for instant access to apps, files, and settings.

## Desktop Suite Layout

```
desktop/
├── apps/                   # Native desktop applications
│   ├── shree-about         # System specifications & identity dialog
│   ├── shree-settings      # System settings panel
│   ├── shree-control-center# Quick toggles (Wi-Fi, dark mode, volume, brightness)
│   └── shree-pkgmanager    # Package browser & frontend for lpm
├── configs/                # X11 & window manager configuration
│   ├── Xresources          # System fonts & 16-color neutral terminal palette
│   ├── picom.conf          # Compositor rules (shadows, corner radius, vsync)
│   ├── dwm-config.h        # dwm keybindings & layout definitions
│   ├── st-config.h         # Terminal emulator typography & padding
│   ├── dmenu-config.h      # Centered search launcher palette
│   └── xinitrc.template    # X session orchestrator
├── scripts/
│   ├── shree-topbar.sh     # System metrics status feed
│   └── shree-launcher.sh   # Super+Space modal search launcher
├── wm/
│   ├── sources.list        # Pinned upstream sources
│   ├── build-wm.sh         # Cross-compilation scripts
│   └── build-all.sh        # Build & stage orchestrator
└── README.md
```

## Default Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Super + Space` | Open ShreeOS Search / Application Launcher |
| `Super + Return` | Launch Terminal (`st`) |
| `Super + q` | Close focused window |
| `Super + 1`–`4` | Switch to workspace 1–4 |
| `Super + b` | Toggle top bar visibility |
| `Super + t` | Tile layout mode |
| `Super + f` | Floating layout mode |
| `Super + m` | Fullscreen / monocle layout mode |
| `Super + Shift + q` | Quit desktop session |

## Building & Launching

```bash
# Build desktop components and install configs into sysroot
bash desktop/wm/build-all.sh

# Start graphical desktop session
startx
```
