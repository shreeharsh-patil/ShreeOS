# ShreeOS Desktop Distribution Implementation Plan

**Status:** The Debian Live base and desktop image build and pass BIOS/UEFI boot checks. The latest strict visual gate failed because the wallpaper and dock were absent from the captured desktop. A follow-up fixes the Plank dconf load root and explicitly includes Debian's SVG image loader; BIOS/UEFI visual validation is pending. Interactive visual acceptance, installation, installed-system updates/recovery, and production release remain open.
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
separate `base` and optional `desktop` profiles. On commit `28f2b38`, GitHub
Actions built both profiles and the base image passed BIOS and UEFI QEMU checks
for the locked temporary account, package database, storage, NetworkManager
and DHCP. The desktop image also booted in BIOS and UEFI and its screenshot
gate passed after the XFCE panel became visible. Visual inspection showed the
wallpaper area was still black and the dock was hidden. The earlier XFCE panel
schema and hierarchy defects are fixed; a panel restart from the first-login
autostart hook had also raced XFCE startup and has been removed. Commit
`61982a9` adds a desktop reload after applying wallpaper settings, keeps the
Plank dock visible, and checks the wallpaper and dock regions in the QEMU
screenshot. That commit also adds the ShreeOS-branded Calamares configuration
and scoped live-media launcher. Its CI run `36961861311` built both profiles
and passed base BIOS/UEFI boot, but failed the desktop wallpaper screenshot
check. The follow-up corrects the dconf root used by the dock launcher and
selects `librsvg2-common` explicitly; this has not yet been rebuilt. This is
not yet visual acceptance, an install test, or physical-hardware coverage. The
desktop profile selects
Debian's XFCE task and ShreeOS artwork, while excluding Debian's
`non-free-firmware` archive. A boot-time hook locks the temporary live user's
default password; the QEMU marker checks that the account has no password
login or sudo access, an intact apt/dpkg package database, QEMU block-device
detection, and an Ethernet DHCP route. In desktop mode it also waits for
LightDM, an XFCE session, the panel, and Plank, then checks that the captured
screen includes a wallpaper and visible dock. The desktop is still not a
release.

The optional desktop now has a staged appearance layer: Arc-Dark GTK styling
with ShreeOS blue focus accents, Papirus-Dark icons, Inter UI text, a ShreeOS
top panel with app menu, task list, workspace pager, tray, audio, power, clock
and session actions, four workspaces, left-side XFWM controls, and a centered
Plank dock configured with ShreeOS surface colors, favorite launchers, and
hover magnification. It uses Shree Search for `Super+Space`,
LightDM's ShreeOS wallpaper and logo, and both original light and dark
wallpapers. Static checks validate these configurations, and the QEMU marker
waits for panel and dock processes. CI has confirmed the image boots to the
desktop; application visuals and interactions still need review from the saved
screenshots and an interactive session. An initial GTK
Control Center provides Wi-Fi and Bluetooth power, sound mute, a dark/light
appearance switch that also updates window borders, GTK preference, wallpaper,
dock palette, and its own styling, a backlight slider when supported,
notification focus mode, airplane mode for Wi-Fi and Bluetooth, battery charge
and charging state when exposed through sysfs, and links to XFCE's network,
sound, display, appearance, power, and notification tools. CPU power-profile
selection, lid-action customization, and suspend/resume validation remain
open. The dock's own preferences are linked for size, position, and hide
behavior. The GRUB splash
and menu theme are now branded and confirmed in the CI boot image at 800×600.
Workspace Overview remains text based without thumbnails or gestures. A full
notification center remains future work. A custom Plymouth theme now places
the ShreeOS logo over a dark gradient with animated blue dots, and the desktop
boot arguments request the splash; BIOS/UEFI splash appearance is not yet
verified. The initial
installed login now has a Welcome window for settings and software shortcuts;
it has not yet been reviewed in the VM. Super+L routes through a password-aware
lock handler; the installed screen-saver lock and unlock flow still need
visual and input validation.
Orca, eSpeak NG speech output, Onboard, and XFCE accessibility settings are
now selected in the desktop profile; the reader, speech service, keyboard and
settings have not yet had keyboard-only or screen-reader validation. Super+Alt+O
starts Orca directly.
Calamares is now configured with ShreeOS branding,
the live SquashFS source, account setup, GRUB, and a confirmation before disk
changes; QEMU installation, reboot, account login, and update validation are
still open. ShreeOS Software searches the
Debian APT catalog, reads dpkg installed state, and uses administrator-gated
`apt-get` actions outside the nonpersistent live session; the installed-system
authorization flow is still unreviewed. The live account has a locked password
by design, so its lock shortcut reports that the temporary session cannot be
locked; installed accounts with a password use XFCE Screensaver through
`xflock4`. The Control Center also opens an original
About ShreeOS dialog backed by `/etc/os-release`, which identifies ShreeOS and
discloses Debian as its upstream.

