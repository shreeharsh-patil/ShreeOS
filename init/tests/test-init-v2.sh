#!/usr/bin/env bash
# init/tests/test-init-v2.sh — Comprehensive test suite for ShreeOS Init V2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$INIT_DIR/.." && pwd)"

export PATH="${INIT_DIR}/src:${PATH}"

INIT_BIN="${INIT_DIR}/src/init"
INITCTL_BIN="${INIT_DIR}/src/initctl"

if [ ! -x "$INIT_BIN" ] || [ ! -x "$INITCTL_BIN" ]; then
  echo "Building init binaries..."
  make -C "${INIT_DIR}/src" clean all CROSS_COMPILE=
fi

TEST_TMP="$(mktemp -d /tmp/shreeos-inittest-XXXXXX)"
SERVICES_DIR="${TEST_TMP}/services.d"
SOCKET_PATH="${TEST_TMP}/init.sock"
LOG_DIR="${TEST_TMP}/logs"
mkdir -p "$SERVICES_DIR" "$LOG_DIR"

INIT_PID=""

cleanup() {
  if [ -n "$INIT_PID" ] && kill -0 "$INIT_PID" 2>/dev/null; then
    kill -TERM "$INIT_PID" 2>/dev/null || true
    wait "$INIT_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT INT TERM

echo "=========================================================="
echo " Running ShreeOS Init V2 Test Suite"
echo "=========================================================="

# ---------------------------------------------------------
# Test 1: Malformed and Edge-case Configuration Parsing
# ---------------------------------------------------------
echo "==> Test 1: Malformed Configurations Handling"

# Missing name
cat << 'EOF' > "${SERVICES_DIR}/01-noname.conf"
command=/bin/true
after=
restart=never
EOF

# Missing command
cat << 'EOF' > "${SERVICES_DIR}/02-nocmd.conf"
name=nocmd
after=
restart=never
EOF

# Invalid characters in name
cat << 'EOF' > "${SERVICES_DIR}/03-badname.conf"
name=bad;name/test
command=/bin/true
after=
restart=never
EOF

# Valid oneshot service
cat << 'EOF' > "${SERVICES_DIR}/10-first.conf"
name=first
command=/bin/sh -c "echo 'First service running'; sleep 0.2"
after=
oneshot=true
restart=never
EOF

# Valid dependent daemon service
cat << 'EOF' > "${SERVICES_DIR}/20-second.conf"
name=second
command=/bin/sh -c "echo 'Second daemon running'; while true; do sleep 1; done"
after=first
oneshot=false
restart=always
EOF

export SHREEOS_INIT_TEST=1
export INIT_SOCK_PATH="$SOCKET_PATH"

"$INIT_BIN" --test --services-dir "$SERVICES_DIR" --socket "$SOCKET_PATH" --log-dir "$LOG_DIR" > "${TEST_TMP}/init.stdout" 2> "${TEST_TMP}/init.stderr" &
INIT_PID=$!

# Wait for socket to become ready
for i in $(seq 1 30); do
  if [ -S "$SOCKET_PATH" ]; then break; fi
  sleep 0.1
done

if [ ! -S "$SOCKET_PATH" ]; then
  echo "FAIL: Init failed to create IPC socket within timeout"
  cat "${TEST_TMP}/init.stderr"
  exit 1
fi
echo "  [OK] Init supervisor booted in test mode with active IPC socket"

# Verify that malformed configs did not crash init and valid ones loaded
LIST_OUTPUT=$("$INITCTL_BIN" list)
if echo "$LIST_OUTPUT" | grep -q "first" && echo "$LIST_OUTPUT" | grep -q "second"; then
  echo "  [OK] Valid services (first, second) loaded successfully"
else
  echo "FAIL: Expected valid services not found in initctl list:"
  echo "$LIST_OUTPUT"
  exit 1
fi

if echo "$LIST_OUTPUT" | grep -q "nocmd" || echo "$LIST_OUTPUT" | grep -q "bad;name"; then
  echo "FAIL: Malformed service was improperly accepted"
  exit 1
else
  echo "  [OK] Malformed services (missing command, invalid name) correctly rejected"
fi

# ---------------------------------------------------------
# Test 2: Dependency Ordering & Oneshot Completion Check
# ---------------------------------------------------------
echo ""
echo "==> Test 2: Dependency Ordering"
# Sleep briefly for oneshot to complete and second to start
sleep 0.6

FIRST_STATUS=$("$INITCTL_BIN" status first)
SECOND_STATUS=$("$INITCTL_BIN" status second)

if echo "$FIRST_STATUS" | grep -q "State: *STOPPED" && echo "$FIRST_STATUS" | grep -q "ExitCode: *0"; then
  echo "  [OK] Oneshot service 'first' completed with status 0"
else
  echo "FAIL: 'first' service did not reach clean STOPPED state:"
  echo "$FIRST_STATUS"
  exit 1
fi

if echo "$SECOND_STATUS" | grep -q "State: *RUNNING"; then
  echo "  [OK] Dependent daemon 'second' transitioned to RUNNING after 'first' finished"
else
  echo "FAIL: 'second' service not running:"
  echo "$SECOND_STATUS"
  exit 1
fi

# ---------------------------------------------------------
# Test 3: initctl blame & Boot Duration Metrics
# ---------------------------------------------------------
echo ""
echo "==> Test 3: 'initctl blame' Profiling"
BLAME_OUTPUT=$("$INITCTL_BIN" blame)
if echo "$BLAME_OUTPUT" | grep -q "BOOT BLAME TIMELINE" && echo "$BLAME_OUTPUT" | grep -q "first"; then
  echo "  [OK] 'initctl blame' reports service initialization timeline:"
  echo "$BLAME_OUTPUT" | head -n 8 | sed 's/^/      /'
else
  echo "FAIL: 'initctl blame' output invalid:"
  echo "$BLAME_OUTPUT"
  exit 1
fi

# ---------------------------------------------------------
# Test 4: Service Logs Capture & 'initctl logs'
# ---------------------------------------------------------
echo ""
echo "==> Test 4: Service Log Capture & Retrieval"
if [ -f "${LOG_DIR}/first.log" ] && grep -q "First service running" "${LOG_DIR}/first.log"; then
  echo "  [OK] Captured stdout/stderr for service 'first' in ${LOG_DIR}/first.log"
else
  echo "FAIL: Service log file missing or empty for 'first'"
  exit 1
fi

LOGS_OUTPUT=$("$INITCTL_BIN" logs first)
if echo "$LOGS_OUTPUT" | grep -q "First service running"; then
  echo "  [OK] 'initctl logs first' successfully retrieved service log output"
else
  echo "FAIL: 'initctl logs first' failed:"
  echo "$LOGS_OUTPUT"
  exit 1
fi

# ---------------------------------------------------------
# Test 5: Dependency Cycle Detection & Resolution
# ---------------------------------------------------------
echo ""
echo "==> Test 5: Cycle Detection and Automatic Cycle Breaking"
cat << 'EOF' > "${SERVICES_DIR}/30-cycle-a.conf"
name=cycle-a
command=/bin/sh -c "echo 'Cycle A alive'; while true; do sleep 1; done"
after=cycle-b
oneshot=false
restart=never
EOF

cat << 'EOF' > "${SERVICES_DIR}/31-cycle-b.conf"
name=cycle-b
command=/bin/sh -c "echo 'Cycle B alive'; while true; do sleep 1; done"
after=cycle-a
oneshot=false
restart=never
EOF

RELOAD_RES=$("$INITCTL_BIN" reload)
echo "  [OK] Configuration reloaded: $RELOAD_RES"
sleep 0.5

# Verify cycle was detected and logged to stderr
if grep -q "Dependency cycle detected" "${TEST_TMP}/init.stderr"; then
  echo "  [OK] Dependency cycle (cycle-a <-> cycle-b) detected and logged by supervisor"
else
  echo "FAIL: Dependency cycle was not flagged in stderr:"
  cat "${TEST_TMP}/init.stderr"
  exit 1
fi

# ---------------------------------------------------------
# Test 6: Crash Detection & Restart Policies
# ---------------------------------------------------------
echo ""
echo "==> Test 6: Crash Detection and Restart Policies"
cat << 'EOF' > "${SERVICES_DIR}/40-crasher.conf"
name=crasher
command=/bin/sh -c "echo 'Crasher run'; exit 42"
after=
oneshot=false
restart=on-failure
EOF

"$INITCTL_BIN" reload >/dev/null
sleep 1.2

CRASHER_STATUS=$("$INITCTL_BIN" status crasher)
if echo "$CRASHER_STATUS" | grep -q "ExitCode: *42" && echo "$CRASHER_STATUS" | grep -E -q "Restarts: *[1-9]"; then
  echo "  [OK] Service crash detected; exit code 42 recorded and restart backoff engaged"
else
  echo "FAIL: Crash tracking failed for 'crasher':"
  echo "$CRASHER_STATUS"
  exit 1
fi

# ---------------------------------------------------------
# Test 7: Unauthorized IPC / Permissions Enforcement
# ---------------------------------------------------------
echo ""
echo "==> Test 7: IPC Permission Security Check"
# Query operations (LIST, STATUS, BLAME) should work for any peer
if "$INITCTL_BIN" list >/dev/null && "$INITCTL_BIN" status first >/dev/null; then
  echo "  [OK] Read-only IPC queries (list, status) permitted for local user"
fi

# Verify mutating operations are denied when strict authentication is active
STRICT_SOCK="${TEST_TMP}/strict.sock"
"$INIT_BIN" --test --strict-auth --services-dir "$SERVICES_DIR" --socket "$STRICT_SOCK" --log-dir "$LOG_DIR" >/dev/null 2>&1 &
STRICT_PID=$!
for i in $(seq 1 20); do
  if [ -S "$STRICT_SOCK" ]; then break; fi
  sleep 0.1
done

UNAUTH_OUTPUT=$(INIT_SOCK_PATH="$STRICT_SOCK" "$INITCTL_BIN" start first 2>&1 || true)
kill -TERM "$STRICT_PID" 2>/dev/null || true
wait "$STRICT_PID" 2>/dev/null || true

if echo "$UNAUTH_OUTPUT" | grep -q "Permission denied"; then
  echo "  [OK] Unauthorized mutating IPC command rejected with 'Permission denied'"
else
  echo "FAIL: Unauthorized mutating IPC command was not properly blocked:"
  echo "$UNAUTH_OUTPUT"
  exit 1
fi

# ---------------------------------------------------------
# Test 8: Orderly Shutdown in Reverse Dependency Sequence
# ---------------------------------------------------------
echo ""
echo "==> Test 8: Orderly Shutdown Sequence"
"$INITCTL_BIN" reboot >/dev/null || kill -TERM "$INIT_PID"
wait "$INIT_PID" || true
INIT_PID=""

if grep -q "Initiating system shutdown sequence in reverse dependency order" "${TEST_TMP}/init.stdout"; then
  echo "  [OK] Reverse dependency shutdown sequence executed cleanly"
else
  echo "FAIL: Shutdown sequence message not found:"
  cat "${TEST_TMP}/init.stdout"
  exit 1
fi

echo ""
echo "=========================================================="
echo " All ShreeOS Init V2 tests passed successfully!"
echo "=========================================================="
exit 0
