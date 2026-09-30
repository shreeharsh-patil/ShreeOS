# Contributing

ShreeOS is built milestone by milestone (see `docs/ROADMAP.md`). Please
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

- For the Debian Live prototype: Debian 13 (Trixie) Linux host or VM, root
  access for `live-build`, and the packages listed in
  `.github/workflows/debian-prototype.yml`. See `docs/BUILD_GUIDE.md`.
- For focused shell, Python, and documentation checks: `bash`, `python3`, and
  `git` as required by the specific test.
- The earlier source-built pipeline has separate host dependencies and is
  retained as an experimental path; its outputs are not the current desktop
  release.

## Running tests locally

```bash
bash tests/smoke/run-all.sh     # fast checks, no full builds required
```

Full builds (toolchain bootstrap, kernel compile, ISO assembly) are exercised
in CI — see `.github/workflows/`.
