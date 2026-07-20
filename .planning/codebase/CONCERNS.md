# Concerns & Technical Debt — ShreeOS

Generated: 2026-07-20
Commit: `1564a4c` (single commit, Milestone 1 scaffold only)

---

## 1. Critical: 11 of 12 Milestones Are Purely Planned

Only **Milestone 1 (Repository Scaffold)** is marked `✅ done`. Milestones 2–12
are all `⏳ next` or `planned` in `docs/ROADMAP.md:6-19`. The IMplementation
Plan (`IMPLEMENTATION_PLAN.md`) is well-written but aspirational — zero build
scripts, zero source tarballs, zero kernel configs, zero line of C code exist
yet. The entire "build a Linux distro" problem remains unsolved.

**Risk:** This is a 95% documentation project today. Turning it into a working
OS requires solving the hardest problems in the Linux-from-scratch space
(toolchain bootstrap, glibc portability, kernel config alidation) without a
single line of executable code in the repo.

---

## 2. 15+ Empty Component Directories

Every component directory under the root contains nothing but a `README.md`
stub and empty subdirectories:

| Directory | Empty subdirectories |
|---|---|
| `toolchain/scripts/` | No build scripts — the LFS two-pass bootstrap is unwritten |
| `kernel/scripts/` | No build script; `kernel/configs/` has zero `.config` files |
| `rootfs/scripts/` | No assembly script; `rootfs/skeleton/` has no files |
| `init/src/` | No `init.c`; `init/services/` has zero service definitions |
| `bootloader/grub/` | No `grub.cfg.template`; `bootloader/scripts/` empty |
| `iso-builder/scripts/` | No `build-iso.sh` |
| `pkgmanager/src/` | No C source; `pkgmanager/spec/` has no format spec; `pkgmanager/tests/` empty |
| `installer/src/` | No source; `installer/tests/` empty |
| `desktop/wm/` | No WM source; `desktop/configs/` empty |
| `branding/logo/` | No logo files; `branding/theme/` empty; `branding/wallpapers/` empty |
| `base-system/scripts/` | No package build scripts |
| `repo-tools/scripts/` | No repo tooling |
| `update/scripts/` | No update scripts |
| `tests/qemu/` | No QEMU boot tests; `tests/unit/` empty |
| `docs/design-decisions/` | Zero design-decision records |

The component `README.md` stubs are all identical templates with `_(populated as this milestone is implemented)_`. Nothing has been populated.

---

## 3. Critical Version Variables Unset

`build.conf:28-31` declares four version variables but leaves them empty:

```bash
export VER_BINUTILS=""
export VER_GCC=""
export VER_GLIBC=""
export VER_LINUX_KERNEL=""
```

Every downstream script is expected to rely on these existing, but they carry
empty strings. The `lumen_fetch` function in `scripts/common.sh` would
download an empty URL if any script naively interpolates `VER_BINUTILS` into a
download URL. This is a latent runtime failure waiting to happen.

Additionally, no `toolchain/sources.list` or `base-system/packages.list` file
exists to pin upstream source checksums — despite `ARCHITECTURE.md:35-36`
explicitly stating they do.

---

## 4. Security: TOCTOU Race in `lumen_fetch`

`scripts/common.sh:19-34` — the checksum-based download function:

1. Checks if `${dest}` exists — if so, skips the download entirely.
2. Downloads to `${dest}.part`, then `mv`s to `${dest}`.
3. Computes and verifies the sha256 of `${dest}` **after** the mv.

**Problems:**
- **Race:** If the script is killed between the `mv` and the checksum check,
  a subsequent run finds `${dest}` exists (step 1) and skips the download,
  but never re-verifies the checksum. A truncated/corrupt file is silently
  accepted.
- **Integrity gap:** The "already downloaded" fast-path at line 21-22 bypasses
  checksum verification entirely. If the file on disk was corrupted by any
  means (bit rot, accidental write, previous partial `mv`), the corruption
  goes undetected.
- **No timeout on curl:** The `curl` call has `--retry 3` but no `--max-time`
  or `--connect-timeout`, so a hanging download can stall the build
  indefinitely.

