#!/usr/bin/env bash
# Build the native X11 desktop graphics stack into the ShreeOS target rootfs.
#
# This intentionally cross-builds every target library. Host X11 development
# packages are not used as link inputs, so a successful build certifies that
# the ISO carries the libraries and server it needs at runtime.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../base-system/scripts/common.sh
source "$REPO_ROOT/base-system/scripts/common.sh"

PACKAGES_FILE="$SCRIPT_DIR/packages.list"
GRAPHICS_BUILD="$LUMEN_BUILD_DIR/desktop-graphics"
GRAPHICS_SOURCES="$LUMEN_SOURCES"
MESON_CROSS="$GRAPHICS_BUILD/shreeos-cross.ini"
BUILD_TRIPLET="$(gcc -dumpmachine)"

mkdir -p "$GRAPHICS_BUILD" "$GRAPHICS_SOURCES"
base_verify_toolchain

pkg_field() {
  local name="$1"
  local field="$2"
  awk -F '\t' -v n="$name" -v f="$field" '
    $0 !~ /^#/ && $1 == n { print $f; exit }
  ' "$PACKAGES_FILE"
}

pkg_version_graphics() { pkg_field "$1" 2; }
pkg_url_graphics() { pkg_field "$1" 3; }
pkg_sha_graphics() { pkg_field "$1" 4; }

pkg_archive_graphics() {
  local url
  url="$(pkg_url_graphics "$1")"
  basename "$url"
}

fetch_graphics_source() {
  local name="$1"
  local url sha archive
  url="$(pkg_url_graphics "$name")"
  sha="$(pkg_sha_graphics "$name")"
  archive="$(pkg_archive_graphics "$name")"
  if [[ -z "$url" || -z "$sha" ]]; then
    lumen_die "Missing source metadata for desktop package: $name"
  fi
  lumen_fetch "$url" "$GRAPHICS_SOURCES/$archive" "$sha"
}

prepare_source() {
  local name="$1"
  local archive src
  fetch_graphics_source "$name"
  archive="$(pkg_archive_graphics "$name")"
  src="$GRAPHICS_BUILD/src-$name"
  rm -rf "$src"
  mkdir -p "$src"
  tar -xf "$GRAPHICS_SOURCES/$archive" -C "$src" --strip-components=1
  printf '%s\n' "$src"
}

graphics_sync_sysroot() {
  local src dst
  base_sync_sysroot

  # Architecture-independent pkg-config metadata and X protocol data are
  # installed below /usr/share. Mirror them into the target sysroot as well.
  src="$LUMEN_STAGE_ROOT/usr/share"
  if [[ -d "$src" ]]; then
    dst="$LUMEN_SYSROOT/usr/share"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
  fi
}

write_meson_cross_file() {
  cat > "$MESON_CROSS" <<EOF
[binaries]
c = '$LUMEN_TOOLS/bin/$LUMEN_TARGET_TRIPLET-gcc'
cpp = '$LUMEN_TOOLS/bin/$LUMEN_TARGET_TRIPLET-g++'
ar = '$LUMEN_TOOLS/bin/$LUMEN_TARGET_TRIPLET-ar'
strip = '$LUMEN_TOOLS/bin/$LUMEN_TARGET_TRIPLET-strip'
pkgconfig = '/usr/bin/pkg-config'

[properties]
needs_exe_wrapper = true
sys_root = '$LUMEN_SYSROOT'
pkg_config_libdir = ['$LUMEN_SYSROOT/usr/lib/pkgconfig', '$LUMEN_SYSROOT/usr/share/pkgconfig']

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[built-in options]
c_args = ['--sysroot=$LUMEN_SYSROOT', '-O2']
cpp_args = ['--sysroot=$LUMEN_SYSROOT', '-O2']
c_link_args = ['--sysroot=$LUMEN_SYSROOT']
cpp_link_args = ['--sysroot=$LUMEN_SYSROOT']
EOF
}

