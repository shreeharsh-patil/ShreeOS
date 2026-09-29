#!/usr/bin/env bash
# tests/base-system/test-base-system-contract.sh
#
# Contract test for the ShreeOS Phase 2 base system.
#
# This asserts the *distributional contract* a target root must satisfy to be a
# usable Linux userspace: a correct filesystem hierarchy, a coherent account
# database, a non-root desktop user with working privilege escalation, DNS
# configuration, resolvable shared libraries, and no contamination copied from
# the build host.
#
# It is deliberately a static contract test. It inspects the assembled target
# root directly rather than booting it, so it gives a precise, fast failure
# signal that names the exact missing or misconfigured item. Runtime behaviour
# (sudo actually elevating, DNS actually resolving) is additionally covered by
# the QEMU suite once the base system is bootable.
#
# Usage:
#   bash tests/base-system/test-base-system-contract.sh [--stage DIR]
#   bash tests/base-system/test-base-system-contract.sh --static

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/build.conf"

STAGE="${SHREEOS_STAGE_ROOT}"
STATIC_ONLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage)
      STAGE="${2:?--stage requires a directory}"
      shift 2
      ;;
    --static)
      # Run only the checks that inspect repository sources. Recipe, hygiene
      # and guard contracts do not need a built root, so `--static` surfaces
      # those in seconds instead of after a full cross-compile of every
      # package. CI runs the full test after the build.
      STATIC_ONLY=1
      shift
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

failures=0
checks=0

fail() {
  failures=$((failures + 1))
  printf '  [FAIL] %s\n' "$1" >&2
}

pass() {
  printf '  [ ok ] %s\n' "$1"
}

check() {
  # check <description> <condition-exit-code-already-evaluated>
  checks=$((checks + 1))
  if [ "$2" -eq 0 ]; then
    pass "$1"
  else
    fail "$1"
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

if [ "$STATIC_ONLY" -eq 0 ] && [ ! -d "$STAGE" ]; then
  printf 'Base system contract FAILED: stage root does not exist: %s\n' "$STAGE" >&2
  printf 'Run `make base-system` before this test, or pass --static to check only\n'
  printf 'the build-script contracts without an assembled root.\n' >&2
  exit 1
fi

printf 'ShreeOS base-system contract test\n'
printf 'Stage root: %s\n' "$STAGE"
if [ "$STATIC_ONLY" -eq 1 ]; then
  printf 'Mode      : static (build-script contracts only)\n'
fi

# Everything below this point inspects the assembled target root. In --static
# mode there is no root yet, so the whole block is skipped and only the
# build-script contracts (guards, recipes, hygiene) run.
if [ "$STATIC_ONLY" -eq 0 ]; then

# --------------------------------------------------------------------------
section "Filesystem hierarchy"
# FHS top level, plus /lib which the dynamic loader requires.
for dir in boot dev etc home lib media mnt opt proc root run sbin srv sys tmp usr var bin; do
  check "/$dir exists" "$([ -d "$STAGE/$dir" ] && echo 0 || echo 1)"
done

# Sticky world-writable temp directories are a security requirement, not a
# cosmetic one: without the sticky bit any user can delete another user's files.
for dir in tmp var/tmp; do
  mode="$(stat -c '%a' "$STAGE/$dir" 2>/dev/null || echo '?')"
  check "/$dir has sticky bit (mode $mode, want 1777)" \
    "$([ "$mode" = "1777" ] && echo 0 || echo 1)"
done
mode="$(stat -c '%a' "$STAGE/root" 2>/dev/null || echo '?')"
check "/root is private (mode $mode, want 700)" \
  "$([ "$mode" = "700" ] && echo 0 || echo 1)"

# --------------------------------------------------------------------------
section "Account database"
for file in passwd group shadow; do
  check "/etc/$file exists and is non-empty" \
    "$([ -s "$STAGE/etc/$file" ] && echo 0 || echo 1)"
done

# /etc/shadow holds password hashes; world-readable means offline cracking.
mode="$(stat -c '%a' "$STAGE/etc/shadow" 2>/dev/null || echo '?')"
check "/etc/shadow is 0600 (mode $mode)" \
  "$([ "$mode" = "600" ] && echo 0 || echo 1)"

# Every passwd name must have a shadow entry, and vice versa.
passwd_names="$(awk -F: 'NF>=3 && $1 !~ /^#/ {print $1}' "$STAGE/etc/passwd" | sort -u)"
shadow_names="$(awk -F: 'NF>=2 && $1 !~ /^#/ {print $1}' "$STAGE/etc/shadow" | sort -u)"
missing_shadow="$(comm -23 <(printf '%s\n' "$passwd_names") <(printf '%s\n' "$shadow_names") | tr -d '\n')"
check "every /etc/passwd user has a shadow entry (missing: '${missing_shadow:-none}')" \
  "$([ -z "$missing_shadow" ] && echo 0 || echo 1)"

# Every passwd primary GID must be defined in /etc/group, otherwise a login
# fails with "setgid: invalid argument".
group_names="$(awk -F: 'NF>=3 && $1 !~ /^#/ {print $1}' "$STAGE/etc/group" | sort -u)"
missing_group="$(awk -F: 'NF>=7 && $1 !~ /^#/ {print $4}' "$STAGE/etc/passwd" | sort -u \
  | while read -r gid; do
      if ! printf '%s\n' "$group_names" | awk -F: -v g="$gid" '$3 == g {found=1} END {exit !found}'; then
        printf '%s ' "$gid"
      fi
    done)"
