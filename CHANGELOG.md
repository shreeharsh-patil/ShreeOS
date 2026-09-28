# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `tools/shreeos-audit.py`: a machine-readable distribution audit tool with
  `repo`, `rootfs`, and `iso` subcommands. It parses `build.conf` without
  sourcing it, audits every source manifest for pinned checksums, reads ISO
  9660 + Rock Ridge + El Torito and newc cpio and SquashFS superblocks in
  pure Python, and reports the live payload broken down by category plus
  desktop-component coverage.
- `tests/audit/test-shreeos-audit.py`: 25 self-tests covering the manifest,
  `build.conf`, cpio and SquashFS parsers, plus an end-to-end audit of the
  real tree. Wired into `make test-audit` and `make test-all`.
- `.github/workflows/audit.yml`: an audit gate that publishes
  `repo-audit.json` and, optionally, inspects a released ISO and publishes
  `iso-audit.json` as a build artifact.
- `docs/audit/PHASE1-AUDIT.md`: the Phase 1 audit, with measured ISO
  contents, the explanation of the current ISO size, and the component
  status table.
- `make audit`, `make audit-iso ISO=...`, `make test-audit` targets.
- `tools/check-workflow-shell.py`: extracts every `run: |` block from a
  workflow, neutralises GitHub expressions, and parses it with `bash -n`, so a
  shell typo inside CI is caught by `make test-audit` and the lint job instead
  of only on a runner.

### Fixed
- Unpinned placeholder checksums in `base-system/packages.list` are no longer
  part of the tree; the audit job now fails if any manifest declares a source
  without a real SHA-256.
- `tools/shreeos-audit.py iso` inferred the build profile from the filename
  only, and fell back to `minimal` for any unrecognised name. The audit job
  downloads release assets as `download.iso`, so every published desktop ISO
  was reported as a minimal image and its missing desktop components were
  measured against the wrong profile. The profile is now read from the
  `shreeos-<version>[-<profile>].iso` name, an unrecognised name reports
  `unknown` instead of guessing, `--profile` overrides the inference, and the
  workflow preserves the asset's real filename.

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
