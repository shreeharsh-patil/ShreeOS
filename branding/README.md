# Branding

Distro name, logo, wallpapers, and theme driven by `DISTRO_NAME` in `build.conf`.

## Layout

```
branding/
├── logo/
│   ├── shreeos-logo.svg        # Primary white/blue vector emblem
│   ├── shreeos-logo-black.svg  # Monochrome for light surfaces
│   ├── shreeos-logo-white.svg  # Monochrome for dark surfaces
│   ├── shreeos-logo-adaptive.svg # currentColor variant with blue sun
│   └── png/                    # Transparent logo and app-icon size exports
├── icons/
│   ├── shreeos-app.svg         # System application icon
│   └── installer.svg           # Installer icon using the same emblem
├── scripts/
│   └── export-logo-pngs.py     # Rebuild PNG exports with Pillow
├── wallpapers/
│   ├── shreeos-wallpaper.svg   # Default desktop wallpaper
│   ├── shreeos-calm-dark.svg   # Dark appearance wallpaper
│   ├── shreeos-calm-light.svg  # Light appearance wallpaper
│   └── shreeos-alpenglow.png   # Plasma photographic wallpaper
├── theme/
└── README.md
```

## Usage

Branding assets are consumed by:
- `desktop/wm/build-all.sh` — copies wallpaper to rootfs
- `rootfs/scripts/make-rootfs.sh` — uses `DISTRO_NAME` in /etc/os-release
- ISO builder — uses `DISTRO_NAME` as volume label

The sunrise-horizon emblem is an original ShreeOS mark based on the attached
sunrise-emblem reference. A rising half-sun sits above two flowing horizon
lines; it contains no letterform or third-party artwork. The primary
white/blue version is used on dark branded surfaces;
black, white, and `currentColor` SVG variants support other surfaces. The
system app icon and installer icon reuse the same mark. All PNG exports have
transparent corners/backgrounds; the square application tile itself has a
dark rounded-square surface.

To regenerate the PNG exports, install Pillow (`python -m pip install Pillow`)
and run:

```sh
python3 branding/scripts/export-logo-pngs.py
```

Exports cover 16, 32, 64, 128, 256, and 512 pixels for the emblem; the app and
installer tiles are exported at 128, 256, and 512 pixels.
