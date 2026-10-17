#!/usr/bin/env python3
"""Guard live QEMU serial monitoring and screenshot failure handling."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "tests/prototype/test-iso.sh"
PERFORMANCE_HARNESS = ROOT / "tests/prototype/test-performance-report.sh"


class QemuHarnessTests(unittest.TestCase):
    def test_serial_console_is_streamed_while_qemu_runs(self):
        script = HARNESS.read_text(encoding="utf-8")
        self.assertIn("-serial stdio -no-reboot", script)
        self.assertIn('>"$log" 2>"$emulator_log" &', script)
        self.assertNotIn('-serial "file:$log"', script)

    def test_timeout_and_missing_capture_fail_before_image_parsing(self):
        script = HARNESS.read_text(encoding="utf-8")
        self.assertIn("if [ \"$PROFILE\" = plasma ]; then qemu_timeout=1800; fi", script)
        self.assertIn("def read_prompt():", script)
        self.assertIn("QEMU monitor prompt timed out", script)
        self.assertIn("QEMU did not create desktop screenshot", script)
        self.assertIn("SHREEOS_BOOT_CHECK: FAIL:", script)
        self.assertIn("local screenshot_captured=0 cleanup_signal_sent=0 boot_check_failed=0", script)
        self.assertIn('setsid xvfb-run', script)
        self.assertIn('kill -TERM -- "-$emulator_pid"', script)
        self.assertIn("for attempt in range(4):", script)
        self.assertIn("def boot_marker_seen():", script)
        self.assertIn('"SHREEOS_LIVE_BOOT_OK" in contents', script)
        boot_wait = script.index("while ! grep -Fq 'SHREEOS_LIVE_BOOT_OK'")
        boot_failure = script.index("if grep -Fq 'SHREEOS_BOOT_CHECK: FAIL:'", boot_wait)
        wait = script.index('wait "$emulator_pid"')
        nonzero_exit = script.index('if [ "$status" -ne 0 ]', wait)
        boot_marker = script.index("if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK'", nonzero_exit)
        screenshot_guard = script.index('if [ ! -s "$screen_dump" ]', boot_marker)
        screenshot_read = script.index("data = image_path.read_bytes()", screenshot_guard)

        self.assertLess(boot_wait, boot_failure)
        self.assertLess(boot_failure, wait)
        self.assertLess(wait, nonzero_exit)
        self.assertLess(nonzero_exit, boot_marker)
        self.assertLess(boot_marker, screenshot_guard)
        self.assertLess(screenshot_guard, screenshot_read)

    def test_successful_desktop_capture_stops_the_live_qemu_group(self):
        script = HARNESS.read_text(encoding="utf-8")
        screenshot = script.index("screenshot_captured=1")
        cleanup = script.index('kill -TERM -- "-$emulator_pid"', screenshot)
        wait = script.index('wait "$emulator_pid"', cleanup)
        normalize = script.index('if (( cleanup_signal_sent ))', wait)

        self.assertIn("local screenshot_captured=0 cleanup_signal_sent=0", script)
        self.assertLess(screenshot, cleanup)
        self.assertLess(cleanup, wait)
        self.assertLess(wait, normalize)
        self.assertIn('[[ "$status" -eq 143 ]]', script)

    def test_screenshot_reveals_and_checks_the_auto_hidden_dock(self):
        script = HARNESS.read_text(encoding="utf-8")

        self.assertIn('command("mouse_move 0 10000")', script)
        self.assertIn('screen-before-dock.ppm', script)
        self.assertIn('changed_dock_pixels < max(256, width * 4)', script)
        self.assertIn('"unknown command"', script)
        capture_before = script.index('command(f"screendump {before_dock}")')
        move_pointer = script.index('command("mouse_move 0 10000")')
        capture_after = script.index('command(f"screendump {output}")', move_pointer)

        self.assertLess(capture_before, move_pointer)
        self.assertLess(move_pointer, capture_after)

    def test_performance_timeout_preserves_live_serial_and_guest_diagnostics(self):
        script = PERFORMANCE_HARNESS.read_text(encoding="utf-8")
        self.assertIn("setsid xvfb-run", script)
        self.assertIn('"-serial" "stdio" "-no-reboot"', script)
        self.assertIn("deadline=$((SECONDS + 1500))", script)
        self.assertIn("qemu_timeout=1800", script)
        self.assertIn('command("sendkey home")', script)
        self.assertIn('command("sendkey ret")', script)
        self.assertIn("for attempt in range(4):", script)
        self.assertIn('"SHREEOS_PERF_END" in Path(serial).read_text', script)
        self.assertIn('"$QEMU_LOG_DIR/grub-menu.ppm"', script)
        self.assertIn("serial=SHREEOSPERF", script)
        self.assertIn("id=perf-disk", script)
        self.assertIn("cache=none", script)
        self.assertIn("storage_write_mib_s", script)
        self.assertIn("storage_read_mib_s", script)
        self.assertIn("metric desktop_ready", script)
        self.assertIn('command("info status")', script)
        self.assertIn('command(f"screendump {output}")', script)
        self.assertIn('cp -f "$MONITOR_LOG" "$QEMU_LOG_DIR/monitor.log"', script)
        self.assertIn('cp -f "$SCREEN" "$QEMU_LOG_DIR/performance-screen.ppm"', script)
        self.assertIn("trap cleanup_capture EXIT", script)
        self.assertIn('kill -KILL -- "-$emulator_pid"', script)
        self.assertIn('save_capture_artifact "$MONITOR_LOG" monitor.log', script)

    def test_monitor_failure_triggers_process_group_cleanup_and_retains_logs(self):
        script = PERFORMANCE_HARNESS.read_text(encoding="utf-8")
        trap = script.index("trap cleanup_capture EXIT")
        qemu_start = script.index('"${qemu_invocation[@]}" >"$SERIAL"')
        cleanup = script.index("cleanup_capture() {")
        terminate = script.index('kill -TERM -- "-$emulator_pid"', cleanup)
        kill_after_grace = script.index('kill -KILL -- "-$emulator_pid"', terminate)
        wait = script.index('wait "$emulator_pid" 2>/dev/null || true', kill_after_grace)
        preserve_monitor_log = script.index('save_capture_artifact "$MONITOR_LOG" monitor.log', wait)
        remove_workdir = script.index('rm -rf -- "$TEST_DIR"', preserve_monitor_log)
        monitor_python = script.index('python3 - "$MONITOR" "$MENU_SCREEN" "$SERIAL"')

        self.assertIn("set -Eeuo pipefail", script)
        self.assertLess(trap, qemu_start)
        self.assertLess(qemu_start, monitor_python)
        self.assertLess(terminate, kill_after_grace)
        self.assertLess(kill_after_grace, wait)
        self.assertLess(wait, preserve_monitor_log)
        self.assertLess(preserve_monitor_log, remove_workdir)

    def test_performance_cgroup_snapshot_and_qemu_pid_capture_bracket_the_guest(self):
        script = PERFORMANCE_HARNESS.read_text(encoding="utf-8")
        self.assertIn('"-pidfile" "$PIDFILE"', script)
        self.assertIn('qemu_pid="$(cat "$PIDFILE")"', script)
        self.assertIn("--process-pid \"$qemu_pid\"", script)
        disk_create = script.index('qemu-img create -q -f raw "$TARGET_DISK" 2G')
        snapshot = script.index('--snapshot "$TEST_DIR/environment-before.json"')
        launch = script.index('"${qemu_invocation[@]}" >"$SERIAL"')
        pid_read = script.index('qemu_pid="$(cat "$PIDFILE")"')
        process_capture = script.index("--process-pid \"$qemu_pid\"")
        guest_menu = script.index("sleep 20", process_capture)
        self.assertLess(disk_create, snapshot)
        self.assertLess(snapshot, launch)
        self.assertLess(launch, pid_read)
        self.assertLess(pid_read, process_capture)
        self.assertLess(process_capture, guest_menu)


if __name__ == "__main__":
    unittest.main()
