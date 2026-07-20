# Contributing

Lumen Linux is built milestone by milestone (see `docs/ROADMAP.md`). Please
follow the same discipline in any contribution:

1. **One milestone/feature per branch and PR.** Don't mix unrelated stages.
2. **Every script must run cleanly** (`bash -n script.sh` at minimum;
   `shellcheck` for anything non-trivial) before it's committed.
3. **Every new component needs:**
   - A `README.md` in its directory explaining what it does and how to
     build/test it standalone.
   - At least one test under `tests/` (unit, smoke, or QEMU boot test as
     appropriate).
   - Pinned, checksummed sources if it downloads anything — never fetch
     "latest".
4. **No hardcoded paths, versions, or names.** Read from `build.conf`.
5. **Commit messages** describe *what stage* and *what changed*, e.g.
   `toolchain: add pass-1 binutils build script`.

## Development environment

- Ubuntu 22.04/24.04 host (or the CI containers under `.github/workflows/`)
- `shellcheck`, `make`, `git`, standard build-essential toolchain for the
  *host* (used to bootstrap the cross-compiler)

## Running tests locally

```bash
bash tests/smoke/run-all.sh     # fast checks, no full builds required
```

Full builds (toolchain bootstrap, kernel compile, ISO assembly) are exercised
in CI — see `.github/workflows/`.
