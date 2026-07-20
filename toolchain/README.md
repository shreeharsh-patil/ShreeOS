# Cross-Compilation Toolchain

Build scripts for the `x86_64-shreeos-linux-gnu-` cross-compilation toolchain (binutils, GCC, glibc, Linux kernel headers).

## Layout

```
toolchain/
├── scripts/
│   ├── common.sh                    # Shared helpers
│   ├── sources.list                 # Pinned URLs + SHA-256
│   ├── build-binutils-pass1.sh      # Binutils (Pass 1)
│   ├── build-gcc-pass1.sh           # GCC (Pass 1)
│   ├── install-kernel-headers.sh    # Linux kernel headers
│   ├── build-glibc.sh               # glibc C library
│   ├── build-libstdcpp.sh           # libstdc++ (GCC runtime)
│   ├── build-gcc-pass2.sh           # GCC (Pass 2)
│   ├── stage-toolchain.sh           # Final staging
│   └── build-all.sh                 # Orchestrator (all 7 steps)
└── README.md
```

## Building

```bash
bash toolchain/scripts/build-all.sh
# or via top-level Makefile:
make toolchain
```

## Verification

```bash
bash tests/smoke/test-toolchain.sh
```
