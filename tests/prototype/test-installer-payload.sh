#!/usr/bin/env bash
# Installer payload verification for a built ShreeOS image.
#
# Extracts the image's SquashFS and proves the graphical installer it ships can
# actually run: every module in the Calamares sequence has a configuration, the
# branding is present, the privilege boundary is scoped, the live session's
# credentials are not reused for the installed user, and the unpack source is
# the real live medium path.
#
# Scope, stated plainly: this verifies the installer payload inside the image.
# Driving Calamares through an interactive disk install still requires a human
# or a keystroke harness, and is tracked as an open release gate in
# docs/SYSTEM-READINESS.md. This test does not claim that an install succeeded.
#
# Usage: tests/prototype/test-installer-payload.sh PATH_TO_ISO
set -Eeuo pipefail

if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: $0 PATH_TO_SHREEOS_ISO" >&2
  exit 2
fi

ISO="$(realpath "$1")"
for tool in xorriso unsquashfs python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing installer verification dependency: $tool" >&2
    exit 2
  }
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

SQUASHFS="$TEST_DIR/filesystem.squashfs"
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$SQUASHFS" >/dev/null
unsquashfs -s "$SQUASHFS" >/dev/null

extract_dir="$TEST_DIR/root"
mkdir -p "$extract_dir"
# Extract only the installer payload; the full root is hundreds of megabytes.
# Keep paths with shared parents in one invocation. Repeated unsquashfs calls
# can reject an already-created parent directory, and ignoring that error can
# silently leave later installer files out of the verification tree.
unsquashfs -q -d "$extract_dir" "$SQUASHFS" \
  etc/calamares usr/local/bin usr/local/libexec usr/lib/calamares >/dev/null

fail() {
  printf 'INSTALLER PAYLOAD FAILED: %s\n' "$*" >&2
  exit 1
}

settings="$extract_dir/etc/calamares/settings.conf"
[ -s "$settings" ] || fail "the image ships no Calamares settings.conf"
[ -s "$extract_dir/etc/calamares/modules/shellprocess.conf" ] || fail 'the image ships no ShreeOS hybrid GRUB shellprocess config'
[ -s "$extract_dir/usr/local/libexec/shreeos-install-bios-grub" ] ||
  fail 'the image ships no hybrid BIOS GRUB helper'

# --- Sequence integrity: each configured module must have a config file ------
# Calamares' own built-ins ship inside libcalamares and need no config, so the
# check is: a module with a shipped config directory entry must have it present.
mapfile -t sequence_modules < <(
  python3 - "$settings" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()
# The YAML sequence lists module names under "sequence:"; pull every list item.
names = []
for line in text.splitlines():
    match = re.match(r"\s*-\s*([A-Za-z0-9_.@-]+)\s*$", line)
    if match:
        names.append(match.group(1))
print("\n".join(names))
PY
)
[ "${#sequence_modules[@]}" -ge 20 ] ||
  fail "the installer sequence has only ${#sequence_modules[@]} modules"

missing=()
for module in "${sequence_modules[@]}"; do
  if [ "$module" = shellprocess@storage-preflight ]; then
    [ -s "$extract_dir/etc/calamares/modules/shellprocess-storage-preflight.conf" ] ||
      fail 'the installer sequence has no storage preflight config'
    continue
  fi
  # Modules known to be provided by the local overrides or shipped in the image.
  if [ -s "$extract_dir/etc/calamares/modules/$module.conf" ]; then
    continue
  fi
  if [ -s "$extract_dir/usr/lib/calamares/modules/$module/module.desc" ]; then
    continue
  fi
  # Calamares' own compiled modules need no config file at all.
  case "$module" in
    welcome | locale | keyboard | partition | users | summary | finished \
    | mount | unpackfs | machineid | fstab | localecfg | displaymanager \
    | networkcfg | hwclock | bootloader | grubcfg | packages | plymouthcfg \
    | initramfs | initramfscfg | luksbootkeyfile | dpkg-unsafe-io \
    | dpkg-unsafe-io-undo | sources-media | sources-media-unmount \
    | services-systemd | bootloader-config | shellprocess | umount)
      continue
      ;;
  esac
  missing+=("$module")
