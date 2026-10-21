# Tests

Test suites for ShreeOS. Every suite is plain `bash` or `python3` and is
self-contained: it builds its own fixtures in a temporary directory and cleans
up after itself, so a suite can be run directly from a checkout.

## Layout

```
tests/
├── audit/        # Distribution audit tool self-tests
│   └── test-shreeos-audit.py
├── auth/         # Authentication and credential tests
│   └── test-auth.sh
├── base-system/  # Base userland contract and rootfs hygiene
│   ├── test-base-system-contract.sh
│   └── test-rootfs-pruning.sh
├── desktop/      # Desktop shell and control-panel wiring
│   └── test-shreed-ui.sh
├── installer/    # Disk installer safety and recovery
│   ├── test-installer-validation.sh
│   └── test-recovery-initramfs.sh
├── pkgmanager/   # lpm package manager transactions
│   └── test-lpm-transactions.sh
├── prototype/    # Debian Live image configuration and boot contracts
│   ├── test-config.sh             # Image configuration contract
│   ├── test-design-tokens.py      # Design token mirrors agree
│   ├── test-iso.sh                # BIOS/UEFI boot and desktop capture
│   ├── test-iso-squashfs.sh       # Image payload and package manifest
│   ├── test-installer-payload.sh  # Installer payload inside the image
│   ├── test-native-tools-package.sh
│   ├── test-performance-config.py
│   ├── test-performance-report.sh
│   ├── test-performance-targets.sh
│   └── test-*-config.py, test-*.py
├── qemu/         # Full boot and install tests (post-build)
│   ├── qemu-common.sh                 # Shared helpers
│   ├── boot-kernel-only.sh            # Kernel + initramfs
│   ├── boot-full-rootfs.sh            # Full rootfs
│   ├── boot-iso-bios.sh               # ISO (BIOS)
│   ├── boot-iso-uefi.sh               # ISO (UEFI)
│   ├── boot-installed-disk.sh         # Installed disk
│   ├── test-e2e-install-and-boot.sh
│   └── run-all-qemu-tests.sh          # Orchestrator
├── release/      # Release contract, artefact and provenance tests
│   ├── test-version-contract.sh
│   ├── test-release-asset-split.sh
│   ├── test-unified-workflow-triggers.py
│   ├── test-unified-artifact-cache.py
│   ├── test-install-acceptance-artifact.py
│   ├── test-capture-native-package-evidence.py
│   └── test-performance-*.py
├── security/     # Security edition and system security audits
│   ├── test-security.sh
│   └── test-security-edition.sh
├── smoke/        # Fast structural checks (every commit)
│   ├── run-all.sh            # Orchestrator
│   ├── test-build-orchestration.sh
│   ├── test-verify-stage.sh
│   ├── test-rootfs-reliability.sh
│   ├── test-toolchain.sh
│   ├── test-base-system.sh
│   └── test-desktop-suite.sh
├── unified/      # Unified image integration boundaries
│   ├── test-install-boundaries.sh
│   ├── test-iso-contents.sh
│   └── test-native-package.sh
└── README.md
```

## Running

The aggregate targets in the repository-root `Makefile` are the supported
entry points:

```bash
make test-all             # all automated test suites
make test-prototype-config # the static configuration gate the release pipeline runs
make test-smoke           # desktop & system smoke suite
make test-qemu            # automated QEMU ISO & installed disk tests
```

Individual suites can also be run directly:

```bash
bash tests/smoke/run-all.sh            # all smoke tests
bash tests/qemu/boot-iso-uefi.sh        # one QEMU boot test
python3 tests/release/test-version-contract.sh
python3 tests/prototype/test-design-tokens.py
```

Several suites need Linux-only tooling (`dpkg-deb`, `cpio`, `qemu`,
`xorriso`, `make`, `live-build`) or a previously built image. They exit with
status 2 and an explicit "missing dependency" message when a prerequisite is
absent, rather than reporting a false pass.
