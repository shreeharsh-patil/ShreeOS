# ShreeOS top-level build orchestration
#
# Profiles:
#   PROFILE=desktop (default: complete graphical desktop environment)
#   PROFILE=minimal (minimal headless rescue/embedded environment)
#   PROFILE=server  (headless networking/server environment)
#
# Targets:
#   toolchain    — Phase 1: cross-compilation toolchain
#   base-system  — Phase 2: base userland packages
#   kernel       — Phase 3: Linux kernel
#   packages     — Phase 4: lpm package manager & utilities
#   desktop      — Phase 5: window manager, UI apps & design system
#   rootfs       — Phase 6: init + full root filesystem assembly
#   iso          — Phase 7: bootable hybrid ISO
#   all          — Complete end-to-end pipeline
#   test-unit    — Package manager unit tests
#   test-smoke   — Desktop & system smoke tests
#   test-qemu    — Automated QEMU boot & install tests
#   test-all     — All test suites
#   qemu         — Run graphical or serial QEMU virtual machine
#   clean        — Remove build artifacts
#   distclean    — Full reset

PROFILE ?= desktop
BUILD_DIR := build
MARKER_DIR := $(BUILD_DIR)/.markers
SHELL := /usr/bin/env bash

export PROFILE

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "ShreeOS Build System (Profile: $(PROFILE))"
	@echo ""
	@echo "Core Pipeline Targets:"
	@echo "  make toolchain            Phase 1: Cross-compilation toolchain"
	@echo "  make base-system          Phase 2: Base userland packages"
	@echo "  make kernel               Phase 3: Linux kernel"
	@echo "  make packages             Phase 4: lpm package manager & tools"
	@echo "  make desktop              Phase 5: Window manager & desktop suite"
	@echo "  make rootfs               Phase 6: Init & rootfs assembly"
	@echo "  make iso                  Phase 7: Bootable hybrid ISO"
	@echo "  make all                  Build everything end-to-end"
	@echo ""
	@echo "Testing & Execution Targets:"
	@echo "  make test-unit            Run LPM package manager unit tests"
	@echo "  make test-smoke           Run desktop & toolchain smoke tests"
	@echo "  make test-qemu            Run automated QEMU ISO & installed disk tests"
	@echo "  make test-all             Run all tests (unit + smoke + qemu)"
	@echo "  make qemu                 Launch built ISO in QEMU (UEFI)"
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

# -- Phase 4: Package Manager -----------------------------------------
.PHONY: packages
packages: $(MARKER_DIR)/.packages

$(MARKER_DIR)/.packages: $(MARKER_DIR)/.toolchain
	$(MAKE) -C pkgmanager/src
	$(MAKE) -C init/src
	@touch $@

# -- Phase 5: Desktop Suite (Only staged for PROFILE=desktop) --------
.PHONY: desktop
desktop: $(MARKER_DIR)/.desktop

$(MARKER_DIR)/.desktop: $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel $(MARKER_DIR)/.packages
ifeq ($(PROFILE),desktop)
	bash desktop/wm/build-all.sh
endif
	@touch $@

# -- Phase 6: RootFS Assembly -----------------------------------------
.PHONY: rootfs
rootfs: $(MARKER_DIR)/.rootfs

$(MARKER_DIR)/.rootfs: $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel $(MARKER_DIR)/.packages $(MARKER_DIR)/.desktop
	bash rootfs/scripts/make-rootfs.sh
	@touch $@

# -- Phase 7: ISO Creation --------------------------------------------
.PHONY: iso
iso: $(MARKER_DIR)/.iso

$(MARKER_DIR)/.iso: $(MARKER_DIR)/.rootfs
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

# -- Tests -----------------------------------------------------------
.PHONY: test-unit
test-unit:
	$(MAKE) -C pkgmanager/tests test

.PHONY: test-smoke
test-smoke:
	bash tests/smoke/run-all.sh

.PHONY: test-qemu
test-qemu:
	bash tests/qemu/run-all-qemu-tests.sh

.PHONY: test-all
test-all: test-unit test-smoke test-qemu

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

.PHONY: distclean
distclean: clean
	rm -rf $(BUILD_DIR)
	rm -rf out
