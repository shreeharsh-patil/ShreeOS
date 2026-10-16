# Interactive install acceptance

The ShreeOS release pipeline verifies the installer payload, the privilege
boundary, the credential policy and the route to APT automatically. It cannot
verify the *wizard*: Calamares has no supported fully-unattended mode for this
configuration, and a keystroke-driven harness would produce a gate that looks
green without proving the install worked.

So the interactive install is a **recorded manual acceptance** instead of a fake
automation. The release job reads this file and refuses to publish unless it
records an acceptance for the exact commit being released.

## Status

```
VERDICT: NOT ACCEPTED
Commit:  none
Version: none
Date:    none
```

The pipeline is expected to fail its install gate until a real acceptance is
recorded below. That is the intended state, not a defect.

## Procedure

Use a disposable virtual machine only. Never run these steps against physical
disks.

1. Build the image: `make shreeos`, then note `out/shreeos(VERSION).iso` and the
   commit (`git rev-parse HEAD`).
2. Create a blank virtual disk of at least 20 GB and attach the ISO.
3. Boot the ISO and let the live Plasma desktop appear. Confirm the ShreeOS
   wallpaper, top panel, centered dock, SDDM greeter branding and that every
   desktop shortcut opens a real application.
4. Run the installer and complete each step deliberately:
   - language, timezone and keyboard layout
   - guided "erase disk" on the **disposable disk only**, then a second run using
     manual partitioning
   - user creation with a password of your choosing, and a hostname
   - confirm the summary shows only the disposable disk and that no live-session
     credential (`shree`, or a blank/locked password) is preselected
5. Let the install finish. Shut the machine down, **detach the ISO**, and boot
   again from the virtual disk alone.
6. Confirm: GRUB appears, the system boots without the installation media, SDDM
   shows the ShreeOS theme, and the account created in step 4 logs in.
7. Inside the installed system confirm:
   - `apt-get update` and `apt-get upgrade` succeed against signed Debian
     repositories
   - `sudo -v` works for the created account and fails for any other account
   - `id` shows the expected supplementary groups
   - `systemctl --failed` is empty
   - desktop settings persist across logout and login
8. Repeat step 3's boot on the same disk in the other firmware mode (BIOS if you
   used UEFI, UEFI if you used BIOS).

## Record format

Append one block per accepted build. Every field is required; the release gate
looks for the commit, the `ACCEPTED` verdict, and evidence for `BIOS`, `UEFI`,
`APT` and `login`.

```
VERDICT: ACCEPTED
Commit: <full 40-character commit SHA of the build that was tested>
Version: <version from VERSION>
Date: <ISO date>
Firmware: BIOS and UEFI both booted from the installed disk alone
Installer: guided erase-disk, manual partitioning, user creation, hostname, timezone, keyboard
Credentials: live session credentials were not reused; installed account authenticates
APT: apt-get update and apt-get upgrade succeeded on signed Debian repositories
Login: SDDM -> Plasma session for the created account; settings persisted across re-login
System: systemctl --failed empty; install media detached before the reboot
Limitations: <anything not covered, e.g. encryption, recovery from a failed install>
```

## Known gaps

These are not covered by the procedure above and remain open release gates:

- LUKS encryption, and the failure path when the encrypted unlock fails.
- Recovery from an interrupted install and from a full target filesystem.
- Installing alongside an existing operating system (dual boot).
- Real hardware: Wi-Fi, Bluetooth, audio, printers, suspend/resume, GPU drivers.