target_autotools() {
  local name="$1"
  shift
  local src build
  src="$(prepare_source "$name")"
  build="$GRAPHICS_BUILD/build-$name"
  rm -rf "$build"
  mkdir -p "$build"

  lumen_step "Desktop graphics: building $name-$(pkg_version_graphics "$name")"

  case "$name" in
    xf86-video-fbdev|xf86-input-keyboard|xf86-input-mouse)
      (cd "$src" && autoreconf -fi)
      ;;
  esac

  (
    cd "$build"
    env \
      CC="$CC" CXX="$CXX" AR="$AR" AS="$AS" LD="$LD" RANLIB="$RANLIB" STRIP="$STRIP" \
      CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
      PKG_CONFIG=/usr/bin/pkg-config \
      PKG_CONFIG_SYSROOT_DIR="$LUMEN_SYSROOT" \
      PKG_CONFIG_LIBDIR="$LUMEN_SYSROOT/usr/lib/pkgconfig:$LUMEN_SYSROOT/usr/share/pkgconfig" \
      PKG_CONFIG_PATH= \
      PYTHON=python3 \
      ac_cv_func_malloc_0_nonnull=yes \
      ac_cv_func_realloc_0_nonnull=yes \
      "$src/configure" \
        --build="$BUILD_TRIPLET" \
        --host="$LUMEN_TARGET_TRIPLET" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --sysconfdir=/etc \
        --localstatedir=/var \
        "$@"
    make -j"$LUMEN_MAKE_JOBS"
    make DESTDIR="$LUMEN_STAGE_ROOT" install
  )
  graphics_sync_sysroot
  lumen_ok "Desktop graphics: $name installed"
}

target_meson() {
  local name="$1"
  shift
  local src build
  src="$(prepare_source "$name")"
  build="$GRAPHICS_BUILD/build-$name"
  rm -rf "$build"

  lumen_step "Desktop graphics: building $name-$(pkg_version_graphics "$name")"
  env \
    PKG_CONFIG_SYSROOT_DIR="$LUMEN_SYSROOT" \
    PKG_CONFIG_LIBDIR="$LUMEN_SYSROOT/usr/lib/pkgconfig:$LUMEN_SYSROOT/usr/share/pkgconfig" \
    PKG_CONFIG_PATH= \
    meson setup "$build" "$src" \
      --cross-file "$MESON_CROSS" \
      --prefix=/usr \
      --libdir=lib \
      --sysconfdir=/etc \
      --localstatedir=/var \
      --buildtype=release \
      --wrap-mode=nodownload \
      "$@"
  env \
    PKG_CONFIG_SYSROOT_DIR="$LUMEN_SYSROOT" \
    PKG_CONFIG_LIBDIR="$LUMEN_SYSROOT/usr/lib/pkgconfig:$LUMEN_SYSROOT/usr/share/pkgconfig" \
    PKG_CONFIG_PATH= \
    meson compile -C "$build" -j "$LUMEN_MAKE_JOBS"
  DESTDIR="$LUMEN_STAGE_ROOT" meson install -C "$build" --no-rebuild
  graphics_sync_sysroot
  lumen_ok "Desktop graphics: $name installed"
}

install_dejavu_fonts() {
  local src font_dst
  src="$(prepare_source dejavu-fonts)"
  font_dst="$LUMEN_STAGE_ROOT/usr/share/fonts/truetype/dejavu"
  mkdir -p "$font_dst"
  find "$src/ttf" -maxdepth 1 -type f -name '*.ttf' -exec cp -f {} "$font_dst/" \;
  if ! find "$font_dst" -maxdepth 1 -type f -name '*.ttf' -print -quit | grep -q .; then
    lumen_die "DejaVu fonts were not installed"
  fi
  lumen_ok "Desktop graphics: DejaVu fonts installed"
}

