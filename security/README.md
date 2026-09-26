# ShreeOS Security Edition

The `security` edition is a ShreeOS-native workstation profile for defensive administration, diagnostics, labs, incident response, and authorized security testing.

It is built on the same independent ShreeOS toolchain, kernel, root filesystem, desktop, LPM package manager, SafeUpdate system, and ISO pipeline as the normal desktop edition. It does not use Kali or Ubuntu as a runtime base.

## Built-in commands

- `shree-audit` — local permissions, privileged-file, account, package-integrity, recovery, and listening-socket audit.
- `shree-netdiag [target] [tls-host]` — interfaces, routes, DNS, reachability, listening sockets, wireless status, and optional TLS diagnostics.
- `system-update.sh` — transactional update, verification, history, repair, and rollback.
- `lpm` — ShreeOS package management.
- `openssl`, BusyBox networking commands, and `wpa_supplicant` from the base system.

The long-term security repository can add separately packaged tools without bloating the standard desktop ISO. Security packages should be pinned, reproducible, and installed through LPM rather than copied from another distribution.
