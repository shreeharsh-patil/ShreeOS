# ShreeOS Desktop Distribution Implementation Plan

**Status:** Phase 1 reviewed; isolated Debian Live base prototype is under way.
**Audit baseline:** repository commit `44677fdeb4e1` (2026-09-30).

This plan turns the desktop-distribution request into reviewable milestones. It
keeps the current bootable image and source-build pipeline available until a
replacement can pass the same boot checks. An ISO size target is deliberately
not used: image growth must come from installed runtime functionality.

## Current verified state

- The build is a seven-stage, x86_64 cross-build: toolchain, base packages,
  kernel, native packages, desktop, root filesystem, and ISO.
- The ISO path puts the full staged root filesystem in
  `initramfs.cpio.gz`; the builder does not yet produce a separate compressed
  live root with a writable overlay and `switch_root`.
- The repo audit currently verifies source pins and workflow structure. It does
  not prove the built image contains or runs the components described by the
  README.
- `base-system/packages.list` has pins for 55 sources, including a systemd
  source, but `base-system/scripts/build-all.sh` builds only 51 recipes and
  the active PID 1 remains ShreeOS's custom init. A source pin is not an
  installed component.
- The current graphical stack is a small X11/dwm-based stack. The installer is
  a text UI. The ISO does not yet provide a complete desktop workflow.
- The current working tree now removes static archives, headers and selected
  build metadata from the staged runtime root after package assembly. Its
  focused fixture passes, but a complete rebuilt ISO is still needed to
  measure the effect and verify the full boot path.
- Two Phase 1 audit files are tracked. Their reported commit IDs and package
  counts differ; neither should be treated as a current package inventory
  without regenerating measurements from a built ISO.

Run the source audit with:

```sh
python3 tools/shreeos-audit.py repo --root . --out build/audit/repo-audit.json --text
python3 tests/audit/test-shreeos-audit.py
```

## Architecture direction

Use a maintained upstream binary package ecosystem for the installed desktop
base rather than attempting to reproduce thousands of interdependent desktop
packages in the current hand-maintained cross-build. The preferred evaluation
candidate is a Debian-derived x86_64 base assembled from signed Debian
repositories, with systemd, apt/dpkg and Flatpak for desktop applications.
ShreeOS owns the branding, default configuration, image composition, installer
experience, documentation, release process and any maintained ShreeOS
packages. The resulting product must clearly document its Debian base and
upstream licensing.

This is a recommendation to validate, not permission to discard the current
implementation. First build a separate experimental image and compare boot,
hardware coverage, update integrity, installer support, image composition and
CI build time. Preserve ShreeOS's kernel configuration and useful native tools
where they integrate cleanly. Do not ship two competing init systems or
package managers in the default installation; make a deliberate migration
decision after the prototype boots and installs in QEMU.

Desktop candidate: XFCE for the first complete release, with X11 fallback and
the upstream-supported graphics stack. It has a smaller integration surface
than a custom desktop rewrite. Revisit Wayland and a more extensive visual
refresh after the live and installed system paths are dependable. Use original
ShreeOS wallpaper, colors, logo and installer identity.

## Delivery phases and gates

| Phase | Deliverable | Exit gate |
|---|---|---|
| 1. Audit and architecture | Current inventory, measured ISO composition, dependency and migration plan | Source/ISO facts are reproducible; open architectural decisions are recorded |
| 2. Base prototype | Separate reproducible Debian-derived rootfs with systemd, apt, accounts, CA certificates and recovery shell | Rootfs builds from pinned inputs; no credentials embedded; package database and services validate |
| 3. Live boot | Minimal initramfs discovers media and `switch_root`s into SquashFS with writable overlay | BIOS and UEFI QEMU boot reach a usable console; failure falls back to recovery |
| 4. Desktop and devices | XFCE, display manager, udev, NetworkManager, firmware policy, Mesa, audio and Bluetooth | VM desktop login, session, Ethernet, virtual audio/storage and shutdown pass smoke checks |
| 5. Applications and identity | Browser, file manager, terminal, editor, viewer, archive tool, settings, ShreeOS artwork | Applications launch in VM; licenses and redistributability recorded |
| 6. Installation | Graphical installer, safe disk selection, partitioning, accounts, bootloader and first boot | Disposable QEMU disk installs and boots without ISO; destructive confirmation tested |
| 7. Updates and recovery | Signed apt sources, Flatpak policy, updates, rescue tools and documentation | Update metadata verified; offline/recovery path tested; no custom unsafe updater |
| 8. CI and release | Reproducible ISO job, BIOS/UEFI and install tests, checksums and gated release | Clean CI build and end-to-end disposable-disk test pass before publishing |

Each phase gets a scoped change and its relevant checks before the next phase
starts. Physical hardware coverage is reported separately from VM coverage;
unsupported devices are not described as tested. The existing source-build
image remains available until the prototype has passed the boot, desktop,
install, reboot and update gates.

### Current checkpoint

The first prototype lives under `prototype/debian-live/`. It pins Debian 13
Trixie package inputs to snapshot `20260929T000000Z`, pins live-build in CI,
creates a systemd/live-boot SquashFS ISO, and checks the boot in BIOS and UEFI
QEMU. The initial package set intentionally stays in Debian's `main` area and
does not include third-party firmware. The build and QEMU checks have not yet
run in this Windows workspace; the new Debian Linux CI workflow is the first
full build environment. This checkpoint is not a desktop release.

## Near-term work

1. Refresh the audit against the current checkout and, where a build artifact
   is available, the actual ISO. Mark older measurements with their source
   commit and release rather than presenting them as current.
2. Prototype the proposed base in a separate build target; do not modify the
   existing `make all` path until the prototype can boot from QEMU.
3. Keep source downloads checksum-verified, pin the base-image repository
   snapshot/release inputs, and record package manifests and licenses in the
   output.
4. Add boot and installed-system acceptance tests around the new output. CI
   must test the same artifact that release jobs publish.
