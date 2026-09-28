#!/usr/bin/env bash
# setup-rootfs.sh — Create the initial root filesystem skeleton for ShreeOS
# Usage: bash base-system/scripts/setup-rootfs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Setting up root filesystem skeleton in ${LUMEN_STAGE_ROOT}"

mkdir -p "${LUMEN_STAGE_ROOT}"/{bin,boot,dev,etc,home,lib,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
mkdir -p "${LUMEN_STAGE_ROOT}/etc"/{default,init.d,skel,sysconfig}
mkdir -p "${LUMEN_STAGE_ROOT}/usr"/{bin,lib,local,sbin,share,src,include}
mkdir -p "${LUMEN_STAGE_ROOT}/var"/{cache,lib,lock,log,mail,opt,run,spool,tmp}
mkdir -p "${LUMEN_STAGE_ROOT}/var/log"/{journal,old}
mkdir -p "${LUMEN_STAGE_ROOT}/run"

chmod 0700 "${LUMEN_STAGE_ROOT}/root"
chmod 1777 "${LUMEN_STAGE_ROOT}/tmp"
chmod 1777 "${LUMEN_STAGE_ROOT}/var/tmp"
# /var/run and /var/lock are canonical symlinks into tmpfs. On rebuilds they may
# already exist as real directories created by an earlier stage; replace those
# directories (keeping their contents under /run) instead of letting ln -sf fail
# with "cannot overwrite directory" under set -e.
if [ -d "${LUMEN_STAGE_ROOT}/var/run" ] && [ ! -L "${LUMEN_STAGE_ROOT}/var/run" ]; then
  rm -rf "${LUMEN_STAGE_ROOT}/var/run"
fi
if [ -d "${LUMEN_STAGE_ROOT}/var/lock" ] && [ ! -L "${LUMEN_STAGE_ROOT}/var/lock" ]; then
  rm -rf "${LUMEN_STAGE_ROOT}/var/lock"
fi
ln -sfn /run "${LUMEN_STAGE_ROOT}/var/run"
ln -sfn /run/lock "${LUMEN_STAGE_ROOT}/var/lock"

HOSTNAME="${DISTRO_CODENAME}"
cat > "${LUMEN_STAGE_ROOT}/etc/hostname" <<EOF
${HOSTNAME}
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/hosts" <<EOF
127.0.0.1  localhost
::1        localhost
127.0.1.1  ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/fstab" <<EOF
# /etc/fstab: static file system information
# <fs>      <mountpoint>  <type>  <opts>           <dump/pass>
proc        /proc         proc    defaults          0 0
sysfs       /sys          sysfs   defaults          0 0
devtmpfs    /dev          devtmpfs defaults         0 0
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/bin/false
bin:x:2:2:bin:/bin:/bin/false
sys:x:3:3:sys:/dev:/bin/false
sync:x:4:65534:sync:/bin:/bin/false
games:x:5:60:games:/usr/games:/bin/false
man:x:6:12:man:/var/cache/man:/bin/false
lp:x:7:7:lp:/var/spool/lpd:/bin/false
mail:x:8:12:mail:/var/mail:/bin/false
news:x:9:13:news:/var/spool/news:/bin/false
uucp:x:10:14:uucp:/var/spool/uucp:/bin/false
proxy:x:13:13:proxy:/bin:/bin/false
www-data:x:33:33:www-data:/var/www:/bin/false
backup:x:34:34:backup:/var/backups:/bin/false
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
EOF
# The default desktop account. A graphical session must not run as root, so the
# image ships a real unprivileged user that the installer can rename, re-home, or
# replace. The password field is '!' (locked): a live image ships no credential,
# and the installer sets one before first boot. An empty field would mean "no
# password required" and is a genuine security defect, so it is never used here.
DESKTOP_USER="${SHREEOS_DESKTOP_USER:-shree}"
DESKTOP_UID="${SHREEOS_DESKTOP_UID:-1000}"
DESKTOP_GID="${SHREEOS_DESKTOP_GID:-1000}"
DESKTOP_HOME="/home/${DESKTOP_USER}"
case "${DESKTOP_UID}" in
  ''|*[!0-9]*) lumen_die "SHREEOS_DESKTOP_UID must be numeric, got '${DESKTOP_UID}'" ;;
