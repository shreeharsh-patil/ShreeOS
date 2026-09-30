#!/usr/bin/env python3
"""Exercise Shree Search's arithmetic parser without requiring a display server."""
from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import sys
import types
from pathlib import Path


def load_search_module():
    gi = types.ModuleType("gi")
    gi.require_version = lambda *_args: None
    repository = types.ModuleType("gi.repository")
    repository.Gdk = object()
    repository.Gio = object()
    repository.GLib = object()
    repository.Gtk = object()
    repository.Pango = object()
    gi.repository = repository
    sys.modules["gi"] = gi
    sys.modules["gi.repository"] = repository
    path = (Path(__file__).resolve().parents[2]
            / "prototype/debian-live/profiles/desktop/includes.chroot/usr/local/bin/shreeos-search")
    loader = SourceFileLoader("shreeos_search", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    search = load_search_module()
    cases = {
        "2 + 3 * 4": 14,
        "(10 - 4) / 2": 3,
        "-5 + 8": 3,
        "2 ** 8": 256,
        "1 / 0": None,
        "2 ** 1000": None,
        "1000000 ** 8": None,
        "(-1) ** 0.5": None,
        "True + 1": None,
        "__import__('os').system('whoami')": None,
        "[1, 2, 3]": None,
    }
    for expression, expected in cases.items():
        actual = search.calculator_value(expression)
        if actual != expected:
            raise SystemExit(f"FAIL: {expression!r} returned {actual!r}; expected {expected!r}")
    print("Shree Search calculator contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
