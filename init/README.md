# Init System

**Status:** scaffolded, implementation lands in Milestone 5 (see `docs/ROADMAP.md`).

## Purpose

Custom minimal PID 1 init written in C, plus service definitions. Not systemd, not a re-skin of one — a small, auditable init tailored to this distro.

## Layout

_(populated as this milestone is implemented)_

## Building standalone

```bash
# once implemented:
# cd init && make
```

## Testing

Tests for this component live in `tests/` and are also runnable from
within this directory once scripts exist here.
