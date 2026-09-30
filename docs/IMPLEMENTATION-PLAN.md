# ShreeOS Desktop Distribution Implementation Plan

**Status:** Phases 1–5 have implementation scaffolding in an isolated Debian Live prototype; Linux build and boot gates are pending. Installer, installed-system update/recovery, and production release phases remain open.
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

The prototype lives under `prototype/debian-live/`. It pins Debian 13 Trixie
package inputs to snapshot `20260929T000000Z`, pins live-build in CI, and has
separate `base` and optional `desktop` profiles. The desktop profile selects
Debian's XFCE task and ShreeOS artwork, while excluding Debian's
`non-free-firmware` archive. A boot-time hook locks the temporary live user's
default password; the QEMU marker checks that the account has no password
login or sudo access, an intact apt/dpkg package database, QEMU block-device
detection, and an Ethernet DHCP route. In desktop mode it also waits for
LightDM and an XFCE session. These profiles are implemented but their Linux
build and QEMU checks have not yet run in this Windows workspace. The desktop
is still not a release.

The optional desktop now has a staged appearance layer: Arc-Dark GTK styling
with ShreeOS blue focus accents, Papirus-Dark icons, Inter UI text, a ShreeOS
top panel with app menu, task list, workspace pager, tray, audio, power, clock
and session actions, four workspaces, left-side XFWM controls, and a centered
Plank dock configured with ShreeOS surface colors, favorite launchers, and
hover magnification. It uses Shree Search for `Super+Space`,
LightDM's ShreeOS wallpaper and logo, and both original light and dark
wallpapers. Static checks validate these configurations, and the QEMU marker
now waits for panel and dock processes. The image and appearance are still
unverified until Linux CI builds and graphically boots it. An initial GTK
Control Center provides Wi-Fi and Bluetooth power, sound mute, dark/light
theme switches, and links to XFCE's network, sound, display, appearance, power,
and notification tools. It does not yet provide brightness, airplane mode,
focus, battery, or power-profile controls, and has not been exercised in a
running desktop. Workspace overview, notification center, lock screen, boot
splash, and installer experiences remain future work.

`Super+Space` now opens Shree Search, a GTK app finder that matches installed
applications (including settings), indexes up to 5,000 files from common user
folders in the background, and evaluates bounded arithmetic expressions
without executing user-provided code. The calculation parser has an isolated
contract test; the interactive GTK window still needs review in a Linux
session.

`Super+Up` opens a ShreeOS Workspace Overview backed by XFCE's four X11
workspaces. It groups open windows by desktop and supports desktop switching,
window activation, moving a window, and closing it. Parser tests cover the
`wmctrl` inventory format; thumbnail cards, workspace creation, animations,
and touchpad gestures remain open, and the GUI action flow still needs VM
validation.

The prototype workflow also runs Bash syntax checks and ShellCheck at error
severity before building either image. This Windows workspace cannot execute
Debian Live, QEMU, or ShellCheck, so those gates have not run here. Do not wire
an installer to the prototype until CI proves the desktop ISO boots: the
existing `installer/` targets the legacy source-built rootfs and is not
compatible with the Debian Live filesystem. The installer phase needs a
Debian-compatible design, an exact target-disk and partition-plan review, and
explicit destructive confirmation. The prototype boot menu also still lacks
the requested ShreeOS “Try / Safe Graphics / Install” choices.

## Near-term work

1. Run Linux CI build and boot gates for both profiles; fix base failures
   before using the desktop output to judge the architecture.
2. Refresh the audit against the current checkout and, where a build artifact
   is available, the actual ISO. Mark older measurements with their source
   commit and release rather than presenting them as current.
3. Keep source downloads checksum-verified, pin the base-image repository
   snapshot/release inputs, and record package manifests and licenses in the
   output.
4. Implement the Debian-compatible installer after desktop boot passes; test
   installation, reboot, account login, package operations and shutdown on a
   disposable virtual disk.
5. Define and test signed repository/update policy and recovery behavior.
6. Extend CI to validate the installed system and publish only the same ISO
   artifact after every acceptance gate passes.
