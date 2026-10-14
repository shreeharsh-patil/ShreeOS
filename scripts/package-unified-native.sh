#!/usr/bin/env bash
# Native utilities become an ordinary Debian package; LPM is source-only.
set -Eeuo pipefail
if [ "$#" -ne 1 ]; then
  echo "Usage: package-unified-native.sh OUTPUT_PACKAGES_DIR" >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$1"
dest="$(cd "$1" && pwd -P)"
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
pkg="$temp/shreeos-native-tools"
mkdir -p "$pkg/DEBIAN"
cat > "$pkg/DEBIAN/control" <<'CONTROL'
Package: shreeos-native-tools
Version: 0.4.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: ShreeOS Developers <noreply@users.noreply.github.com>
Depends: bash, coreutils, procps, konsole, systemd
Description: Compatible native ShreeOS utilities for the unified Plasma image
 Read-only system information, the original terminal system monitor, and
 historical LPM package source; Debian continues to own system packages.
CONTROL
install -Dm0755 "$root/scripts/shreeinfo" "$pkg/usr/bin/shreeinfo"
install -Dm0755 "$root/desktop/apps/shree-sysmon.sh" "$pkg/usr/bin/shreeos-sysmon"
install -Dm0755 "$root/scripts/shreeos-native-status" "$pkg/usr/bin/shreeos-native-status"
install -Dm0755 "$root/scripts/shreeos-verify-installed" "$pkg/usr/bin/shreeos-verify-installed"
# Compile native hardware service in isolated temporary staging; Debian owns PID 1.
cp -a "$root/hardware" "$temp/hardware"
make -C "$temp/hardware" CROSS_COMPILE= LDFLAGS= all
install -Dm0755 "$temp/hardware/shreed" "$pkg/usr/libexec/shreeos/shreed"
install -Dm0755 "$temp/hardware/shreedctl" "$pkg/usr/bin/shreedctl"
mkdir -p "$pkg/usr/share/applications" "$pkg/lib/systemd/system"
cat > "$pkg/lib/systemd/system/shreeos-hardware.service" <<'SERVICE'
[Unit]
Description=ShreeOS native read-only hardware inventory service
Documentation=file:/usr/share/doc/shreeos-native-tools/README.md
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/libexec/shreeos/shreed --foreground
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
SERVICE
# Enable through systemd's preset policy, not a conflicting native init system.
mkdir -p "$pkg/usr/lib/systemd/system-preset"
printf 'enable shreeos-hardware.service\n' > "$pkg/usr/lib/systemd/system-preset/60-shreeos-native.preset"
cat > "$pkg/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "${1:-}" = configure ] && command -v deb-systemd-helper >/dev/null 2>&1; then
  deb-systemd-helper unmask shreeos-hardware.service >/dev/null 2>&1 || true
  deb-systemd-helper enable shreeos-hardware.service
fi
exit 0
POSTINST
chmod 0755 "$pkg/DEBIAN/postinst"
cat > "$pkg/usr/share/applications/shreeos-native-monitor.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ShreeOS Native System Monitor
Comment=ShreeOS process and resource monitor
Exec=konsole -e /usr/bin/shreeos-sysmon
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
DESKTOP
cat > "$pkg/usr/share/applications/shreeos-native-info.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ShreeOS Native System Info
Comment=System information from native ShreeOS tools
Exec=konsole -e /usr/bin/shreeinfo
Icon=computer
Terminal=false
Categories=System;
DESKTOP
doc="$pkg/usr/share/doc/shreeos-native-tools"
mkdir -p "$doc/lpm/src" "$doc/lpm/spec"
cp "$root/pkgmanager/src/"*.c "$root/pkgmanager/src/"*.h "$root/pkgmanager/src/Makefile" "$doc/lpm/src/"
cp "$root/pkgmanager/spec/lpkg-format.md" "$doc/lpm/spec/"
install -m0644 "$root/docs/UNIFIED-IMAGE.md" "$doc/README.md"
install -m0644 "$root/LICENSE" "$doc/LICENSE"
dpkg-deb --root-owner-group --build "$pkg" "$dest/shreeos-native-tools_0.4.0_amd64.deb"
dpkg-deb --field "$dest/shreeos-native-tools_0.4.0_all.deb" Package Version
