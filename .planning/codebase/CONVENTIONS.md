# ShreeOS Code Conventions

> Last updated: 2026-07-20
> Milestone 1 — repository scaffold. Conventions documented here are forward-looking,
> capturing the patterns established so far and the expectations for all future code.

---

## 1. Repository Layout

Every top-level component follows a standard structure documented in `README.md`,
`README.md` at the root:

```
toolchain/          # Cross-compilation toolchain build scripts
  README.md
  scripts/          # bash build scripts (one per stage)
  sources.list      # pinned upstream URLs + checksums (future)
kernel/
  README.md
  scripts/
  configs/          # kernel .config files
rootfs/
  README.md
  scripts/
  skeleton/         # minimal root filesystem tree
init/
  README.md
  src/              # C source for the custom init (lumen-init)
  services/         # service definitions / config
bootloader/
  README.md
  grub/             # GRUB config templates
  scripts/
pkgmanager/
  README.md
  src/              # C source for lpm
  tests/            # unit / integration tests for lpm
  spec/             # .lpkg package format specification
repo-tools/
  README.md
  scripts/
installer/
  README.md
  src/              # C source for the guided installer
  tests/
iso-builder/
  README.md
  scripts/
desktop/
  README.md
  wm/               # window manager source
  configs/          # WM / DE config files
branding/
  README.md
  logo/
  theme/
  wallpapers/
update/
  README.md
  scripts/
tests/              # cross-component smoke / integration / QEMU tests
  README.md
  smoke/
.github/workflows/  # CI pipelines
docs/               # architecture, roadmap, design decisions
  design-decisions/
scripts/            # shared shell helpers (common.sh)
```

**Rule:** Every component MUST have a `README.md`. This is enforced in CI via
`.github/workflows/lint.yml:34-41`.

---

## 2. Shell (Bash) Conventions

### 2.1 Shebang and Strict Mode

