# ShreeOS top-level build orchestration
#
# Profiles:
#   PROFILE=desktop (default: complete graphical desktop environment)
#   PROFILE=minimal (minimal headless rescue/embedded environment)
#   PROFILE=server  (headless networking/server environment)
#
# Targets:
#   toolchain       — Phase 1: cross-compilation toolchain
#   base-system     — Phase 2: base userland packages
#   kernel          — Phase 3: Linux kernel
#   packages        — Phase 4: lpm package manager & init binaries
#   desktop         — Phase 5: window manager & desktop suite (PROFILE=desktop)
#   rootfs          — Phase 6: init & rootfs assembly
#   iso             — Phase 7: bootable hybrid ISO
#   all             — Full end-to-end pipeline
#   test-unit       — LPM package manager unit tests
#   test-security   — System security audit tests
#   test-auth       — Authentication & credential tests
#   test-installer  — Disk installer validation tests
#   test-pkgmanager — LPM transaction & hash verification tests
#   test-desktop    — Desktop suite syntax & token tests
#   test-hardware   — shreed daemon IPC lifecycle tests
#   test-smoke      — Smoke test aggregator
#   test-qemu       — Automated QEMU boot & install tests
#   test-all        — All automated test suites
#   qemu            — Launch built ISO in QEMU (UEFI)
#   qemu-bios       — Launch built ISO in QEMU (BIOS)

PROFILE ?= desktop
BUILD_DIR := build
MARKER_DIR := $(BUILD_DIR)/.markers
SHELL := /usr/bin/env bash

export PROFILE

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "ShreeOS Build System (Active Profile: $(PROFILE))"
	@echo ""
	@echo "Core Pipeline Targets:"
	@echo "  make toolchain            Phase 1: Cross-compilation toolchain"
	@echo "  make base-system          Phase 2: Base userland packages"
	@echo "  make kernel               Phase 3: Linux kernel"
	@echo "  make packages             Phase 4: lpm package manager & init tools"
	@echo "  make desktop              Phase 5: Window manager & desktop suite"
	@echo "  make rootfs               Phase 6: Init & rootfs assembly"
	@echo "  make iso                  Phase 7: Bootable hybrid ISO"
	@echo "  make all                  Build everything end-to-end"
	@echo ""
	@echo "Diagnostic & Verification Targets:"
	@echo "  make bootstrap-wsl        Install/check supported WSL2 build dependencies"
	@echo "  make doctor               Check environment, host tools, and build readiness"
	@echo "  make verify-sources       Verify upstream URLs, checksum format, and downloaded tarballs"
	@echo "  make graphics             Strictly validate target desktop graphics readiness"
	@echo "  make verify-iso           Validate ISO structure and BIOS/UEFI boot"
	@echo ""
	@echo "Testing & Execution Targets:"
	@echo "  make test-unit            Run LPM package manager C unit tests"
	@echo "  make test-security        Run system security audits"
	@echo "  make test-auth            Run authentication & credential tests"
	@echo "  make test-installer       Run disk installer validation tests"
	@echo "  make test-pkgmanager      Run LPM transaction tests"
	@echo "  make test-hardware        Run shreed daemon IPC lifecycle tests"
	@echo "  make test-smoke           Run desktop & system smoke suite"
	@echo "  make test-qemu            Run automated QEMU ISO & installed disk tests"
	@echo "  make test-all             Run all automated test suites"
	@echo "  make qemu                 Launch built ISO in QEMU (UEFI mode)"
	@echo "  make qemu-bios            Launch built ISO in QEMU (BIOS mode)"
	@echo ""
	@echo "Maintenance Targets:"
	@echo "  make clean                Remove build staging and markers"
	@echo "  make clean-toolchain      Remove toolchain/sysroot and dependent markers"
	@echo "  make clean-base           Remove base-system state and dependent markers"
	@echo "  make clean-kernel         Remove kernel state and dependent markers"
	@echo "  make clean-desktop        Remove desktop state and dependent markers"
	@echo "  make clean-iso            Remove ISO state/artifacts only"
	@echo "  make distclean            Full reset including build/ and out/"
	@echo ""
	@echo "Options:"
	@echo "  PROFILE=desktop|minimal|server  (default: desktop)"
	@echo "  FORCE=1                         (rebuild all stages)"

