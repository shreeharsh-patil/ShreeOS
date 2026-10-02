# Desktop component integration matrix

This review compares elementary OS's GTK/Vala components with the KDE Plasma
stack selected for the Debian Live profile. The elementary GitHub organization
was enumerated through its public repository API on 2026-10-02 (153 public
repositories). Repository-level SPDX metadata is useful for triage, but it is
not a substitute for the license and copyright header of an individual file.
No elementary or KDE source files are copied by this integration.

## Selected architecture

The Debian Live `plasma` profile is the ShreeOS GUI architecture: Plasma and
KWin on X11, Qt/QML shell components, and official Debian packages for desktop
services and applications. The legacy source-built ShreeOS path remains
separate. ShreeOS-owned JavaScript layout, QML greeter, themes, artwork,
launchers, and configuration connect the installed packages. elementary
components were considered as engineering references; the Pantheon shell
components are not mixed into the Plasma session.

| ShreeOS feature | elementary source reviewed | KDE source reviewed | Selected ShreeOS approach | Compatibility and license decision |
|---|---|---|---|---|
| Dock, pinned apps, running windows | [elementary/dock](https://github.com/elementary/dock), `src/AppSystem/Launcher.vala`, `src/ItemManager.vala`, `src/WindowSystem/*` | [plasma-desktop](https://invent.kde.org/plasma/plasma-desktop), `applets/taskmanager/qml/Task.qml`, `TaskList.qml` | Plasma `org.kde.plasma.icontasks` panel widget, configured with pinned ShreeOS launchers | elementary/dock is Vala + GTK 4 + libadwaita + Granite 7; running-window and workspace tracking call Gala's `org.pantheon.gala` D-Bus API. Its Wayland panel/blur path uses the Pantheon shell protocol; its X11 path sets Mutter hints. These are not KWin integrations. KDE's task manager is native to Plasma. Repository license metadata: elementary GPL-3.0; inspected KDE task QML file SPDX: GPL-2.0-or-later. Use packages/configuration; no source copied. |
| Top panel, status area | [elementary/wingpanel](https://github.com/elementary/wingpanel), [elementary/panel-network](https://github.com/elementary/panel-network), [elementary/panel-sound](https://github.com/elementary/panel-sound), [elementary/panel-bluetooth](https://github.com/elementary/panel-bluetooth) | Plasma panels, system tray, `plasma-nm`, `plasma-pa`, BlueDevil | Plasma panel with Kickoff, active-app menu, spacer, system tray and date clock | Wingpanel indicators are built for Pantheon/GTK and its indicator protocols. Plasma applets use the same session services as the selected shell. Repo metadata: Wingpanel GPL-3.0; panel-network LGPL-2.1; panel-bluetooth LGPL-2.1; panel-sound has no repository-level SPDX assertion. |
| App launcher and search | [elementary/applications-menu](https://github.com/elementary/applications-menu) | Plasma Kickoff and KRunner | Kickoff menu; Meta+Space invokes KRunner | Keep launcher, desktop-file discovery and runner integrations in Plasma instead of adding a second GTK launcher. Repo metadata: applications-menu GPL-3.0. |
| Quick settings and indicators | [elementary/quick-settings](https://github.com/elementary/quick-settings), panel network/sound/Bluetooth projects | Plasma system tray, `plasma-nm`, `plasma-pa`, PowerDevil, BlueDevil | Native tray applets and their NetworkManager, PipeWire and BlueZ services | Pantheon quick-settings is GTK/Vala and expects Wingpanel/its indicators. Plasma tray modules are already wired to KDE services. Repo metadata: quick-settings GPL-3.0. |
| Settings | [elementary/settings](https://github.com/elementary/settings) and `settings-*` plug-ins | KDE System Settings and Plasma KCMs | KDE System Settings with ShreeOS defaults | elementary's settings shell and plug-ins use GTK/Granite/Switchboard; they do not host KDE KCMs. Repo metadata: elementary/settings LGPL-2.1; individual plug-in licenses vary. |
| Notifications | [elementary/notifications](https://github.com/elementary/notifications), [elementary/panel-notifications](https://github.com/elementary/panel-notifications) | Plasma Workspace notification service and tray | Plasma's notification service | elementary notifications depend on the Pantheon desktop/GTK stack. Repo metadata: notifications GPL-3.0; panel-notifications LGPL-2.1. |
| File manager | [elementary/files](https://github.com/elementary/files) | [Dolphin](https://invent.kde.org/system/dolphin) | Dolphin package and ShreeOS Downloads/Trash launchers | Keep file-management portals and Qt/KIO integration coherent with Plasma. Repo metadata: elementary/files GPL-3.0. |
| Login | [elementary/greeter](https://github.com/elementary/greeter) | [SDDM](https://github.com/sddm/sddm) | SDDM with an original ShreeOS QML theme | elementary/greeter is GTK/Vala and Pantheon-oriented; the ShreeOS QML theme uses SDDM's documented API. Repo metadata: elementary/greeter GPL-3.0. No greeter source copied. |
| Window manager, effects, overview | [elementary/gala](https://github.com/elementary/gala) and dock's Gala D-Bus interface | [KWin](https://invent.kde.org/plasma/kwin) and Plasma Overview effect | KWin X11, four Plasma virtual desktops and the native Overview shortcut | Gala is the Pantheon Mutter-based compositor and exposes desktop-specific interfaces. It is not a KWin plug-in. Use the compositor shipped with Plasma. Repo metadata: Gala GPL-3.0. |
| Installer | [elementary/installer](https://github.com/elementary/installer) | KDE/Calamares-compatible system base | ShreeOS-branded Calamares using the existing Debian Live configuration and ShreeOS installer launcher | elementary's Vala/GTK installer is tied to its OS modules and install flow. Keep the existing Calamares path. Repo metadata: elementary/installer GPL-3.0. |
| Software center | [elementary/appcenter](https://github.com/elementary/appcenter) | [KDE Discover](https://invent.kde.org/plasma/discover), PackageKit and Flatpak backends | Discover with Debian PackageKit and optional user-selected Flathub Flatpaks | AppCenter's elementary OS package/Flatpak integration is OS-specific. Discover is the Plasma-native frontend. Repo metadata: AppCenter GPL-3.0. |
| Icons and visual theme | [elementary/icons](https://github.com/elementary/icons), [elementary/stylesheet](https://github.com/elementary/stylesheet) | Breeze GTK/Qt theme and Plasma color schemes | ShreeOS color schemes and original artwork; package-provided Papirus/Breeze assets | GTK icon and stylesheet assets do not form a Qt/Plasma theme. No elementary assets copied. Repo metadata: icons and stylesheet GPL-3.0. |
| Boot | [elementary/plymouth-theme](https://github.com/elementary/plymouth-theme) | Plymouth used by the Debian profile | Original ShreeOS Plymouth artwork and configuration | Reuse the project-owned artwork across profiles; no elementary boot assets copied. Repo metadata: elementary/plymouth-theme GPL-3.0. |

## Source and license review notes

The elementary organization inventory contains desktop applications, shell
components, settings plug-ins, web services, community, build and repository
maintenance projects. Only the desktop-relevant projects in the table were
considered for integration. Public repo metadata identifies the dock as GPL-3.0
and the repository was reviewed at commit
[`bb172d7a7b01f4da23c5094650aa8f2ab04acf7d`](https://github.com/elementary/dock/tree/bb172d7a7b01f4da23c5094650aa8f2ab04acf7d).
Its GPL text is in `LICENSE`; inspected implementation files also carry
elementary copyright notices and GPL-3.0 SPDX headers. No dock code is copied.

The KDE repository's API metadata does not declare one repository-wide SPDX
license. The inspected Plasma task-manager files carry their own SPDX headers;
for example, `Task.qml` and `TaskList.qml` are GPL-2.0-or-later. ShreeOS uses
Debian's installed Plasma package instead of copying these files. If a future
change copies any source, first record that exact file's commit, SPDX header,
copyright notice and required license text in `docs/UPSTREAM_CODE.md` and
`THIRD_PARTY_LICENSES.md`.

Upstream references: [elementary/dock README and build requirements](https://github.com/elementary/dock/tree/bb172d7a7b01f4da23c5094650aa8f2ab04acf7d),
[Plasma task-manager sources at the reviewed commit](https://invent.kde.org/plasma/plasma-desktop/-/tree/3e30bb249dc4a4788d38be3c73d72ec64545e87f/applets/taskmanager),
[Plasma scripting API](https://develop.kde.org/docs/plasma/scripting/), and
[SDDM theme API](https://github.com/sddm/sddm/wiki/Theming).
