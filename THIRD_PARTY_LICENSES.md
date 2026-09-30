# Third-party licenses

ShreeOS-authored code is generally available under the MIT License in
[`LICENSE`](LICENSE), unless a file states otherwise. This does not change the
license of any third-party component included in a build.

## Existing source-built path

The source-built path downloads and builds pinned upstream components listed
in `base-system/packages.list`, the toolchain configuration, kernel
configuration, and other build manifests. Their licenses vary by component
and version; this file is not a complete inventory of a generated ISO. Do not
infer an image's contents from source pins alone. The generated package and
root filesystem audits are needed to identify what was actually installed.

## Debian Live prototype

The experimental prototype currently selects Debian's `main` archive area,
which contains free software under a range of licenses. It does not include
the `contrib` or `non-free` archive areas or request Debian's non-free
firmware. The actual installed package names and versions are recorded in
`out/shreeos-<version>-packages.txt` and in the ISO's
`/live/filesystem.packages`. Debian packages retain upstream copyright and
license information in their installed documentation, usually under
`/usr/share/doc/<package>/copyright`.

The base includes or depends on projects such as Debian Live, Linux, systemd,
APT/dpkg, GRUB, NetworkManager and GNU utilities. Their exact versions and
applicable license texts must be read from the corresponding package and
upstream source; a short project-level list cannot replace those notices.

The optional desktop profile adds the Debian `firmware-linux-free` package,
which Debian describes as firmware compliant with the Debian Free Software
Guidelines. It deliberately does not enable `non-free-firmware` or bundle
device blobs whose redistribution terms have not been reviewed. This is a
limited set and does not imply broad device support. See the
[Debian package record](https://packages.debian.org/trixie/firmware-linux-free)
and preserve its installed copyright record with the image.

## Redistribution checklist

Before publishing an image:

1. Preserve the copyright and license files installed by each package.
2. Archive the exact package manifest and source/build metadata with the
   release.
3. Check each package's Debian copyright record and upstream license for the
   exact released version, including firmware and artwork.
4. Make corresponding source available when the license requires it, and
   record the source archive location and retention period.
5. Include notices and source instructions with the image or release in a
   way that satisfies the applicable license.

No image is declared license-complete solely because it uses open-source
software. Firmware, codecs, fonts, wallpapers, icons, trademarks and other
assets require their own redistribution review.