**Fix:** Always verify the checksum, even when the file already exists.

---

## 5. Security: No Input Validation in `lumen_die`

`scripts/common.sh:14` — `lumen_die` prints and exits 1. If a malicious or
unexpected string flows into its argument (e.g., from a tainted URL or user
input), it could produce confusing terminal output (escape sequence injection
in the terminal). The script functions that call `lumen_die` with user-facing
data paths should sanitize.

---

## 6. Fragile: `build.conf` Executes at Source Time

`build.conf:17` and `build.conf:34` execute commands during `source`:

```bash
export LUMEN_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
...
export LUMEN_MAKE_JOBS="$(nproc 2>/dev/null || echo 4)"
```

- `LUMEN_ROOT_DIR` uses `${BASH_SOURCE[0]:-$0}` which behaves differently
  under `sh` vs `bash`. If a script sources `build.conf` without a proper
  Bash shebang/environment, `$0` may resolve incorrectly.
- `nproc` is not available on macOS or some minimal Linux environments. The
  fallback of 4 is silent and may oversubscribe the host.

---

## 7. Missing Error-Handling in `scripts/common.sh`

- **`lumen_require_dir`** (`build.conf:37-39`) calls `mkdir -p` but never
  checks the exit code. If the directory cannot be created (permissions, disk
  full, read-only filesystem), the script continues blindly and fails later
  with a confusing error.
- **`lumen_require_cmd`** (`scripts/common.sh:42-49`) checks for commands but
  only prints which are missing. It doesn't suggest install commands or check
  minimum versions.
- **`lumen_fetch`** passes `-f` to curl (fail on HTTP error) but doesn't
  validate the HTTP response code explicitly for redirects to error pages that
  return 200 with garbage content.

---

## 8. No Makefiles, Contradicting README Promises

Every component README documents a build workflow like:

```bash
# cd toolchain && make
```

But there are **zero Makefiles** anywhere in the repository. The root
`IMPLEMENTATION_PLAN.md:315-318` says a top-level `Makefile` lands in
Phase 9 (Milestone 10), but the individual component READMEs all claim
`make` works today. A user who clones the repo and follows the README will
immediately hit `make: *** No targets.  No makefile.  Stop.`.

---

## 9. CI Pipeline Is Minimal

`.github/workflows/lint.yml:1-42` is the only CI workflow. It runs only:

- `shellcheck` on `.sh` files
- `bash -n` on `build.conf` and `common.sh`
- A README existence check

There are no CI workflows for:
- Building the toolchain (`toolchain.yml`)
- Building the kernel (`kernel.yml`)
- Building the ISO (`iso.yml`)
- Running tests beyond the lint level
- Publishing releases (`release.yml`)

The `IMPLEMENTATION_PLAN.md` acknowledges these are planned for Phase 10, but
without CI, there is no automated quality gate at all.

---

## 10. Missing Key Documentation

- **`docs/BUILD_GUIDE.md`** is referenced from `README.md:53-55`,
  `docs/README.md:5`, and `IMPLEMENTATION_PLAN.md:323` but does not exist.
- **`docs/TESTING.md`** is referenced from `IMPLEMENTATION_PLAN.md:358` but
  does not exist.
- **`docs/design-decisions/`** is empty — referenced from
  `ARCHITECTURE.md:75` for rationale on libc/init/package-format choices.

---

## 11. Unconventional Target Triplet

`build.conf:14` defines the target as `x86_64-shreeos-linux-gnu`. This is a
non-standard GNU triplet. Many autoconf-based packages and glibc itself may
misdetect or reject this triplet. Common practice in LFS-style builds is to
use `x86_64-linux-gnu` (keeping the vendor field empty) to maximize
compatibility. The custom vendor string `shreeos` could cause subtle build
failures across the dozens of packages planned in Milestone 3.

---

## 12. Smoke Tests Are Structure-Only

`tests/smoke/run-all.sh` passes 21 checks, all of which verify that:
- Shell scripts have valid syntax (`bash -n`)
- README files exist
- `LICENSE` and `ROADMAP.md` exist