finalize_xorg_wrapper() {
  local wrapper real
  mkdir -p "$LUMEN_STAGE_ROOT/usr/bin" "$LUMEN_STAGE_ROOT/etc/X11"

  wrapper="$LUMEN_STAGE_ROOT/usr/lib/xorg/Xorg.wrap"
  real="$LUMEN_STAGE_ROOT/usr/lib/xorg/Xorg"
  if [[ -x "$wrapper" && -x "$real" ]]; then
    chmod 4755 "$wrapper"
    ln -sfn ../lib/xorg/Xorg.wrap "$LUMEN_STAGE_ROOT/usr/bin/Xorg"
    ln -sfn Xorg "$LUMEN_STAGE_ROOT/usr/bin/X"
  elif [[ -x "$LUMEN_STAGE_ROOT/usr/bin/Xorg" ]]; then
    ln -sfn Xorg "$LUMEN_STAGE_ROOT/usr/bin/X"
  else
    lumen_die "Xorg server was not installed at an expected path"
  fi

  cat > "$LUMEN_STAGE_ROOT/etc/X11/Xwrapper.config" <<'EOF'
allowed_users=console
needs_root_rights=yes
EOF
  chmod 0644 "$LUMEN_STAGE_ROOT/etc/X11/Xwrapper.config"
}

require_target_pkgconfig() {
  local package
  for package in "$@"; do
    if ! PKG_CONFIG_SYSROOT_DIR="$LUMEN_SYSROOT" \
      PKG_CONFIG_LIBDIR="$LUMEN_SYSROOT/usr/lib/pkgconfig:$LUMEN_SYSROOT/usr/share/pkgconfig" \
      pkg-config --exists "$package"; then
      lumen_die "Target pkg-config module missing after desktop build: $package"
    fi
  done
}

write_meson_cross_file

# Typography and basic protocol metadata.
target_autotools expat --without-xmlwf --without-docbook --without-examples --without-tests
target_autotools freetype --without-harfbuzz --without-brotli --without-bzip2 --without-png --with-zlib
target_meson fontconfig -Dtests=disabled -Ddoc=disabled -Dcache-dir=/var/cache/fontconfig
target_autotools xorgproto --enable-legacy
target_autotools xcb-proto
target_autotools libpthread-stubs
target_autotools libXau --disable-static --enable-shared
target_autotools libXdmcp --disable-static --enable-shared
target_autotools libxcb --disable-static --enable-shared --with-doxygen=no
target_autotools xtrans
target_autotools libX11 --disable-static --enable-shared --disable-malloc0returnsnull --disable-specs --without-perl

# X11 extension/client libraries used by Xorg and the ShreeOS desktop.
target_autotools libXext --disable-static --enable-shared
target_autotools libXfixes --disable-static --enable-shared
target_autotools libXrender --disable-static --enable-shared
target_autotools libXi --disable-static --enable-shared
target_autotools libXres --disable-static --enable-shared
target_autotools libXft --disable-static --enable-shared
target_autotools libXcursor --disable-static --enable-shared
target_autotools libXinerama --disable-static --enable-shared
target_autotools libXrandr --disable-static --enable-shared
target_autotools libXdamage --disable-static --enable-shared
target_autotools libXxf86vm --disable-static --enable-shared
target_autotools libICE --disable-static --enable-shared
target_autotools libSM --disable-static --enable-shared
target_autotools libXt --disable-static --enable-shared
target_autotools libXmu --disable-static --enable-shared
target_autotools libxkbfile --disable-static --enable-shared
target_meson libxcvt -Ddefault_library=shared
target_autotools libfontenc --disable-static --enable-shared
target_autotools libXfont2 --disable-static --enable-shared --disable-devel-docs

# Rendering, KMS metadata and a software OpenGL implementation.
target_meson pixman \
  -Dloongson-mmi=disabled \
  -Dvmx=disabled \
  -Dmips-dspr2=disabled \
  -Dopenmp=disabled \
  -Dgnuplot=false \
  -Dgtk=disabled \
  -Dlibpng=disabled \
  -Dtests=disabled