check "every passwd primary GID exists in /etc/group (missing: '${missing_group:-none}')" \
  "$([ -z "$missing_group" ] && echo 0 || echo 1)"

# The shadow last-change field must be a number. An empty field makes some PAM
# stacks and `chage` reject the account entirely.
bad_lastchg="$(awk -F: 'NF>=3 && $1 !~ /^#/ && $3 != "" && $3 !~ /^[0-9]+$/ {print $1}' "$STAGE/etc/shadow" | tr '\n' ' ')"
check "shadow last-change fields are numeric (offenders: '${bad_lastchg:-none}')" \
  "$([ -z "$bad_lastchg" ] && echo 0 || echo 1)"

# Root must exist, be uid 0, and have a valid login shell.
check "root account exists with uid 0" \
  "$(awk -F: '$1 == "root" && $3 == 0 {found=1} END {exit !found}' "$STAGE/etc/passwd" && echo 0 || echo 1)"
root_shell="$(awk -F: '$1 == "root" {print $7}' "$STAGE/etc/passwd")"
check "root shell is /bin/bash (got '${root_shell:-none}')" \
  "$([ "$root_shell" = "/bin/bash" ] && echo 0 || echo 1)"
if [ -x "$STAGE/bin/bash" ] || [ -x "$STAGE/usr/bin/bash" ]; then
  check "root shell resolves to an installed interpreter" 0
else
  check "root shell resolves to an installed interpreter" 1
fi

# --------------------------------------------------------------------------
section "Normal user account"
# A desktop distribution must ship a usable non-root account. Without one the
# installer has nothing to log in as and the "non-root desktop" requirement in
# Phase 13 cannot be met.
DESKTOP_USER="${SHREEOS_DESKTOP_USER:-shree}"
user_line="$(awk -F: -v u="$DESKTOP_USER" '$1 == u {print; exit}' "$STAGE/etc/passwd")"
check "default desktop user '${DESKTOP_USER}' exists in /etc/passwd" \
  "$([ -n "$user_line" ] && echo 0 || echo 1)"

if [ -n "$user_line" ]; then
  IFS=: read -r _ uid gid _ home shell <<<"$user_line"
  check "desktop user is non-root (uid $uid)" \
    "$([ "$uid" != "0" ] && echo 0 || echo 1)"
  check "desktop user home is ${home} and exists" \
    "$([ -d "$STAGE$home" ] && echo 0 || echo 1)"
  # Ownership of /home/<user> is deliberately NOT asserted here, because it is
  # not a property of the staging tree and not a property of the shipped image:
  #
  #   * The build runs unprivileged, so setup-rootfs.sh cannot chown anything.
  #   * make-rootfs.sh packs the tree with `cpio --owner=0:0`, so every entry in
  #     the shipped archive is root:root regardless of what the staging
  #     filesystem happens to look like.
  #
  # root:root in a read-only live image is correct and expected. What a user
  # session actually needs is that the mode permits the owner to use the
  # directory, and that some privileged path applies real ownership. Those are
  # the invariants asserted below instead.
  check "desktop user home is usable by its owner (mode $(
      stat -c '%a' "$STAGE$home" 2>/dev/null || echo '?'))" \
    "$(mode="$(stat -c '%a' "$STAGE$home" 2>/dev/null || echo '')"
      case "$mode" in
        7??|?7?|??7) echo 0 ;;
        *) echo 1 ;;
      esac)"
  check "desktop user gid $gid has a matching group entry" \
    "$(awk -F: -v g="$gid" '$3 == g {found=1} END {exit !found}' "$STAGE/etc/group" \
      && echo 0 || echo 1)"
  check "desktop user shell is valid and installed (${shell})" \
    "$([ -x "$STAGE${shell}" ] && echo 0 || echo 1)"
  check "desktop user has a shadow entry" \
    "$(awk -F: -v u="$DESKTOP_USER" '$1 == u {found=1} END {exit !found}' "$STAGE/etc/shadow" && echo 0 || echo 1)"
  # A locked password ('!') is correct for a not-yet-configured live image;
  # an empty field means no password at all, which is a security defect.
  pwfield="$(awk -F: -v u="$DESKTOP_USER" '$1 == u {print $2}' "$STAGE/etc/shadow")"
  check "desktop user password is locked or hashed, never empty ('${pwfield}')" \
    "$([ -n "$pwfield" ] && echo 0 || echo 1)"
fi

# Groups a desktop session needs.
for grp in wheel audio video network plugdev input render; do
  check "supplementary group '${grp}' exists" \
    "$(awk -F: -v g="$grp" '$1 == g {found=1} END {exit !found}' "$STAGE/etc/group" && echo 0 || echo 1)"
