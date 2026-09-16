# INTEGRATIONS.md — ShreeOS External Integrations

> Generated: 2026-07-20 | Commit: `1564a4c`
> Status: **Milestone 1 — Repository Scaffold (complete)**
> The project is in early scaffold stage. Most integrations (package repos,
> ISO publishing, CI artifact storage) are planned but not yet implemented.

---

## 1. External APIs & Network Services

### Currently Active

None. The project has no running services, no API keys, no authentication
providers, no webhooks configured.

### Planned

| Integration | Purpose | Target Phase | Details |
|---|---|---|---|
| **GitHub Actions API** | CI/CD pipeline execution | Phase 1+ | `.github/workflows/lint.yml` exists. Future workflows will use `ubuntu-latest` runners with `actions/checkout@v4`. Planned additions: `toolchain.yml`, `kernel.yml`, `iso.yml`, `release.yml` |
| **GitHub Releases API** | Tagged ISO distribution | Phase 11 | `release.yml` (planned) will attach `.iso` + `SHA256SUMS.txt` to GitHub Release on version tags |
| **GitHub Actions caching** | Cross-toolchain build cache | Phase 1 | Full glibc/gcc bootstrap takes hours; CI will cache `$LUMEN_TOOLS` and `$LUMEN_SYSROOT` between runs |
| **Package repository (HTTPS)** | `lpm` fetches `.lpkg` packages | Phase 6 | `lpm` will download from an HTTPS-serving package repository. The repository index is a JSON file. Hosting details TBD (GitHub Pages, S3, or self-hosted) |
| **Upstream source mirrors** | Download pinned tarballs | Phase 1+ | Planned: `toolchain/sources.list`, `base-system/packages.list`, `kernel/sources.list` — all fetched via `curl` from canonical upstream URLs (kernel.org, gnu.org, etc.) |

---

## 2. Database Systems

**None.** ShreeOS is a Linux distribution, not an application platform. There
are no databases, no ORMs, no migration files, no data stores beyond the
package manager's on-disk manifest database (flat JSON files under
`/var/lib/lpm/` — planned for Phase 6).

---

## 3. Authentication & Authorization

**None.** The project has no user authentication, no OAuth providers, no
API keys, no secrets management, no SSO integration.

Future considerations (post-v1.0):
- Package signing with a real GPG/Signify trust chain for repository
  authentication (`ROADMAP.md:39`)
- No login/auth is planned; ShreeOS is a general-purpose OS, not a
  multi-user cloud platform

---

## 4. Webhooks

**None configured.**

Planned:
- GitHub webhooks are not currently configured. CI is purely
  push/PR-triggered via GitHub Actions (`on: [push, pull_request]` in
  `.github/workflows/lint.yml:6-9`)
- No external service webhooks (Slack, Discord, etc.) are configured

---

## 5. CI/CD Pipeline

### Current Workflow: `lint.yml`

| Property | Value | Source |
|---|---|---|
| File | `.github/workflows/lint.yml` | `lint.yml:1-42` |
| Trigger | Push to `main` + any PR | `lint.yml:6-9` |
| Runner | `ubuntu-latest` | `lint.yml:12` |
| Jobs | `shellcheck`, `structure-check` | `lint.yml:11-42` |

**shellcheck job:**
```yaml
- uses: actions/checkout@v4
- run: sudo apt-get update && sudo apt-get install -y shellcheck
- run: find . -name '*.sh' ... | xargs shellcheck -x
- run: bash -n build.conf && bash -n scripts/common.sh
```

**structure-check job:**
```yaml
- uses: actions/checkout@v4
- run: verify README.md exists in every component directory
```

### Planned Workflows (from `IMPLEMENTATION_PLAN.md`)

| Workflow | Phase | Trigger | Purpose |
|---|---|---|---|
| `toolchain.yml` | Phase 1 | Push to `main` + PR | Build + cache cross-toolchain (binutils/gcc/glibc). Multi-hour build. |
| `kernel.yml` | Phase 3 | Push to `main` + PR | Build kernel against cached toolchain. |
| `iso.yml` | Phase 5+ | Push to `main` | Full `make all` chain, upload ISO as build artifact. |
| `release.yml` | Phase 11 | Tag push (`v*.*.*`) | Run `iso.yml` build + attach `.iso` + `SHA256SUMS.txt` to GitHub Release. |

---

## 6. Package Repository (Planned)

