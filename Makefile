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
	@echo "  make distclean            Full reset including build/ and out/"
	@echo ""
	@echo "Options:"
	@echo "  PROFILE=desktop|minimal|server  (default: desktop)"
	@echo "  FORCE=1                         (rebuild all stages)"

# Marker directory creation
$(MARKER_DIR):
	mkdir -p $(MARKER_DIR)

ifdef FORCE
$(shell rm -f $(MARKER_DIR)/.* 2>/dev/null)
endif

# -- Phase 1: Toolchain -----------------------------------------------
.PHONY: toolchain
toolchain: $(MARKER_DIR)/.toolchain

$(MARKER_DIR)/.toolchain: | $(MARKER_DIR)
	bash toolchain/scripts/build-all.sh --skip-tests
	@touch $@

.PHONY: toolchain-test
toolchain-test:
	bash tests/smoke/test-toolchain.sh

# -- Phase 2: Base System --------------------------------------------
.PHONY: base-system
base-system: $(MARKER_DIR)/.base-system

$(MARKER_DIR)/.base-system: $(MARKER_DIR)/.toolchain
	bash base-system/scripts/build-all.sh
	@touch $@

# -- Phase 3: Kernel --------------------------------------------------
.PHONY: kernel
kernel: $(MARKER_DIR)/.kernel

$(MARKER_DIR)/.kernel: $(MARKER_DIR)/.toolchain
	bash kernel/scripts/build-kernel.sh
	@touch $@

# -- Phase 4: Package Manager, Init & Hardware Service ----------------
.PHONY: packages
packages: $(MARKER_DIR)/.packages

$(MARKER_DIR)/.packages: $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system
	$(MAKE) -C pkgmanager/src
	$(MAKE) -C init/src
	$(MAKE) -C hardware
	@touch $@

# -- Phase 5: Desktop Suite (Profile-aware) ---------------------------
.PHONY: desktop
desktop: $(MARKER_DIR)/.desktop-$(PROFILE)

$(MARKER_DIR)/.desktop-$(PROFILE): $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel $(MARKER_DIR)/.packages
ifeq ($(PROFILE),desktop)
	bash desktop/wm/build-all.sh
endif
	@touch $@

# -- Phase 6: RootFS Assembly (Profile-aware) -------------------------
.PHONY: rootfs
rootfs: $(MARKER_DIR)/.rootfs-$(PROFILE)

$(MARKER_DIR)/.rootfs-$(PROFILE): $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel $(MARKER_DIR)/.packages $(MARKER_DIR)/.desktop-$(PROFILE)
	bash rootfs/scripts/make-rootfs.sh
	@touch $@

# -- Phase 7: ISO Creation (Profile-aware) ----------------------------
.PHONY: iso
iso: $(MARKER_DIR)/.iso-$(PROFILE)

$(MARKER_DIR)/.iso-$(PROFILE): $(MARKER_DIR)/.rootfs-$(PROFILE)
	bash iso-builder/scripts/build-iso.sh
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
	bash tests/qemu/run-all-qemu-tests.sh

.PHONY: test-all
test-all: test-unit test-security test-auth test-installer test-pkgmanager test-desktop test-hardware test-qemu

.PHONY: tests
tests: test-smoke

# -- Cleanup ---------------------------------------------------------
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)/.markers $(BUILD_DIR)/build-*
	rm -rf $(BUILD_DIR)/tools $(BUILD_DIR)/sysroot
	rm -rf $(BUILD_DIR)/rootfs $(BUILD_DIR)/rootfs.cpio.gz
	rm -rf out/*.iso
	$(MAKE) -C pkgmanager/src clean
	$(MAKE) -C init/src clean
	$(MAKE) -C hardware clean

.PHONY: distclean
distclean: clean
	rm -rf $(BUILD_DIR)
	rm -rf out
