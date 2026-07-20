# `.lpkg` Package Format — Specification v1

## Overview

`.lpkg` is the binary package format for ShreeOS. Each file is a
gzip-compressed tar archive containing a JSON manifest plus the
files to be installed.

## File Layout

```
archive.tar.gz
├── manifest.json          # required, first entry
├── usr/bin/foo            # installed to /
├── usr/lib/libfoo.so.1
└── etc/foo.conf
```

## manifest.json

```json
{
  "name":        "package-name",
  "version":     "1.2.3",
  "description": "Human-readable description",
  "dependencies":  ["dep-a", "dep-b >= 1.0"],
  "conflicts":     ["other-pkg"],
  "files":         ["/usr/bin/foo", "/usr/lib/libfoo.so.1"],
  "checksums": {
    "/usr/bin/foo":          "sha256hex",
    "/usr/lib/libfoo.so.1":  "sha256hex"
  },
  "install_hooks": {
    "pre":   "/bin/sh -c '...'",
    "post":  "/bin/sh -c '...'",
    "remove": "/bin/sh -c '...'"
  }
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Package name (lowercase, hyphens) |
| `version` | string | yes | Semantic version |
| `description` | string | no | Human-readable summary |
| `dependencies` | array of strings | no | Package deps (`name` or `name >= version`) |
| `conflicts` | array of strings | no | Conflicting packages |
| `files` | array of strings | yes | Files belonging to this package |
| `checksums` | object | no | SHA-256 per file (key = path, value = hex) |
| `install_hooks` | object | no | Pre/post install/remove shell commands |

## Compression

**v1:** gzip (via `tar.gz`).  
**Planned:** zstd (`.tar.zst`) for faster decompression.

## Repository Index

Repositories use a `repo.json` index at the root:

```json
{
  "name": "shreeos-main",
  "packages": {
    "package-name": {
      "version": "1.2.3",
      "filename": "pool/main/package-name-1.2.3.lpkg",
      "sha256": "hex",
      "description": "...",
      "dependencies": ["dep-a"]
    }
  }
}
```

## On-Disk Database

Installed packages are recorded under `/var/lib/lpm/installed/<name>/`:

```
/var/lib/lpm/
├── repo.json               # cached repo index
└── installed/
    └── package-name/
        └── manifest.json   # copy of install-time manifest
```
