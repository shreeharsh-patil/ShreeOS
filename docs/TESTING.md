# Testing ShreeOS

## Test Pyramid

```
     ╱╲
    ╱ QEMU ╲        ← Full boot tests (slow, minutes)
   ╱  boot   ╲
  ╱───────────╲
 ╱   Smoke     ╲     ← Structural checks (fast, seconds)
 ╱───────────────╲
╱     Shellcheck   ╲  ← Syntax + lint (fastest, seconds)
╱───────────────────╲
```

## Layer 1: Lint (every commit)

```bash
shellcheck -x scripts/*.sh toolchain/scripts/*.sh
bash -n build.conf
bash -n scripts/common.sh
```

Automated in `.github/workflows/lint.yml` on every push and PR.

## Layer 2: Smoke Tests (every build)

```bash
bash tests/smoke/run-all.sh
```

Checks: directory structure, README presence, config file syntax. Fast (seconds).

## Layer 3: QEMU Boot Tests (post-build)

All require built artifacts. Run in order:

```bash
# 1. Kernel + initramfs (fastest boot)
bash tests/qemu/boot-kernel-only.sh

# 2. Full rootfs (includes init, base system)
bash tests/qemu/boot-full-rootfs.sh

# 3. ISO (BIOS)
bash tests/qemu/boot-iso-bios.sh

# 4. ISO (UEFI) — requires ovmf package
bash tests/qemu/boot-iso-uefi.sh

# 5. Installed disk (requires installer)
bash tests/qemu/boot-installed-disk.sh /path/to/disk.img
```

## CI Pipeline

| Workflow | Trigger | Scope |
|----------|---------|-------|
| `lint.yml` | Every push/PR | Shellcheck + structure |
| `toolchain.yml` | Push to main | Full toolchain build |
| `kernel.yml` | Push to main | Kernel against cached toolchain |
| `iso.yml` | Push to main, tags | Full chain → ISO artifact |
| `release.yml` | v* tags | GitHub Release with ISO |

## Writing Tests

- Smoke tests: add a `.sh` file to `tests/smoke/`; must exit 0 on success
- QEMU tests: use the helper in `tests/qemu/qemu-common.sh` for consistent QEMU invocation
- Unit tests: add to `tests/unit/` for logic-level tests (init parser, lpm resolver)
