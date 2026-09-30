# Source information

This document records the source policy for ShreeOS build outputs. It does not
make the current prototype a published release or by itself satisfy source
distribution obligations for a future binary release.

## Experimental Debian Live prototype

The prototype uses Debian GNU/Linux 13 (Trixie), the `main` archive area, and
the dated Debian and Debian Security snapshots selected in
[`prototype/debian-live/versions.conf`](prototype/debian-live/versions.conf).
The build uses Debian `live-build`; its exact expected version is pinned in the
same file. The CI job installs the base image's packages from those snapshot
repositories, and the resulting installed system uses signed Debian Trixie
and security repositories for updates.

Each successful prototype build records:

- installed binary package names and versions in
  `out/shreeos-<version>-packages.txt`;
- the Debian suite, snapshot timestamp, `live-build` version and host tool
  versions in `out/shreeos-<version>-build-info.txt`;
- the ISO SHA-256 checksum in a sibling `.sha256` file.

The package copyright and license records are retained inside the live root
under `/usr/share/doc/<package>/copyright`, subject to verification against
the actual built image. The base image's package manifest is available at
`/live/filesystem.packages`. The Debian snapshot service retains source
packages corresponding to the selected binary snapshot. Before a public
release, CI/release automation must archive a machine-readable source-package
inventory and publish clear instructions and a durable location for obtaining
any corresponding source required by the applicable licenses.

To inspect and obtain Debian source packages from the configured archive,
enable a matching `deb-src` entry for the same suite/component and snapshot,
then use `apt-get source <source-package>` with the appropriate Debian
archive keyring. Use the recorded binary manifest to identify packages and
consult each package's copyright record for source-package name and license
details. Do not treat a current moving repository as a substitute for the
source corresponding to a pinned binary build.

## Existing source-built path

The legacy cross-build pins source versions and checksums in repository build
configuration. Those pins describe candidate build inputs, not necessarily the
contents of a completed ISO. Build logs and a generated image inventory are
needed to associate exact source packages with shipped binaries. GPL and other
source obligations must be satisfied for the versions actually redistributed.

## ShreeOS source

ShreeOS-authored material is generally licensed under the repository's MIT
License unless otherwise stated. Source code and build scripts are available
in this repository. Third-party packages, fonts, firmware, artwork and other
assets retain their own licenses and notices; see
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).