target_meson libpciaccess -Dzlib=enabled
target_meson libdrm \
  -Dcairo-tests=disabled \
  -Dman-pages=disabled \
  -Dintel=disabled \
  -Dradeon=disabled \
  -Damdgpu=disabled \
  -Dnouveau=disabled \
  -Dvmwgfx=disabled \
  -Domap=disabled \
  -Detnaviv=disabled \
  -Dexynos=disabled \
  -Dfreedreno=disabled \
  -Dtegra=disabled \
  -Dvc4=disabled \
  -Dudev=false \
  -Dvalgrind=disabled \
  -Dtests=false
target_meson mesa \
  -Dplatforms=x11 \
  -Dgallium-drivers=softpipe \
  -Dvulkan-drivers= \
  -Dllvm=disabled \
  -Dglx=xlib \
  -Dglx-direct=true \
  -Dopengl=true \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dvalgrind=disabled \
  -Dlibunwind=disabled \
  -Dlmsensors=disabled \
  -Dzstd=disabled \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgallium-xa=disabled \
  -Dvideo-codecs=all_free \
  -Dbuild-tests=false \
  -Dtools=

# Keyboard data and session authentication.
target_autotools xbitmaps
target_autotools xkbcomp --disable-static
target_meson xkeyboard-config
target_autotools xauth --disable-static
target_autotools xinit MCOOKIE=/usr/bin/mcookie

# Xorg server and deterministic fallback drivers. The server is intentionally
# built without udev/systemd/dbus so ShreeOS's own init + mdev stack is enough.
target_autotools xorg-server \
  --enable-xorg \
  --enable-libdrm \
  --enable-suid-wrapper \
  --libexecdir=/usr/lib/xorg \
  --disable-config-hal \
  --disable-config-udev \
  --disable-config-udev-kms \
  --disable-config-dbus \
  --without-systemd-daemon \
  --disable-systemd-logind \
  --disable-kdrive \
  --disable-xephyr \
  --disable-xvfb \
  --disable-xnest \
  --disable-unit-tests \
  --disable-dri \
  --disable-glx \
  --disable-dri2 \
  --disable-dri3 \
  --disable-glamor \
  --disable-composite \
  --disable-screensaver \
  --disable-libunwind \
  --disable-xvmc \
  --enable-record \
  --with-sha1=libcrypto \
  --with-fontrootdir=/usr/share/fonts/X11 \
  --with-xkb-bin-directory=/usr/bin \
  CFLAGS="-O2 -I$LUMEN_SYSROOT/usr/include/pixman-1"

target_autotools xf86-video-fbdev --disable-static --enable-shared
target_autotools xf86-input-keyboard --disable-static --enable-shared
target_autotools xf86-input-mouse --disable-static --enable-shared

install_dejavu_fonts
finalize_xorg_wrapper
graphics_sync_sysroot

require_target_pkgconfig \
  x11 xext xfixes xrender xi xft xinerama fontconfig freetype2 pixman-1 libdrm gl

required_files=(
  "$LUMEN_STAGE_ROOT/usr/bin/Xorg"
  "$LUMEN_STAGE_ROOT/usr/bin/X"
  "$LUMEN_STAGE_ROOT/usr/bin/startx"
  "$LUMEN_STAGE_ROOT/usr/bin/xinit"
  "$LUMEN_STAGE_ROOT/usr/bin/xauth"
  "$LUMEN_STAGE_ROOT/usr/lib/xorg/modules/drivers/fbdev_drv.so"
  "$LUMEN_STAGE_ROOT/usr/lib/xorg/modules/input/kbd_drv.so"
  "$LUMEN_STAGE_ROOT/usr/lib/xorg/modules/input/mouse_drv.so"
)
for file in "${required_files[@]}"; do
  [[ -e "$file" ]] || lumen_die "Desktop graphics output missing: ${file#"$LUMEN_STAGE_ROOT"}"
done

lumen_ok "Native ShreeOS X11 graphics stack is complete"
