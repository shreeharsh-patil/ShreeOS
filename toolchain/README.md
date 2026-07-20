# Toolchain

**Status:** scaffolded, implementation lands in Milestone 2 (see `docs/ROADMAP.md`).

## Purpose

Builds the cross-compilation toolchain (binutils, gcc, glibc) used to compile everything else in this repo, following the LFS two-pass method. Produces a self-contained compiler installed under $LUMEN_TOOLS that never touches the host system's own toolchain.

## Layout

_(populated as this milestone is implemented)_

## Building standalone

```bash
# once implemented:
# cd toolchain && make
```

## Testing

Tests for this component live in `tests/` and are also runnable from
within this directory once scripts exist here.
