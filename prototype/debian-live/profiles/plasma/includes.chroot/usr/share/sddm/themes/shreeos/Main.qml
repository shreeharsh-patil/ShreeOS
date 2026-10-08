import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#0b111d"

    property string errorMessage: ""
    property date currentDate: new Date()

    function submitLogin() {
        errorMessage = ""
        sddm.login(userPicker.currentText, passwordField.text, sessionPicker.currentIndex)
    }

    Image {
        anchors.fill: parent
        source: "file:///usr/share/backgrounds/shreeos/shreeos-alpenglow.png"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }

    Rectangle {
        anchors.fill: parent
        color: "#22080e18"
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
        width: Math.min(400, root.width - 40)
        height: Math.min(472, root.height - 40)
        radius: 22
        color: "#e6141c2b"
        border.width: 1
        border.color: "#35d7e7ff"

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#e61c2940" }
            GradientStop { position: 1.0; color: "#e6101725" }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 8

            Image {
                width: 48
                height: 48
                anchors.horizontalCenter: parent.horizontalCenter
                source: "file:///usr/share/pixmaps/shreeos-logo.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                text: "ShreeOS"
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#f5f8ff"
                font.family: "Inter"
                font.pixelSize: 25
                font.weight: Font.DemiBold
            }

            Text {
                text: "A calmer place to work."
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#aebbd0"
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
                    color: "#f2f5fc"
                    font: userPicker.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                background: Rectangle {
                    radius: 10
                    color: "#35172030"
                    border.width: 1
                    border.color: userPicker.activeFocus ? "#6c9fff" : "#35dbe6f5"
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
                color: "#f2f5fc"
                selectionColor: "#2878ed"
                selectedTextColor: "white"
                placeholderTextColor: "#8290a6"
                onAccepted: root.submitLogin()
                Component.onCompleted: forceActiveFocus()

                background: Rectangle {
                    radius: 10
                    color: "#35172030"
                    border.width: 1
                    border.color: passwordField.activeFocus ? "#6c9fff" : "#35dbe6f5"
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
                    color: "#f2f5fc"
                    font: sessionPicker.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                background: Rectangle {
                    radius: 10
                    color: "#35172030"
                    border.width: 1
                    border.color: sessionPicker.activeFocus ? "#6c9fff" : "#35dbe6f5"
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
                    radius: 10
                    color: parent.down ? "#2469df" : parent.hovered ? "#3985f7" : "#2878ed"
                    border.width: 1
                    border.color: "#638fdd"
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
                        width: 94
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