| Aspect | Detail | Source |
|---|---|---|
| Protocol | HTTPS | `IMPLEMENTATION_PLAN.md:224` |
| Index format | JSON (repo index written by `repo-tools/scripts/build-repo.sh`) | `IMPLEMENTATION_PLAN.md:224` |
| Package format | `.lpkg` — tar + zstd + JSON manifest | `ARCHITECTURE.md:53` |
| Signing (post-v1.0) | GPG or Signify trust chain | `ROADMAP.md:39` |
| Mirror/CDN (post-v1.0) | Binary package mirroring / CDN | `ROADMAP.md:38` |

---

## 7. External Build Dependencies (Downloaded Sources)

These are the upstream components the build system will download. Each will be
pinned to an exact version and verified by SHA-256 checksum. No versions are
set yet (all `VER_*` variables in `build.conf` are empty — `build.conf:28-31`).

| Component | Source URL Pattern | Planned Version Source |
|---|---|---|
| **binutils** | `https://ftp.gnu.org/gnu/binutils/binutils-<VER>.tar.xz` | `VER_BINUTILS` in `build.conf` |
| **GCC** | `https://ftp.gnu.org/gnu/gcc/gcc-<VER>/gcc-<VER>.tar.xz` | `VER_GCC` in `build.conf` |
| **glibc** | `https://ftp.gnu.org/gnu/glibc/glibc-<VER>.tar.xz` | `VER_GLIBC` in `build.conf` |
| **Linux kernel** | `https://github.com/torvalds/linux/archive/refs/tags/v<VER>.tar.gz` | `VER_LINUX_KERNEL` in `build.conf` |
| **Coreutils, bash, util-linux** (Phase 2) | Various GNU/nongnu.org URLs | `base-system/packages.list` (planned) |

The download mechanism (`lumen_fetch` in `scripts/common.sh:19-34`) uses:
```bash
curl -fL --retry 3 -o "${dest}.part" "${url}"
sha256sum verification before finalizing
```

---

## 8. Build Artifact Outputs

| Artifact | Format | Location | Phase |
|---|---|---|---|
| Cross-compiler | Directory tree under `$LUMEN_TOOLS` | `build/tools/` | Phase 1 |
| Sysroot | Headers + libs under `$LUMEN_SYSROOT` | `build/sysroot/` | Phase 1 |
| Kernel image | `bzImage` | `build/` (kernel build dir) | Phase 3 |
| Root filesystem | Directory tree under `$LUMEN_STAGE_ROOT` | `build/rootfs/` | Phase 4 |
| Bootable ISO | `.iso` (hybrid BIOS/UEFI) | `out/` | Phase 5 |
| Packages | `.lpkg` files | `out/packages/` or repo dir | Phase 6 |
| CI artifacts | ISO uploaded to GitHub Actions | `.github/workflows/*` | Phase 10+ |

---

## 9. Security Considerations

| Concern | Current State | Mitigation |
|---|---|---|
| Source integrity | Planned | Every upstream tarball verified by SHA-256 via `lumen_fetch` in `scripts/common.sh:29-33` |
| Package signing | Post-v1.0 | GPG/Signify trust chain for repository |
| CI secrets | None stored | No API keys, tokens, or secrets in the repository |
| Supply chain | Planned | Pinned versions in `build.conf`, no `latest` references |
| Credentials in code | None | No hardcoded credentials, tokens, or passwords |

---

## 10. Planned Integration Points Summary

| Integration | Type | When | Status |
|---|---|---|---|
| GitHub Actions `checkout@v4` | CI action | Now | Active |
| `shellcheck` (apt) | CI tool | Now | Active |
| `curl` HTTPS downloads | Build-time | Phase 1+ | Planned |
| GNU FTP mirrors (binutils, gcc, glibc) | Source fetch | Phase 1 | Planned |
| `torvalds/linux` GitHub mirror | Source fetch | Phase 3 | Planned |
| GitHub Actions caching | CI optimization | Phase 1 | Planned |
| GitHub Releases API | Artifact publishing | Phase 11 | Planned |
| HTTPS package repository | Runtime | Phase 6 | Planned |

---

*This document was generated by exploring the repository at commit `1564a4c`. The project is in early scaffold stage — no external APIs, databases, auth providers, or webhooks are currently integrated. Everything listed under "Planned" is derived from `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, and `IMPLEMENTATION_PLAN.md`.*
