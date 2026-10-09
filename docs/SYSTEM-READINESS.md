# ShreeOS desktop readiness — 2026-10-06

The current desktop implementation is the Debian 13 Live Plasma profile.
This pass strengthens it for everyday use; it is not evidence of parity with
Ubuntu, a complete Kali tool collection, or a production-ready release.

## Findings and changes

| Finding | Change | Evidence and remaining work |
| --- | --- | --- |
| Installer GUI loses DISPLAY/XAUTHORITY at pkexec; root cannot grant itself X access beforehand | Scoped GUI policy; the desktop user grants access before authorization and revokes it on return | Policy and argument regression checks; an actual GUI disk install remains required |
| Concurrent installers could race while moving live fstab | Exclusive flock, private temporary backup, cleanup and terminating signal traps | Shell checks; concurrent launch and failure recovery need Linux integration testing |
| Plasma shortcuts used tabs instead of KConfig list delimiters | Correct comma-separated shortcut records, plus workspace navigation | Configuration check; keyboard interaction needs a Plasma session |
| XFCE launcher files were outside Plank's dock1 directory | Move launchers into the directory Plank uses | Desktop configuration checks; boot screenshots still required |
| First-login and dock disagree when XDG_CONFIG_HOME is customized | Both use the XDG configuration location; transient units follow graphical-session teardown | Existing custom-layout regression tests; logout/login testing still required |
| Graphics defaults force OpenGL options and override the driver's unsafe state | Remove forced renderer/unsafe-state options; let KWin choose | Configuration review; Intel, AMD, NVIDIA and software rendering benchmarks pending |
| Desktop lacks office, media, printer/scanner, accessibility and power integrations | Add LibreOffice, VLC, CUPS/Print Manager, Simple Scan, Orca/speech/Onboard, power profiles and Discover firmware support | All package names found in the pinned snapshot; use cases need runtime acceptance |
| Only free firmware selected; many ordinary PCs need additional blobs | Standard graphical firmware selection with explicit free-only override | Snapshot availability checked; Wi-Fi/audio/GPU hardware coverage and release license review pending |
| No compressed swap defaults | Add capped, on-demand LZ4 zram to Plasma | Configuration checked; activation and performance measurements pending |
| Desktop animations cannot adapt to slow graphics or motion preference | Native KDE Magic Lamp, Scale and Slide defaults; balanced/performance/reduced settings | Real command regression test with isolated session-command fixtures; visual and frame-time review pending |
| Installed repository setup relies on Debian helper discovering the mount point from text | Calamares job uses the target root, explicit HTTPS signed sources, and firmware policy | Target provision/idempotence/keyring/policy tests; installed apt update/upgrade still required |
| Runtime could inherit stale snapshot settings | Explicit runtime freshness/signature checks; snapshot exception stays in build invocation | Configured policy; negative signature/expiry tests on an installed system pending |
| Specialist applications would make every image unnecessarily large | Optional developer, security and creative sets, build-time or administrator-authorized installed APT selection | Invalid input regression checks; full optional-bundle dependency and installation checks pending |

## Local validation

- Prototype configuration, XFCE configuration, calculator and overview parser checks.
- Plasma configuration and preserved-user-profile tests.
- New system feature tests for repository provisioning, command boundaries,
  motion settings, customized XDG paths and shortcut records.
- Shell syntax, ShellCheck and diff whitespace checks.
- Both edited CI workflows' run blocks pass shell syntax checks using Git Bash;
  immutable action pins pass the GitHub reference check.
- Desktop and optional tool package names compared with the **actual pinned
  20260929T000000Z Trixie main/non-free-firmware indexes**. This is availability
  validation, not a dependency resolution or ISO build.

Latest local results: 5 Plasma tests passed; 12 system feature tests passed
and one symlink test skipped on Windows; 43 repository audit tests passed
and their Linux-shell class skipped. The four other prototype configuration
and parser entry points also passed. Neither the Linux boot tests nor the
legacy comprehensive suite are claimed as passing.

On this Windows host, the target Linux VM/ISO environment is unavailable.
The legacy source-built comprehensive suite also failed here: missing make,
Windows/POSIX API and path differences, and several validation expectations.
Those failures require a supported Linux rerun before separating host issues
from source-built regressions. They are not a passing release gate.

The new symlink escape test skips when the host cannot create symlinks; Linux
CI must exercise it. No claim is made about measured resource improvements.

## Release gates still open

1. Build current Plasma and XFCE ISOs; BIOS/UEFI boot, inspect actual desktop
   screenshots, and exercise mouse/keyboard application workflows.
2. Install offline and online to disposable VM disks; reboot without ISO;
   validate passwords, permissions, disk bootloader, encrypted install, and
   installed account/session behavior.
3. Verify installed APT/Flatpak updates, reject invalid/expired signatures,
   and recover from interrupted package operations. Package ShreeOS's own
   assets in versioned `.deb`s and publish a signed repository for those
   customizations. Debian package updates already use APT; a custom desktop
   file update channel is not deployed yet.
4. Measure cold boot, idle RAM, CPU use and frame times with balanced,
   performance and reduced motion profiles. Record hardware, display scale,
   kernel/Mesa versions, workload and repeated results.
5. Validate Wi-Fi, Bluetooth, audio, printers, multi-monitor, screen lock,
   accessibility and suspend/resume on representative Intel/AMD/NVIDIA PCs.
6. Validate optional bundles separately, retain package licenses/source
   obligations, and publish an accurate package manifest for each image.

## Desktop direction

The reference layout uses an original mountain wallpaper, light translucent
menu bar, centered rounded dock, left window controls, app menus, search,
four workspaces and native Overview. Magic Lamp/Scale/Slide and dock
magnification provide familiar Mac-style motion through Linux components.
It does not include Apple's code, applications, services or proprietary
animation implementation. Plank is an X11 dock; full Wayland touchpad gesture
support requires a later native Plasma dock and session migration.

## 2026-10-09 repository audit and identity pass

The current source inventory and implementation blockers are recorded in
[`docs/audit/2026-10-09-AUDIT.md`](audit/2026-10-09-AUDIT.md). The latest
master CI result at audit time passed the ISO, lint, and Debian Live Prototype
workflows, including the scripted BIOS/UEFI Plasma desktop capture. That is
virtual boot evidence only; Calamares installation, first boot from the
installed disk, physical hardware, and stable-release acceptance remain open.

The former geometric S logo did not meet the product identity requirement. The
new ShreeOS sunrise mark has primary, black, white, and adaptive SVGs, PNG
exports at 16–512px, a system app icon, and a matching installer icon. The
builder now uses these assets for the KDE icon, Calamares, the greeters, and
Plymouth/GRUB. Review of the actual 2026-10-08 Plasma QEMU capture also found
Debian's "Install Debian" desktop shortcut. The Plasma profile now masks the
upstream shortcut autostart in its new-user template; the ISO test checks that
the mask is packaged. A rebuilt QEMU capture is still needed to confirm the
visible shortcut is gone and the new brand renders in the complete boot path.

Local checks on the Windows workspace passed: logo SVG/PNG asset validation,
Plasma and desktop configuration checks, the Debian prototype config contract,
shell syntax, and `git diff --check`. The Linux ISO rebuild and QEMU retest
have not run in this workspace.

Implementation details and build/install commands:
[system features](../prototype/debian-live/features/README.md).
