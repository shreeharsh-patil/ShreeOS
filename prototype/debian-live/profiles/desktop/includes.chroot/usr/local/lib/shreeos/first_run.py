#!/usr/bin/python3
"""ShreeOS first-login welcome window for installed desktop sessions."""
from __future__ import annotations

import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk


MARKER = Path.home() / ".config/shreeos/first-run-complete"
BLUE = "#2878ff"


class FirstRun(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="Welcome to ShreeOS")
        self.set_default_size(760, 560)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("delete-event", self._finish)

        css = Gtk.CssProvider()
        css.load_from_data(b"""
            window { background: #111722; color: #edf3ff; }
            .welcome-title { font-size: 30px; font-weight: 600; }
            .welcome-subtitle { color: #a8b5cb; font-size: 14px; }
            .welcome-card { background: #1a2331; border: 1px solid #2c3b50; border-radius: 12px; }
            .welcome-card-title { font-size: 16px; font-weight: 600; }
            .welcome-card-copy { color: #a8b5cb; }
            button.suggested-action { background: #2878ff; color: white; border-radius: 8px; padding: 9px 18px; }
            button { border-radius: 8px; padding: 7px 12px; }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        outer.set_border_width(30)
        self.add(outer)

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        hero.set_halign(Gtk.Align.CENTER)
        logo = Gtk.Image.new_from_icon_name("shreeos", Gtk.IconSize.DIALOG)
        logo.set_pixel_size(72)
        hero.pack_start(logo, False, False, 0)
        title = Gtk.Label(label="Welcome to ShreeOS")
        title.get_style_context().add_class("welcome-title")
        subtitle = Gtk.Label(label="A calmer way to compute. Your desktop is ready.")
        subtitle.get_style_context().add_class("welcome-subtitle")
        hero.pack_start(title, False, False, 0)
        hero.pack_start(subtitle, False, False, 0)
        outer.pack_start(hero, False, False, 0)

        cards = Gtk.Grid(column_spacing=14, row_spacing=14)
        cards.set_column_homogeneous(True)
        cards.attach(self._card(
            "Make it yours",
            "Choose a light or dark look, adjust your dock, and tune display and sound settings.",
            "Open Control Center",
            "/usr/local/bin/shreeos-control-center",
        ), 0, 0, 1, 1)
        cards.attach(self._card(
            "Find your apps",
            "Browse available software and install tools when you are ready.",
            "Open ShreeOS Software",
            "/usr/local/bin/shreeos-store",
        ), 1, 0, 1, 1)
        cards.attach(self._card(
            "Explore the desktop",
            "Use Super+Space to find apps and files, and Super+Up to see your workspaces.",
            "Got it",
            None,
        ), 0, 1, 2, 1)
        outer.pack_start(cards, True, True, 0)

        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        footer.set_halign(Gtk.Align.END)
        finish = Gtk.Button(label="Finish setup")
        finish.get_style_context().add_class("suggested-action")
        finish.connect("clicked", self._finish)
        footer.pack_end(finish, False, False, 0)
        outer.pack_end(footer, False, False, 0)

    def _card(self, heading: str, copy: str, button_label: str,
              command: str | None) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.get_style_context().add_class("welcome-card")
        card.set_border_width(18)
        title = Gtk.Label(label=heading, xalign=0)
        title.get_style_context().add_class("welcome-card-title")
        description = Gtk.Label(label=copy, xalign=0, yalign=0)
        description.set_line_wrap(True)
        description.set_max_width_chars(40)
        description.get_style_context().add_class("welcome-card-copy")
        button = Gtk.Button(label=button_label)
        if command is not None:
            button.connect("clicked", self._launch, command)
        else:
            button.connect("clicked", self._finish)
        card.pack_start(title, False, False, 0)
        card.pack_start(description, True, True, 0)
        card.pack_end(button, False, False, 0)
        return card

    @staticmethod
    def _launch(_button: Gtk.Button, command: str) -> None:
        subprocess.Popen([command], start_new_session=True)

    def _finish(self, *_args: object) -> bool:
        MARKER.parent.mkdir(parents=True, exist_ok=True)
        MARKER.touch(exist_ok=True)
        self.destroy()
        return True


def main() -> int:
    window = FirstRun()
    window.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
