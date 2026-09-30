# Build guide

## Experimental Debian Live prototype

The current recommended path for evaluating the proposed package-managed
base is the console-only Debian Live prototype. It targets Debian 13 (Trixie)
on amd64 and must be built as root on a Debian 13 Linux host or disposable VM.
Native Windows is not supported. WSL may work only with a functioning Linux
distribution and root filesystem support.

The exact Debian snapshot and `live-build` version are recorded in
[`../prototype/debian-live/versions.conf`](../prototype/debian-live/versions.conf).
CI installs the supporting tools listed in
[`../.github/workflows/debian-prototype.yml`](../.github/workflows/debian-prototype.yml).

```sh
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
git switch master
make test-prototype-config
make prototype-debian
make test-prototype ISO=out/shreeos-0.3.0-prototype-amd64.iso
```

Build output is written to ignored `build/` and `out/` directories. The build
script deletes only its dedicated `build/debian-live-prototype` scratch
directory. The ISO validation extracts the SquashFS and checks the package
manifest, then boots the image in BIOS and UEFI QEMU configurations. It does
not yet test desktop login, physical hardware, graphical installation or an
installed system.

The matching GitHub Actions workflow runs the build and boot checks in a
Debian Trixie container for pushes to `master`, pull requests targeting
`master`, or manual dispatch. It uploads a temporary CI artifact with the ISO,
checksum, package manifest and build metadata. This is not a release pipeline
and the artifact is not a supported distribution download.

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