esac
case "${DESKTOP_GID}" in
  ''|*[!0-9]*) lumen_die "SHREEOS_DESKTOP_GID must be numeric, got '${DESKTOP_GID}'" ;;
esac
if [ "${DESKTOP_UID}" = "0" ]; then
  lumen_die "The desktop user must not be root (uid 0)"
fi
printf '%s:x:%s:%s:%s:%s:/bin/bash\n' \
  "${DESKTOP_USER}" "${DESKTOP_UID}" "${DESKTOP_GID}" \
  "ShreeOS User" "${DESKTOP_HOME}" \
  >> "${LUMEN_STAGE_ROOT}/etc/passwd"

mkdir -p "${LUMEN_STAGE_ROOT}${DESKTOP_HOME}"
chmod 0755 "${LUMEN_STAGE_ROOT}${DESKTOP_HOME}"
# Ownership is deliberately not set here. This script must run unprivileged --
# tests/smoke/test-rootfs-reliability.sh invokes it without fakeroot -- and it is
# also pointless: make-rootfs.sh packs the tree with `cpio --owner=0:0`, which
# stamps every archive entry as root:root regardless of the staging filesystem.
# The installed/live session therefore materialises the user's home at runtime;
# see docs/audit/PHASE-1-AUDIT.md for the ownership gap this leaves in Phase 5.

mkdir -p "${LUMEN_STAGE_ROOT}/nonexistent"
chmod 0755 "${LUMEN_STAGE_ROOT}/nonexistent"

cat > "${LUMEN_STAGE_ROOT}/etc/group" <<'EOF'
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mem:x:8:
kmem:x:9:
cdrom:x:11:
mail:x:12:
news:x:13:
uucp:x:14:
man:x:15:
dialout:x:20:
floppy:x:23:
tape:x:26:
users:x:100:
nobody:x:65534:
EOF
# Groups a graphical desktop session requires for hardware access.
#
#   audio   /dev/snd/*            ALSA and PipeWire access
#   video   capture framebuffers  webcam and screen-capture devices
#   render  /dev/dri/*            DRM/KMS GPU access
#   input   /dev/input/*          seat input devices via logind
#   plugdev hot-pluggable devices USB storage, removable media, USB audio
#   network netdev capability     NetworkManager may configure interfaces
#   wheel   privilege escalation  the only group granted sudo
#
# These are appended rather than merged into the block above so the ordering is
# explicit: a group must be declared exactly once, because getent returns the
# first match and a duplicate with an empty member list would silently strip
# every supplementary group a desktop session needs.
cat >> "${LUMEN_STAGE_ROOT}/etc/group" <<EOF
video:x:998:${DESKTOP_USER}
input:x:997:${DESKTOP_USER}
render:x:999:${DESKTOP_USER}
network:x:1001:
plugdev:x:1002:${DESKTOP_USER}
audio:x:1003:${DESKTOP_USER}
wheel:x:10:${DESKTOP_USER}
EOF
# Service accounts referenced by /etc/passwd above need matching primary groups,
# or login fails with "setgid: invalid argument".
cat >> "${LUMEN_STAGE_ROOT}/etc/group" <<'EOF'
games:x:60:
www-data:x:33:
backup:x:34:
EOF
# The desktop user's own primary group, created last so its GID is unambiguous.
printf '%s:x:%s:\n' "${DESKTOP_USER}" "${DESKTOP_GID}" \
  >> "${LUMEN_STAGE_ROOT}/etc/group"

cat > "${LUMEN_STAGE_ROOT}/etc/shadow" <<'EOF'
root:!::0:::::
daemon:*::0:::::
bin:*::0:::::
sys:*::0:::::
sync:*::0:::::
games:*::0:::::
man:*::0:::::
lp:*::0:::::
mail:*::0:::::
news:*::0:::::
uucp:*::0:::::
proxy:*::0:::::
www-data:*::0:::::
backup:*::0:::::
nobody:*::0:::::
EOF
# The desktop account, locked rather than empty. A literal '*' in field 3 (the
# last-change day) keeps chage and PAM stacks from rejecting the account, and
# the empty second field for root means root has no password-based login at all.
printf '%s:!:%s:0:99999:7:::\n' "${DESKTOP_USER}" "${SHADOW_EPOCH_DAYS:-19700}" \
  >> "${LUMEN_STAGE_ROOT}/etc/shadow"
