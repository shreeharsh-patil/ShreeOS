import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#172334"

    property string errorMessage: ""
    property date currentDate: new Date()

    function submitLogin() {
        errorMessage = ""
        sddm.login(userPicker.currentText, passwordField.text, sessionPicker.currentIndex)
    }

    Image {
        anchors.fill: parent
        source: "file:///usr/share/backgrounds/shreeos/shreeos-ember-flow.png"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#17111d34" }
            GradientStop { position: 0.52; color: "#080d1728" }
            GradientStop { position: 1.0; color: "#36131a31" }
        }
    }

    // The full-screen clock gives the greeter the quiet, focused feel of a
    // desktop lock screen. Hide it on short displays so it never covers sign-in.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.currentDate = new Date()
    }

    Column {
        anchors.top: parent.top
        anchors.topMargin: Math.max(24, Math.min(48, root.height * 0.05))
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        visible: root.height >= 750

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.currentDate, "h:mm")
            font.family: "Inter"
            font.pixelSize: 54
            font.weight: Font.Light
            color: "#ffffff"
            style: Text.Raised
            styleColor: "#550a1524"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.currentDate, "dddd, MMMM d")
            font.family: "Inter"
            font.pixelSize: 16
            color: "#f5f8ff"
            style: Text.Raised
            styleColor: "#550a1524"
        }
    }

    Rectangle {
        id: loginCard
        anchors.centerIn: parent
        width: Math.min(372, root.width - 40)
        height: Math.min(444, root.height - 40)
        radius: 26
        color: "#e8f5f1ec"
        border.width: 1
        border.color: "#c9ffffff"

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#edf8f5f0" }
            GradientStop { position: 0.52; color: "#e8f2f0ec" }
            GradientStop { position: 1.0; color: "#e8e8e9ee" }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 1
            radius: 1
            color: "#dfffffff"
        }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 7

            Image {
                width: 52
                height: 52
                anchors.horizontalCenter: parent.horizontalCenter
                source: "file:///usr/share/icons/hicolor/scalable/apps/shreeos.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                text: "ShreeOS"
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#253244"
                font.family: "Inter"
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }

            Text {
                text: "A calmer place to work."
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#687487"
                font.family: "Inter"
                font.pixelSize: 13
            }

            Item { width: 1; height: 4 }

            ComboBox {
                id: userPicker
                width: parent.width
                height: 38
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
                font.family: "Inter"
                font.pixelSize: 13
                leftPadding: 12
                rightPadding: 30

                contentItem: Text {
                    text: userPicker.displayText
                    color: "#2f3c4e"
                    font: userPicker.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                background: Rectangle {
                    radius: 11
                    color: "#aafffefa"
                    border.width: 1
                    border.color: userPicker.activeFocus ? "#4d98d0" : "#aabac8d4"
                }
            }

            TextField {
                id: passwordField
                width: parent.width
                height: 38
                placeholderText: "Password"
                echoMode: TextInput.Password
                selectByMouse: true
                font.family: "Inter"
                font.pixelSize: 13
                leftPadding: 12
                color: "#2f3c4e"
                selectionColor: "#3c87c9"
                selectedTextColor: "white"
                placeholderTextColor: "#8993a1"
                onAccepted: root.submitLogin()
                Component.onCompleted: forceActiveFocus()

                background: Rectangle {
                    radius: 11
                    color: "#aafffefa"
                    border.width: 1
                    border.color: passwordField.activeFocus ? "#4d98d0" : "#aabac8d4"
                }
            }

            ComboBox {
                id: sessionPicker
                width: parent.width
                height: 38
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
                font.family: "Inter"
                font.pixelSize: 13
                leftPadding: 12
                rightPadding: 30

                contentItem: Text {
                    text: sessionPicker.displayText
                    color: "#2f3c4e"
                    font: sessionPicker.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                background: Rectangle {
                    radius: 11
                    color: "#aafffefa"
                    border.width: 1
                    border.color: sessionPicker.activeFocus ? "#4d98d0" : "#aabac8d4"
                }
            }

            Button {
                width: parent.width
                height: 40
                text: "Sign in"
                enabled: passwordField.text.length > 0
                font.family: "Inter"
                font.pixelSize: 13
                font.weight: Font.Medium
                onClicked: root.submitLogin()

                background: Rectangle {
                    radius: 11
                    color: parent.down ? "#3471b5" : parent.hovered ? "#5293d1" : "#4385c6"
                    border.width: 1
                    border.color: "#7eb3e0"
                    opacity: parent.enabled ? 1.0 : 0.48
                }

                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font: parent.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                id: message
                width: parent.width
                height: 18
                text: root.errorMessage
                color: "#ffb4ab"
                horizontalAlignment: Text.AlignHCenter
                font.family: "Inter"
                font.pixelSize: 12
                elide: Text.ElideRight
                opacity: text.length ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Repeater {
                    model: [
                        { label: "Sleep", available: sddm.canSuspend, action: "suspend" },
                        { label: "Restart", available: sddm.canReboot, action: "reboot" },
                        { label: "Power off", available: sddm.canPowerOff, action: "powerOff" }
                    ]

                    delegate: Button {
                        width: 90
                        height: 30
                        text: modelData.label
                        visible: modelData.available
                        flat: true
                        font.family: "Inter"
                        font.pixelSize: 11
                        onClicked: {
                            if (modelData.action === "suspend") sddm.suspend()
                            else if (modelData.action === "reboot") sddm.reboot()
                            else sddm.powerOff()
                        }

                        background: Rectangle {
                            radius: 9
                            color: parent.hovered ? "#83ffffff" : "#00ffffff"
                            border.width: parent.hovered ? 1 : 0
                            border.color: "#8daab9c7"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#425064"
                            font: parent.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.errorMessage = "Sign-in failed. Check your password and try again."
            passwordField.clear()
        }
    }
}
