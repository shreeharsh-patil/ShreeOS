# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.2-dev] - 2026-09-27

Publishes `shreeos-0.2.2-dev-desktop.iso` under the `v0.2.2-dev` tag, following
the `v0.2.1-dev` release. The desktop image is built and certified entirely by
GitHub Actions: native X11 / Mesa / Xorg stack, root filesystem, ISO structure,
BIOS and UEFI QEMU boots, and the full automated test suite.

### Fixed
- Xorg client libraries (libXext, libXi, libXinerama, libXrandr) no longer abort
  their cross-build with "cannot run test program while cross compiling"; the
  `malloc(0)` probe is answered for the target instead of being run.
- Mesa is built with `-Dgallium-drivers=swrast`, the name mesa 24.x accepts and
  the one `-Dglx=xlib` requires (the old `softpipe` value is rejected).
- Xorg fbdev/keyboard/mouse drivers use the configure script shipped in their
  release tarballs; regenerating it with host macros left
  `XORG_DRIVER_CHECK_EXT` unexpanded and aborted configure.
- `dwm`'s keymap defines `dmenucmd`, which `spawn()` dereferences
  unconditionally, and binds Super+space through it so the launcher opens on the
  focused monitor.
- `st`'s configuration carries the keyboard, mouse, selection and geometry
  settings st 0.9.2's `x.c` requires, and defines `defaultcs` to match the
  `extern` declaration in `st.h`.
- The centered-Spotlight `dmenu` patch has valid unified-diff headers again.
- dwm, st and dmenu are all built with the ShreeOS cross compiler; st ships its
  `CC` line commented out, so the compiler is now forced on the make command line.
- The strict graphics-readiness certification runs after `/etc/X11` is staged.
- QEMU ISO boot tests resolve the default ISO path from `PROFILE`.
- The default-profile smoke check ignores an ambient `PROFILE`, so the
  minimal-profile Kernel workflow no longer fails it.
- `shreeinfo` reports the version the system was built as instead of a
  hardcoded string.

## [Unreleased]

### Added
- Milestone 1: repository scaffold — directory structure, `build.conf`,
  shared `scripts/common.sh` helpers, architecture and roadmap docs,
  per-component README stubs, MIT license, contribution guide.
