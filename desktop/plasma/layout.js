// Original ShreeOS layout using Plasma's installed panel and widget APIs.
// This is applied once for a new ShreeOS user; it does not vendor KDE code.

var requiredWidgets = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.appmenu",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.panelspacer",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.icontasks"
];

for (var requiredIndex = 0; requiredIndex < requiredWidgets.length; requiredIndex++) {
    if (!knownWidgetTypes.includes(requiredWidgets[requiredIndex])) {
        print("ShreeOS layout missing required Plasma widget: " + requiredWidgets[requiredIndex]);
        throw new Error("Required Plasma widget is not installed");
    }
}

var previousPanels = panels();
for (var panelIndex = 0; panelIndex < previousPanels.length; panelIndex++) {
    previousPanels[panelIndex].remove();
}

var menuBar = new Panel();
menuBar.location = "top";
menuBar.lengthMode = "fill";
menuBar.height = 38;
menuBar.hiding = "none";
menuBar.floating = false;
var launcher = menuBar.addWidget("org.kde.plasma.kickoff");
launcher.writeConfig("icon", "shreeos");
menuBar.addWidget("org.kde.plasma.appmenu");
menuBar.addWidget("org.kde.plasma.panelspacer");
menuBar.addWidget("org.kde.plasma.systemtray");
var clock = menuBar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", "true");
menuBar.locked = true;

var dock = new Panel();
dock.location = "bottom";
dock.lengthMode = "fit";
dock.alignment = "center";
dock.height = 58;
dock.hiding = "autohide";
// Keep the dock anchored; floating panels can make KWin crash while the
// layout script is applied during the first Plasma session.
dock.floating = false;
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.writeConfig(
    "launchers",
    "applications:org.kde.dolphin.desktop," +
    "applications:shreeos-downloads.desktop," +
    "applications:org.kde.konsole.desktop," +
    "applications:firefox-esr.desktop," +
    "applications:org.kde.discover.desktop," +
    "applications:systemsettings.desktop," +
    "applications:shreeos-installer.desktop," +
    "applications:shreeos-trash.desktop"
);
dock.locked = true;
