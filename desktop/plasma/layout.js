// Original ShreeOS layout using Plasma's installed panel and widget APIs.
// This is applied once for a new ShreeOS user; it does not vendor KDE code.

var requiredWidgets = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.appmenu",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.panelspacer",
    "org.kde.plasma.digitalclock"
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
menuBar.height = 28;
menuBar.hiding = "none";
menuBar.floating = false;
var launcher = menuBar.addWidget("org.kde.plasma.kickoff");
launcher.currentConfigGroup = ["General"];
launcher.writeConfig("icon", "shreeos");
launcher.writeConfig("menuLabel", "Applications");
launcher.writeConfig("compactMode", true);
menuBar.addWidget("org.kde.plasma.appmenu");
menuBar.addWidget("org.kde.plasma.panelspacer");
var clock = menuBar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", 1);
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd, MMM d");
clock.writeConfig("autoFontAndSize", false);
clock.writeConfig("fontFamily", "Inter");
clock.writeConfig("fontSize", 9);
clock.writeConfig("boldText", false);
menuBar.addWidget("org.kde.plasma.panelspacer");
menuBar.addWidget("org.kde.plasma.systemtray");
menuBar.locked = true;

// Plank owns the dock in this X11 profile. Keeping one Plasma panel prevents
// a second taskbar and avoids resetting KWin's floating panel geometry during
// the first-login look-and-feel reset.
