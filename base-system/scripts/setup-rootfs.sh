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

chmod 1777 "${LUMEN_STAGE_ROOT}/tmp"
chmod 1777 "${LUMEN_STAGE_ROOT}/var/tmp"
ln -sf /run "${LUMEN_STAGE_ROOT}/var/run"
ln -sf /run/lock "${LUMEN_STAGE_ROOT}/var/lock"

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
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/group" <<'EOF'
root:x:0:
daemon:x:1:
bin:x:2:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:12:
nobody:x:65534:
users:x:100:
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/shadow" <<'EOF'
root:!::0:::::
daemon:*::0:::::
bin:*::0:::::
nobody:*::0:::::
EOF
chmod 640 "${LUMEN_STAGE_ROOT}/etc/shadow"

cat > "${LUMEN_STAGE_ROOT}/etc/os-release" <<EOF
NAME="${DISTRO_NAME}"
VERSION="${DISTRO_VERSION}"
ID=${DISTRO_ID}
PRETTY_NAME="${DISTRO_NAME} ${DISTRO_VERSION}"
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/nsswitch.conf" <<'EOF'
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
EOF

cat > "${LUMEN_STAGE_ROOT}/etc/ld.so.conf" <<'EOF'
/usr/lib
/lib
EOF

lumen_ok "Root filesystem skeleton created at ${LUMEN_STAGE_ROOT}"
