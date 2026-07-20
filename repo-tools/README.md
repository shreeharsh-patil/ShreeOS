# Repository Tools

Tools for building `.lpkg` packages and generating repository indices for `lpm`.

## Layout

```
repo-tools/
├── scripts/
│   └── build-repo.sh    # Scans staging dir, builds .lpkg files, writes repo.json
└── README.md
```

## Usage

```bash
bash repo-tools/scripts/build-repo.sh \
  build/staging/packages \
  out/repo
```

## Output

- `pool/<name>-<version>.lpkg` — binary packages
- `repo.json` — repository index
