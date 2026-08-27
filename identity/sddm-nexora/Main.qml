import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1280
    height: 720
    color: "#080A0D"

    property color textPrimary: "#F7F9FC"
    property color textSecondary: "#C7D0DA"
    property color textTertiary: "#8B99A8"
    property color accent: "#62E7D5"
    property string nowTime: Qt.formatTime(new Date(), "HH:mm")
    property string nowDate: Qt.formatDate(new Date(), "dddd, dd MMMM")

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            root.nowTime = Qt.formatTime(new Date(), "HH:mm")
            root.nowDate = Qt.formatDate(new Date(), "dddd, dd MMMM")
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0D131B" }
            GradientStop { position: 0.58; color: "#090D12" }
            GradientStop { position: 1.0; color: "#06080B" }
        }
    }
    Rectangle {
        width: Math.max(520, parent.width * 0.5); height: width; radius: width / 2
        x: parent.width * 0.64; y: -height * 0.62
        color: accent; opacity: 0.04
    }

    Row {
        anchors.left: parent.left; anchors.leftMargin: 28
        anchors.top: parent.top; anchors.topMargin: 24
        spacing: 10
        Rectangle {
            width: 28; height: 28; radius: 9; color: "#172029"; border.color: "#5062E7D5"
            Text { anchors.centerIn: parent; text: "N"; color: accent; font.pixelSize: 13; font.bold: true }
        }
        Text { text: "Nexora OS"; color: textPrimary; font.pixelSize: 14; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -18
        width: Math.min(430, parent.width - 70)
        spacing: 14

        Text { width: parent.width; text: root.nowTime; color: textPrimary; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 54; font.weight: Font.Light }
        Text { width: parent.width; text: root.nowDate; color: textSecondary; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 12 }
        Item { width: 1; height: 8 }

        Rectangle {
            width: parent.width; height: 52; radius: 17; color: "#E0171D24"; border.color: "#40536270"
            TextField {
                id: userField
                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                text: userModel.lastUser
                placeholderText: "Username"; placeholderTextColor: textTertiary; color: textPrimary
                background: Item {}
            }
        }
        Rectangle {
            width: parent.width; height: 52; radius: 17; color: "#E0171D24"; border.color: passwordField.activeFocus ? "#8062E7D5" : "#40536270"
            TextField {
                id: passwordField
                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                echoMode: TextInput.Password
                placeholderText: "Password"; placeholderTextColor: textTertiary; color: textPrimary
                background: Item {}
                onAccepted: sddm.login(userField.text, passwordField.text, sessionBox.currentIndex)
            }
        }

        RowLayout {
            width: parent.width; height: 42
            ComboBox {
                id: sessionBox
                Layout.fillWidth: true; Layout.preferredHeight: 40
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
            }
            Rectangle {
                Layout.preferredWidth: 112; Layout.preferredHeight: 40; radius: 14
                color: loginMouse.containsMouse ? "#7CF0E0" : accent
                Text { anchors.centerIn: parent; text: "Continue"; color: "#07100F"; font.pixelSize: 11; font.bold: true }
                MouseArea {
                    id: loginMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: sddm.login(userField.text, passwordField.text, sessionBox.currentIndex)
                }
            }
        }

        Text { id: errorText; width: parent.width; text: ""; color: "#FF9C9C"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 10 }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 22
        text: "Built for focused technical work"
        color: textTertiary; font.pixelSize: 9
    }

    Connections {
        target: sddm
        function onLoginFailed() { errorText.text = "That login didn't work."; passwordField.text = ""; passwordField.forceActiveFocus() }
        function onLoginSucceeded() { errorText.text = "" }
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}
