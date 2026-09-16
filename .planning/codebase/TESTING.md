# ShreeOS Testing Guide

> Last updated: 2026-07-20
> Milestone 1 — repository scaffold. The test infrastructure is scaffolded
> and the first smoke tests are implemented. Full unit, integration, and
> QEMU boot test suites will be added as each milestone lands.

---

## 1. Testing Philosophy

ShreeOS follows a **test-every-milestone** policy: no milestone is considered
complete until its components have at least a basic test. Testing is never
deferred to the end. This is documented in:

- `CONTRIBUTING.md:13` — "At least one test under `tests/`"
- `docs/ROADMAP.md:3-4` — "Each milestone must have working, compiling/running
  code and at least a basic test"
- `docs/ARCHITECTURE.md:30-33` — "Every stage is independently buildable and
  testable"

### Goals

1. **Catch regressions early.** A change to the toolchain should not silently
   break the kernel build. Tests catch this before merging.
2. **Document expected behavior.** A test for the init system's PID 1 behavior
   is also a specification of that behavior.
3. **Enable safe refactoring.** With tests, we can rewrite components without
   fear of breaking the system.
4. **Trust the CI pipeline.** The GitHub Actions workflow should produce enough
   confidence that a passing pipeline means "ship it."

---

## 2. Test Hierarchy

Tests are organized in three tiers, roughly mirroring the standard test pyramid:

```
     /\
    /  \          Tier 3: QEMU boot tests  (slow, full-system)
   /    \
  /------\        Tier 2: Integration tests (component interaction)
 /--------\
/----------\      Tier 1: Unit + smoke tests (fast, no full builds)
```

### Tier 1: Unit + Smoke Tests (`tests/smoke/`)

**Scope:** Fast checks that need no full builds. Validate repository structure,
config file syntax, script validity, and individual function behavior.

**Location:** `tests/smoke/run-all.sh`

**Current tests (Milestone 1):**
- `bash -n build.conf` — config file is valid bash
- `bash -n scripts/common.sh` — shared helpers are valid bash
- `bash -c "source build.conf"` — config sources cleanly (no missing deps)
- `test -f "${d}/README.md"` for every top-level component — all
  15 component directories have READMEs
- `test -f LICENSE` — license file exists
- `test -f docs/ROADMAP.md` — roadmap exists
- `test -f docs/ARCHITECTURE.md` — architecture doc exists

**How to run:**
```bash
bash tests/smoke/run-all.sh
```

### Tier 2: Integration Tests (per-component `tests/` directories)

**Scope:** Verify that a component's build script produces the expected output,
that the cross-compiler can compile a static binary, that the init system
parses its config correctly, etc.

**Location:** Each component with a `tests/` subdirectory:

| Component       | Test Directory                 | Status |
|-----------------|--------------------------------|--------|
| `pkgmanager/`   | `pkgmanager/tests/`            | scaffolded, empty |
| `installer/`    | `installer/tests/`             | scaffolded, empty |

**Expected test types per component:**

- **toolchain:** Compile a "hello world" C program with the cross-compiler and
  verify it's a static `x86_64` ELF binary. Run `file` on it; check it returns
  exit 0 under QEMU user-mode.
- **kernel:** Verify `.config` has expected options set (`CONFIG_INITRAMFS_SOURCE`,
  `CONFIG_BLK_DEV_SD`, etc.). Check that `make` (or the build script) produces
  a `vmlinux` and `bzImage`.
- **init:** Unit tests for config parsing (service file format). Integration
  test: spawn the init under a minimal chroot and verify it reaches PID 1
  and spawns a getty.
- **pkgmanager:** Test package creation (`lpm-build`), install, and removal
  in a temporary root. Verify `.lpkg` format compliance.
- **installer:** Test partitioning logic, filesystem creation, and bootloader
  installation against a loopback disk image (in a VM or chroot with device
  mapper).
- **rootfs:** Verify the skeleton tree has required directories (`/bin`, `/sbin`,
  `/etc`, `/var`, `/proc`, `/sys`, `/dev`, `/tmp`, `/run`). Verify ownership
  and permissions.