done

# ---------------------------------------------------------------------------
section "Home ownership mechanism"
# The staging tree cannot express ownership (see the note in the user section
# above), so assert that the two components which *do* own that responsibility
# are wired up. If either regresses, no installed system would have a usable
# home directory and the failure would otherwise only appear at first login.
check "archive builder pins ownership (make-rootfs.sh uses cpio --owner)" \
  "$(grep -Eq 'cpio .*--owner' "$REPO_ROOT/rootfs/scripts/make-rootfs.sh" && echo 0 || echo 1)"
check "installer applies home ownership (configure-user.sh chowns /home)" \
  "$(grep -Eq 'chown .*\$\{?TARGET\}?/home/' "$REPO_ROOT/installer/scripts/configure-user.sh" \
    && echo 0 || echo 1)"

# Regression guard. setup-rootfs.sh runs unprivileged in CI and on a developer
# machine, so any chown/chgrp/mknod it issues aborts the whole build with
# "Operation not permitted". The ownership guarantee is carried by cpio
# --owner=0:0 instead, so such a call can only ever be a bug. Grep for the
# command form only, so the explanatory comments may still mention the word.
check "setup-rootfs.sh issues no privileged ownership commands" \
  "$(grep -Eq '^[[:space:]]*(chown|chgrp|mknod)[[:space:]]' \
      "$REPO_ROOT/base-system/scripts/setup-rootfs.sh" && echo 1 || echo 0)"
check "setup-rootfs.sh sets the security modes those commands implied" \
  "$(for m in 'chmod 0600 .*/etc/shadow' 'chmod 0440 .*/etc/sudoers"'; do
       grep -Eq "$m" "$REPO_ROOT/base-system/scripts/setup-rootfs.sh" || exit 1
     done && echo 0 || echo 1)"

# Re-runnability guard. make-rootfs.sh invokes setup-rootfs.sh against a stage
# directory that already holds the previous run's output, so a second pass is
# the normal path, not an edge case. Any file the script writes and then
# tightens to a mode that is not owner-writable (e.g. /etc/sudoers at 0440)
# cannot then be truncated in place, and the second run dies with EACCES. This
# is a behavioural test rather than a grep, because the failure depends on the
# ordering of the writes and the chmods, which no single pattern can express.
check_setup_rootfs_reruns() {
  # Behave as the guard in the section above: no privileged calls, and the
  # restrictive modes those calls used to imply are set explicitly.
  local dir status mode
  dir="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand $dir now, not at trap time
  trap "rm -rf '$dir'" RETURN

  # Twice, because the second run is the one that finds the first run's output.
  local pass=0
  for _ in 1 2; do
    if SHREEOS_STAGE_ROOT="$dir" \
        bash "$REPO_ROOT/base-system/scripts/setup-rootfs.sh" >/dev/null 2>&1; then
      pass=$((pass + 1))
    fi
  done
  status=0
  [ "$pass" -eq 2 ] || status=1

  # The policy must survive intact and keep the mode sudo requires.
  grep -Eq '^[^#]*%wheel[[:space:]]+ALL=' "$dir/etc/sudoers" || status=1
  mode="$(stat -c '%a' "$dir/etc/sudoers" 2>/dev/null || echo '?')"
  [ "$mode" = "440" ] || status=1
  # No temporary file from the atomic write may be left behind.
  [ -z "$(find "$dir/etc" -maxdepth 1 -name '.sudoers.*' -print -quit)" ] || status=1
  return "$status"
}
check "setup-rootfs.sh is re-runnable and leaves no temp files" \
  "$(setup_rootfs_reruns && echo 0 || echo 1)"

# --------------------------------------------------------------------------
section "Privilege escalation (sudo)"
check "sudo binary is installed" \
  "$([ -x "$STAGE/usr/bin/sudo" ] || [ -x "$STAGE/usr/local/bin/sudo" ] && echo 0 || echo 1)"
check "sudoers file exists" "$([ -f "$STAGE/etc/sudoers" ] && echo 0 || echo 1)"
# sudo refuses to run if sudoers is group/world writable.
if [ -f "$STAGE/etc/sudoers" ]; then
  mode="$(stat -c '%a' "$STAGE/etc/sudoers" 2>/dev/null || echo '?')"
  check "sudoers mode is 0440 (mode $mode)" \
    "$([ "$mode" = "440" ] && echo 0 || echo 1)"
  check "sudoers grants the wheel group" \
    "$(grep -Eq '^[^#]*%wheel[[:space:]]+ALL=' "$STAGE/etc/sudoers" && echo 0 || echo 1)"
fi
check "desktop user is a member of wheel" \
  "$(awk -F: -v g="wheel" '$1 == g {print $4}' "$STAGE/etc/group" | tr ',' '\n' \
     | grep -Fxq "$DESKTOP_USER" && echo 0 || echo 1)"

