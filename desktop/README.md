# Desktop Environment

X11 + lightweight window manager (dwm) optional package layer.

## Layout

```
desktop/
├── wm/
│   ├── sources.list        # Pinned upstream URLs (dwm, st, dmenu)
│   ├── build-wm.sh         # Cross-compile suckless tools
│   └── build-all.sh        # Orchestrator
├── configs/
│   ├── xinitrc.template    # X session startup
│   ├── dwm-config.template # WM keybindings
│   └── autostart/
└── README.md
```

## Building

```bash
bash desktop/wm/build-all.sh
```

## Components

| Package | Purpose |
|---------|---------|
| dwm 6.5 | Dynamic window manager |
| st 0.9.2 | Terminal emulator |
| dmenu 5.3 | Application launcher |

## Prerequisites

- Cross-compiler (`x86_64-shreeos-linux-gnu-gcc`)
- X11 headers + libs in sysroot