### Tier 3: QEMU Boot Tests

**Scope:** Boot the full ISO under QEMU and verify the system reaches a login
prompt or a defined target. These are the slowest but most valuable tests.

**Location:** `tests/qemu/` (to be created)

**Expected approach:**
```bash
bash tests/qemu/boot-test.sh \
  --iso out/shreeos-0.1.0-amd64.iso \
  --timeout 60 \
  --expect "shreeos login:"
```

The test harness would:
1. Launch QEMU with the ISO (BIOS or UEFI).
2. Connect to the serial console.
3. Wait for an expected string (e.g., "shreeos login:").
4. If found within timeout, pass; if timeout or kernel panic, fail.

**Variants:**
- BIOS boot test
- UEFI boot test
- Install-to-disk-and-reboot test (uses a QEMU scratch disk image)

---

## 3. Test Framework & Runners

### 3.1 Shell Script Tests

The smoke test suite (`tests/smoke/run-all.sh`) uses a minimalist custom
framework defined inline:

```bash
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  [ok]   %s\n' "${desc}"
    pass=$((pass + 1))
  else
    printf '  [FAIL] %s\n' "${desc}"
    fail=$((fail + 1))
  fi
}
```

This pattern is intentionally simple — no external test framework dependency.
Larger shell test suites (e.g., for `toolchain/`) may adopt `shunit2` or a
similar lightweight framework if the number of tests grows beyond ~20.

### 3.2 C Unit Tests

C components (`init/`, `pkgmanager/`, `installer/`) will use a minimal C test
framework. Candidates to be evaluated when those milestones land:

- **Greatest Test Framework (greatest):** A single-header C test framework with
  no dependencies. Fits the "from-scratch" philosophy.
- **Unity:** Another small, portable C test framework.
- **Custom:** Given the small size of each component, a minimal custom test
  runner (a `main()` that calls test functions and tracks pass/fail) may be
  simplest.

The chosen framework's name and location will be documented in
`docs/design-decisions/` when the first C test is added.

### 3.3 QEMU Tests

QEMU tests are standalone shell scripts using `expect` or a simple
expectation-loop on the serial console output. No additional framework.

The `kernel/` and `iso-builder/` milestones will define a shared helper
(`tests/qemu/qemu-common.sh`) analogous to `scripts/common.sh` for:

- Launching QEMU with consistent flags
- Waiting for serial output with timeout
- Taking screenshots / dumping serial log on failure

---

## 4. Mocking and Stubbing

### 4.1 Shell Script Mocks

For shell scripts that call external commands (curl, tar, gcc, etc.), create
mock wrappers in a `tests/mocks/` directory:

```bash
# tests/mocks/curl — mock curl that returns a local file instead of fetching
#!/usr/bin/env bash
case "${*}" in
  *url-for-package-v1*)
    cat tests/fixtures/package-v1.tar.gz
    ;;
  *)
    echo "Unexpected curl call: $*" >&2
    exit 1
    ;;
esac
```

Prepend `tests/mocks` to `PATH` in test scripts:
```bash
PATH="${REPO_ROOT}/tests/mocks:${PATH}"
```

### 4.2 C Code Stubs

For C unit tests, stub out:

- **System calls** (`write`, `open`, `read`, `ioctl`) — wrap in a testable
  layer (e.g., `lumen_io_write` instead of raw `write(2)`) that can be
  replaced in test builds.
- **Kernel interfaces** (for `init/`) — abstract `/proc`, `/sys`, and device
  node access behind a thin veneer that can point to a test fixture directory.

The stubbing pattern: define a header with function pointers or weak symbols
that the test build overrides.

---

## 5. Fixtures

Test fixtures (sample config files, minimal ELF binaries, dummy initramfs
archives) live in `tests/fixtures/`:

```
tests/fixtures/
  hello.c                   # minimal "hello world" for toolchain test
  sample-service.conf       # sample init service definition
  sample-package.lpkg       # minimal valid .lpkg package
  kernel-config-minimal     # subset of kernel .config options for validation
```

Fixtures are version-controlled and never auto-generated.

---

## 6. Coverage

### 6.1 Shell Script Coverage

