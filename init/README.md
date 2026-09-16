# Init System & Service Supervisor

Custom PID 1 service supervisor and init system written in C for ShreeOS.

The default service set includes `shreed`, the foreground ShreeOS hardware
service. It starts after early sysinit and is restarted by PID 1 if it exits.

## Features

- **Essential Virtual Filesystems:** Mounts `/proc`, `/sys`, `/dev`, `/run`, `/dev/pts`, `/dev/shm`, `/tmp`.
- **Declarative Services:** Service definitions loaded from `/etc/services.d/*.conf`.
- **Dependency Ordering:** Startup sequencing based on `after=` directives.
- **Zombie Process Reaping:** Asynchronous, non-blocking `SIGCHLD` handler (`waitpid(-1, WNOHANG)`) that reaps all orphaned children.
- **Service State Machine:** Supports `STOPPED`, `STARTING`, `RUNNING`, `FAILED`, `STOPPING`.
- **Restart Policies:** `always`, `on-failure`, `never` with exponential backoff / rate-limiting to prevent CPU spinning.
- **Multi-Stage Clean Shutdown:** 
  1. Gracefully stop supervised services (`SIGTERM`) in reverse dependency order.
  2. Broadcast `SIGTERM` to remaining processes, then `SIGKILL`.
  3. Sync filesystems (`sync()`).
  4. Remount root filesystem read-only (`MS_REMOUNT | MS_RDONLY`).
  5. Hardware reboot / poweroff / halt.

## Layout

```
init/
├── src/
│   ├── init.c          # PID 1 supervisor implementation
│   ├── initctl.c       # Control CLI (status, reload, reboot, poweroff, halt)
│   └── Makefile        # Cross-compilation targets
├── services/           # Service definition templates (.conf)
│   ├── 00-sysinit.conf
│   ├── 10-hostname.conf
│   ├── 20-network.conf
│   └── 90-console.conf
└── README.md
```

## Service Definition Format

Example `/etc/services.d/network.conf`:

```ini
name=network
command=/bin/sh -c "ip link set lo up"
after=hostname
restart=never
oneshot=true
critical=false
```

## Building

```bash
# Cross-compile (from repo root):
export CROSS_COMPILE=x86_64-shreeos-linux-gnu-
make -C init/src

# Or via Makefile:
make rootfs
```
