# ShreeOS Hardware Service

`shreed` is the native ShreeOS hardware service. It exposes local, read-only
health and hardware inventory interfaces; it performs no device control.

## IPC

The daemon listens on `/run/shreed.sock`.  Each request and response is a
length-prefixed JSON object: a four-byte network-byte-order payload length,
followed by UTF-8 JSON.  Payloads are capped at 1024 bytes.

Supported requests:

```json
{"action":"ping"}
{"action":"status"}
{"action":"subscribe"}
{"action":"hardware"}
{"action":"cpu"}
{"action":"gpu"}
{"action":"memory"}
{"action":"disks"}
{"action":"pci"}
{"action":"usb"}
{"action":"network"}
{"action":"interfaces"}
{"action":"ethernet"}
```

`subscribe` keeps the connection registered for asynchronous events. Network
changes are received from the Linux rtnetlink API and emit
`NETWORK_INTERFACE_ADDED`, `NETWORK_INTERFACE_REMOVED`, `NETWORK_CONNECTED`,
`NETWORK_DISCONNECTED`, and `IP_ADDRESS_CHANGED` event objects.

Optional device modules use the same event stream. BlueZ device changes emit
`BLUETOOTH_DEVICE_ADDED`/`BLUETOOTH_DEVICE_REMOVED`; ALSA changes emit
`AUDIO_DEVICE_ADDED`/`AUDIO_DEVICE_REMOVED` and `VOLUME_CHANGED`; sysfs power
changes emit `BATTERY_CHANGED`, `BATTERY_LOW`, `POWER_CONNECTED`,
`POWER_DISCONNECTED`, and `BRIGHTNESS_CHANGED`. Missing optional hardware is
reported as unavailable and never causes the daemon or boot to fail.

Network queries use kernel sysfs, `getifaddrs(3)`, `/proc/net/route`, and
`/etc/resolv.conf`; no NetworkManager dependency is required. The boot service
brings up Ethernet devices and tries `dhcpcd`, falling back to BusyBox
`udhcpc`. Failure is explicitly non-fatal so it cannot block boot.

The hardware requests read kernel-provided `/proc` and `/sys` data only. They
return `null`, empty lists, or zero counts when an interface or device is not
available; no values are inferred from external command output.

The socket mode is `0666` because every implemented operation is read-only and
contains no sensitive data.  The daemon limits active clients, validates peer
credentials, validates every frame and JSON object, and never logs request
payloads.

## Build and test

```bash
make -C hardware
make -C hardware test
```
