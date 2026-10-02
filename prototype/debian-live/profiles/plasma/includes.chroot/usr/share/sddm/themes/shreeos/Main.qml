import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#101521"

    property string errorMessage: ""

    function submitLogin() {
        errorMessage = ""
        sddm.login(userPicker.currentText, passwordField.text, sessionPicker.currentIndex)
    }

    Image {
        anchors.fill: parent
        source: "file:///usr/share/backgrounds/shreeos/shreeos-calm-dark.png"
        fillMode: Image.PreserveAspectCrop
        smooth: true
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(400, root.width - 32)
        height: Math.min(440, root.height - 32)
        radius: 24
        color: "#df171d29"
        border.width: 1
        border.color: "#51617b"

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Image {
                width: 52
                height: 52
                anchors.horizontalCenter: parent.horizontalCenter
                source: "file:///usr/share/pixmaps/shreeos-logo.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                text: "ShreeOS"
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#f4f6fb"
                font.family: "Inter"
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Text {
                text: "Welcome back"
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#bec9d9"
                font.family: "Inter"
                font.pixelSize: 14
            }

            ComboBox {
                id: userPicker
                width: parent.width
                height: 36
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
            }

            TextField {
                id: passwordField
                width: parent.width
                height: 36
                placeholderText: "Password"
                echoMode: TextInput.Password
                selectByMouse: true
                onAccepted: root.submitLogin()
                Component.onCompleted: forceActiveFocus()
            }

            ComboBox {
                id: sessionPicker
                width: parent.width
                height: 36
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
            }

            Button {
                width: parent.width
                height: 36
                text: "Sign in"
                onClicked: root.submitLogin()
            }

            Text {
                id: message
                width: parent.width
                text: root.errorMessage
                color: "#ffb4ab"
                horizontalAlignment: Text.AlignHCenter
                font.family: "Inter"
                font.pixelSize: 13
                opacity: text.length ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Button {
                    width: 96
                    text: "Suspend"
                    visible: sddm.canSuspend
                    onClicked: sddm.suspend()
                }
                Button {
                    width: 96
                    text: "Restart"
                    visible: sddm.canReboot
                    onClicked: sddm.reboot()
                }
                Button {
                    width: 96
                    text: "Shut down"
                    visible: sddm.canPowerOff
                    onClicked: sddm.powerOff()
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
