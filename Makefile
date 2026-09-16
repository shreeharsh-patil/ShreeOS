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
#   tests        — run all smoke tests
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
	@echo "  make tests         Run all smoke tests"
	@echo "  make clean         Remove build artifacts"
	@echo "  make distclean     Full reset"
	@echo ""
	@echo "Options: FORCE=1 to rebuild an already-completed target"

# Marker-based idempotency: a target runs only if its marker is missing.
# Force with: make <target> FORCE=1
$(MARKER_DIR):
	mkdir -p $(MARKER_DIR)

define MARKER_TARGET
$(MARKER_DIR)/.$(1): | $(MARKER_DIR)
	@if [ -f "$(MARKER_DIR)/.$(1)" ] && [ -z "$(FORCE)" ]; then \
		echo "[skip] $(1) already done (use FORCE=1 to rebuild)"; \
		exit 0; \
	fi
endef

# -- Phase 1: Toolchain -----------------------------------------------
.PHONY: toolchain
toolchain: $(MARKER_DIR)/.toolchain

$(eval $(call MARKER_TARGET,toolchain))
$(MARKER_DIR)/.toolchain:
	bash toolchain/scripts/build-all.sh --skip-tests
	@touch $(MARKER_DIR)/.toolchain

.PHONY: toolchain-test
toolchain-test:
	bash tests/smoke/test-toolchain.sh

# -- Phase 2: Base System --------------------------------------------
.PHONY: base-system
base-system: $(MARKER_DIR)/.base-system

$(eval $(call MARKER_TARGET,base-system))
$(MARKER_DIR)/.base-system: toolchain
	bash base-system/scripts/build-all.sh
	@touch $(MARKER_DIR)/.base-system

# -- Phase 3: Kernel --------------------------------------------------
.PHONY: kernel
kernel: $(MARKER_DIR)/.kernel

$(eval $(call MARKER_TARGET,kernel))
$(MARKER_DIR)/.kernel: toolchain
	bash kernel/scripts/build-kernel.sh
	@touch $(MARKER_DIR)/.kernel

# -- Phase 4: Init + RootFS ------------------------------------------
.PHONY: rootfs
rootfs: $(MARKER_DIR)/.rootfs

$(eval $(call MARKER_TARGET,rootfs))
$(MARKER_DIR)/.rootfs: base-system kernel
	bash rootfs/scripts/make-rootfs.sh
	@touch $(MARKER_DIR)/.rootfs

# -- Phase 5: ISO -----------------------------------------------------
.PHONY: iso
iso: $(MARKER_DIR)/.iso

$(eval $(call MARKER_TARGET,iso))
$(MARKER_DIR)/.iso: rootfs
	bash iso-builder/scripts/build-iso.sh
	@touch $(MARKER_DIR)/.iso

# -- Phase 6: Package Manager -----------------------------------------
.PHONY: packages
packages: $(MARKER_DIR)/.packages

$(eval $(call MARKER_TARGET,packages))
$(MARKER_DIR)/.packages: toolchain
	$(MAKE) -C pkgmanager/src
	@touch $(MARKER_DIR)/.packages

# -- Phase 7: Desktop + Installer ------------------------------------
.PHONY: desktop
desktop: $(MARKER_DIR)/.desktop

$(eval $(call MARKER_TARGET,desktop))
$(MARKER_DIR)/.desktop: toolchain base-system kernel
	bash desktop/wm/build-all.sh
	@touch $(MARKER_DIR)/.desktop

.PHONY: installer
installer:
	@echo "Installer is run on-demand (needs target disk):"
	@echo "  bash installer/scripts/install-to-disk.sh /dev/sda"

# -- All -------------------------------------------------------------
.PHONY: all
all: toolchain base-system kernel rootfs iso packages desktop

# -- Tests -----------------------------------------------------------
.PHONY: tests
tests:
	bash tests/smoke/run-all.sh

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
