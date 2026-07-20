# Lumen Linux — Phased Implementation Plan

This is the detailed execution plan behind `ROADMAP.md`'s summary table. Each
phase lists its objective, exact deliverables, the technical approach, where
it executes (local sandbox vs. CI), and the exit criteria that must pass
before the next phase starts. Nothing in a later phase is allowed to paper
over a gap in an earlier one.

**Rule for every phase:** explain → implement → configure → test → commit →
confirm with the project owner → next phase.

---

## Phase 0 — Repository Scaffold ✅ complete

**Objective:** a real git project with clean architecture, before any distro
code exists.

**Delivered:**
- Full directory layout for all downstream phases
- `build.conf` (single source of truth: arch, versions, paths, branding)
- `scripts/common.sh` (logging, checksummed fetch, guard helpers)
- `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`
- README in every component directory
- `tests/smoke/run-all.sh` (21/21 passing)
- `.github/workflows/lint.yml` (shellcheck + structure enforcement)
- MIT `LICENSE`, `CONTRIBUTING.md`, `CHANGELOG.md`, initial commit

**Exit criteria:** `bash tests/smoke/run-all.sh` passes; every component
directory has a README; repo has at least one git commit. **Met.**

---

## Phase 1 — Cross-Compilation Toolchain

**Objective:** a working cross-compiler (binutils + gcc + glibc) targeting
`x86_64-lumen-linux-gnu`, installed to `$LUMEN_TOOLS`, isolated from the host
toolchain — the foundation every later phase compiles against.

**Technical approach (LFS two-pass method):**
1. Pin exact versions of binutils, gcc, glibc, and Linux kernel headers in
   `toolchain/sources.list`, each with a SHA-256 checksum.
2. **Pass 1 — binutils:** cross-assembler/linker only, no libc dependency.
3. **Pass 1 — gcc:** minimal C-only compiler (`--without-headers`), enough to
   build glibc's headers and static startup files.
4. **Linux API headers:** exported from the pinned kernel source into
   `$LUMEN_SYSROOT/usr/include`.
5. **glibc:** built and installed into `$LUMEN_SYSROOT` using the pass-1
   compiler.
6. **libstdc++ (pass 1):** built against the new glibc.
7. **Pass 2 — binutils, gcc:** full rebuild against the sysroot, producing
   the final, self-hosting cross-compiler.

**Deliverables:**
- `toolchain/sources.list` — pinned URLs + checksums
- `toolchain/scripts/01-binutils-pass1.sh` … `07-gcc-pass2.sh`
- `toolchain/scripts/build-all.sh` — orchestrates 01→07 in order, idempotent
  (skips a step if its output already exists and is valid)
- `toolchain/README.md` updated with the exact build sequence and prerequisites

**Exit criteria / tests:**
- `${LUMEN_TOOLS}/bin/x86_64-lumen-linux-gnu-gcc --version` runs
- A trivial static C program cross-compiles and, under `qemu-x86_64` (user
  mode) or on a matching host, executes and returns the expected exit code
- `toolchain/tests/` script asserting the above, runnable standalone

**Execution environment:** Script *correctness* and the early binutils/gcc
pass-1 steps are verified interactively here. The full pass-2 gcc + glibc
bootstrap (the multi-hour part) is exercised end-to-end in a new
`.github/workflows/toolchain.yml` CI job, with build artifacts cached so
later phases don't re-pay that cost on every run.

**Risks:** version incompatibilities between binutils/gcc/glibc/kernel-headers
are the single most common LFS failure mode — versions are pinned together
and tested as a set, not upgraded independently.

---

## Phase 2 — Base System

**Objective:** a minimal, chroot-able userland compiled *with* the Phase 1
cross-compiler: bash, coreutils, util-linux, and the small set of packages
LFS/BLFS treats as load-bearing (e.g. ncurses, zlib, file, m4, bison,
readline where required as build deps of the above).

**Technical approach:**
- Each package gets its own numbered script under `base-system/scripts/`
  (`build.conf`-driven `$LUMEN_STAGE_ROOT` as install target), following the
  same fetch → verify → configure → make → make install pattern as Phase 1.
- A `base-system/packages.list` records exact versions/checksums, same
  discipline as `toolchain/sources.list`.

**Deliverables:**
- `base-system/packages.list`
- `base-system/scripts/*.sh` per package + `build-all.sh`
- Updated `base-system/README.md`

