# Package Manager

`lpm` — custom package manager for ShreeOS. Installs, removes, and queries `.lpkg` packages.

## Layout

```
pkgmanager/
├── spec/lpkg-format.md    # .lpkg format specification
├── src/                    # lpm CLI source (C)
│   ├── main.c              # CLI entry point
│   ├── json.c/h            # Minimal JSON parser
│   ├── manifest.c/h         # Package manifest
│   ├── install.c            # Install/remove logic
│   ├── resolve.c            # Query/list commands
│   └── Makefile
├── tests/
│   ├── test-manifest.c     # Manifest parse/save/load tests
│   └── Makefile
└── README.md
```

## Usage

```bash
lpm install package.lpkg
lpm remove  package-name
lpm query   package-name
lpm list
```

## Building

```bash
make -C pkgmanager/src                # host build
make -C pkgmanager/src CROSS_COMPILE=x86_64-shreeos-linux-gnu-  # target
```

## Tests

```bash
make -C pkgmanager/tests test
```