`Super+Space` now opens Shree Search, a GTK app finder that matches installed
applications (including settings), indexes up to 5,000 files from common user
folders in the background, and evaluates bounded arithmetic expressions
without executing user-provided code. The calculation parser has an isolated
contract test; the interactive GTK window and its keyboard flow still need
review in a Linux session.

`Super+Up` opens a ShreeOS Workspace Overview backed by XFCE's four X11
workspaces. It groups open windows by desktop and supports desktop switching,
window activation, moving a window, and closing it. Parser tests cover the
`wmctrl` inventory format; thumbnail cards, workspace creation, animations,
and touchpad gestures remain open. CI confirms the XFCE session can launch the
overview process, but its interactive action flow still needs VM review.

The dock now includes ShreeOS Search, Workspace Overview, and Control Center
alongside the browser, terminal, file manager, image viewer, editor, settings,
Downloads, and Trash. Thunar's GTK bookmarks provide Desktop, Documents,
Downloads, Pictures, Music, Videos, Computer, Network, and Trash. These are
starter favorites; dock separators and drag/reorder behavior still depend on
interactive review of the packaged Plank build.

ShreeOS Software is now available from the dock and application menu. It
searches Debian's APT package catalog and uses `apt-get` through `pkexec` for
catalog refresh and package changes, while reading installed state from dpkg.
It requires administrator authorization, disables package changes in the
temporary live session, and prevents direct removal of essential or required
packages. The installed-system authorization flow still needs review after the
Debian-compatible installer exists; the live prototype has no persistent
administrator account.

The panel also enables XFCE Notifyd's recent-notification dropdown next to
the clock. It is a history menu, not yet the requested calendar, widgets, and
notification-center surface; visual behavior and notification actions require
desktop review.

The Debian Live prototype supplies original ShreeOS GRUB splash artwork and a
matching boot-menu theme for BIOS and UEFI. live-build continues to generate
the boot and recovery entries from its normal configuration. CI has booted
both firmware paths, and the QEMU job retains a boot-menu image for review.

Keyboard controls now switch workspaces with Ctrl+Alt+Left/Right, move the
focused window with Ctrl+Alt+Shift+Left/Right, and select desktops 1–4 with
Super+1–4. XFWM/XFCE keybinding configuration is checked statically; input
behavior still needs interactive VM and hardware validation.
`Super+Shift+S` now opens Debian's XFCE screenshot tool in region-selection
mode; its package and key binding are covered by the prototype checks.

The prototype workflow also runs Bash syntax checks and ShellCheck before
building either image, then validates SquashFS and BIOS/UEFI QEMU boot paths.
The boot test saves both menu and post-boot screen captures for visual review.
This Windows workspace cannot execute Debian Live or QEMU locally. The legacy
`installer/` still targets the source-built rootfs and is not used by the Debian
Live profile. The new Calamares integration needs an install from ISO to a
disposable disk, reboot without the ISO, account login, package operations,
shutdown, and an update/recovery check. The prototype boot menu still does not
provide a true safe-graphics mode or an installer boot entry; the graphical
installer currently starts from the desktop session.

## Near-term work

1. Finish CI validation for the wallpaper and dock screenshot gate, then review
   the screenshot and key UI actions.
2. Review the first-run welcome, accessibility launch paths, and lock/unlock
   flow in a Linux desktop session.
3. Refresh the audit against the current checkout and built ISO artifacts.
   Mark older measurements with their source commit and release rather than
   presenting them as current.
4. Keep source downloads checksum-verified, pin the base-image repository
   snapshot/release inputs, and record package manifests and licenses in the
   output.
5. Test the Calamares installer configuration by installing to a disposable
   virtual disk, rebooting without the ISO, logging in, using package
   operations, and shutting down.
6. Define and test signed repository/update policy and recovery behavior.
7. Extend CI to validate the installed system and publish only the same ISO
   artifact after every acceptance gate passes.