# --------------------------------------------------------------------------
section "System configuration"
# os-release is what every tool reads to identify the distribution.
check "/etc/os-release exists" "$([ -s "$STAGE/etc/os-release" ] && echo 0 || echo 1)"
for key in NAME ID VERSION_ID PRETTY_NAME; do
  check "/etc/os-release defines ${key}" \
    "$(grep -Eq "^${key}=" "$STAGE/etc/os-release" && echo 0 || echo 1)"
done
# An unresolved shell variable means the file was generated from a template
# that was never expanded, which breaks every consumer.
checks=$((checks + 1))
if grep -q '\${' "$STAGE/etc/os-release" 2>/dev/null; then
  fail "/etc/os-release contains unexpanded variables"
else
  pass "/etc/os-release has no unexpanded variables"
fi

check "/etc/hostname is non-empty" \
  "$([ -s "$STAGE/etc/hostname" ] && echo 0 || echo 1)"
check "/etc/hosts defines localhost" \
  "$(grep -Eq '^[[:space:]]*127\.0\.0\.1[[:space:]]+.*localhost' "$STAGE/etc/hosts" && echo 0 || echo 1)"
check "/etc/hosts maps the hostname to a loopback address" \
  "$(host="$(cat "$STAGE/etc/hostname" 2>/dev/null | head -n1)"
      [ -n "$host" ] && grep -Eq "^[[:space:]]*127\.0\.1\.1[[:space:]]+.*\b${host}\b" "$STAGE/etc/hosts" && echo 0 || echo 1)"
check "/etc/fstab exists" "$([ -s "$STAGE/etc/fstab" ] && echo 0 || echo 1)"
for fs in proc sysfs devtmpfs; do
  check "/etc/fstab mounts ${fs}" \
    "$(awk -v f="$fs" '$3 == f {found=1} END {exit !found}' "$STAGE/etc/fstab" && echo 0 || echo 1)"
done
check "/etc/nsswitch.conf resolves users from files" \
  "$(grep -Eq '^passwd:[[:space:]]+files' "$STAGE/etc/nsswitch.conf" && echo 0 || echo 1)"
# nsswitch "hosts: files dns" is what makes getent/ping honour /etc/hosts first.
check "/etc/nsswitch.conf configures hosts lookup" \
  "$(grep -Eq '^hosts:[[:space:]]+.*\b(files|dns)\b' "$STAGE/etc/nsswitch.conf" && echo 0 || echo 1)"

# DNS: without a nameserver line, nothing resolves in a live session.
check "/etc/resolv.conf exists" "$([ -f "$STAGE/etc/resolv.conf" ] && echo 0 || echo 1)"
check "/etc/resolv.conf defines at least one nameserver" \
  "$(grep -Eq '^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F:.]+' "$STAGE/etc/resolv.conf" 2>/dev/null && echo 0 || echo 1)"

# /etc/skel is what gives every new user a sane starting dotfile set.
check "/etc/skel exists" "$([ -d "$STAGE/etc/skel" ] && echo 0 || echo 1)"

# --------------------------------------------------------------------------
section "Core utilities"
# These are the commands a user and the init system assume exist. Each must be
# a real executable in the target root, not a BusyBox applet stand-in.
for util in bash ls cat cp mv rm mkdir ln chmod chown mount umount ps kill \
           grep sed awk find tar sh env id date uname hostname sleep; do
  found=1
  for dir in /bin /usr/bin /sbin /usr/sbin /usr/local/bin; do
    if [ -x "$STAGE$dir/$util" ]; then found=0; break; fi
  done
  check "core utility '${util}' is installed and executable" "$found"
done

# Networking and hardware utilities the Phase 2 specification requires.
for util in ip ping dhclient udhcpc wpa_supplicant lspci lsusb dmidecode; do
  found=1
  for dir in /bin /usr/bin /sbin /usr/sbin /usr/local/bin; do
    if [ -x "$STAGE$dir/$util" ]; then found=0; break; fi
  done
  check "utility '${util}' is installed and executable" "$found"
done

# The dynamic loader must exist at the path ld.so.cache/interp expects.
check "dynamic loader ld-linux-x86-64.so.2 is present" \
  "$([ -e "$STAGE/lib64/ld-linux-x86-64.so.2" ] || [ -e "$STAGE/lib/ld-linux-x86-64.so.2" ] \
     || find "$STAGE" -name 'ld-linux-x86-64.so.2' -print -quit | grep -q . && echo 0 || echo 1)"

# Compression and archive tools named in the Phase 2 specification.
for util in gzip bzip2 xz zstd; do
  found=1
  for dir in /bin /usr/bin; do
    if [ -x "$STAGE$dir/$util" ]; then found=0; break; fi
  done
  check "compression utility '${util}' is installed" "$found"
done

