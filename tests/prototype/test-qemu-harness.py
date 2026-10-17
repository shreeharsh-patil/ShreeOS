#!/usr/bin/env python3
"""Guard live QEMU serial monitoring and screenshot failure handling."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "tests/prototype/test-iso.sh"


class QemuHarnessTests(unittest.TestCase):
    def test_serial_console_is_streamed_while_qemu_runs(self):
        script = HARNESS.read_text(encoding="utf-8")
        self.assertIn("-serial stdio -no-reboot", script)
        self.assertIn('>"$log" 2>"$emulator_log" &', script)
        self.assertNotIn('-serial "file:$log"', script)

    def test_timeout_and_missing_capture_fail_before_image_parsing(self):
        script = HARNESS.read_text(encoding="utf-8")
        self.assertIn("def read_prompt():", script)
        self.assertIn("QEMU monitor prompt timed out", script)
        self.assertIn("QEMU did not create desktop screenshot", script)
        self.assertIn('kill -TERM "$emulator_pid"', script)
        wait = script.index('wait "$emulator_pid"')
        nonzero_exit = script.index('if [ "$status" -ne 0 ]', wait)
        boot_marker = script.index("if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK'", nonzero_exit)
        screenshot_guard = script.index('if [ ! -s "$screen_dump" ]', boot_marker)
        screenshot_read = script.index("data = path.read_bytes()", screenshot_guard)

        self.assertLess(wait, nonzero_exit)
        self.assertLess(nonzero_exit, boot_marker)
        self.assertLess(boot_marker, screenshot_guard)
        self.assertLess(screenshot_guard, screenshot_read)


if __name__ == "__main__":
    unittest.main()