# Diagnostic & source verification
.PHONY: bootstrap-wsl
bootstrap-wsl:
	bash scripts/bootstrap-wsl.sh

.PHONY: doctor
doctor:
	bash scripts/doctor.sh

.PHONY: verify-sources
verify-sources:
	bash scripts/verify-sources.sh

.PHONY: graphics
graphics: toolchain base-system
	bash scripts/graphics-readiness.sh --strict

.PHONY: verify-iso
verify-iso:
	bash scripts/verify-iso.sh

# Marker directory creation
$(MARKER_DIR):
	mkdir -p $(MARKER_DIR)

ifdef FORCE
$(shell rm -rf $(MARKER_DIR) 2>/dev/null)
endif

# Source file dependencies for accurate cache invalidation.
# A marker is rebuilt when its own stage inputs change, so interrupted builds
# can resume without silently reusing stale outputs.
COMMON_BUILD_DEPS := build.conf scripts/common.sh Makefile
TOOLCHAIN_DEPS := $(COMMON_BUILD_DEPS) $(shell find toolchain -type f 2>/dev/null)
BASE_DEPS := $(COMMON_BUILD_DEPS) $(shell find base-system -type f 2>/dev/null)
KERNEL_DEPS := $(COMMON_BUILD_DEPS) $(shell find kernel -type f 2>/dev/null)
PKG_DEPS := $(COMMON_BUILD_DEPS) $(shell find pkgmanager/src init/src hardware -type f 2>/dev/null)
DESKTOP_DEPS := $(COMMON_BUILD_DEPS) scripts/graphics-readiness.sh $(shell find desktop -type f 2>/dev/null)
ROOTFS_DEPS := $(COMMON_BUILD_DEPS) $(shell find rootfs -type f 2>/dev/null)
ISO_DEPS := $(COMMON_BUILD_DEPS) scripts/verify-iso.sh $(shell find iso-builder bootloader -type f 2>/dev/null)

# Marker cache guards. Order-only phony prerequisites execute on every invocation
# without making a valid marker look stale. They fail fast when a marker exists
# but its real stage output is gone/corrupt.
.PHONY: check-toolchain-cache check-base-cache check-kernel-cache check-packages-cache check-desktop-cache check-rootfs-cache check-iso-cache
check-toolchain-cache:
	@if [ -f "$(MARKER_DIR)/.toolchain" ]; then bash scripts/verify-stage.sh toolchain; fi
check-base-cache:
	@if [ -f "$(MARKER_DIR)/.base-system" ]; then bash scripts/verify-stage.sh base-system; fi
check-kernel-cache:
	@if [ -f "$(MARKER_DIR)/.kernel" ]; then bash scripts/verify-stage.sh kernel; fi
check-packages-cache:
	@if [ -f "$(MARKER_DIR)/.packages" ]; then bash scripts/verify-stage.sh packages; fi
check-desktop-cache:
	@if [ -f "$(MARKER_DIR)/.desktop-$(PROFILE)" ]; then bash scripts/verify-stage.sh desktop; fi
check-rootfs-cache:
	@if [ -f "$(MARKER_DIR)/.rootfs-$(PROFILE)" ]; then bash scripts/verify-stage.sh rootfs; fi
check-iso-cache:
	@if [ -f "$(MARKER_DIR)/.iso-$(PROFILE)" ]; then bash scripts/verify-stage.sh iso; fi