There is zero testing of:
- Build logic (no builds happen)
- Cross-compilation
- Package format parsing
- Init service parsing
- Kernel config validation

The test framework (`check()` function) is reasonable but the test surface is
purely structural.

---

## 13. CRLF/LF Line Ending Inconsistency

`git status` shows LF→CRLF warnings on 7 modified files:

```
warning: in the working copy of 'CONTRIBUTING.md', LF will be replaced
by CRLF the next time Git touches it
```

This affects `CONTRIBUTING.md`, `README.md`, `build.conf`,
`docs/ARCHITECTURE.md`, `repo-tools/README.md`, `scripts/common.sh`, and
`tests/smoke/run-all.sh`. If someone on Windows commits `.gitattributes` or
auto-crlf settings change, every file in the repo will show as modified,
making code review and blame difficult.

---

## 14. Untracked Implementation Plan

`IMPLEMENTATION_PLAN.md` (the detailed 405-line execution plan) is not
tracked in git. If the working directory is cleaned or the repo is cloned
fresh, this document is lost. Since it contains the detailed technical
approach for every phase, it should be version-controlled alongside
`ROADMAP.md`.

---

## 15. Hardcoded Host Assumptions

- **`.github/workflows/lint.yml:12`** hardcodes `ubuntu-latest` with no
  container image pinning. A future `ubuntu-latest` may drop `shellcheck` from
  its default repos or change behavior.
- **`tests/smoke/run-all.sh:6`** assumes the repo root can be computed
  relative to the script itself. This works for `bash tests/smoke/run-all.sh`
  but fails if run from another directory via an absolute path in certain
  shell configurations.
- **`build.conf:18-23`** uses paths like `/build/`, `/out/` which work on
  Linux but may behave differently on case-insensitive or symlink-challenged
  filesystems.

---

## 16. Ghost Dependencies Referenced in Docs

The ARCHITECTURE pipeline diagram (`docs/ARCHITECTURE.md:10-24`) describes a
7-stage build chain where each stage depends on the previous. However, no
inter-stage artifact format or contract is documented anywhere. For example:
- What format does the toolchain's output take? (Directory layout under `$LUMEN_TOOLS`)
- What ABI/API does `rootfs/` expect from `base-system/`?
- What kernel features are required by `init/`?

Without these contracts, stages built by different people or at different times
may not compose correctly.

---

## 17. No Version Pinning Strategy for CI Images

`lint.yml` uses `ubuntu-latest` and runs `sudo apt-get update` without
pinning. If a package version changes or a repository becomes unavailable
mid-build, the lint step silently breaks. Recommended: pin to a specific
Ubuntu image tag (e.g., `ubuntu:24.04`) and use a versioned actions
checkout (already done: `actions/checkout@v4`).

---

## 18. `curl` Dependency Not Verified Upfront

`scripts/common.sh:25` calls `curl` but `lumen_require_cmd` is never invoked
for `curl` anywhere in the smoke tests or build bootstrap. A user on a minimal
system (Docker container, WSL, etc.) that lacks `curl` will get an opaque
command-not-found error deep into a build script.

---

## 19. No Checksum for curl Itself

The `lumen_fetch` function (`scripts/common.sh:19-34`) relies on `curl` and
`sha256sum` to be present and trustworthy. If either is compromised or absent,
there is no defense-in-depth. `sha256sum` is from `coreutils` which is
universal on Linux, but `curl` has no integrity check.

---

## Summary of Urgency

| Severity | Count | Key Items |
|---|---|---|
| **Critical** | 4 | Empty version vars, TOCTOU race in fetch, 0% milestones implemented, 15 empty component dirs |
| **High** | 6 | Missing Makefiles contradicts README, no CI beyond lint, no build guide, unvalidated sed, untracked IMPLEMENTATION_PLAN, unconvential triplet |
| **Medium** | 5 | CRLF vs LF, no sources.list files, host assumption hardcodes, build time code execution, missing error handling |
| **Low** | 4 | Empty design-decisions, ghost dependencies unpinned, ghost CI workflow names, curl not pre-checked |
