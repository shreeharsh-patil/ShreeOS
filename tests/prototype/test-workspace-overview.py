#!/usr/bin/env python3
"""Check parsing of X11 workspace/window inventories used by the overview."""
from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import sys
import types
from pathlib import Path


def load_overview_module():
    gi = types.ModuleType("gi")
    gi.require_version = lambda *_args: None
    repository = types.ModuleType("gi.repository")
    repository.Gdk = object()
    repository.GLib = object()
    repository.Gtk = object()
    gi.repository = repository
    sys.modules["gi"] = gi
    sys.modules["gi.repository"] = repository
    path = (Path(__file__).resolve().parents[2]
            / "prototype/debian-live/profiles/desktop/includes.chroot/usr/local/bin/shreeos-overview")
    loader = SourceFileLoader("shreeos_overview", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    overview = load_overview_module()
    desktops = overview.read_workspaces(
        "0 * DG: 1920x1080 VP: 0,0 WA: 0,0 1920x1046 N=Workspace 1\n"
        "1 - DG: 1920x1080 VP: 0,0 WA: 0,0 1920x1046 N=Focus & notes\n"
        "malformed\n"
    )
    expected_desktops = [(0, "Workspace 1", True), (1, "Focus & notes", False)]
    if desktops != expected_desktops:
        raise SystemExit(f"FAIL: workspace parsing returned {desktops!r}")

    windows = overview.read_windows(
        "0x03e00007  0  1356  10 20 800 600 firefox-esr.Firefox localhost ShreeOS desktop brief\n"
        "0x03e00009 -1  1450  0 0 400 300 utility.Dialog localhost Keep on all workspaces\n"
        "broken line\n"
    )
    expected_windows = [
        ("0x03e00007", 0, "firefox-esr.Firefox", "ShreeOS desktop brief"),
        ("0x03e00009", -1, "utility.Dialog", "Keep on all workspaces"),
    ]
    if windows != expected_windows:
        raise SystemExit(f"FAIL: window parsing returned {windows!r}")
    print("Workspace Overview parser contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
