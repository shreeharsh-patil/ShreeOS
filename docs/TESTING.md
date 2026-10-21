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

The authoritative pipeline for the release product is
`shreeos-release.yml`; the others are regression or experimental paths.

| Workflow | Trigger | Scope |
|----------|---------|-------|
| `shreeos-release.yml` | Push to `master`, `v*` tags, PRs, manual dispatch | The one release pipeline: static checks, ISO build, BIOS/UEFI boot, installer and performance gates, publish |
| `lint.yml` | Every push/PR | Shellcheck + structure |
| `audit.yml` | Push/PR touching audited paths | Repository and ISO audit reports |
| `toolchain.yml` | Push to `master` | Full toolchain build |
| `kernel.yml` | Push to `master` | Kernel against cached toolchain |
| `base-system.yml` | Push/PR touching the base system | Base userland build |
| `iso.yml` | Push to `master`, PR | Experimental source-built chain → ISO artifact |
| `unified-iso.yml` | Push/PR touching the unified image | Unified image build check |
| `debian-prototype.yml` | Push/PR touching the live-build tree | Console, XFCE and Plasma prototypes |
| `security.yml` | PR touching security paths | Security edition checks |
| `performance-baseline.yml` | Manual dispatch only | Records the untouched-build performance baseline |

## Writing Tests

- Smoke tests: add a `.sh` file to `tests/smoke/`; must exit 0 on success
- QEMU tests: use the helper in `tests/qemu/qemu-common.sh` for consistent QEMU invocation
- Unit tests: add to `pkgmanager/tests/` (lpm resolver, manifest), `init/tests/` (init parser) or `hardware/tests/` (shreed collectors) for logic-level tests