**Exit criteria / tests:**
- `chroot $LUMEN_STAGE_ROOT /bin/bash -c 'echo hello'` succeeds under QEMU or
  a compatible host
- Core utilities (`ls`, `cat`, `mount`, `ps`) run inside the chroot
- Smoke test script asserting the above

**Execution environment:** Buildable and testable locally for individual
packages; full-set build verified in CI.

---

## Phase 3 — Kernel

**Objective:** a mainline Linux kernel, configured and compiled for
`$LUMEN_ARCH`, that boots to a shell under QEMU.

**Technical approach:**
- Pin a specific LTS tag (recorded in `build.conf` as `VER_LINUX_KERNEL`),
  sourced from the `torvalds/linux` GitHub mirror.
- Start from a config fragment strategy: `kernel/configs/x86_64-minimal.config`
  (just enough to boot: PC platform, ext4/virtio block+net for QEMU, serial
  console) and `x86_64-generic.config` (broader hardware support for real
  installs), both generated via `make ARCH=x86_64 CROSS_COMPILE=... olddefconfig`
  from a documented baseline.
- `kernel/scripts/build-kernel.sh` cross-compiles the kernel + modules using
  the Phase 1 toolchain, installs modules into `$LUMEN_STAGE_ROOT`.

**Deliverables:**
- `kernel/configs/*.config`
- `kernel/scripts/build-kernel.sh`
- `kernel/README.md` documenting config choices and how to add hardware support

**Exit criteria / tests:**
- Kernel + a trivial initramfs boots under QEMU (`qemu-system-x86_64`) far
  enough to print a kernel log and reach a shell prompt
- `tests/qemu/boot-kernel-only.sh` automates this and checks for a known
  marker string in serial output

**Execution environment:** Kernel compile is CPU-heavy but bounded (tens of
minutes with `-j$(nproc)`); feasible to run a *minimal*-config build
interactively here, with the full generic-config build in CI. QEMU boot
testing runs wherever `qemu-system-x86_64` is available (installable via the
whitelisted `archive.ubuntu.com`).

---

## Phase 4 — Root Filesystem

**Objective:** combine Phase 2's base system, Phase 3's kernel modules, and a
new custom init into one clean root filesystem layout that reaches PID 1
successfully.

