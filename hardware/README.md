# ShreeOS Hardware Service

`shreed` is the native ShreeOS hardware-service foundation.  Phase 1 exposes
only a local, read-only health interface; it deliberately performs no hardware
probing or device control.

## IPC

The daemon listens on `/run/shreed.sock`.  Each request and response is a
length-prefixed JSON object: a four-byte network-byte-order payload length,
followed by UTF-8 JSON.  Payloads are capped at 1024 bytes.

Supported requests:

```json
{"action":"ping"}
{"action":"status"}
{"action":"subscribe"}
```

`subscribe` keeps the connection registered for future hardware events.  No
hardware events are emitted in Phase 1.

The socket mode is `0666` because every implemented operation is read-only and
contains no sensitive data.  The daemon limits active clients, validates peer
credentials, validates every frame and JSON object, and never logs request
payloads.

## Build and test

```bash
make -C hardware
make -C hardware test
```
