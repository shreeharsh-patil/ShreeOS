# Kernel

**Status:** scaffolded, implementation lands in Milestone 4 (see `docs/ROADMAP.md`).

## Purpose

Kernel configuration fragments and build scripts for mainline Linux, pinned to a specific LTS tag. Produces a bzImage and modules tree targeting $LUMEN_ARCH.

## Layout

_(populated as this milestone is implemented)_

## Building standalone

```bash
# once implemented:
# cd kernel && make
```

## Testing

Tests for this component live in `tests/` and are also runnable from
within this directory once scripts exist here.