- No shell coverage tool is planned — the value proposition for shell scripts
  is low relative to the complexity of setting up coverage measurement.
- Instead, focus on edge-case coverage through functional tests (e.g., test
  what happens when `curl` fails, when a checksum mismatches, when a required
  command is missing).

### 6.2 C Code Coverage

When C code is added, evaluate `gcov` (built into GCC) for line and branch
coverage. Expected minimum coverage thresholds (once tests exist):

- `init/`: 80% line coverage
- `pkgmanager/`: 75% line coverage (more I/O paths, harder to mock)
- `installer/`: 70% line coverage (many syscall-heavy paths)

These thresholds are aspirational and will be adjusted as the codebase matures.

### 6.3 CI Integration

Coverage reports are generated in CI and uploaded as build artifacts. They are
not gating (no hard coverage minimum in CI), but developers are expected to
check coverage before merging substantial refactors.

---

## 7. Continuous Integration

The CI pipeline is defined in `.github/workflows/lint.yml`.

### Current CI Jobs

| Job              | Runs on        | What it checks                        |
|------------------|----------------|---------------------------------------|
| `shellcheck`     | ubuntu-latest  | shellcheck on all `.sh` files         |
| `structure-check`| ubuntu-latest  | README exists in every component dir  |

### Planned CI Pipeline (full)

When all milestones land, the CI will include:

```
Lint (shellcheck + bash -n)
  |
  +-- Toolchain build (smoke: compile hello.c)
  |     |
  |     +-- Kernel build (smoke: verify .config, produce bzImage)
  |           |
  |           +-- Rootfs assembly (verify skeleton, init binary)
  |                 |
  |                 +-- ISO assembly (verify hybrid ISO structure)
  |                       |
  |                       +-- QEMU boot test (BIOS + UEFI)
  |
  +-- Package manager tests (unit + integration)
  +-- Installer tests (unit + loopback disk)
  +-- Desktop build (verify X11 + WM start)
```

Each stage consumes the artifacts of the prior one. A failure at any stage
aborts the pipeline.

---

## 8. Running Tests Locally

### All smoke tests:
```bash
bash tests/smoke/run-all.sh
```

### Component-specific tests (once implemented):
```bash
# Toolchain: compile a test binary
cd toolchain && make test

# Init: unit tests
cd init && make test

# Package manager: unit + integration
cd pkgmanager && make test

# Full ISO boot test (requires completed build)
bash tests/qemu/boot-test.sh --iso out/shreeos-0.1.0-amd64.iso
```

### Test environment requirements:
- Ubuntu 22.04/24.04 (or same container as CI)
- `shellcheck`, `bash`, `git`, `make`, `curl`
- For QEMU tests: `qemu-system-x86_64`
- ~30 GB free disk for full build tests

See `CONTRIBUTING.md:22-24` for detailed host setup.

---

## 9. Adding New Tests

### Checklist

When contributing a new component or feature, include:

1. **At least one smoke test** in `tests/smoke/run-all.sh` (or a new script
   sourced by it) that validates the component exists, its config is valid,
   and its build script has valid syntax.
2. **At least one functional test** in the component's `tests/` directory
   that exercises the component's core function (compile a binary, parse a
   config, create a package).
3. **Update `tests/README.md`** if the test layout changes.

### Pull Request workflow

1. Run `bash tests/smoke/run-all.sh` — must pass.
2. Run `shellcheck` on all new/changed shell scripts — must pass cleanly.
3. If the PR touches C code, run the C component's test suite.
4. If the PR touches build logic, verify a clean build from scratch still
   passes the QEMU boot test (if applicable).

---

## 10. Future Test Infrastructure

Items deferred to later milestones (tracked in `docs/ROADMAP.md`):

- **QEMU boot test framework** (`tests/qemu/`) — Milestone 4 or 6
- **C unit test framework selection** — Milestone 2 (init) or 5 (pkgmanager)
- **Coverage reporting in CI** — Milestone 11
- **Regression test database** (historical CI results) — Post-v1.0
- **Performance benchmarks** (kernel boot time, package install speed) —
  Post-v1.0