# --------------------------------------------------------------------------
section "Host contamination"
# Everything in the target root must be an x86-64 ELF built by our toolchain.
# A host Ubuntu binary would be dynamically linked against libraries that do
# not exist on ShreeOS and would fail only at runtime, in the live session.
if [ -x "$STAGE/usr/bin/bash" ]; then
  interp="$(readelf -l "$STAGE/usr/bin/bash" 2>/dev/null \
            | sed -n 's/.*program interpreter: \(.*\)\]/\1/p' | head -n1)"
  case "$interp" in
    /lib64/ld-linux-x86-64.so.2|/lib/ld-linux-x86-64.so.2)
      check "bash links against the target dynamic loader" 0
      ;;
    "")
      check "bash is statically linked or has no interpreter" 0
      ;;
    *)
      fail "bash requests a foreign dynamic loader: ${interp}"
      ;;
  esac
  # A binary carrying a .note.package section was produced by a distribution
  # rebuild, not by our build scripts.
  if readelf -S "$STAGE/usr/bin/bash" 2>/dev/null | grep -q 'note.package'; then
    fail "bash carries a distribution .note.package section (host build contamination)"
  else
    check "bash has no distribution .note.package section" 0
  fi
fi
check "no Ubuntu host metadata in /etc (os-release not overridden)" \
  "$([ -s "$STAGE/etc/os-release" ] && ! grep -qi 'ubuntu' "$STAGE/etc/os-release" && echo 0 || echo 1)"

fi  # end of assembled-root checks

# --------------------------------------------------------------------------
section "Host-contamination guard behaviour"
# base_assert_no_host_binary is the per-package guard against copying a build
# host binary into the target root. These cases test the guard itself rather
# than the rootfs, because a guard that cannot fail is worse than no guard: it
# would report success while contaminated binaries shipped.
# shellcheck source=/dev/null
source "$REPO_ROOT/base-system/scripts/common.sh"

guard() {
  ( base_assert_no_host_binary "$@" ) >/dev/null 2>&1
}

if [ -x "$STAGE/usr/bin/bash" ]; then
  if guard "$STAGE/usr/bin/bash"; then
    check "guard accepts a genuine target binary" 0
  else
    fail "guard rejected our own target binary: $STAGE/usr/bin/bash"
  fi
else
  printf '  [skip] guard cases needing a target binary (bash not staged)\n'
fi

if guard "$STAGE/usr/bin/definitely-not-installed-xyz"; then
  fail "guard passed a path that does not exist"
else
  check "guard rejects a path that does not exist" 0
fi

scratch="$(mktemp -d)"
printf 'this is not an ELF object\n' > "$scratch/plain.txt"
if guard "$scratch/plain.txt"; then
  fail "guard reported a pass when no ELF object was inspected"
else
  check "guard refuses to report a pass when nothing was inspected" 0
fi
rm -rf "$scratch"

# The fail-closed case. If readelf is unavailable, the ELF header probe fails
# for every file, which the "not an ELF" branch would otherwise treat as
# "nothing to check" -- turning the guard into a no-op that always passes.
empty_path="$(mktemp -d)"
if ( PATH="$empty_path" base_assert_no_host_binary "$STAGE/usr/bin/bash" ) >/dev/null 2>&1; then
  fail "guard reported a pass with no readelf in PATH"
else
  check "guard fails closed when readelf is unavailable" 0
fi
rm -rf "$empty_path"

# --------------------------------------------------------------------------
section "Cross-dependency guard behaviour"
# base_require_sysroot_dependency is what stops a package from configuring
# against a dependency that is not really in the target sysroot. An earlier
# version used a bare `pkg-config --exists attr`, which reported a healthy
# sysroot as empty because host pkg-config never searches ${LUMEN_SYSROOT}.
# These cases pin the correct behaviour, including the fail-closed cases.
dep_scratch="$(mktemp -d)"
dep_saved_sysroot="${LUMEN_SYSROOT}"

dep_guard() {
  ( LUMEN_SYSROOT="$dep_scratch/sysroot" base_require_sysroot_dependency "$@" ) \
    >/dev/null 2>&1
}

mkdir -p "$dep_scratch/sysroot/usr/include/attr" "$dep_scratch/sysroot/usr/lib"
printf '/* header */\n' > "$dep_scratch/sysroot/usr/include/attr/xattr.h"
: > "$dep_scratch/sysroot/usr/lib/libattr.so"

if dep_guard "attr" "usr/include/attr/xattr.h" "usr/lib/libattr.so"; then
  check "dependency guard accepts a sysroot holding the header and library" 0
else
  fail "dependency guard rejected a sysroot that does contain libattr"
fi

# A leading slash must be tolerated: callers should not have to agree on a
# slash convention for sysroot-relative paths.
if dep_guard "attr" "/usr/lib/libattr.so"; then
  check "dependency guard tolerates a leading slash on the path" 0
else
  fail "dependency guard rejects an otherwise valid absolute-style path"
fi

# Any one of the listed artifacts is enough: version-suffixed sonames differ
# between releases, so requiring a specific name would be brittle.
if dep_guard "attr" "usr/lib/libattr.so.1" "usr/lib/libattr.so"; then
  check "dependency guard accepts any one of the listed artifacts" 0
else
  fail "dependency guard rejects a sysroot matching only the fallback name"
fi

if dep_guard "attr" "usr/lib/libnowhere.so"; then
  fail "dependency guard passed a sysroot missing every listed artifact"
else
  check "dependency guard rejects a sysroot missing every listed artifact" 0