Every shell script begins with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e` — exit on error
- `set -u` — treat unset variables as an error
- `set -o pipefail` — propagate failure through pipes

Exceptions are documented inline (e.g., a test that intentionally tests a failing
command).

### 2.2 Sourcing Bootstrap

Every component script sources the shared config and helpers at the top:

```bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/build.conf"
source "${REPO_ROOT}/scripts/common.sh"
```

The `../..` depth varies by location. For a script at `toolchain/scripts/foo.sh`,
the depth is `..` (to `toolchain/`) then `..` again (to repo root).

### 2.3 Logging Functions

Use the helpers from `scripts/common.sh:11-14` rather than raw `echo` or `printf`:

| Function       | Output   | Purpose                       |
|----------------|----------|-------------------------------|
| `lumen_log`    | stdout   | Informational step messages   |
| `lumen_ok`     | stdout   | Success confirmation          |
| `lumen_warn`   | stderr   | Non-fatal warnings            |
| `lumen_die`    | stderr   | Fatal error + `exit 1`        |

Example:
```bash
lumen_log "Configuring kernel ..."
lumen_ok "Kernel configured"
lumen_warn "Missing optional feature: FOO"
lumen_die "Kernel source not found at ${KERNEL_SRC}"
```

### 2.4 Function Naming

All public shell functions use the `lumen_` prefix to avoid collisions with
system commands or other scripts:

- `lumen_fetch` — download and verify (in `common.sh`)
- `lumen_step` — log a labeled build step (in `common.sh`)
- `lumen_require_cmd` — verify required host tools (in `common.sh`)
- `lumen_require_dir` — ensure directory exists (in `build.conf`)

Component-specific functions should not need a prefix in their own script (they
are scoped), but MUST use `local` for all variables.

### 2.5 Variable Discipline

- All function-local variables MUST be declared `local`.
- All variables from `build.conf` are exported as uppercase with the `LUMEN_`
  or `DISTRO_`/`VER_` prefix: `$LUMEN_ARCH`, `$LUMEN_TOOLS`, `$DISTRO_NAME`,
  `$VER_BINUTILS`.
- No script may hardcode a version, path, architecture, or distro name. Read
  from `build.conf` at `build.conf:1-39`.
- `build.conf` uses `export` so sub-scripts and child processes inherit values.

### 2.6 Error Handling

- Fail fast with `lumen_die` and a descriptive message. Never let a script
  silently continue after an unexpected state.
- Use `lumen_require_cmd` to validate host dependencies before starting work:
  ```bash
  lumen_require_cmd curl sha256sum tar gcc make
  ```
- Every download MUST be followed by a checksum verification (see
  `scripts/common.sh:19-34`). The pattern is:
  ```bash
  lumen_fetch "${url}" "${dest}" "${expected_sha256}"
  ```
- Never fetch "latest". Every upstream component is pinned to an exact version
  in `build.conf` and verified by checksum.

### 2.7 Quoting

- Always double-quote variable expansions: `"${var}"` not `${var}`.
- Use `@` rather than `*` when expanding arrays: `"${arr[@]}"`.
- Quote arguments to `[[ ... ]]` comparisons: `[[ -f "${file}" ]]`.

### 2.8 File Naming

- Executable scripts use `.sh` extension.
- Config files like `build.conf` use `.conf` extension.
- Kernel configs use `.config` extension.
- All scripts are `chmod +x` in the repository.
- Hyphens separate words in filenames: `build-kernel.sh`, `run-all.sh`.
- No spaces in filenames anywhere in the repo.

### 2.9 Shellcheck Compliance

CI runs `shellcheck -x` on every `.sh` file (excluding `build/`). All scripts
MUST pass shellcheck cleanly before commit. Run locally:

```bash
shellcheck -x path/to/script.sh
```

See `.github/workflows/lint.yml:18-20`.

### 2.10 Syntax Validation

CI also runs `bash -n` on key files (`build.conf`, `scripts/common.sh`, and
every script). Run locally:

```bash
bash -n script.sh
```

---

## 3. C Source Conventions

### 3.1 Language Standard

C code targets C11 (the GNU dialect, `-std=gnu11`) to use GCC extensions
(`__attribute__`, inline assembly) when needed while staying close to the
standard. This is the baseline for all components planned in C: `init/`,
`pkgmanager/`, `installer/`.

### 3.2 Compilation

All C code is cross-compiled with the `x86_64-shreeos-linux-gnu-` toolchain
produced by `toolchain/`. Host compilation (for tools that run on the build
machine) uses the native GCC with no prefix.

Expected compiler flags (embedded in makefiles or build scripts):

```makefile
CC      = ${LUMEN_TARGET_TRIPLET}-gcc
CFLAGS  = -std=gnu11 -Wall -Wextra -Wpedantic -O2 -D_FORTIFY_SOURCE=2
LDFLAGS = -static-pie
```

### 3.3 Naming

- Functions: `snake_case` — `lumen_init_main`, `pkg_install`.
- Types: `snake_case_t` — `lpm_package_t`, `init_service_t`.
- Macros and constants: `UPPER_SNAKE_CASE` — `MAX_SERVICES`, `LPM_VERSION`.
- File names: hyphen-separated, matching the component — `lumen-init.c`,
  `pkg-install.c`.
- Header guards use the full path pattern: `LUMEN_INIT_SERVICE_H`.

### 3.4 Error Handling

- Return negative `errno`-style values from functions: `return -ENOMEM`.
- Use `enum lumen_error` for domain-specific errors, falling back to errno for
  system calls.
- Check every syscall and libc function that can fail.
- Log errors to stderr via `fprintf(stderr, ...)` or a component-specific
  logging macro. The init system should also log to the kernel ring buffer
  via `kmsg` or `syslog`.

### 3.5 Memory Management

- Favor stack allocation for small, fixed-size buffers.
- Heap allocations use `calloc` (zeroed) or `malloc`; MUST check for NULL.
- Every `malloc`/`calloc`/`strdup` MUST have a matching `free`.
- Use `__attribute__((cleanup))` sparingly — prefer explicit cleanup labels
  (`goto cleanup` pattern) for readability.
- No variable-length arrays (VLAs) in production code.

---

## 4. Makefile Conventions

Each component that compiles anything provides a `Makefile` or is driven by a
build script that wraps `make`. Makefiles follow these patterns:

- `CC`, `CFLAGS`, `LDFLAGS` are overridable by the environment (so
  `build.conf` and the toolchain prefix can inject cross-compilation flags).
- Targets: `all`, `clean`, `distclean`, `install` (with `DESTDIR` support).
- No recursive make invocations unless unavoidable; prefer including sub-makefiles.

---

## 5. Configuration

### 5.1 Single Source of Truth

`build.conf` at `build.conf` is the **only** place where the following are defined:

- `DISTRO_NAME`, `DISTRO_CODENAME`, `DISTRO_VERSION`, `DISTRO_ID`
- `LUMEN_ARCH`, `LUMEN_TARGET_TRIPLET`
- `LUMEN_BUILD_DIR`, `LUMEN_TOOLS`, `LUMEN_SYSROOT`, `LUMEN_STAGE_ROOT`,
  `LUMEN_SOURCES`, `LUMEN_OUT`
- `VER_BINUTILS`, `VER_GCC`, `VER_GLIBC`, `VER_LINUX_KERNEL` (and later,
  coreutils, bash, etc.)
- `LUMEN_MAKE_JOBS`

Scripts never repeat these values. Changing the target architecture or a
component version is a single-line change in `build.conf`.

### 5.2 Build Artifact Hygiene

Build artifacts and downloaded sources live under `build/` and `out/`, both
gitignored at `.gitignore:2-3`. Removing these directories and re-running a
script must produce identical results.

---

## 6. Documentation

- Every component directory has a `README.md` explaining its purpose, how to
  build/test it standalone, and what it produces.
- `docs/ARCHITECTURE.md` describes the overall build pipeline and data flow
  between stages.
- `docs/ROADMAP.md` tracks milestone progress.
- `docs/design-decisions/` contains rationale for major technology choices
  (libc, init, package format, etc.), one file per decision.
- Inline code comments explain *why*, not *what*. The code itself documents
  what it does.

---

## 7. Git Workflow

### 7.1 Branching

- One milestone or feature per branch and PR.
- The `main` branch always represents the latest completed milestone.
- Branches are named after the milestone: `milestone-2-toolchain`,
  `milestone-3-base-system`.

### 7.2 Commit Messages

Pattern: `<component>: <short description in imperative mood>`

Examples from `CHANGELOG.md`:
```
toolchain: add pass-1 binutils build script
kernel: add build-kernel.sh with default x86_64 config
```

Messages should describe *what stage* and *what changed*. The body can expand
on *why* if the change is non-obvious.

### 7.3 Pre-Commit Checks

Before committing, run:
1. `bash -n` on all new/modified scripts
2. `shellcheck` on all non-trivial scripts
3. `bash tests/smoke/run-all.sh` to pass the smoke test suite

CI enforces these checks on every push via `.github/workflows/lint.yml`.

---

## 8. File Permissions

- Shell scripts (`*.sh`) are executable (`chmod +x`).
- Configuration files (`*.conf`, `*.config`) are not executable.
- Makefiles are not executable (run via `make`).

---

## 9. Third-Party Sources

- Every upstream component (binutils, GCC, glibc, Linux kernel, busybox, etc.)
  is pinned to an exact version, with a checksum recorded alongside its URL.
- Sources lists live per-component (e.g., `toolchain/sources.list`,
  `kernel/sources.list`).
- The `lumen_fetch` function in `scripts/common.sh:19-34` enforces checksum
  verification. A failed checksum is a fatal error.
- Patches (if any) live in a `patches/` subdirectory within the component and
  are applied by name in order.