# field 3 must be numeric for the account to be valid; assert it rather than
# trusting the heredoc above to stay correct as accounts are added.
if awk -F: 'NF >= 3 && $1 !~ /^#/ && $3 != "" && $3 !~ /^[0-9]+$/ { found = 1 }
           END { exit !found }' "${LUMEN_STAGE_ROOT}/etc/shadow"; then
  lumen_die "Generated /etc/shadow has a non-numeric last-change field"
fi
chmod 0600 "${LUMEN_STAGE_ROOT}/etc/shadow"
# Ownership is intentionally not set here. The build runs unprivileged, so chown
# would fail outright, and it would be a no-op regardless: make-rootfs.sh packs
# the tree with `cpio --owner=0:0`, so every entry in the shipped archive is
# root:root no matter what the staging filesystem looks like. The mode is the
# part that carries security meaning, and chmod applies it unprivileged.

# ---------------------------------------------------------------------------
# Privilege escalation
# ---------------------------------------------------------------------------
# sudo refuses to load a sudoers file that is group- or world-writable, so the
# mode is part of the contract rather than a cosmetic detail: 0440 root:wheel.
cat > "${LUMEN_STAGE_ROOT}/etc/sudoers" <<'EOF'
## ShreeOS sudo policy
##
## The desktop account escalates through the `wheel` group only. Granting
## NOPASSWD would let any process in a user session become root unattended, and
## a user account must never be granted ALL on the command list.

Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults lecture_file="/etc/sudoers.lecture"
Defaults log_input,log_output
Defaults passwd_timeout=0
Defaults timestamp_timeout=15
Defaults !visiblepw
Defaults use_pty
Defaults requiretty
Defaults env_keep += "LANG LC_* DISPLAY WAYLAND_DISPLAY XAUTHORITY"

root    ALL=(ALL:ALL) ALL

# The desktop account escalates through `wheel` only. `%sudo` is declared
# unprivileged so a later installer can grant it deliberately rather than by
# accident.
%sudo   ALL=(ALL:ALL) ALL
%wheel  ALL=(ALL:ALL) ALL
EOF
mkdir -p "${LUMEN_STAGE_ROOT}/etc/sudoers.d"
# sudoers itself must be 0440: sudo refuses to start if it is group- or
# world-writable, because a writable policy is equivalent to passwordless root.
chmod 0440 "${LUMEN_STAGE_ROOT}/etc/sudoers"
# The drop-in directory is 0750 root:wheel so only the administrator group can
# add policy; world-write here would be the same defect as a writable sudoers.
chmod 0750 "${LUMEN_STAGE_ROOT}/etc/sudoers.d"
# See the note above /etc/shadow: ownership is pinned by `cpio --owner=0:0` at
# archive time, so no chown is issued here. Both modes are set because sudo
# refuses to start when its policy is group- or world-writable.

cat > "${LUMEN_STAGE_ROOT}/etc/os-release" <<EOF
NAME="${DISTRO_NAME}"
VERSION="${DISTRO_VERSION}"
ID=${DISTRO_ID}
VERSION_ID="${DISTRO_VERSION_ID}"
VERSION_CODENAME=${DISTRO_CODENAME}
PRETTY_NAME="${DISTRO_NAME} ${DISTRO_VERSION}"
HOME_URL="${DISTRO_HOME_URL}"
SUPPORT_URL="${DISTRO_SUPPORT_URL}"
BUG_REPORT_URL="${DISTRO_BUG_REPORT_URL}"
DOCUMENTATION_URL="${DISTRO_DOCUMENTATION_URL}"
EOF
# An unexpanded ${...} here means the file was written from a template that was
# never substituted, which silently breaks every tool that reads os-release
# (lsb_release, systemd, package managers, the desktop settings panel).
if grep -q '\${' "${LUMEN_STAGE_ROOT}/etc/os-release"; then
  lumen_die "/etc/os-release contains unexpanded shell variables"
fi

# /etc/resolv.conf ships a usable resolver so a live session resolves names even
# before DHCP hands one down. The network stack replaces it at runtime; this is
# the safe fallback, not the primary mechanism.
cat > "${LUMEN_STAGE_ROOT}/etc/resolv.conf" <<'EOF'
# ShreeOS resolver configuration
#
# Regenerated at runtime by the DHCP client. These public resolvers are the
# fallback used when no network configuration has been supplied yet.
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0 trust-ad
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/nsswitch.conf" <<'EOF'
passwd:         files
group:          files
shadow:         files
hosts:          files dns
networks:       files
protocols:      files
services:       files
ethers:         files
rpc:            files
EOF

