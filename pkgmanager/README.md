# Package Manager

**Status:** scaffolded, implementation lands in Milestone 7 (see `docs/ROADMAP.md`).

## Purpose

Source for `lpm`, the custom package manager, and the `.lpkg` package format spec (tar + zstd + JSON manifest). Built for both the host (packaging) and the target (install/remove/query).

## Layout

_(populated as this milestone is implemented)_

## Building standalone

```bash
# once implemented:
# cd pkgmanager && make
```

## Testing

Tests for this component live in `tests/` and are also runnable from
within this directory once scripts exist here.