fi

# Fail-closed: no paths at all must not report success.
if dep_guard "attr"; then
  fail "dependency guard reported a pass when given no paths"
else
  check "dependency guard refuses to pass vacuously with no paths" 0
fi

rm -rf "$dep_scratch"
LUMEN_SYSROOT="$dep_saved_sysroot"

# The acl recipe must assert on the artifacts acl actually consumes
# (AC_CHECK_LIB/AC_CHECK_HEADERS), not on a host pkg-config lookup.
acl_recipe="$REPO_ROOT/base-system/scripts/30-acl.sh"
if grep -qE '^\s*(if\s+!|)\s*pkg-config --exists attr' "$acl_recipe"; then
  fail "acl recipe gates on a bare 'pkg-config --exists attr' host lookup"
else
  check "acl recipe does not gate on a host pkg-config lookup" 0
fi
if grep -q 'base_require_sysroot_dependency' "$acl_recipe"; then
  check "acl recipe asserts its libattr dependency in the sysroot" 0
else
  fail "acl recipe has no sysroot dependency assertion for libattr"
fi

# gettext is not in the Phase 2 package set. Both recipes must disable NLS
# explicitly, otherwise they bind to whatever gettext the CI runner image
# happens to ship and the build stops being reproducible.
for recipe in 29-attr.sh 30-acl.sh; do
  if grep -q -- '--disable-nls' "$REPO_ROOT/base-system/scripts/$recipe"; then
    check "$recipe disables NLS explicitly" 0
  else
    fail "$recipe leaves AM_GNU_GETTEXT([external]) to pick up host gettext"
  fi
done

# --------------------------------------------------------------------------
section "Unpinned host-dependent configure knob contract"
# shadow 4.18's configure hard-requires readpassphrase() plus
# <readpassphrase.h> unless --without-libbsd is passed (upstream
# configure.ac:358-370). glibc provides neither and libbsd is not in the
# Phase 2 package set, so an unpinned knob aborts configure -- which the
# 2026-09-29 CI run demonstrated at package 36/51, 18 minutes into a build
# whose earlier packages had all succeeded. Like the bzip2 section below,
# these static checks catch the mistake in seconds instead.
#
# A recipe that already disables the feature must keep doing so; a recipe
# that drops the flag silently re-exposes the host-dependent probe.
shadow_recipe="$REPO_ROOT/base-system/scripts/36-shadow.sh"
if grep -q -- '--without-libbsd' "$shadow_recipe"; then
  check "shadow recipe disables libbsd support explicitly" 0
else
  fail "shadow recipe leaves --with-libbsd to a host-dependent default; configure aborts without host libbsd"
fi

# --------------------------------------------------------------------------
section "Multi-call binary install contract"
# bzip2's Makefile builds only `bzip2` and `bzip2recover`. `bunzip2` and
# `bzcat` are the *same* executable: bzip2.c copies argv[0], strips the
# directory, and switches on strstr(progName, "unzip"/"zcat"). An earlier
# revision of this recipe tried to `install` those names as separate build
# products, which fails late in the 50-minute build with
# "install: cannot stat 'bunzip2'".
#
# These static checks catch that class of mistake in seconds.
# Referenced by full path so this section does not depend on a variable that
# a later section defines; the test runs under `set -u`.
bzip2_recipe="$REPO_ROOT/base-system/scripts/34-bzip2.sh"

# Only real build products may be installed. bunzip2/bzcat must be aliases.
for phantom in bunzip2 bzcat; do
  if grep -qE "^[[:space:]]*install[[:space:]]+(-[a-zA-Z0-9]+[[:space:]]+)*\b${phantom}\b" \
      "$bzip2_recipe"; then
    fail "bzip2 recipe installs ${phantom} as if it were a separate build product"
  else
    check "bzip2 recipe does not install ${phantom} as a build product" 0
  fi
done

# The aliases must exist and must be symlinks, since the dispatcher only sees
# argv[0] -- a copied binary would be indistinguishable from plain bzip2.
for alias in bunzip2 bzcat; do
  if grep -qE "ln -sfn[[:space:]]+\"?bzip2\"?[[:space:]].*\/usr\/bin\/${alias}\"" \
      "$bzip2_recipe"; then
    check "bzip2 recipe installs ${alias} as a symlink to the multi-call binary" 0
  else
    fail "bzip2 recipe does not symlink ${alias} to the multi-call binary"
  fi
done

# bzip2recover is a genuinely separate program; aliasing it to the compressor
# would silently produce a broken "recover" that instead re-compresses.
if grep -qE "ln -sfn[[:space:]]+\"?bzip2\"?[[:space:]].*bzip2recover" "$bzip2_recipe"; then
  fail "bzip2 recipe aliases bzip2recover to bzip2; it is a separate program"
else
  check "bzip2 recipe keeps bzip2recover as a separate program" 0
fi

# The recipe must build the two real targets explicitly, since upstream's
# "all" target runs the host test suite against a cross-built binary.
if grep -qE "^[[:space:]]*make .*\bbzip2[[:space:]]+bzip2recover\b" "$bzip2_recipe"; then
  check "bzip2 recipe builds only real targets, avoiding the host test suite" 0
