# ShreeOS Glass

Original Plasma 6 style for the ShreeOS X11 desktop. It overrides the panel
background with a flat translucent surface and uses the installed Breeze style
for other widgets. Text and surface colors follow the selected color scheme.
The opaque variant keeps the bar readable without compositing.

The prototype builder installs this directory in
`/usr/share/plasma/desktoptheme/shreeos-glass`. First-login setup selects it
with `plasma-apply-desktoptheme shreeos-glass`.

The top panel uses native application menu, global menu, clock and tray widgets.
Plank provides the bottom dock, including running-app indicators, drag-to-pin,
tooltips and hover magnification. Its preferences and light/dark themes live in
the Plasma profile under `usr/share/shreeos/defaults` and `usr/share/plank`.

Run `bash tests/prototype/test-config.sh` for source configuration checks.
Build the Plasma ISO on Debian 13 and run the BIOS/UEFI boot checks to verify
the actual desktop. A source or preview check does not certify live rendering.

Upstream format reference:
https://develop.kde.org/docs/plasma/theme/theme-details/