**Technical approach:**
- `rootfs/skeleton/` holds the static layout (`/etc` templates, `/var`
  structure, device-node manifest for `/dev`, `/etc/os-release` templated
  from `build.conf`'s `DISTRO_*` variables).
- `init/src/` — a small C program: mounts `/proc`, `/sys`, `/dev` (or
  consumes an already-populated `/dev` from initramfs), reads
  `init/services/*` service definitions, execs a shell or launches services
  in order, handles reboot/poweroff syscalls directly.
- `rootfs/scripts/make-rootfs.sh` assembles skeleton + base-system +
  kernel modules + compiled init into `$LUMEN_STAGE_ROOT`, then archives it.

**Deliverables:**
- `rootfs/skeleton/*`
- `init/src/init.c` + `init/services/*`
- `rootfs/scripts/make-rootfs.sh`
- Updated `init/README.md`, `rootfs/README.md`

**Exit criteria / tests:**
- Booting the assembled rootfs + kernel in QEMU reaches a shell spawned by
  the *custom* init (not a busybox/toybox stand-in)
- `tests/qemu/boot-full-rootfs.sh` automates this
- `init/tests/` unit-tests the service-parsing logic outside of a real boot
  (pure logic test, fast, no QEMU needed)

**Execution environment:** init development/unit-testing is fully local;
full QEMU boot verification can run locally if QEMU is available, mirrored
in CI regardless.

---

## Phase 5 — Bootloader + Bootable ISO

**Objective:** a hybrid BIOS/UEFI-bootable ISO of the assembled root
filesystem.

**Technical approach:**
- `bootloader/grub/grub.cfg.template` — GRUB2 menu templated with
  `DISTRO_NAME`/`DISTRO_VERSION`.
- `bootloader/scripts/install-grub.sh` — installs GRUB2 into a target
  (disk or ISO staging directory) for both BIOS and UEFI.
- `iso-builder/scripts/build-iso.sh` — lays out `/boot`, kernel, initramfs,
  squashfs (or plain rootfs) and GRUB, then runs `grub-mkrescue`/`xorriso`
  to produce a single hybrid `.iso`.

**Deliverables:**
- `bootloader/grub/grub.cfg.template`, `bootloader/scripts/install-grub.sh`
- `iso-builder/scripts/build-iso.sh`
- Updated `bootloader/README.md`, `iso-builder/README.md`

**Exit criteria / tests:**
- The produced ISO boots to the custom-init shell under QEMU in **both**
  `-bios` (legacy) and `-bios OVMF` (UEFI) modes
- `tests/qemu/boot-iso-bios.sh` and `tests/qemu/boot-iso-uefi.sh`

**Execution environment:** Fully buildable/testable locally given `xorriso`
and `ovmf` packages (both installable via the whitelisted Ubuntu mirrors);
also run in CI for regression protection.

---

## Phase 6 — Package Manager + Repository Tools

**Objective:** `lpm`, a working install/remove/query package manager, plus
tooling to build a package repository it can pull from.

**Technical approach:**
- **Format (`.lpkg`):** tar+zstd payload + a JSON manifest (name, version,
  dependencies, file list, pre/post install hooks, checksums per file).
  Spec written first and versioned under `pkgmanager/spec/`.
- **`lpm` core (C, statically linkable):** `lpm install <pkg>`,
  `lpm remove <pkg>`, `lpm query <pkg>`, `lpm list`, dependency resolution
  (topological, no version-range SAT solving for v1 — exact/minimum version
  match only, documented as a v1 limitation).
- **`repo-tools`:** `build-repo.sh` packages a directory tree into `.lpkg`s
  and writes a repo index (JSON) `lpm` can fetch and parse.

**Deliverables:**
- `pkgmanager/spec/lpkg-format.md`
- `pkgmanager/src/*.c` + `Makefile`
- `pkgmanager/tests/` — unit tests for manifest parsing, dependency
  resolution, and install/remove against a scratch root (no real system
  needed)
- `repo-tools/scripts/build-repo.sh`

**Exit criteria / tests:**
- `lpm install` places files correctly into a scratch root and records them
  for later removal
- `lpm remove` fully reverses an install (verified by directory diff)
- Dependency resolution test with a 3-package chain (A depends on B depends
  on C) installs in the correct order

**Execution environment:** Entirely local — this phase has no multi-hour
build step, it's application development or C tooling.

---

## Phase 7 — Installer

**Objective:** a guided installer, runnable from the live ISO, that
partitions a target disk, writes the rootfs, and installs the bootloader.

**Technical approach:**
- `installer/src/` — a small text-mode (ncurses or plain-line) installer:
  disk selection → partition (via `sfdisk`/`parted` calls) → filesystem
  creation (`mkfs.ext4`) → rootfs copy → `bootloader/scripts/install-grub.sh`
  invocation → first-boot config (hostname, user creation).
- Designed to be scriptable/non-interactive (`installer --answer-file=...`)
  so it's testable without a human driving a TUI.

**Deliverables:**
- `installer/src/*`
- `installer/tests/` — a test that runs the installer non-interactively
  against a QEMU-attached virtual disk and verifies the disk is bootable
  afterward

**Exit criteria / tests:**
- Non-interactive install to a blank virtual disk image, followed by
  booting *that disk* (not the ISO) in QEMU, reaching the custom init's
  shell

**Execution environment:** Runs locally with QEMU + a scratch disk image;
mirrored in CI.

---

## Phase 8 — Desktop Environment

**Objective:** an optional X11 + lightweight window manager layer,
installable as a package set via `lpm`, with branding wired in.

**Technical approach:**
- `desktop/wm/` — build scripts for a minimal WM (evaluated: dwm-style
  suckless WM vs. a small independent WM; decision recorded in
  `docs/design-decisions/` when this phase starts) plus a terminal emulator
  and a basic launcher.
- `desktop/configs/` — default configs (keybindings, autostart) templated
  with `branding/` assets (wallpaper, theme colors).
- Packaged as `.lpkg`s via `repo-tools`, so "installing the desktop" is just
  `lpm install lumen-desktop-minimal`.

**Deliverables:**
- `desktop/wm/*`, `desktop/configs/*`
- `branding/logo/*`, `branding/wallpapers/*`, `branding/theme/*` (real
  placeholder assets, not empty directories)
- Desktop package(s) buildable via `repo-tools/scripts/build-repo.sh`

**Exit criteria / tests:**
- Booting the ISO with the desktop package installed reaches a working X11
  session with the WM running (verified via QEMU + VNC/screenshot capture,
  or a scripted check that the X server and WM processes are alive and a
  test window can be mapped)

**Execution environment:** Compiling a WM is a normal, boundable local build;
the *visual* verification (screenshot-based) is best run in CI where a
consistent virtual display is available, with a lighter local check
(process-alive) available for quick iteration.

---

## Phase 9 — Automated Build Orchestration

**Objective:** a single entry point that chains Phases 1–8 end-to-end
reproducibly.

**Technical approach:**
- Top-level `Makefile` with targets mirroring the phases (`make toolchain`,
  `make kernel`, `make rootfs`, `make iso`, `make packages`, `make all`),
  each depending on the previous, each idempotent (skips completed steps
  based on marker files under `$LUMEN_BUILD_DIR`).
- `make clean` / `make distclean` for controlled resets.

**Deliverables:**
- Root `Makefile`
- `docs/BUILD_GUIDE.md` — the full walkthrough referenced from the root
  README, now actually accurate end-to-end

**Exit criteria / tests:**
- `make all` from a clean checkout produces a bootable ISO with no manual
  intervention (verified in CI, where the runtime budget exists for a full
  from-scratch run)

**Execution environment:** Orchestration logic is developed and unit-tested
locally against stubbed/short-circuited phase scripts; the real full-chain
run is a CI job.

---

## Phase 10 — Testing & CI/CD

**Objective:** comprehensive automated verification replacing ad hoc manual
checks, gating every merge.

**Technical approach:**
- `tests/unit/` — fast, no-build logic tests (init service parsing, `lpm`
  dependency resolution, manifest parsing) — run on every push.
- `tests/smoke/` — structure/config sanity checks (already started in
  Phase 0) — run on every push.
- `tests/qemu/` — the boot tests accumulated in Phases 3–7 — run on a
  schedule and on release branches (they're slower).
- `.github/workflows/`:
  - `lint.yml` (exists) — shellcheck + structure
  - `toolchain.yml` — builds and caches the cross-toolchain
  - `kernel.yml` — builds the kernel against the cached toolchain
  - `iso.yml` — full chain via `make all`, uploads the ISO as a build
    artifact
  - `release.yml` — triggered on version tags, runs `iso.yml`'s build and
    attaches the ISO to a GitHub Release

**Deliverables:** the workflow files above, plus a `docs/TESTING.md`
explaining the test pyramid and how to run each layer locally.

**Exit criteria:** a fresh PR triggers lint + unit + smoke automatically; a
push to `main` additionally triggers the full toolchain→ISO chain; all green
before merge is the project's actual merge gate, not aspirational.

**Execution environment:** CI-first by design — this phase's whole purpose
is to move the expensive verification off the interactive path.

---

## Phase 11 — v1.0 Release

**Objective:** a tagged, reproducible, documented release.

**Technical approach:**
- Freeze `build.conf` versions, run the full `make all` chain in CI via
  `release.yml`, triggered by pushing a `v1.0.0` tag.
- `CHANGELOG.md` finalized for `1.0.0`.
- `docs/BUILD_GUIDE.md`, all component READMEs reviewed for accuracy against
  the actual, final build (not the plan — the real thing).
- GitHub Release created with the ISO attached, checksummed
  (`SHA256SUMS.txt`), and release notes summarizing what v1.0 includes and
  its known limitations (single arch, minimal desktop, no version-range
  dependency solving in `lpm`, etc.) — set honestly, not oversold.

**Exit criteria:** a stranger can clone the repo, read `README.md` and
`docs/BUILD_GUIDE.md`, run `make all` (or download the released ISO), boot
it in QEMU or on real hardware, log in, and install a package with `lpm` —
without asking a single follow-up question.

---

## Cross-cutting notes

- **Local sandbox vs. CI, restated simply:** anything measured in minutes
  (script development, unit tests, config generation, small compiles) is
  done and verified here, interactively, with real output shown to you.
  Anything measured in hours (full glibc/gcc bootstrap, full kernel
  defconfig build, full `make all`) is scripted here but *executed and
  verified* in GitHub Actions, where the runtime budget exists. Every phase
  above states explicitly which bucket it falls into.
- **No phase starts until the previous phase's exit criteria are met and
  committed.** If a phase's tests fail, that's the next thing worked on —
  not the next phase.
- **This document is updated as phases complete**, same discipline as
  `ROADMAP.md`'s status column.
