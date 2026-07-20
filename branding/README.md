# Branding

Distro name, logo, wallpapers, and theme driven by `DISTRO_NAME` in `build.conf`.

## Layout

```
branding/
├── logo/
│   └── shreeos-logo.svg        # Vector logo
├── wallpapers/
│   └── shreeos-wallpaper.png   # Default desktop wallpaper
├── theme/
└── README.md
```

## Usage

Branding assets are consumed by:
- `desktop/wm/build-all.sh` — copies wallpaper to rootfs
- `rootfs/scripts/make-rootfs.sh` — uses `DISTRO_NAME` in /etc/os-release
- ISO builder — uses `DISTRO_NAME` as volume label
