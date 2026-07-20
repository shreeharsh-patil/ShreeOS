# Installer

**Status:** scaffolded, implementation lands in Milestone 8 (see `docs/ROADMAP.md`).

## Purpose

Guided installer that runs from the live ISO: partitions a target disk, writes the root filesystem, installs the bootloader, and hands off to the new system.

## Layout

_(populated as this milestone is implemented)_

## Building standalone

```bash
# once implemented:
# cd installer && make
```

## Testing

Tests for this component live in `tests/` and are also runnable from
within this directory once scripts exist here.
