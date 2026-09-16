# Init System

Custom minimal PID 1 init written in C. Mounts proc/sys/dev, spawns a shell on the console, handles reboot on SIGTERM.

## Layout

```
init/
├── src/
│   ├── init.c      # PID 1 implementation
│   └── Makefile    # Cross-compilation
├── services/       # Service definitions (empty — future)
├── tests/          # Unit tests (empty — future)
└── README.md
```

## Building

```bash
# Cross-compile (from repo root):
export CROSS_COMPILE=x86_64-shreeos-linux-gnu-
make -C init/src

# Or via Makefile:
make rootfs
```

## Integration

The init binary is installed to `/sbin/init` by `rootfs/scripts/make-rootfs.sh`.