# -- Phase 1: Toolchain -----------------------------------------------
.PHONY: toolchain
toolchain: $(MARKER_DIR)/.toolchain
	bash scripts/verify-stage.sh toolchain

$(MARKER_DIR)/.toolchain: $(TOOLCHAIN_DEPS) | $(MARKER_DIR) check-toolchain-cache
	bash toolchain/scripts/build-all.sh --skip-tests
	bash scripts/verify-stage.sh toolchain
	@touch $@

.PHONY: toolchain-test
toolchain-test:
	bash tests/smoke/test-toolchain.sh

# -- Phase 2: Base System --------------------------------------------
.PHONY: base-system
base-system: $(MARKER_DIR)/.base-system
	bash scripts/verify-stage.sh base-system

$(MARKER_DIR)/.base-system: $(MARKER_DIR)/.toolchain $(BASE_DEPS) | check-toolchain-cache check-base-cache
	bash base-system/scripts/build-all.sh
	bash scripts/verify-stage.sh base-system
	@touch $@

# -- Phase 3: Kernel --------------------------------------------------
.PHONY: kernel
kernel: $(MARKER_DIR)/.kernel
	bash scripts/verify-stage.sh kernel

$(MARKER_DIR)/.kernel: $(MARKER_DIR)/.toolchain $(KERNEL_DEPS) | check-toolchain-cache check-kernel-cache
	bash kernel/scripts/build-kernel.sh
	bash scripts/verify-stage.sh kernel
	@touch $@

# -- Phase 4: Package Manager, Init & Hardware Service ----------------
.PHONY: packages
packages: $(MARKER_DIR)/.packages
	bash scripts/verify-stage.sh packages

$(MARKER_DIR)/.packages: $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system $(PKG_DEPS) | check-toolchain-cache check-base-cache check-packages-cache
	$(MAKE) -C pkgmanager/src
	$(MAKE) -C init/src
	$(MAKE) -C hardware
	bash scripts/verify-stage.sh packages
	@touch $@

# -- Phase 5: Desktop Suite (Profile-aware) ---------------------------
.PHONY: desktop
desktop: $(MARKER_DIR)/.desktop-$(PROFILE)
	bash scripts/verify-stage.sh desktop

$(MARKER_DIR)/.desktop-$(PROFILE): $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel $(MARKER_DIR)/.packages $(DESKTOP_DEPS) | check-toolchain-cache check-base-cache check-kernel-cache check-packages-cache check-desktop-cache
ifeq ($(PROFILE),desktop)
	bash desktop/wm/build-all.sh
endif
	bash scripts/verify-stage.sh desktop
	@touch $@

# -- Phase 6: RootFS Assembly (Profile-aware) -------------------------
.PHONY: rootfs
rootfs: $(MARKER_DIR)/.rootfs-$(PROFILE)
	bash scripts/verify-stage.sh rootfs

$(MARKER_DIR)/.rootfs-$(PROFILE): $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel $(MARKER_DIR)/.packages $(MARKER_DIR)/.desktop-$(PROFILE) $(ROOTFS_DEPS) | check-base-cache check-kernel-cache check-packages-cache check-desktop-cache check-rootfs-cache
	bash rootfs/scripts/make-rootfs.sh
	bash scripts/verify-stage.sh rootfs
	@touch $@

# -- Phase 7: ISO Creation (Profile-aware) ----------------------------
.PHONY: iso
iso: $(MARKER_DIR)/.iso-$(PROFILE)
	bash scripts/verify-stage.sh iso

$(MARKER_DIR)/.iso-$(PROFILE): $(MARKER_DIR)/.rootfs-$(PROFILE) $(ISO_DEPS) | check-rootfs-cache check-iso-cache
	bash iso-builder/scripts/build-iso.sh
	bash scripts/verify-stage.sh iso
	@touch $@

.PHONY: installer
installer:
	@echo "Installer is executed on-demand (e.g. within live ISO or target disk):"
	@echo "  bash installer/scripts/install-to-disk.sh /dev/sda"