# %sudo is referenced by the sudoers policy; it starts with no members so the
# grant is inert until an administrator or the installer adds someone.
printf 'sudo:x:27:\n' >> "${LUMEN_STAGE_ROOT}/etc/group"

# /etc/skel is copied into every new account's home. A login shell that starts
# with no PATH, no umask, and no locale is a poor default, so the baseline is
# defined once here rather than re-implemented by the installer.
cat > "${LUMEN_STAGE_ROOT}/etc/skel/.profile" <<'EOF'
# ~/.profile: executed by the login shell for interactive sessions.
# This file is copied from /etc/skel, so edits here become the default for new
# accounts. Local customisation belongs in ~/.profile.local, which is sourced
# last and is never managed by the distribution.

export USER="${USER:-$(id -un)}"
export HOME="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
export PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
export SHELL="${SHELL:-/bin/bash}"

# Locale: a UTF-8 locale is required for correct text rendering in the desktop.
if [ -z "${LANG:-}" ]; then
  export LANG=C.UTF-8
fi
unset LC_ALL

# umask 022 keeps files private by default. A session that creates world-readable
# files without asking is a real information-disclosure path.
umask 022

# Load the interactive shell configuration only for interactive sessions, so a
# scp or a non-interactive ssh command is not slowed by terminal setup.
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi

[ -f "$HOME/.profile.local" ] && . "$HOME/.profile.local"

# Include an optional directory that can be used to execute commands once.
if [ -d "$HOME/bin" ]; then
  PATH="$HOME/bin:$PATH"
  export PATH
fi
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/skel/.bashrc" <<'EOF'
# ~/.bashrc: interactive shell configuration. Not read by non-interactive shells.

# Return early for non-interactive shells so aliases and prompt setup do not
# slow down every scp, rsync, or CI invocation that sources this file.
case $- in
  *i*) ;;
    *) return ;;
esac

HISTFILE="$HOME/.bash_history"
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize
shopt -s cmdhist lithist
PROMPT_COMMAND='history -a; history -n'
export HISTFILE HISTSIZE HISTFILESIZE HISTCONTROL

# Colour support, disabled when the output is not a terminal so redirected
# output and logs stay free of escape sequences.
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then
  if [ -r /etc/bash.bashrc ] && . /etc/bash.bashrc; then
    :
  fi
else
  PS1='\s-\v\$ '
fi

# A modest, readable prompt: user@host, current directory, and exit status.
PS1='\[\e[32;1m\]\u@\h\[\e[0m\]:\[\e[34;1m\]\w\[\e[0m\]\$ '

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
EOF

# /etc/login.defs: password and account policy applied by the account tools.
cat > "${LUMEN_STAGE_ROOT}/etc/login.defs" <<'EOF'
# /etc/login.defs - account and password policy for ShreeOS.
# Values here are applied by useradd, chage, and passwd at account-creation time.

# Password hashing. SHA-512 ($6$) with a high cost is the strongest option the
# base crypt supports; the salt is per-user and random.
MD5_CRYPT_ENCRYPT no
SHA_CRYPT_MIN_ROUNDS 10000
SHA_CRYPT_MAX_ROUNDS 500000
ENCRYPT_METHOD SHA512

# Password ageing.
PASS_MAX_DAYS 365
PASS_MIN_DAYS 0
PASS_WARN_AGE 14

# Account expiry, and the grace window after an expired password.
ACCT_EXPIRE_MAX_DAYS 3650
USERDEL_CMD rmdir
USERDEL_MAIL_DIR
MAIL_DIR /var/mail
MAIL_FILE .mail

# Login retries and controls.
LOGIN_RETRIES 3
LOGIN_TIMEOUT 60
FAIL_DELAY 3
FAILLOG_ENAB yes
LASTLOG_ENAB yes
FTMP_FILE /var/log/btmp
SU_NAME su
SU_WHEEL_ONLY no
UMASK 022
ENV_PATH PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
ENV_SUPATH PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/ld.so.conf" <<'EOF'
/usr/lib
/lib
EOF

lumen_ok "Root filesystem skeleton created at ${LUMEN_STAGE_ROOT}"