else
  fail "bzip2 recipe does not build bzip2 and bzip2recover explicitly"
fi

# --------------------------------------------------------------------------
section "Build-script hygiene"
# Static analysis of the build scripts themselves. These checks need no
# cross-compiled rootfs, so they catch a broken package recipe in seconds
# instead of after a full 51-package build.
#
# The bug this exists for: a recipe invoking a make target that does not
# exist in the upstream tarball ("install-lib" for libcap) fails only halfway
# through CI, after every earlier package has been built.
scripts_dir="$REPO_ROOT/base-system/scripts"

# Every numbered recipe must be listed in the build order array, otherwise
# the package is silently never built.
declared="$(grep -oE '"[0-9]{2}-[a-z0-9-]+"' "$scripts_dir/build-all.sh" \
           | tr -d '"' | sort -u)"
# -printf is a GNU find extension; use -name/-exec so the check also runs on a
# non-GNU host rather than silently producing an empty "present" list.
present="$(find "$scripts_dir" -maxdepth 1 -name '[0-9][0-9]-*.sh' \
           -exec basename {} .sh \; | sort -u)"
# Fail closed: if either list came back empty the comparisons below would pass
# vacuously and report a clean tree regardless of what is actually on disk.
if [ -z "$present" ]; then
  fail "found no numbered build recipes under ${scripts_dir}"
  exit 1
fi
if [ -z "$declared" ]; then
  fail "parsed no build order from ${scripts_dir}/build-all.sh"
  exit 1
fi

missing_from_order="$(comm -13 <(printf '%s\n' "$declared") \
                                <(printf '%s\n' "$present") | tr '\n' ' ')"
check "every numbered recipe is in the build order" \
  "$([ -z "$missing_from_order" ] && echo 0 || echo 1)"
if [ -n "$missing_from_order" ]; then
  fail "recipes never built (absent from build-all.sh): ${missing_from_order}"
fi

orphan="$(comm -23 <(printf '%s\n' "$declared") \
                    <(printf '%s\n' "$present") | tr '\n' ' ')"
check "build order references no missing recipe" \
  "$([ -z "$orphan" ] && echo 0 || echo 1)"
if [ -n "$orphan" ]; then
  fail "build-all.sh lists recipes with no script: ${orphan}"
fi

# make targets referenced by recipes must be plain upstream targets. A
# 'install-*' variant is a strong signal of a guessed target name.
if grep -nE '^\s*install-[a-z]+\s*\\?$' "$scripts_dir"/[0-9][0-9]-*.sh \
     >/dev/null 2>&1; then
  fail "a recipe passes a guessed 'install-*' make target; use plain 'install'"
else
  check "no recipe uses a guessed install-<subdir> make target" 0
fi

# Host-dependent upstream defaults must be pinned, or a runner that happens
# to have these tools changes what gets built into the target root.
for var in PAM_CAP GOLANG RAISE_SETFCAP; do
  if grep -lE "^\s*${var}=" "$scripts_dir"/[0-9][0-9]-*.sh >/dev/null 2>&1; then
    check "recipe pins ${var} explicitly" 0
  else
    :
  fi
done
unpinned=""
for recipe in "$scripts_dir"/[0-9][0-9]-*.sh; do
  # Only libcap honours these knobs; skip recipes that never mention libcap.
  grep -q 'libcap' "$recipe" || continue
  for var in PAM_CAP GOLANG; do
    grep -qE "^\s*${var}=" "$recipe" || unpinned="${unpinned} $(basename "$recipe"):${var}"
  done
done
check "libcap recipe pins host-dependent Make.Rules defaults" \
  "$([ -z "$unpinned" ] && echo 0 || echo 1)"
if [ -n "$unpinned" ]; then
  fail "libcap recipe leaves host-dependent defaults unpinned:${unpinned}"
fi

# Recipes must not suppress failures. A swallowed error turns a real build
# break into a mystery at ISO-validation time.
if grep -nE '\|\|[[:space:]]*true' "$scripts_dir"/[0-9][0-9]-*.sh \
     >/dev/null 2>&1; then
  fail "a base-system recipe suppresses a failure with '|| true'"
else
  check "no base-system recipe uses '|| true'" 0
fi

# --------------------------------------------------------------------------
section "Command-substitution stdout hygiene"
# base_pkg_extract() is consumed as  srcdir="$(base_pkg_extract <pkg>)"  so
# its stdout IS its return value. Any diagnostic written to stdout there is
# captured into ${srcdir}, turning the build directory into a log string --
# which is how Linux-PAM-1.7.0 failed with
#   "build directory '[shreeos] Normalizing source directory ...'"
#
# shreeos_log/shreeos_ok print to stdout; shreeos_warn/shreeos_die to stderr.
# So inside base_pkg_extract every logging call needs an explicit >&2.
extract_body="$(awk '
  /^base_pkg_extract\(\)/ { inside = 1 }
  inside               { print }
  inside && /^}/       { exit }