# -- All -------------------------------------------------------------
.PHONY: all
all: toolchain base-system kernel packages desktop rootfs iso

# -- QEMU ------------------------------------------------------------
.PHONY: qemu
qemu:
	bash tests/qemu/boot-iso-uefi.sh

.PHONY: qemu-bios
qemu-bios:
	bash tests/qemu/boot-iso-bios.sh

# -- Individual & Aggregate Tests ------------------------------------
.PHONY: test-unit
test-unit:
	$(MAKE) -C pkgmanager/tests test

.PHONY: test-init
test-init:
	$(MAKE) -C init/tests test

.PHONY: test-security
test-security:
	bash tests/security/test-security.sh

.PHONY: test-auth
test-auth:
	bash tests/auth/test-auth.sh

.PHONY: test-installer
test-installer:
	bash tests/installer/test-installer-validation.sh

.PHONY: test-pkgmanager
test-pkgmanager:
	bash tests/pkgmanager/test-lpm-transactions.sh

.PHONY: test-desktop
test-desktop:
	bash tests/smoke/test-desktop-suite.sh

.PHONY: test-hardware
test-hardware:
	$(MAKE) -C hardware test

.PHONY: test-smoke
test-smoke:
	bash tests/smoke/run-all.sh

.PHONY: test-qemu
test-qemu:
	bash tests/qemu/run-all-qemu-tests.sh --strict

.PHONY: test-all
test-all: test-unit test-init test-security test-auth test-installer test-pkgmanager test-desktop test-hardware test-qemu

.PHONY: tests
tests: test-smoke

# -- Cleanup ---------------------------------------------------------
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)/.markers $(BUILD_DIR)/build-*
	rm -rf $(BUILD_DIR)/tools $(BUILD_DIR)/sysroot
	rm -rf $(BUILD_DIR)/rootfs $(BUILD_DIR)/initramfs.cpio.gz
	rm -rf out/*.iso
	$(MAKE) -C pkgmanager/src clean
	$(MAKE) -C init/src clean
	$(MAKE) -C hardware clean

.PHONY: clean-toolchain
clean-toolchain:
	rm -rf $(BUILD_DIR)/tools $(BUILD_DIR)/sysroot
	rm -f $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system $(MARKER_DIR)/.packages
	rm -f $(MARKER_DIR)/.desktop-* $(MARKER_DIR)/.rootfs-* $(MARKER_DIR)/.iso-*

.PHONY: clean-base
clean-base:
	rm -rf $(BUILD_DIR)/base-system
	rm -f $(MARKER_DIR)/.base-system $(MARKER_DIR)/.packages
	rm -f $(MARKER_DIR)/.desktop-* $(MARKER_DIR)/.rootfs-* $(MARKER_DIR)/.iso-*

.PHONY: clean-kernel
clean-kernel:
	rm -rf $(BUILD_DIR)/build-kernel
	rm -rf $(BUILD_DIR)/rootfs/lib/modules
	rm -f $(MARKER_DIR)/.kernel $(MARKER_DIR)/.desktop-* $(MARKER_DIR)/.rootfs-* $(MARKER_DIR)/.iso-*

.PHONY: clean-desktop
clean-desktop:
	rm -rf $(BUILD_DIR)/desktop $(BUILD_DIR)/.state/graphics.status
	rm -f $(MARKER_DIR)/.desktop-* $(MARKER_DIR)/.rootfs-* $(MARKER_DIR)/.iso-*

.PHONY: clean-iso
clean-iso:
	rm -rf $(BUILD_DIR)/iso-staging
	rm -f $(MARKER_DIR)/.iso-*
	rm -f out/*.iso out/*.iso.sha256 out/*-manifest.json

.PHONY: distclean
distclean: clean
	rm -rf $(BUILD_DIR)
	rm -rf out
