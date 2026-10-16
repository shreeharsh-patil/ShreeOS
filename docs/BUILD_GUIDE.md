# Build guide

## Build the ShreeOS desktop image

`make shreeos` is the canonical build for the ShreeOS operating system. It
targets Debian 13 (Trixie) on amd64, must run as root on a Debian 13 Linux host
or disposable VM, and produces exactly one primary artifact:

```
out/shreeos(VERSION).iso
```

`VERSION` is the repository-root `VERSION` file. That file is the single
authoritative version source for the whole project: `build.conf`,
`prototype/debian-live/versions.conf`, the generated `/etc/os-release`, the ISO
filename and the release tag all derive from it. `scripts/verify-version.sh`
enforces that, and the build fails rather than ship a mismatched image.

Native Windows is not a supported build host. WSL works only with a functioning
Linux distribution and root filesystem support.

The exact Debian snapshot and `live-build` version are recorded in
[`../prototype/debian-live/versions.conf`](../prototype/debian-live/versions.conf).
The authoritative pipeline that installs the supporting tools is
[`../.github/workflows/shreeos-release.yml`](../.github/workflows/shreeos-release.yml).

```sh
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
git switch master

make shreeos-check     # validate dependencies, live-build pin and version contract
make shreeos           # build out/shreeos(VERSION).iso and its metadata
make shreeos-verify    # re-verify an existing image without rebuilding
```

Useful build knobs:

| Variable | Effect |
|---|---|
| `SHREEOS_FIRMWARE=standard` | Default for the unified image: main + non-free-firmware |
| `SHREEOS_FIRMWARE=free` | Free-firmware-only image |
| `SHREEOS_TOOLSETS=developer,security,creative` | Add optional software bundles |

Build output is written to ignored `build/` and `out/` directories. The script
deletes only this image's own prior outputs and its dedicated
`build/debian-live-prototype` scratch directory; it refuses to delete anything
outside the output directory. It also refuses to reuse a cached artifact unless
that artifact re-verifies against its recorded checksum.

`tests/prototype/test-iso.sh` extracts the SquashFS, checks the package manifest
and required assets, then boots the image in BIOS and UEFI QEMU configurations
and rejects blank or empty desktop screenshots. Physical hardware acceptance and
interactive installer acceptance are separate, still-open gates.

### Experimental profiles

The console (`base`) and XFCE (`desktop`) Debian Live images remain buildable for
research and regression coverage:

```sh
SHREEOS_LIVE_PROFILE=base bash scripts/build-debian-prototype.sh
SHREEOS_LIVE_PROFILE=desktop bash scripts/build-debian-prototype.sh
```

They emit suffixed throwaway names such as `shreeos-VERSION-desktop-amd64.iso`
and are never published. The unified Plasma image is the ShreeOS operating
system; these are not alternative products.

## Existing source-built path

The repository also contains the earlier cross-build pipeline. Its published
documentation and product claims are being audited and should not be used as
evidence that the complete desktop, installer or installed-system experience
is functional. See [`IMPLEMENTATION-PLAN.md`](IMPLEMENTATION-PLAN.md) for the
current audit findings and migration gates. Avoid running its broad cleanup or
release targets without first inspecting their effects and the generated
artifacts.

## Reproducibility and licensing

The prototype pins the package-install snapshot, but the complete build has
not yet been executed in this Windows workspace. CI is the first Linux
end-to-end validation. Preserve the emitted package manifest, build metadata,
checksums and package copyright records for any future redistribution. Source
and license handling is described in
[`../SOURCE_INFORMATION.md`](../SOURCE_INFORMATION.md) and
[`../THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).