done
[ "${#missing[@]}" -eq 0 ] || fail "sequence modules have no configuration: ${missing[*]}"

# --- The ShreeOS-authored module must ship, config and all -------------------
shreeos_module="$extract_dir/usr/lib/calamares/modules/shreeos-sources"
[ -s "$shreeos_module/main.py" ] || fail 'the shreeos-sources module has no main.py'
[ -s "$shreeos_module/module.desc" ] || fail 'the shreeos-sources module has no module.desc'
if [ -d "$shreeos_module/__pycache__" ]; then
  fail 'compiled Python bytecode was shipped into the image'
fi

# --- Branding ---------------------------------------------------------------
branding="$extract_dir/etc/calamares/branding/shreeos"
for asset in branding.desc shreeos-logo.svg shreeos-app.svg; do
  [ -s "$branding/$asset" ] || fail "installer branding is missing $asset"
done
grep -Fq 'productIcon: shreeos-app.svg' "$branding/branding.desc" ||
  fail 'installer branding does not use the ShreeOS product icon'

# --- The unlock source must be the real live medium -------------------------
unpack="$extract_dir/etc/calamares/modules/unpackfs.conf"
if [ -s "$unpack" ]; then
  grep -Fq '/run/live/medium' "$unpack" ||
    fail 'unpackfs does not install from the live medium mount'
fi

# --- Credentials: the live account must not become the installed account ----
users="$extract_dir/etc/calamares/modules/users.conf"
if [ -s "$users" ]; then
  python3 - "$users" <<'PY' || fail 'the installer would reuse the live session credentials'
import re
import sys

text = open(sys.argv[1]).read()
# A fixed password (or a fixed live user name) in the target-user config would
# ship an account whose credentials are public in the ISO.
if re.search(r"^\s*(password|userPassword)\s*:", text, re.MULTILINE):
    raise SystemExit("users.conf presets a password; the live credentials must not be reused")
if re.search(r"^\s*username\s*:\s*shree\s*$", text, re.MULTILINE):
    raise SystemExit("users.conf presets the live account name as the installed user")
if not re.search(r"^\s*setRootPassword\s*:", text, re.MULTILINE):
    raise SystemExit("users.conf does not state its root-password policy")
if not re.search(r"^\s*passwordRequirements\s*:", text, re.MULTILINE):
    raise SystemExit("users.conf sets no password strength requirements")
PY
fi

# --- Privilege boundary -----------------------------------------------------
wrapper="$extract_dir/usr/local/bin/shreeos-installer"
privileged="$extract_dir/usr/local/libexec/shreeos-installer-privileged"
[ -s "$wrapper" ] || fail 'the ShreeOS installer launcher is not packaged'
[ -s "$privileged" ] || fail 'the ShreeOS privileged installer is not packaged'

policy="$TEST_DIR/policy.xml"
unsquashfs -q -cat "$SQUASHFS" usr/share/polkit-1/actions/org.shreeos.installer.policy \
  >"$policy" 2>/dev/null || fail 'the installer polkit policy is not packaged'
python3 - "$policy" "$privileged" <<'PY' || fail 'the installer polkit policy is not scoped to the privileged helper'
import sys
import xml.etree.ElementTree as ET

actions = ET.parse(sys.argv[1]).findall("action")
if len(actions) != 1:
    raise SystemExit(f"expected exactly one polkit action, found {len(actions)}")
annotations = {node.get("key"): node.text for node in actions[0].findall("annotate")}
expected = sys.argv[2].replace("/root/", "/")
if annotations.get("org.freedesktop.policykit.exec.path") != expected:
    raise SystemExit("polkit action is not scoped to the packaged privileged helper")
if annotations.get("org.freedesktop.policykit.exec.allow_gui") != "true":
    raise SystemExit("polkit action does not allow the graphical installer to display")
PY

# --- Desktop launcher -------------------------------------------------------
launcher="$extract_dir/usr/share/applications/shreeos-installer.desktop"
if [ -s "$launcher" ]; then
  grep -Eq '^Exec=/usr/local/bin/shreeos-installer' "$launcher" ||
    fail 'the installer launcher does not call the packaged wrapper'
fi

printf 'Installer payload verification passed for %s.\n' "$(basename -- "$ISO")"