' "$scripts_dir/common.sh" | sed -e 's/[[:space:]]*#.*$//')"

leaked="$(printf '%s\n' "$extract_body" | awk '
  # Report logging calls that are not explicitly redirected to stderr.
  /shreeos_log|shreeos_ok|lumen_log|lumen_ok/ {
    if ($0 !~ />&[[:space:]]*2/) print FNR ":" $0
  }
')"

if [ -n "$leaked" ]; then
  fail "base_pkg_extract writes a diagnostic to stdout; it would be captured
       into \${srcdir} by srcdir=\"\$(base_pkg_extract <pkg>)\":
${leaked}"
else
  check "base_pkg_extract sends every diagnostic to stderr" 0
fi

# The function must still emit exactly the source directory on stdout: a
# caller that captured only the warnings would silently build in ${PWD}.
if [ "$(printf '%s\n' "$extract_body" | grep -c "printf '%s" )" -ge 1 ]; then
  check "base_pkg_extract still returns its path via stdout printf" 0
else
  fail "base_pkg_extract no longer prints the source directory on stdout"
fi

# Other helpers consumed in command substitution must have the same property.
# lumen's historical name is retained here so a future rename cannot silently
# reintroduce the bug under a new spelling.
subs="$(grep -ohE '[A-Za-z_][A-Za-z0-9_]*="\$\((base_pkg_extract|pkg_[a-z_]+)' \
  "$scripts_dir"/[0-9][0-9]-*.sh 2>/dev/null | sed -E 's/.*"\$\(//' \
  | sort -u | tr '\n' ' ')"
printf 'command-substituted helpers: %s\n' "${subs:-none}"

# --------------------------------------------------------------------------
section "Meson option value contract"
# meson validates every -D value during setup, before any build logic runs.
# A boolean/feature option accepts enabled/disabled/true/false, but a combo
# only accepts its declared choices -- passing "disabled" to one aborts the
# whole package. That is how Linux-PAM 1.7.0 failed at 37/51:
#   ERROR: Value "disabled" (of type "string") for option "db" is not one
#   of the choices. Possible choices are (as string): "db", "gdbm", "ndbm", "auto".
# The pam recipe is the only meson consumer in the base system, so pin the
# exact -D lines that must (and must not) appear.
pam_recipe="$REPO_ROOT/base-system/scripts/37-pam.sh"

# -Ddb=disabled is illegal: 'db' is a combo (db/gdbm/ndbm/auto).
if grep -q -- '-Ddb=disabled' "$pam_recipe"; then
  fail "pam recipe passes -Ddb=disabled; 'db' is a combo whose choices are db/gdbm/ndbm/auto"
else
  check "pam recipe does not pass the illegal -Ddb=disabled value" 0
fi

# pam_userdb is the only consumer of the db backend (pam meson.build:336-398
# reads get_option('db') solely inside the not-disabled pam_userdb branch).
# It must be disabled explicitly, or meson's cc.find_library probe could pull
# a host libdb/libgdbm into the cross build.
if grep -q -- '-Dpam_userdb=disabled' "$pam_recipe"; then
  check "pam recipe disables pam_userdb explicitly" 0
else
  fail "pam recipe leaves pam_userdb at auto; the db backend probe could bind to the host"
fi

# ...and db itself must stay at a legal combo choice.
if grep -q -- '-Ddb=auto' "$pam_recipe"; then
  check "pam recipe leaves the db combo at its legal 'auto' choice" 0
else
  fail "pam recipe does not pass -Ddb=auto; the combo value must be one of db/gdbm/ndbm/auto"
fi

# iputils 20250605 is the other meson consumer. Its option set changed
# between releases: rarpd/rdisc/ninfod and USE_ROOTNO were removed upstream,
# so the flag names from older releases are now unknown options that abort
# meson setup. The recipe is pinned to the 20250605 names.
iputils_recipe="$REPO_ROOT/base-system/scripts/43-iputils.sh"
for stale in USE_ROOTNO BUILD_RARPD BUILD_RDISC BUILD_NINFOD; do
  if grep -q -- "-D${stale}=" "$iputils_recipe"; then
    fail "iputils recipe passes -D${stale}=; that option does not exist in 20250605"
  else
    check "iputils recipe does not pass the removed option -D${stale}" 0
  fi
done
# gettext must be pinned off, or meson probes the host msgfmt/intl.
if grep -q -- '-DUSE_GETTEXT=false' "$iputils_recipe"; then
  check "iputils recipe disables USE_GETTEXT explicitly" 0
else
  fail "iputils recipe leaves USE_GETTEXT to auto; the host gettext could leak in"
fi

# --------------------------------------------------------------------------
printf '\n== Summary ==\n'
printf 'checks run : %d\n' "$checks"
printf 'failures   : %d\n' "$failures"
if [ "$failures" -ne 0 ]; then
  printf '\nBase system contract FAILED with %d unmet requirement(s).\n' "$failures" >&2
  exit 1
fi
printf '\nBase system contract PASSED: all %d requirements met.\n' "$checks"
