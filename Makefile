# ShreeOS top-level build orchestration
#
# Targets:
#   toolchain    — Phase 1: cross-compilation toolchain
#   base-system  — Phase 2: base userland packages
#   kernel       — Phase 3: Linux kernel + initramfs
#   rootfs       — Phase 4: init + root filesystem assembly
#   iso          — Phase 5: bootable hybrid ISO
#   packages     — Phase 6: lpm package manager
#   desktop      — Phase 7: WM + configs
#   installer    — Phase 7: disk installer
#   all          — Phases 1-7 end-to-end
#   test-unit    — run package manager unit tests
#   test-smoke   — run build smoke tests
#   test-qemu    — run automated QEMU boot test suite
#   test-all     — run all test suites
#   clean        — remove build artifacts (keeps sources)
#   distclean    — full reset

BUILD_DIR := build
MARKER_DIR := $(BUILD_DIR)/.markers
SHELL := /usr/bin/env bash

# Default target
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "ShreeOS build targets:"
	@echo ""
	@echo "  make toolchain     Phase 1: Cross-compilation toolchain"
	@echo "  make base-system   Phase 2: Base userland packages"
	@echo "  make kernel        Phase 3: Linux kernel + initramfs"
	@echo "  make rootfs        Phase 4: Init + root filesystem"
	@echo "  make iso           Phase 5: Bootable hybrid ISO"
	@echo "  make packages      Phase 6: lpm package manager"
	@echo "  make desktop       Phase 7: Window manager + configs"
	@echo "  make installer     Phase 7: Disk installer"
	@echo "  make all           Phases 1-7 end-to-end"
	@echo "  make test-unit     Run package manager unit tests"
	@echo "  make test-smoke    Run base smoke tests"
	@echo "  make test-qemu     Run automated QEMU boot suite"
	@echo "  make test-all      Run all tests (unit + smoke + qemu)"
	@echo "  make clean         Remove build artifacts"
	@echo "  make distclean     Full reset"
	@echo ""
	@echo "Options: FORCE=1 to rebuild an already-completed target"

# Marker directory creation
$(MARKER_DIR):
	mkdir -p $(MARKER_DIR)

# Handle FORCE=1 by removing marker if requested
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

# -- Phase 4: Init + RootFS ------------------------------------------
.PHONY: rootfs
rootfs: $(MARKER_DIR)/.rootfs

$(MARKER_DIR)/.rootfs: $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel
	bash rootfs/scripts/make-rootfs.sh
	@touch $@

# -- Phase 5: ISO -----------------------------------------------------
.PHONY: iso
iso: $(MARKER_DIR)/.iso

$(MARKER_DIR)/.iso: $(MARKER_DIR)/.rootfs
	bash iso-builder/scripts/build-iso.sh
	@touch $@

# -- Phase 6: Package Manager -----------------------------------------
.PHONY: packages
packages: $(MARKER_DIR)/.packages

$(MARKER_DIR)/.packages: $(MARKER_DIR)/.toolchain
	$(MAKE) -C pkgmanager/src
	@touch $@

# -- Phase 7: Desktop + Installer ------------------------------------
.PHONY: desktop
desktop: $(MARKER_DIR)/.desktop

$(MARKER_DIR)/.desktop: $(MARKER_DIR)/.toolchain $(MARKER_DIR)/.base-system $(MARKER_DIR)/.kernel
	bash desktop/wm/build-all.sh
	@touch $@

.PHONY: installer
installer:
	@echo "Installer is run on-demand (needs target disk):"
	@echo "  bash installer/scripts/install-to-disk.sh /dev/sda"

# -- All -------------------------------------------------------------
.PHONY: all
all: toolchain base-system kernel rootfs iso packages desktop

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

.PHONY: distclean
distclean: clean
	rm -rf $(BUILD_DIR)
	rm -rf out
