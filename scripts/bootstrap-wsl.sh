#!/usr/bin/env bash
# Prepare an Ubuntu/Debian WSL2 environment for reliable ShreeOS builds.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

is_wsl=false
is_wsl2=false
kernel_release="$(uname -r 2>/dev/null || true)"
kernel_version="$(cat /proc/version 2>/dev/null || true)"

if grep -qi microsoft <<<"$kernel_release $kernel_version"; then
  is_wsl=true
fi
if grep -qiE 'wsl2|microsoft-standard' <<<"$kernel_release"; then
  is_wsl2=true
fi

if [ "$is_wsl" != true ]; then
  echo "[fail] This bootstrap script is intended for Windows Subsystem for Linux." >&2
  echo "       On normal Ubuntu/Debian use: bash scripts/install-build-deps-apt.sh" >&2
  exit 1
fi

if [ "$is_wsl2" != true ]; then
  echo "[fail] WSL1 detected. ShreeOS builds are supported on WSL2 only." >&2
  echo "       From PowerShell run: wsl --set-version <DistroName> 2" >&2
  exit 1
fi

case "$REPO_ROOT" in
  /mnt/[a-zA-Z]/*)
    if [ "${SHREEOS_ALLOW_WINDOWS_FS:-0}" != "1" ]; then
      echo "[fail] ShreeOS is located on the Windows-mounted filesystem:" >&2
      echo "       $REPO_ROOT" >&2
      echo "       Clone it under the WSL Linux filesystem instead, e.g. ~/ShreeOS." >&2
      echo "       Set SHREEOS_ALLOW_WINDOWS_FS=1 only if you accept slower/less reliable builds." >&2
      exit 1
    fi
    ;;
esac

bash "$SCRIPT_DIR/install-build-deps-apt.sh"

echo
echo "[ok] WSL2 host dependencies are installed."
echo "[info] Recommended repository location: ~/ShreeOS"
echo "[info] Recommended Windows .wslconfig for a capable machine:"
cat <<'EOF'
[wsl2]
memory=8GB
processors=6
swap=8GB
EOF
echo
echo "After editing %UserProfile%\\.wslconfig, run 'wsl --shutdown' in PowerShell."
echo
bash "$SCRIPT_DIR/doctor.sh"
