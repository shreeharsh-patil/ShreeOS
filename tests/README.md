# Tests

Test suites for ShreeOS across three layers.

## Layout

```
tests/
├── smoke/        # Fast structural checks (every commit)
│   ├── run-all.sh            # Orchestrator
│   ├── test-toolchain.sh     # Toolchain verification
│   └── test-base-system.sh   # Base system checks
├── qemu/         # Full boot tests (post-build)
│   ├── qemu-common.sh                 # Shared helpers
│   ├── boot-kernel-only.sh            # Kernel + initramfs
│   ├── boot-full-rootfs.sh            # Full rootfs
│   ├── boot-iso-bios.sh               # ISO (BIOS)
│   ├── boot-iso-uefi.sh               # ISO (UEFI)
│   └── boot-installed-disk.sh         # Installed disk
├── unit/         # Logic tests (empty — future)
└── README.md
```

## Running

```bash
bash tests/smoke/run-all.sh           # all smoke tests
bash tests/qemu/boot-kernel-only.sh   # QEMU boot test
```
