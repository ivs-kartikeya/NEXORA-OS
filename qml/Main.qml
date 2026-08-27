import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs

Window {
    id: root
    visible: true
    visibility: Window.Maximized
    title: "Nexora OS"
    color: "#080A0D"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint

    // V1 visual language: calm, readable, glassy, and lightly technical.
    // Engineering belongs in the workflow and project model, not in dashboard chrome.
    property color bg0: "#080A0D"
    property color bg1: "#0D1117"
    property color glass: "#D9161B22"
    property color glassStrong: "#F01A2029"
    property color glassHover: "#F0252E39"
    property color hairline: "#40536270"
    property color textPrimary: "#FFFFFF"
    property color textSecondary: "#E6ECF2"
    property color textTertiary: "#B5C0CB"
    property color accent: "#62E7D5"
    property color accentSoft: "#263DE0C7"
    property color blue: "#69B7FF"
    property color violet: "#A58CFF"
    property color warning: "#FFBF69"
    property color danger: "#FF7D7D"
    property color success: "#6FE7A8"
    property string uiFont: "Noto Sans"

    property bool launcherOpen: false
    property bool controlOpen: false
    property bool notificationsOpen: false
    property bool commandOpen: false
    property bool powerOpen: false
    property string commandResponse: "Tony is local, private, and ready to help."
    property int volumePreview: systemBackend.volumeLevel
    property bool volumeDragging: false
    property bool brightnessDragging: false
    property var processModel: []
    property var projectNames: []
    property var appCatalogModel: []
    property string appCategory: "All"
    property string filesPath: systemBackend.homeDirectory
    property var filesModel: []
    property string terminalHtml: "<span style='color:#FFFFFF'><b>Nexora Console</b></span><br><span style='color:#D4DCE5'>Nexora Console · PTY session</span>"
    property int settingsPage: 0
    property bool desktopMode: false
    property var desktopRestoreApps: []

    function refreshProjects() { projectNames = systemBackend.listProjects() }
    function refreshAppCatalog() { appCatalogModel = systemBackend.appCatalog() }
    function refreshFiles(path) {
        filesPath = systemBackend.normalizePath(path)
        filesModel = systemBackend.listDirectory(filesPath)
    }
    function appendTerminalOutput(output) {
        if (output === "__CLEAR__") {
            terminalHtml = ""
            return
        }
        terminalHtml += "<br>" + output
        // Keep the built-in terminal from becoming an unbounded RAM sink when
        // a command prints huge logs. Preserve roughly the newest 100k chars.
        if (terminalHtml.length > 120000) {
            var cut = terminalHtml.length - 100000
            var boundary = terminalHtml.indexOf("<br>", cut)
            if (boundary < 0) boundary = cut
            terminalHtml = "<span style='color:#7F8A96'>… older terminal output trimmed …</span><br>" + terminalHtml.substring(boundary + (boundary === cut ? 0 : 4))
        }
    }
    function closeOverlays() {
        launcherOpen = false
        controlOpen = false
        notificationsOpen = false
        commandOpen = false
        powerOpen = false
    }
    function toggleTony() {
        var wasOpen = commandOpen
        closeOverlays()
        commandOpen = !wasOpen
        if (commandOpen) commandField.forceActiveFocus()
    }
    function toggleControl() {
        var wasOpen = controlOpen
        closeOverlays()
        controlOpen = !wasOpen
    }
    function toggleLauncher() {
        var wasOpen = launcherOpen
        closeOverlays()
        launcherOpen = !wasOpen
        if (launcherOpen) launcherSearch.forceActiveFocus()
    }
    function toggleNotifications() {
        var wasOpen = notificationsOpen
        closeOverlays()
        notificationsOpen = !wasOpen
    }
    function coreWindow(app) {
        if (app === "files") return filesWindow
        if (app === "terminal") return terminalWindow
        if (app === "projects") return projectsWindow
        if (app === "appcenter") return appCenterWindow
        if (app === "notes") return notesWindow
        if (app === "monitor") return monitorWindow
        if (app === "settings") return settingsWindow
        return null
    }
    function windowIsRunning(w) {
        return w !== null && (w.visible || w.visibility === Window.Minimized)
    }
    function presentWindow(w) {
        if (w === null) return
        if (w.visibility === Window.Minimized) w.showNormal()
        else if (!w.visible) w.show()
        w.raise()
        w.requestActivate()
    }
    function taskRunning(app) {
        return windowIsRunning(coreWindow(app))
    }
    function taskActive(app) {
        var w = coreWindow(app)
        return windowIsRunning(w) && w.active && w.visibility !== Window.Minimized
    }
    function leaveDesktopMode() {
        if (!desktopMode) return
        systemBackend.restoreDesktop()
        var restore = desktopRestoreApps
        desktopRestoreApps = []
        desktopMode = false
        for (var i = 0; i < restore.length; ++i) {
            var w = coreWindow(restore[i])
            if (windowIsRunning(w)) presentWindow(w)
        }
    }
    function toggleDesktop() {
        closeOverlays()
        if (desktopMode) {
            leaveDesktopMode()
            return
        }
        var apps = ["files","terminal","projects","appcenter","notes","monitor","settings"]
        var restore = []
        for (var i = 0; i < apps.length; ++i) {
            var w = coreWindow(apps[i])
            if (windowIsRunning(w) && w.visibility !== Window.Minimized) {
                restore.push(apps[i])
                w.showMinimized()
            }
        }
        desktopRestoreApps = restore
        systemBackend.showDesktop()
        desktopMode = true
    }
    function taskAction(app) {
        if (app === "launcher") { toggleLauncher(); return }
        if (app === "tony") { toggleTony(); return }
        var w = coreWindow(app)
        if (desktopMode) {
            leaveDesktopMode()
            w = coreWindow(app)
            if (w !== null) presentWindow(w)
            else openCoreApp(app)
            return
        }
        if (!windowIsRunning(w)) { openCoreApp(app); return }
        if (w.visibility === Window.Minimized) { presentWindow(w); return }
        if (w.active) { w.showMinimized(); return }
        presentWindow(w)
    }
    function minimizeAllCore() {
        var apps = ["files","terminal","projects","appcenter","notes","monitor","settings"]
        for (var i = 0; i < apps.length; ++i) {
            var w = coreWindow(apps[i])
            if (windowIsRunning(w) && w.visibility !== Window.Minimized) w.showMinimized()
        }
        closeOverlays()
    }
    function openCoreApp(name) {
        if (desktopMode) leaveDesktopMode()
        closeOverlays()
        if (name.startsWith("files:")) {
            refreshFiles(name.substring(6)); presentWindow(filesWindow)
        } else if (name === "files") {
            refreshFiles(filesPath); presentWindow(filesWindow)
        } else if (name === "terminal") {
            if (!systemBackend.terminalSessionReady) systemBackend.terminalRestart()
            presentWindow(terminalWindow); terminalInput.forceActiveFocus()
        } else if (name === "settings") {
            presentWindow(settingsWindow)
        } else if (name === "projects") {
            refreshProjects(); presentWindow(projectsWindow)
        } else if (name === "appcenter") {
            refreshAppCatalog(); presentWindow(appCenterWindow)
        } else if (name === "notes") {
            presentWindow(notesWindow); noteEditor.forceActiveFocus()
        } else if (name === "monitor") {
            processModel = systemBackend.topProcesses(); presentWindow(monitorWindow)
        } else if (name === "tony" || name === "command") {
            commandOpen = true; commandField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        refreshProjects()
        refreshFiles(filesPath)
        volumePreview = systemBackend.volumeLevel
        systemBackend.refreshTonyStatus()
    }

    function handleAppRequest(app) {
        if (app === "showdesktop") { toggleDesktop(); return }
        if (app.startsWith("overlay:")) {
            var panel = app.substring(8)
            if (panel === "control" || panel === "controlcenter") toggleControl()
            else if (panel === "launcher" || panel === "apps") toggleLauncher()
            else if (panel === "activity" || panel === "notifications") toggleNotifications()
            else if (panel === "tony") toggleTony()
            return
        }
        root.openCoreApp((app === "ai" || app === "command") ? "tony" : app)
    }

    Connections {
        target: systemBackend
        function onAppRequested(app) { root.handleAppRequest(app) }
        function onTonyChanged() { root.commandResponse = systemBackend.tonyReply }
        function onAudioChanged() { if (!root.volumeDragging) root.volumePreview = systemBackend.volumeLevel }
        function onTerminalOutput(output) { root.appendTerminalOutput(output) }
        function onAppJobChanged() {
            if (!systemBackend.appJobBusy) root.refreshAppCatalog()
        }
    }

    // V1 uses keyboard labels that exist on normal PC keyboards. The Windows/Meta
    // key remains free for the host/VM; Nexora's primary shortcuts use Ctrl/Alt.
    Shortcut { sequence: "Ctrl+Space"; onActivated: root.toggleTony() }
    Shortcut { sequence: "Ctrl+Shift+Space"; onActivated: { root.commandOpen = true; systemBackend.toggleVoiceListening() } }
    Shortcut { sequence: "Ctrl+Alt+F"; onActivated: root.openCoreApp("files") }
    Shortcut { sequence: "Ctrl+Alt+T"; onActivated: root.openCoreApp("terminal") }
    Shortcut { sequence: "Ctrl+Alt+P"; onActivated: root.openCoreApp("projects") }
    Shortcut { sequence: "Ctrl+Alt+Comma"; onActivated: root.openCoreApp("settings") }
    Shortcut { sequence: "Ctrl+Alt+A"; onActivated: root.openCoreApp("appcenter") }
    Shortcut { sequence: "Ctrl+Alt+N"; onActivated: root.openCoreApp("notes") }
    Shortcut { sequence: "Ctrl+Alt+M"; onActivated: root.openCoreApp("monitor") }
    Shortcut { sequence: "Ctrl+Alt+D"; onActivated: root.toggleDesktop() }
    Shortcut { sequence: "Escape"; onActivated: root.closeOverlays() }

    // ---------- Desktop background ----------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#10243A" }
            GradientStop { position: 0.46; color: "#0B1626" }
            GradientStop { position: 1.0; color: "#070A11" }
        }
    }

    // V1 wallpaper: quiet engineering texture instead of a dashboard.
    Canvas {
        id: blueprintTexture
        anchors.fill: parent
        opacity: 0.20
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = "rgba(105,183,255,0.12)"
            ctx.lineWidth = 1
            var step = 48
            for (var x = 0; x < width; x += step) {
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
            for (var y = 0; y < height; y += step) {
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
            ctx.strokeStyle = "rgba(98,231,213,0.17)"
            ctx.lineWidth = 1.2
            ctx.beginPath()
            ctx.moveTo(width * 0.06, height * 0.73)
            ctx.bezierCurveTo(width * 0.28, height * 0.57, width * 0.43, height * 0.86, width * 0.67, height * 0.63)
            ctx.bezierCurveTo(width * 0.78, height * 0.52, width * 0.86, height * 0.60, width * 0.96, height * 0.43)
            ctx.stroke()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // Soft ambient light, deliberately subtle.
    Rectangle {
        width: Math.max(540, root.width * 0.46)
        height: width
        radius: width / 2
        x: root.width * 0.60
        y: -height * 0.58
        color: accent
        opacity: 0.035
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 0.022; to: 0.048; duration: 5200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.048; to: 0.022; duration: 5200; easing.type: Easing.InOutSine }
        }
    }
    Rectangle {
        width: Math.max(460, root.width * 0.36)
        height: width
        radius: width / 2
        x: -width * 0.48
        y: root.height * 0.66
        color: blue
        opacity: 0.024
    }

    // ---------- Status bar ----------
    Item {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 62
        z: 20

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.margins: 10
            height: 42; radius: 18
            color: "#B5131B27"
            border.color: "#324C6575"
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Rectangle {
                width: 26; height: 26; radius: 9
                color: "#172029"
                border.color: "#5062E7D5"
                Text {
                    anchors.centerIn: parent
                    text: "N"
                    color: accent
                    font.family: uiFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
            }
            Text {
                text: "Nexora OS"
                color: textPrimary
                font.family: uiFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // System capsule — a quiet identity element, not an engineering dashboard.
        Rectangle {
            id: systemCapsule
            width: capsuleMouse.containsMouse ? 198 : 168
            height: 32
            radius: 16
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: capsuleMouse.containsMouse ? "#D9242C35" : "#C9181E25"
            border.color: "#35475562"
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 130 } }

            Row {
                anchors.centerIn: parent
                spacing: 8
                Rectangle {
                    width: 7; height: 7; radius: 4
                    color: systemBackend.privateMode ? warning : accent
                }
                Text {
                    text: systemBackend.privateMode ? "Context paused" : (systemBackend.tonyModelOnline ? "Tony ready" : "System ready")
                    color: textSecondary
                    font.family: uiFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Text {
                    text: "·  V1"
                    visible: capsuleMouse.containsMouse
                    color: textTertiary
                    font.family: uiFont
                    font.pixelSize: 10
                }
            }
            MouseArea {
                id: capsuleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleTony()
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                width: 38; height: 32; radius: 12
                color: systemBackend.voiceListening ? "#3762E7D5" : (voiceTopMouse.containsMouse ? glassHover : "transparent")
                Row { anchors.centerIn: parent; spacing: 4
                    Rectangle { width: 6; height: 6; radius: 3; color: systemBackend.voiceOnline ? (systemBackend.voiceListening ? accent : textSecondary) : textTertiary }
                    Text { text: "V"; color: systemBackend.voiceListening ? accent : textSecondary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Bold }
                }
                MouseArea { id: voiceTopMouse; anchors.fill: parent; hoverEnabled: true; enabled: !systemBackend.voiceRequestBusy && !systemBackend.voiceTranscribing; cursorShape: Qt.PointingHandCursor; onClicked: { root.commandOpen = true; systemBackend.voiceSpeaking ? systemBackend.stopSpeaking() : systemBackend.toggleVoiceListening() } }
            }

            Rectangle {
                width: 36; height: 32; radius: 12
                color: notifyMouse.containsMouse ? glassHover : "transparent"
                Text { anchors.centerIn: parent; text: "•"; color: systemBackend.recentEvents.length > 0 ? accent : textTertiary; font.pixelSize: 22 }
                MouseArea {
                    id: notifyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleNotifications()
                }
            }

            Rectangle {
                width: 42; height: 32; radius: 12
                color: controlMouse.containsMouse ? glassHover : "transparent"
                Row {
                    anchors.centerIn: parent; spacing: 3
                    Rectangle { width: 4; height: 4; radius: 2; color: systemBackend.networkConnected ? success : textTertiary }
                    Rectangle { width: 4; height: 9; radius: 2; color: textSecondary }
                    Rectangle { width: 4; height: 14; radius: 2; color: textSecondary }
                }
                MouseArea {
                    id: controlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleControl()
                }
            }

            Column {
                width: 72
                anchors.verticalCenter: parent.verticalCenter
                spacing: -2
                Text {
                    width: parent.width
                    text: systemBackend.currentTime
                    color: textPrimary
                    horizontalAlignment: Text.AlignRight
                    font.family: uiFont
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: systemBackend.currentDate
                    color: textTertiary
                    horizontalAlignment: Text.AlignRight
                    font.family: uiFont
                    font.pixelSize: 8
                }
            }
        }
    }

    // ---------- Home surface ----------
    Column {
        id: homeContent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -34
        width: Math.min(root.width * 0.76, 880)
        spacing: 16

        Text {
            width: parent.width
            text: systemBackend.currentTime
            color: textPrimary
            horizontalAlignment: Text.AlignHCenter
            font.family: uiFont
            font.pixelSize: Math.max(54, Math.min(78, root.height * 0.095))
            font.weight: Font.Light
        }

        Text {
            width: parent.width
            text: "Build without leaving your flow."
            color: textPrimary
            horizontalAlignment: Text.AlignHCenter
            font.family: uiFont
            font.pixelSize: 27
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: projectNames.length > 0 ? "Projects, tools, and Tony stay quietly in context." : "A simple workspace with a local intelligence layer underneath."
            color: textSecondary
            horizontalAlignment: Text.AlignHCenter
            font.family: uiFont
            font.pixelSize: 13
        }

        Rectangle {
            width: Math.min(parent.width, 590)
            height: 52
            radius: 18
            anchors.horizontalCenter: parent.horizontalCenter
            color: commandMouse.containsMouse ? "#E41E2630" : "#CF171D24"
            border.color: commandMouse.containsMouse ? "#7062E7D5" : hairline
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 17
                anchors.rightMargin: 15
                spacing: 10
                Text { text: "⌕"; color: accent; font.family: uiFont; font.pixelSize: 17 }
                Text {
                    Layout.fillWidth: true
                    text: systemBackend.voiceListening ? "Tony is listening…" : (systemBackend.voiceTranscribing ? "Transcribing locally…" : "Search, ask Tony, or control Nexora")
                    color: textSecondary
                    font.family: uiFont
                    font.pixelSize: 13
                }
                Rectangle {
                    width: 66; height: 26; radius: 9
                    color: "#252E38"
                    Text { anchors.centerIn: parent; text: systemBackend.voiceListening ? "Listening" : "Ctrl  Space"; color: systemBackend.voiceListening ? accent : textTertiary; font.family: uiFont; font.pixelSize: 8 }
                }
            }
            MouseArea {
                id: commandMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleTony()
            }
        }

        Row {
            id: recentRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            visible: projectNames.length > 0

            Repeater {
                model: root.projectNames.slice(0, 3)
                delegate: Rectangle {
                    width: 176; height: 62; radius: 18
                    color: recentMouse.containsMouse ? "#E326303A" : "#C9181F27"
                    border.color: recentMouse.containsMouse ? "#5662E7D5" : hairline
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    scale: recentMouse.containsMouse ? 1.025 : 1.0

                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                        spacing: 2
                        Text {
                            width: parent.width
                            text: modelData
                            color: textPrimary
                            elide: Text.ElideRight
                            font.family: uiFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text { text: "Workspace"; color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                    }
                    MouseArea {
                        id: recentMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.refreshFiles(systemBackend.projectsDirectory + "/" + modelData); root.presentWindow(filesWindow) }
                    }
                }
            }
        }
    }

    // ---------- Nexora OS taskbar ----------
    Rectangle {
        id: dock
        height: 72
        width: Math.min(root.width - 34, Math.max(240, dockRow.width + 24))
        radius: 27
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        color: "#C7111924"
        border.color: "#52627B8E"
        z: 30

        Flickable {
            id: dockFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 58
            contentWidth: dockRow.width
            contentHeight: 58
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            Row {
                id: dockRow
                height: 58
                spacing: 5

            Repeater {
                model: [
                    {label:"Home", glyph:"N", app:"launcher", tint:"#62E7D5"},
                    {label:"Files", glyph:"F", app:"files", tint:"#69B7FF"},
                    {label:"Terminal", glyph:">", app:"terminal", tint:"#A7B0BC"},
                    {label:"Projects", glyph:"P", app:"projects", tint:"#A58CFF"},
                    {label:"Apps", glyph:"A", app:"appcenter", tint:"#6FE7A8"},
                    {label:"Notes", glyph:"N", app:"notes", tint:"#FFBF69"},
                    {label:"Monitor", glyph:"M", app:"monitor", tint:"#69B7FF"},
                    {label:"Tony", glyph:"T", app:"tony", tint:"#62E7D5"},
                    {label:"Settings", glyph:"S", app:"settings", tint:"#8C9AAA"}
                ]
                delegate: Item {
                    property bool running: modelData.app === "tony" ? root.commandOpen : root.taskRunning(modelData.app)
                    property bool activeTask: modelData.app === "tony" ? root.commandOpen : root.taskActive(modelData.app)
                    width: running ? (dockItemMouse.containsMouse ? 88 : 76) : (dockItemMouse.containsMouse ? 66 : 54)
                    height: 58
                    Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                    Rectangle {
                        width: dockItemMouse.containsMouse ? 46 : 42
                        height: width
                        radius: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: dockItemMouse.containsMouse ? 1 : 6
                        color: modelData.tint
                        opacity: 0.92
                        Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on anchors.topMargin { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.glyph
                            color: modelData.app === "terminal" ? "#0B0D10" : "#07100F"
                            font.family: uiFont
                            font.pixelSize: modelData.app === "tony" ? 16 : 15
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: modelData.label
                        color: activeTask ? textPrimary : textSecondary
                        opacity: running || dockItemMouse.containsMouse ? 1 : 0
                        font.family: uiFont
                        font.pixelSize: 8
                        font.weight: running ? Font.DemiBold : Font.Normal
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    Rectangle {
                        width: activeTask ? 16 : 6; height: 3; radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: -5
                        visible: running
                        color: activeTask ? accent : textTertiary
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: dockItemMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.taskAction(modelData.app)
                        }
                    }
                }
            }
            Rectangle {
                width: systemBackend.externalWindows.length > 0 ? 1 : 0
                height: 34
                color: hairline
                anchors.verticalCenter: parent.verticalCenter
                visible: systemBackend.externalWindows.length > 0
            }
            Repeater {
                model: systemBackend.externalWindows
                delegate: Item {
                    property bool activeTask: !!modelData.active && !modelData.minimized
                    width: externalTaskMouse.containsMouse ? 118 : 86
                    height: 58
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Rectangle {
                        width: 38; height: 38; radius: 13
                        anchors.left: parent.left; anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.attention ? warning : (activeTask ? accent : "#34404B")
                        Text {
                            anchors.centerIn: parent
                            text: (modelData.app && modelData.app.length > 0 ? modelData.app : modelData.title).charAt(0).toUpperCase()
                            color: activeTask ? "#07100F" : textPrimary
                            font.family: uiFont; font.pixelSize: 13; font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 47
                        anchors.right: parent.right; anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        color: activeTask ? textPrimary : textSecondary
                        font.family: uiFont; font.pixelSize: 8; font.weight: activeTask ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Rectangle {
                        width: activeTask ? 18 : 6; height: 3; radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: -5
                        color: activeTask ? accent : textTertiary
                    }
                    MouseArea {
                        id: externalTaskMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.MiddleButton) {
                                systemBackend.windowAction(modelData.id, "close")
                                return
                            }
                            var wasDesktop = root.desktopMode
                            if (wasDesktop) root.leaveDesktopMode()
                            systemBackend.windowAction(modelData.id, wasDesktop ? "activate" : "toggle")
                        }
                    }
                }
            }
            Rectangle {
                width: 1; height: 34; color: hairline; anchors.verticalCenter: parent.verticalCenter
            }
            Item {
                width: 42; height: 58
                Rectangle {
                    width: 30; height: 30; radius: 10; anchors.centerIn: parent
                    color: desktopMouse.containsMouse ? glassHover : "transparent"
                    Text { anchors.centerIn: parent; text: root.desktopMode ? "⌃" : "⌄"; color: root.desktopMode ? accent : textSecondary; font.pixelSize: 15 }
                    MouseArea { id: desktopMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleDesktop() }
                }
            }
            }
        }
    }

    // ---------- Launcher / App Library ----------
    Rectangle {
        id: launcher
        width: Math.min(720, root.width - 60)
        height: launcherOpen ? Math.min(500, root.height - 150) : 0
        opacity: launcherOpen ? 1 : 0
        radius: 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: dock.top
        anchors.bottomMargin: 12
        color: glassStrong
        border.color: "#4D61707E"
        clip: true
        visible: opacity > 0.01
        z: 40
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 130 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 15

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Apps"; color: textPrimary; font.family: uiFont; font.pixelSize: 23; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                Text { text: "Nexora OS"; color: textTertiary; font.family: uiFont; font.pixelSize: 10 }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 15
                color: "#A910151B"; border.color: hairline
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    Text { text: "⌕"; color: accent; font.pixelSize: 16 }
                    TextField {
                        id: launcherSearch
                        Layout.fillWidth: true
                        placeholderText: "Find an app"
                        placeholderTextColor: textTertiary
                        color: textPrimary
                        font.family: uiFont
                        font.pixelSize: 12
                        background: Item {}
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: root.width < 1100 ? 3 : 4
                rowSpacing: 10
                columnSpacing: 10

                Repeater {
                    model: [
                        {name:"Files", note:"Browse your workspace", app:"files", glyph:"F", tint:"#69B7FF"},
                        {name:"Terminal", note:"Local shell", app:"terminal", glyph:">", tint:"#A7B0BC"},
                        {name:"Projects", note:"Engineering workspaces", app:"projects", glyph:"P", tint:"#A58CFF"},
                        {name:"App Center", note:"Find and install software", app:"appcenter", glyph:"A", tint:"#6FE7A8"},
                        {name:"Notes", note:"Fast local scratchpad", app:"notes", glyph:"N", tint:"#FFBF69"},
                        {name:"System Monitor", note:"Processes and resources", app:"monitor", glyph:"M", tint:"#69B7FF"},
                        {name:"Settings", note:"System preferences", app:"settings", glyph:"S", tint:"#8C9AAA"},
                        {name:"Web", note:"Open your browser", app:"browser", glyph:"W", tint:"#6FE7A8"},
                        {name:"Tony", note:"Local system intelligence", app:"tony", glyph:"T", tint:"#62E7D5"}
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        visible: launcherSearch.text.length === 0 || modelData.name.toLowerCase().indexOf(launcherSearch.text.toLowerCase()) >= 0
                        radius: 20
                        color: launcherTileMouse.containsMouse ? glassHover : "#B7161D24"
                        border.color: launcherTileMouse.containsMouse ? "#5662E7D5" : hairline
                        scale: launcherTileMouse.containsMouse ? 1.018 : 1.0
                        Behavior on scale { NumberAnimation { duration: 110 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Rectangle {
                                width: 46; height: 46; radius: 15
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: modelData.tint
                                Text { anchors.centerIn: parent; text: modelData.glyph; color: "#07100F"; font.family: uiFont; font.pixelSize: 16; font.weight: Font.Bold }
                            }
                            Text { text: modelData.name; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.note; color: textTertiary; font.family: uiFont; font.pixelSize: 8; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea {
                            id: launcherTileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.app === "browser") { root.closeOverlays(); systemBackend.launchApp("browser") }
                                else root.openCoreApp(modelData.app)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Tony — local system intelligence ----------
    Rectangle {
        id: commandCenter
        width: Math.min(700, root.width - 70)
        height: commandOpen ? (systemBackend.tonyApprovalPending ? 440 : 380) : 0
        opacity: commandOpen ? 1 : 0
        radius: 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 72
        color: "#F2181F27"
        border.color: systemBackend.tonyBusy ? "#7A62E7D5" : "#5962E7D5"
        clip: true
        visible: opacity > 0.01
        z: 60
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 11

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 34; height: 34; radius: 12
                    color: systemBackend.tonyOnline ? accent : "#39434D"
                    Text { anchors.centerIn: parent; text: "T"; color: "#07100F"; font.family: uiFont; font.pixelSize: 15; font.weight: Font.Bold }
                    SequentialAnimation on opacity {
                        running: systemBackend.tonyBusy; loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 520; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Text { text: "Tony"; color: textPrimary; font.family: uiFont; font.pixelSize: 16; font.weight: Font.DemiBold }
                    Text { text: systemBackend.tonyStatus; color: systemBackend.tonyModelOnline ? accent : textTertiary; font.family: uiFont; font.pixelSize: 9 }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 78; height: 28; radius: 11
                    color: systemBackend.voiceListening ? accent : (systemBackend.voiceSpeaking ? "#31465E" : "#202A31")
                    border.color: systemBackend.voiceOnline ? "#45546370" : "#553D424A"
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            color: systemBackend.voiceListening ? "#07100F" : (systemBackend.voiceOnline ? accent : textTertiary)
                            SequentialAnimation on opacity {
                                running: systemBackend.voiceListening || systemBackend.voiceSpeaking
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 420 }
                                NumberAnimation { to: 1.0; duration: 420 }
                            }
                        }
                        Text { text: systemBackend.voiceRequestBusy ? "Starting" : (systemBackend.voiceTranscribing ? "Working" : (systemBackend.voiceListening ? "Listening" : (systemBackend.voiceSpeaking ? "Speaking" : "Voice"))); color: systemBackend.voiceListening ? "#07100F" : textSecondary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        enabled: !systemBackend.voiceRequestBusy && !systemBackend.voiceTranscribing
                        onClicked: systemBackend.voiceSpeaking ? systemBackend.stopSpeaking() : systemBackend.toggleVoiceListening()
                    }
                }
                Rectangle {
                    width: 78; height: 26; radius: 10
                    color: systemBackend.privateMode ? "#3A33231E" : "#202A31"
                    Text { anchors.centerIn: parent; text: systemBackend.privateMode ? "Private" : "Aware"; color: systemBackend.privateMode ? warning : accent; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Medium }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 17
                color: "#E00D1218"; border.color: commandField.activeFocus ? "#8A62E7D5" : hairline
                TextField {
                    id: commandField
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    placeholderText: systemBackend.tonyModelOnline ? "Ask Tony anything about your system or work…" : "Ask Tony anything — the local model wakes only when reasoning is needed"
                    placeholderTextColor: textTertiary
                    color: textPrimary
                    selectionColor: accent
                    selectedTextColor: "#07100F"
                    font.family: uiFont
                    font.pixelSize: 13
                    enabled: !systemBackend.tonyBusy
                    background: Item {}
                    onAccepted: {
                        if (text.trim().length === 0) return
                        root.commandResponse = "Thinking…"
                        systemBackend.askTony(text)
                        root.refreshProjects()
                        text = ""
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: (systemBackend.voiceListening || systemBackend.voiceTranscribing || systemBackend.voiceTranscript.length > 0) ? 34 : 0
                visible: systemBackend.voiceListening || systemBackend.voiceTranscribing || systemBackend.voiceTranscript.length > 0
                radius: 12
                color: systemBackend.voiceListening ? "#253A3734" : "#181F26"
                border.color: systemBackend.voiceListening ? "#5A62E7D5" : hairline
                clip: true
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 11; spacing: 8
                    Rectangle { width: 6; height: 6; radius: 3; color: systemBackend.voiceListening ? accent : textTertiary }
                    Text {
                        Layout.fillWidth: true
                        text: systemBackend.voiceListening ? "Listening locally · press the mic again when you're done" : (systemBackend.voiceTranscribing ? "Transcribing on this device…" : (systemBackend.voiceTranscript.length > 0 ? "Heard: “" + systemBackend.voiceTranscript + "”" : systemBackend.voiceStatus))
                        color: systemBackend.voiceListening ? textPrimary : textTertiary
                        elide: Text.ElideRight
                        font.family: uiFont; font.pixelSize: 9
                    }
                    Text { text: "Ctrl ⇧ Space"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 17
                color: "#A910151B"
                border.color: "#25313B45"
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    TextArea {
                        text: root.commandResponse
                        color: textSecondary
                        font.family: uiFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        readOnly: true
                        selectByMouse: true
                        background: Item {}
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: systemBackend.tonyApprovalPending ? 66 : 0
                visible: systemBackend.tonyApprovalPending
                radius: 17
                color: "#322C211B"
                border.color: "#70FFBF69"
                clip: true
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Text { text: "Approval required"; color: warning; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; text: systemBackend.tonyApprovalText; color: textSecondary; font.family: uiFont; font.pixelSize: 10; elide: Text.ElideRight }
                    }
                    Rectangle {
                        width: 72; height: 34; radius: 11; color: denyTonyMouse.containsMouse ? "#3A3131" : "#25282D"
                        Text { anchors.centerIn: parent; text: "Cancel"; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                        MouseArea { id: denyTonyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.denyTonyAction() }
                    }
                    Rectangle {
                        width: 72; height: 34; radius: 11; color: approveTonyMouse.containsMouse ? "#78F4DD" : accent
                        Text { anchors.centerIn: parent; text: "Allow"; color: "#07100F"; font.family: uiFont; font.pixelSize: 10; font.weight: Font.Bold }
                        MouseArea { id: approveTonyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.approveTonyAction() }
                    }
                }
            }
        }
    }

    // ---------- Control Center ----------
    Rectangle {
        id: controlCenter
        width: 330
        height: controlOpen ? (systemBackend.brightnessAvailable ? 646 : 576) : 0
        opacity: controlOpen ? 1 : 0
        radius: 26
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.top: statusBar.bottom
        anchors.topMargin: 8
        color: "#F0181F27"
        border.color: "#4E5B6976"
        clip: true
        visible: opacity > 0.01
        z: 60
        Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 110 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Control Center"; color: textPrimary; font.family: uiFont; font.pixelSize: 16; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                Text { text: systemBackend.currentTime; color: textTertiary; font.family: uiFont; font.pixelSize: 10 }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 9
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 82; radius: 19
                    color: systemBackend.networkConnected ? "#27305242" : "#C61B222A"
                    border.color: systemBackend.networkConnected ? "#536FE7A8" : hairline
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: systemBackend.wifiAvailable ? "Wi-Fi" : "Network"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { text: systemBackend.wifiAvailable ? (systemBackend.wifiEnabled ? (systemBackend.networkConnected ? "On · connected" : "On") : "Off") : (systemBackend.networkConnected ? "Online" : "Offline"); color: (systemBackend.wifiAvailable ? systemBackend.wifiEnabled : systemBackend.networkConnected) ? success : textTertiary; font.family: uiFont; font.pixelSize: 10 }
                    }
                    MouseArea { anchors.fill: parent; enabled: systemBackend.wifiAvailable; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: systemBackend.setWifiEnabled(!systemBackend.wifiEnabled) }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 82; radius: 19
                    color: systemBackend.privateMode ? "#3A33231E" : "#27314B47"
                    border.color: systemBackend.privateMode ? "#5EFFBF69" : "#5362E7D5"
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: "Context"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { text: systemBackend.privateMode ? "Paused" : "Local"; color: systemBackend.privateMode ? warning : accent; font.family: uiFont; font.pixelSize: 10 }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setPrivateMode(!systemBackend.privateMode) }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 88; radius: 19
                color: "#C7161D24"; border.color: hairline
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: !systemBackend.audioAvailable ? "Volume · no audio device" : (systemBackend.muted ? "Volume · muted" : "Volume · " + root.volumePreview + "%"); color: textPrimary; font.family: uiFont; font.pixelSize: 11; font.weight: Font.Medium }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 30; height: 24; radius: 9; color: muteMouse.containsMouse ? glassHover : "transparent"
                            Text { anchors.centerIn: parent; text: systemBackend.muted ? "×" : "♪"; color: systemBackend.muted ? danger : accent; font.pixelSize: 13 }
                            MouseArea { id: muteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setMuted(!systemBackend.muted) }
                        }
                    }
                    Item {
                        id: volumeTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        enabled: true
                        opacity: systemBackend.audioAvailable ? 1.0 : 0.70

                        Timer {
                            id: volumeCommit
                            interval: 100
                            repeat: false
                            onTriggered: systemBackend.setVolume(root.volumePreview)
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6; radius: 3; color: "#34404C"
                            Rectangle {
                                width: parent.width * root.volumePreview / 100.0
                                height: parent.height; radius: 3; color: accent
                                Behavior on width { enabled: !root.volumeDragging; NumberAnimation { duration: 100 } }
                            }
                        }
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            x: Math.max(0, Math.min(parent.width - width, (parent.width - width) * root.volumePreview / 100.0))
                            anchors.verticalCenter: parent.verticalCenter
                            color: textPrimary
                            border.color: "#A862E7D5"
                            Behavior on x { enabled: !root.volumeDragging; NumberAnimation { duration: 100 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: parent.enabled
                            function updateFromX(px) {
                                root.volumePreview = Math.max(0, Math.min(100, Math.round(px / Math.max(1, width) * 100)))
                                volumeCommit.restart()
                            }
                            onPressed: function(mouse) { root.volumeDragging = true; updateFromX(mouse.x) }
                            onPositionChanged: function(mouse) { if (pressed) updateFromX(mouse.x) }
                            onReleased: function(mouse) { updateFromX(mouse.x); root.volumeDragging = false; systemBackend.setVolume(root.volumePreview) }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 19
                color: systemBackend.voiceListening ? "#283E3A" : "#C7161D24"; border.color: systemBackend.voiceListening ? "#5A62E7D5" : hairline
                RowLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 10
                    Rectangle { width: 9; height: 9; radius: 5; color: systemBackend.voiceOnline ? (systemBackend.voiceListening ? accent : success) : textTertiary }
                    ColumnLayout { Layout.fillWidth: true; spacing: 1
                        Text { text: "Tony Voice"; color: textPrimary; font.family: uiFont; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Text { text: systemBackend.voiceStatus + " · " + systemBackend.voiceTtsBackend; color: textTertiary; font.family: uiFont; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    Rectangle {
                        width: 70; height: 30; radius: 11; color: systemBackend.voiceListening ? accent : "#242D36"
                        Text { anchors.centerIn: parent; text: systemBackend.voiceRequestBusy ? "Starting" : (systemBackend.voiceTranscribing ? "Working" : (systemBackend.voiceListening ? "Stop" : (systemBackend.voiceSpeaking ? "Quiet" : "Listen"))); color: systemBackend.voiceListening ? "#07100F" : textSecondary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; enabled: !systemBackend.voiceRequestBusy && !systemBackend.voiceTranscribing; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.voiceSpeaking ? systemBackend.stopSpeaking() : systemBackend.toggleVoiceListening() }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        {label:"Files", app:"files", glyph:"F"},
                        {label:"Console", app:"terminal", glyph:">_"},
                        {label:"Apps", app:"appcenter", glyph:"A"}
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 16
                        color: quickMouse.containsMouse ? "#27333F" : "#C7161D24"
                        border.color: quickMouse.containsMouse ? "#48627A" : hairline
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.glyph; color: modelData.app === "terminal" ? blue : accent; font.family: modelData.app === "terminal" ? "monospace" : uiFont; font.pixelSize: 11; font.weight: Font.Bold }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: textSecondary; font.family: uiFont; font.pixelSize: 8 }
                        }
                        MouseArea { id: quickMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openCoreApp(modelData.app) }
                    }
                }
            }

            Rectangle {
                visible: systemBackend.brightnessAvailable
                Layout.fillWidth: true; Layout.preferredHeight: visible ? 68 : 0; radius: 19
                color: "#C7161D24"; border.color: hairline
                RowLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 10
                    Text { text: "Brightness"; color: textPrimary; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: "#34404C"
                        Rectangle { width: parent.width * systemBackend.brightnessLevel / 100.0; height: parent.height; radius: 3; color: blue; Behavior on width { NumberAnimation { duration: 120 } } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: function(mouse) { systemBackend.setBrightness(Math.max(1, Math.min(100, Math.round(mouse.x / width * 100)))) } }
                    }
                    Text { text: systemBackend.brightnessLevel + "%"; color: textSecondary; font.family: uiFont; font.pixelSize: 9; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 88; radius: 19
                color: "#C7161D24"; border.color: hairline
                RowLayout {
                    anchors.fill: parent; anchors.margins: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        Text { text: "System"; color: textPrimary; font.family: uiFont; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Text { text: Math.round(systemBackend.cpuUsage) + "% CPU  ·  " + Math.round(systemBackend.memoryUsage) + "% RAM"; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                        Text { text: "Uptime " + systemBackend.uptimeText; color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                    }
                    Rectangle {
                        width: 38; height: 38; radius: 13; color: "#222B34"
                        Text { anchors.centerIn: parent; text: "⚙"; color: textPrimary; font.pixelSize: 15 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openCoreApp("settings") }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Repeater {
                    model: [
                        {name:"Log out", action:"logout"},
                        {name:"Restart", action:"reboot"},
                        {name:"Power", action:"poweroff"}
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 42; radius: 14
                        color: powerButtonMouse.containsMouse ? (modelData.action === "poweroff" ? "#463030" : glassHover) : "#C7161D24"
                        border.color: hairline
                        Text { anchors.centerIn: parent; text: modelData.name; color: modelData.action === "poweroff" ? "#FFB0A8" : textSecondary; font.family: uiFont; font.pixelSize: 10; font.weight: Font.Medium }
                        MouseArea {
                            id: powerButtonMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: systemBackend.powerAction(modelData.action)
                        }
                    }
                }
            }
        }
    }

    // ---------- Activity / notification center ----------
    Rectangle {
        id: notifications
        width: 350
        height: notificationsOpen ? 410 : 0
        opacity: notificationsOpen ? 1 : 0
        radius: 26
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.top: statusBar.bottom
        anchors.topMargin: 8
        color: "#F0181F27"
        border.color: "#4E5B6976"
        clip: true
        visible: opacity > 0.01
        z: 60
        Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 110 } }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 17; spacing: 11
            Text { text: "Activity"; color: textPrimary; font.family: uiFont; font.pixelSize: 17; font.weight: Font.DemiBold }
            Text { text: "Quiet system events. Nothing here interrupts your work."; color: textTertiary; font.family: uiFont; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }

            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                Column {
                    width: notifications.width - 34
                    spacing: 8
                    Repeater {
                        model: systemBackend.recentEvents.length > 0 ? systemBackend.recentEvents : ["No recent activity"]
                        delegate: Rectangle {
                            width: parent.width; height: 58; radius: 16
                            color: "#C7161D24"; border.color: hairline
                            Row {
                                anchors.fill: parent; anchors.margins: 12; spacing: 10
                                Rectangle { width: 8; height: 8; radius: 4; color: index === 0 && systemBackend.recentEvents.length > 0 ? accent : "#596673"; anchors.verticalCenter: parent.verticalCenter }
                                Text { width: parent.width - 32; text: modelData; color: systemBackend.recentEvents.length > 0 ? textSecondary : textTertiary; font.family: uiFont; font.pixelSize: 10; wrapMode: Text.WordWrap; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================== Native core apps ==================

    // Shared visual pattern is duplicated intentionally in V1 to keep the QML resource simple and robust.

    FileDialog {
        id: localPackageDialog
        title: "Install a local package"
        nameFilters: ["App packages (*.deb *.AppImage *.flatpak *.flatpakref)", "All files (*)"]
        onAccepted: systemBackend.installLocalPackage(selectedFile.toString())
    }

    // ---------- Files ----------
    Window {
        id: filesWindow
        width: 980; height: 640
        minimumWidth: 760; minimumHeight: 480
        visible: false
        title: "Files"
        color: bg1
        flags: Qt.Window | Qt.FramelessWindowHint

        Rectangle { anchors.fill: parent; color: "#10151B"; border.color: "#3D4C5966"; border.width: 1; radius: 16 }

        RowLayout {
            anchors.fill: parent; spacing: 0

            Rectangle {
                Layout.preferredWidth: 190; Layout.fillHeight: true
                color: "#0D1217"; radius: 16
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: 40
                        Rectangle { width: 26; height: 26; radius: 9; color: blue; Text { anchors.centerIn: parent; text: "F"; color: "#081019"; font.family: uiFont; font.weight: Font.Bold } }
                        Text { text: "Files"; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                    }
                    Text { text: "PLACES"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; font.weight: Font.DemiBold; Layout.topMargin: 4 }
                    Repeater {
                        model: [
                            {name:"Home", path:systemBackend.homeDirectory},
                            {name:"Projects", path:systemBackend.projectsDirectory},
                            {name:"Downloads", path:systemBackend.homeDirectory + "/Downloads"},
                            {name:"Documents", path:systemBackend.homeDirectory + "/Documents"}
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 36; radius: 12
                            color: root.filesPath === systemBackend.normalizePath(modelData.path) ? "#283247" : (placeMouse.containsMouse ? "#1B232C" : "transparent")
                            Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: root.filesPath === systemBackend.normalizePath(modelData.path) ? textPrimary : textSecondary; font.family: uiFont; font.pixelSize: 11 }
                            MouseArea { id: placeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refreshFiles(modelData.path) }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text { text: "Nexora OS Files"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 58; color: "#151B22"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; spacing: 8
                        Rectangle {
                            width: 32; height: 32; radius: 11; color: fileUpMouse.containsMouse ? glassHover : "transparent"
                            Text { anchors.centerIn: parent; text: "↑"; color: textPrimary; font.pixelSize: 15 }
                            MouseArea { id: fileUpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refreshFiles(systemBackend.parentDirectory(root.filesPath)) }
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 12; color: "#0D1217"; border.color: hairline
                            TextField {
                                id: pathField
                                anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 11
                                text: root.filesPath; color: textSecondary; selectionColor: accent; selectedTextColor: "#07100F"
                                font.family: uiFont; font.pixelSize: 10; background: Item {}
                                onAccepted: root.refreshFiles(text)
                            }
                        }
                        Rectangle { width: 34; height: 32; radius: 10; color: minFilesMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: textSecondary; font.pixelSize: 13 }
                            MouseArea { id: minFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: filesWindow.showMinimized() } }
                        Rectangle { width: 34; height: 32; radius: 10; color: maxFilesMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: filesWindow.visibility === Window.Maximized ? "◇" : "□"; color: textSecondary; font.pixelSize: 12 }
                            MouseArea { id: maxFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (filesWindow.visibility === Window.Maximized) filesWindow.showNormal(); else filesWindow.showMaximized() } } }
                        Rectangle {
                            width: 34; height: 32; radius: 11; color: closeFilesMouse.containsMouse ? "#4B2B2B" : "transparent"
                            Text { anchors.centerIn: parent; text: "×"; color: textPrimary; font.pixelSize: 16 }
                            MouseArea { id: closeFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: filesWindow.hide() }
                        }
                    }
                    MouseArea { anchors.fill: parent; z: -1; onPressed: filesWindow.startSystemMove() }
                }

                GridView {
                    id: fileGrid
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.margins: 18
                    cellWidth: 150; cellHeight: 116
                    model: root.filesModel
                    clip: true
                    delegate: Item {
                        width: fileGrid.cellWidth; height: fileGrid.cellHeight
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 5; radius: 18
                            color: fileMouse.containsMouse ? "#222B35" : "transparent"
                            border.color: fileMouse.containsMouse ? "#4E60707F" : "transparent"
                            Column {
                                anchors.centerIn: parent; width: parent.width - 22; spacing: 8
                                Rectangle {
                                    width: 42; height: 42; radius: modelData.isDir ? 13 : 12; anchors.horizontalCenter: parent.horizontalCenter
                                    color: modelData.isDir ? "#355E89BA" : "#26323D"
                                    Text { anchors.centerIn: parent; text: modelData.isDir ? "▱" : "·"; color: modelData.isDir ? blue : textSecondary; font.pixelSize: 17 }
                                }
                                Text { width: parent.width; text: modelData.name; color: textPrimary; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle; font.family: uiFont; font.pixelSize: 10; font.weight: Font.Medium }
                                Text { width: parent.width; text: modelData.modified; color: textTertiary; horizontalAlignment: Text.AlignHCenter; font.family: uiFont; font.pixelSize: 8 }
                            }
                            MouseArea {
                                id: fileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onDoubleClicked: {
                                    if (modelData.isDir) root.refreshFiles(modelData.path)
                                    else systemBackend.openFile(modelData.path)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Nexora Console ----------
    Window {
        id: terminalWindow
        width: 940; height: 590
        minimumWidth: 700; minimumHeight: 430
        visible: false
        title: "Nexora Console"
        color: "#06162B"
        flags: Qt.Window | Qt.FramelessWindowHint

        Rectangle {
            anchors.fill: parent
            radius: 14
            border.color: "#304965"
            border.width: 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#071C36" }
                GradientStop { position: 1.0; color: "#041326" }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                color: "#091522"
                border.color: "#24384C"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 9

                    Rectangle {
                        width: 25; height: 25; radius: 6; color: "#0B65C2"
                        Text { anchors.centerIn: parent; text: ">_"; color: "white"; font.family: "monospace"; font.pixelSize: 10; font.weight: Font.Bold }
                    }
                    Text { text: "Nexora Console"; color: "#F6FAFF"; font.family: uiFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle { width: 1; height: 17; color: "#31506D" }
                    Text {
                        text: systemBackend.terminalSessionReady ? "PowerShell-style · Bash PTY" : "Console sleeping"
                        color: systemBackend.terminalSessionReady ? "#8BC6FF" : "#7D8D9F"
                        font.family: uiFont; font.pixelSize: 9
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: systemBackend.terminalWorkingDirectory; color: "#8797A9"; font.family: "monospace"; font.pixelSize: 8; elide: Text.ElideMiddle; Layout.maximumWidth: 270 }

                    Rectangle {
                        width: 54; height: 28; radius: 7; color: restartTermMouse.containsMouse ? "#173755" : "transparent"
                        Text { anchors.centerIn: parent; text: "Restart"; color: "#BFDFFF"; font.family: uiFont; font.pixelSize: 8 }
                        MouseArea { id: restartTermMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.terminalRestart() }
                    }
                    Rectangle {
                        width: 46; height: 28; radius: 7; color: breakTermMouse.containsMouse ? "#4A2D2D" : "transparent"
                        Text { anchors.centerIn: parent; text: "Break"; color: "#FFB5B5"; font.family: uiFont; font.pixelSize: 8 }
                        MouseArea { id: breakTermMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.terminalInterrupt() }
                    }
                    Rectangle { width: 32; height: 28; radius: 8; color: minTermMouse.containsMouse ? "#183149" : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: "#D8E8F8"; font.pixelSize: 12 }
                        MouseArea { id: minTermMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: terminalWindow.showMinimized() } }
                    Rectangle { width: 32; height: 28; radius: 8; color: maxTermMouse.containsMouse ? "#183149" : "transparent"; Text { anchors.centerIn: parent; text: terminalWindow.visibility === Window.Maximized ? "◇" : "□"; color: "#D8E8F8"; font.pixelSize: 11 }
                        MouseArea { id: maxTermMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: terminalWindow.visibility === Window.Maximized ? terminalWindow.showNormal() : terminalWindow.showMaximized() } }
                    Rectangle { width: 32; height: 28; radius: 8; color: closeTermMouse.containsMouse ? "#7B3131" : "transparent"; Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 15 }
                        MouseArea { id: closeTermMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: terminalWindow.hide() } }
                }
                MouseArea { anchors.fill: parent; z: -1; onPressed: terminalWindow.startSystemMove() }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 28
                color: "#06203E"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 15
                    Text { text: "NEXORA  /  LOCAL CONSOLE"; color: "#6EB8FF"; font.family: "monospace"; font.pixelSize: 8; font.weight: Font.Bold }
                    Item { Layout.fillWidth: true }
                    Text { text: "Ctrl+Alt+T"; color: "#7590AA"; font.family: uiFont; font.pixelSize: 8 }
                }
            }

            ScrollView {
                id: terminalScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                TextArea {
                    id: terminalOutput
                    text: root.terminalHtml
                    textFormat: Text.RichText
                    readOnly: true
                    wrapMode: TextEdit.WrapAnywhere
                    color: "#F3F7FB"
                    font.family: "DejaVu Sans Mono"
                    font.pixelSize: 12
                    padding: 18
                    selectByMouse: true
                    background: Rectangle { color: "#071B33" }
                    onTextChanged: cursorPosition = length
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                color: "#06172C"
                border.color: "#183A5A"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8
                    Text { text: "PS"; color: "#75C8FF"; font.family: "DejaVu Sans Mono"; font.pixelSize: 12; font.weight: Font.Bold }
                    Text { text: ">"; color: "#A4B9CC"; font.family: "DejaVu Sans Mono"; font.pixelSize: 12 }
                    TextField {
                        id: terminalInput
                        Layout.fillWidth: true
                        placeholderText: systemBackend.terminalSessionReady ? "Type a command…" : "Restart console to begin"
                        placeholderTextColor: "#66829D"
                        color: "#FFFFFF"
                        selectionColor: "#2B76B9"
                        selectedTextColor: "white"
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 12
                        enabled: systemBackend.terminalSessionReady
                        background: Item {}
                        onAccepted: {
                            if (text.length > 0) systemBackend.runTerminalCommand(text)
                            text = ""
                        }
                    }
                }
            }
        }
    }

    // ---------- Projects ----------
    Window {
        id: projectsWindow
        width: 940; height: 610
        minimumWidth: 720; minimumHeight: 480
        visible: false
        title: "Projects"
        color: bg1
        flags: Qt.Window | Qt.FramelessWindowHint

        Rectangle { anchors.fill: parent; color: "#10151B"; border.color: "#3D4C5966"; border.width: 1; radius: 16 }
        ColumnLayout {
            anchors.fill: parent; spacing: 0
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 62; color: "#151B22"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 12
                    Rectangle { width: 28; height: 28; radius: 10; color: violet; Text { anchors.centerIn: parent; text: "P"; color: "#0C0913"; font.family: uiFont; font.weight: Font.Bold } }
                    ColumnLayout {
                        Text { text: "Projects"; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { text: "Engineering workspaces, without the engineering-dashboard clutter."; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle { width: 34; height: 32; radius: 10; color: minProjMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: textSecondary; font.pixelSize: 13 }
                        MouseArea { id: minProjMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: projectsWindow.showMinimized() } }
                    Rectangle { width: 34; height: 32; radius: 10; color: maxProjMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: projectsWindow.visibility === Window.Maximized ? "◇" : "□"; color: textSecondary; font.pixelSize: 12 }
                        MouseArea { id: maxProjMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (projectsWindow.visibility === Window.Maximized) projectsWindow.showNormal(); else projectsWindow.showMaximized() } } }
                    Rectangle { width: 34; height: 32; radius: 10; color: closeProjMouse.containsMouse ? "#4B2B2B" : "transparent"; Text { anchors.centerIn: parent; text: "×"; color: textPrimary; font.pixelSize: 16 }
                    MouseArea { id: closeProjMouse; anchors.fill: parent; hoverEnabled: true; onClicked: projectsWindow.hide() } }
                }
                MouseArea { anchors.fill: parent; z: -1; onPressed: projectsWindow.startSystemMove() }
            }

            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 72; Layout.leftMargin: 20; Layout.rightMargin: 20; spacing: 10
                Rectangle {
                    Layout.fillWidth: true; height: 42; radius: 14; color: "#0D1217"; border.color: hairline
                    TextField { id: newProjectName; anchors.fill: parent; anchors.leftMargin: 13; anchors.rightMargin: 13; placeholderText: "New project name"; placeholderTextColor: textTertiary; color: textPrimary; font.family: uiFont; font.pixelSize: 11; background: Item {} }
                }
                Rectangle {
                    width: 112; height: 42; radius: 14; color: newProjectMouse.containsMouse ? "#79F0E0" : accent
                    Text { anchors.centerIn: parent; text: "New project"; color: "#07100F"; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                    MouseArea {
                        id: newProjectMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (newProjectName.text.trim().length > 0) {
                                root.commandResponse = systemBackend.executeIntent("create project " + newProjectName.text)
                                newProjectName.text = ""; root.refreshProjects()
                            }
                        }
                    }
                }
            }

            GridView {
                id: projectGrid
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 18
                cellWidth: 260; cellHeight: 150
                model: root.projectNames
                clip: true
                delegate: Item {
                    width: projectGrid.cellWidth; height: projectGrid.cellHeight
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 6; radius: 20
                        color: projectCardMouse.containsMouse ? "#232C36" : "#171E26"
                        border.color: projectCardMouse.containsMouse ? "#5B6D7C89" : hairline
                        Column {
                            anchors.fill: parent; anchors.margins: 16; spacing: 9
                            Row {
                                width: parent.width
                                spacing: 9
                                Rectangle { width: 34; height: 34; radius: 11; color: "#403D335E"; Text { anchors.centerIn: parent; text: "P"; color: violet; font.family: uiFont; font.weight: Font.Bold } }
                                Text { text: modelData; color: textPrimary; font.family: uiFont; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 48; elide: Text.ElideRight }
                            }
                            Text { text: "Mechanical · Electronics · Simulation · Software · Documents"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; wrapMode: Text.WordWrap; width: parent.width }
                            Item { width: 1; height: 4 }
                            Text { text: "Open workspace  →"; color: accent; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Medium }
                        }
                        MouseArea {
                            id: projectCardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.refreshFiles(systemBackend.projectsDirectory + "/" + modelData); root.presentWindow(filesWindow) }
                        }
                    }
                }
            }
        }
    }

    // ---------- App Center ----------
    Window {
        id: appCenterWindow
        width: 980; height: 660
        minimumWidth: 820; minimumHeight: 540
        visible: false
        title: "App Center"
        color: bg1
        flags: Qt.Window | Qt.FramelessWindowHint

        Rectangle { anchors.fill: parent; color: "#0F141A"; border.color: "#46535F6B"; border.width: 1; radius: 18 }

        ColumnLayout {
            anchors.fill: parent; spacing: 0

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 68; color: "#151B22"; radius: 18
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 14; spacing: 10
                    ColumnLayout {
                        spacing: 1
                        Text { text: "App Center"; color: textPrimary; font.family: uiFont; font.pixelSize: 18; font.weight: Font.DemiBold }
                        Text { text: "Engineering tools and everyday apps"; color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 92; height: 34; radius: 12; color: refreshAppsMouse.containsMouse ? glassHover : "#222A33"
                        Text { anchors.centerIn: parent; text: systemBackend.appJobBusy ? "Working…" : "Refresh"; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                        MouseArea { id: refreshAppsMouse; anchors.fill: parent; hoverEnabled: true; enabled: !systemBackend.appJobBusy; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.refreshAppSources() }
                    }
                    Rectangle {
                        width: 116; height: 34; radius: 12; color: localPkgMouse.containsMouse ? "#2A413D" : "#203631"
                        Text { anchors.centerIn: parent; text: "Install file…"; color: accent; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                        MouseArea { id: localPkgMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: localPackageDialog.open() }
                    }
                    Rectangle { width: 34; height: 32; radius: 10; color: minAppsMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: textSecondary; font.pixelSize: 13 }
                        MouseArea { id: minAppsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: appCenterWindow.showMinimized() } }
                    Rectangle { width: 34; height: 32; radius: 10; color: maxAppsMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: appCenterWindow.visibility === Window.Maximized ? "◇" : "□"; color: textSecondary; font.pixelSize: 12 }
                        MouseArea { id: maxAppsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (appCenterWindow.visibility === Window.Maximized) appCenterWindow.showNormal(); else appCenterWindow.showMaximized() } } }
                    Rectangle { width: 34; height: 34; radius: 11; color: closeAppsMouse.containsMouse ? "#4B2B2B" : "transparent"; Text { anchors.centerIn: parent; text: "×"; color: textPrimary; font.pixelSize: 16 }
                        MouseArea { id: closeAppsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: appCenterWindow.hide() }
                    }
                }
                MouseArea { anchors.fill: parent; z: -1; onPressed: appCenterWindow.startSystemMove() }
            }

            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

                Rectangle {
                    Layout.preferredWidth: 190; Layout.fillHeight: true; color: "#0C1116"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 7
                        Text { text: "Browse"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold; Layout.leftMargin: 8; Layout.bottomMargin: 4 }
                        Repeater {
                            model: ["All", "Engineering", "Development", "Creative", "General"]
                            delegate: Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 12
                                color: root.appCategory === modelData ? "#26343D45" : (appCatMouse.containsMouse ? "#182128" : "transparent")
                                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: root.appCategory === modelData ? textPrimary : textSecondary; font.family: uiFont; font.pixelSize: 10; font.weight: root.appCategory === modelData ? Font.DemiBold : Font.Normal }
                                MouseArea { id: appCatMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.appCategory = modelData }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Text { text: "Sources"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; Layout.leftMargin: 8 }
                        Text { text: "Debian · Flathub\nLocal files · you verify"; color: textSecondary; font.family: uiFont; font.pixelSize: 9; Layout.leftMargin: 8; lineHeight: 1.35 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                    Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 16; Layout.bottomMargin: 16

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 14; color: "#151C23"; border.color: hairline
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8
                            Text { text: "⌕"; color: accent; font.pixelSize: 15 }
                            TextField {
                                id: appSearchField; Layout.fillWidth: true
                                placeholderText: "Search Debian apps and tools"
                                placeholderTextColor: textTertiary; color: textPrimary; font.family: uiFont; font.pixelSize: 11
                                background: Item {}
                                onAccepted: systemBackend.searchDebianPackagesAsync(text)
                            }
                            Rectangle {
                                width: 66; height: 30; radius: 10; color: appSearchMouse.containsMouse ? glassHover : "#222B34"
                                Text { anchors.centerIn: parent; text: systemBackend.appSearchBusy ? "…" : "Search"; color: textSecondary; font.family: uiFont; font.pixelSize: 9 }
                                MouseArea { id: appSearchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.searchDebianPackagesAsync(appSearchField.text) }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 42; radius: 13
                        color: systemBackend.appJobBusy ? "#222D31" : "#121920"; border.color: systemBackend.appJobBusy ? "#4862E7D5" : hairline
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                            Rectangle { width: 7; height: 7; radius: 4; color: systemBackend.appJobBusy ? accent : success }
                            Text { Layout.fillWidth: true; text: systemBackend.appJobStatus; color: textSecondary; font.family: uiFont; font.pixelSize: 9; elide: Text.ElideRight }
                            Text { text: "Software from repositories is verified by its source."; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        ColumnLayout {
                            width: appCenterWindow.width - 245
                            spacing: 8

                            Repeater {
                                model: appSearchField.text.length >= 2 ? systemBackend.appSearchResults : root.appCatalogModel
                                delegate: Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: 72; radius: 17
                                    visible: appSearchField.text.length >= 2 || root.appCategory === "All" || modelData.category === root.appCategory
                                    color: appRowMouse.containsMouse ? "#1A232C" : "#141B22"; border.color: appRowMouse.containsMouse ? "#48586572" : hairline
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                                        Rectangle {
                                            width: 44; height: 44; radius: 14
                                            color: modelData.category === "Engineering" ? "#263538" : (modelData.category === "Development" ? "#262D3B" : "#242B32")
                                            Text { anchors.centerIn: parent; text: modelData.name.substring(0,1).toUpperCase(); color: modelData.category === "Engineering" ? accent : textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.Bold }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 2
                                            Text { text: modelData.name; color: textPrimary; font.family: uiFont; font.pixelSize: 11; font.weight: Font.DemiBold }
                                            Text { text: modelData.summary; color: textSecondary; font.family: uiFont; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: modelData.category + " · " + (modelData.source === "flatpak" ? "Flathub" : "Debian"); color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                        }
                                        Rectangle {
                                            visible: modelData.installed
                                            width: visible ? 62 : 0; height: 32; radius: 11
                                            color: removeAppMouse.containsMouse ? "#432A2D" : "transparent"
                                            Text { anchors.centerIn: parent; text: "Remove"; color: danger; font.family: uiFont; font.pixelSize: 9 }
                                            MouseArea { id: removeAppMouse; anchors.fill: parent; hoverEnabled: true; enabled: !systemBackend.appJobBusy; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.removeCatalogApp(modelData.source, modelData.id) }
                                        }
                                        Rectangle {
                                            width: modelData.installed && modelData.launch !== "" ? 70 : 82; height: 34; radius: 12
                                            color: modelData.installed ? "#20332F" : accent
                                            opacity: systemBackend.appJobBusy ? 0.45 : 1
                                            Text { anchors.centerIn: parent; text: modelData.installed ? (modelData.launch !== "" ? "Open" : "Installed") : "Get"; color: modelData.installed ? accent : "#07110F"; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                                            MouseArea {
                                                id: appRowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                enabled: !systemBackend.appJobBusy && (!modelData.installed || modelData.launch !== "")
                                                onClicked: {
                                                    if (modelData.installed && modelData.launch !== "") systemBackend.launchCatalogApp(modelData.source, modelData.id, modelData.launch)
                                                    else systemBackend.installCatalogApp(modelData.source, modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    // ---------- Notes ----------
    Window {
        id: notesWindow
        width: 760; height: 560
        minimumWidth: 560; minimumHeight: 400
        visible: false
        title: "Notes"
        color: bg1
        flags: Qt.Window | Qt.FramelessWindowHint

        Rectangle { anchors.fill: parent; color: "#10151B"; border.color: "#3D4C5966"; border.width: 1; radius: 16 }
        ColumnLayout {
            anchors.fill: parent; spacing: 0
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 56; color: "#151B22"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; spacing: 10
                    Rectangle { width: 27; height: 27; radius: 9; color: warning; Text { anchors.centerIn: parent; text: "N"; color: "#161008"; font.family: uiFont; font.weight: Font.Bold } }
                    Text { text: "Notes"; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { text: "Local · ~/NexoraNotes/Quick Note.txt"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle }
                    Rectangle {
                        width: 62; height: 32; radius: 10; color: saveNoteMouse.containsMouse ? "#78F4DD" : accent
                        Text { anchors.centerIn: parent; text: "Save"; color: "#07100F"; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Bold }
                        MouseArea { id: saveNoteMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.saveQuickNote(noteEditor.text) }
                    }
                    Rectangle { width: 34; height: 32; radius: 10; color: minNotesMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: textSecondary; font.pixelSize: 13 }
                        MouseArea { id: minNotesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: notesWindow.showMinimized() } }
                    Rectangle { width: 34; height: 32; radius: 10; color: maxNotesMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: notesWindow.visibility === Window.Maximized ? "◇" : "□"; color: textSecondary; font.pixelSize: 12 }
                        MouseArea { id: maxNotesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (notesWindow.visibility === Window.Maximized) notesWindow.showNormal(); else notesWindow.showMaximized() } } }
                    Rectangle { width: 34; height: 32; radius: 10; color: closeNotesMouse.containsMouse ? "#4B2B2B" : "transparent"; Text { anchors.centerIn: parent; text: "×"; color: textPrimary; font.pixelSize: 16 }
                        MouseArea { id: closeNotesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: notesWindow.hide() } }
                }
                MouseArea { anchors.fill: parent; z: -1; onPressed: notesWindow.startSystemMove() }
            }
            TextArea {
                id: noteEditor
                Layout.fillWidth: true; Layout.fillHeight: true
                text: systemBackend.quickNote
                color: textPrimary
                selectionColor: accent
                selectedTextColor: "#07100F"
                placeholderText: "Write anything. Tony can work with project files; Notes stays a simple local scratchpad."
                placeholderTextColor: textTertiary
                wrapMode: TextEdit.Wrap
                font.family: uiFont
                font.pixelSize: 13
                padding: 24
                background: Rectangle { color: "#0D1217" }
            }
        }
        Shortcut { sequence: "Ctrl+S"; onActivated: systemBackend.saveQuickNote(noteEditor.text) }
    }

    // ---------- System Monitor ----------
    Window {
        id: monitorWindow
        width: 980; height: 650
        minimumWidth: 760; minimumHeight: 500
        visible: false
        title: "System Monitor"
        color: bg1
        flags: Qt.Window | Qt.FramelessWindowHint
        property int page: 0
        property real ramPercent: Math.max(0, Math.min(100, systemBackend.memoryUsage))
        property real cpuPercent: Math.max(0, Math.min(100, systemBackend.cpuUsage))
        property string ramUsedText: systemBackend.memoryTotalGiB > 0.01
            ? systemBackend.memoryUsedGiB.toFixed(1) + " / " + systemBackend.memoryTotalGiB.toFixed(1) + " GiB"
            : "Detecting RAM…"
        property string ramAvailableText: systemBackend.memoryTotalGiB > 0.01
            ? Math.max(0, systemBackend.memoryTotalGiB - systemBackend.memoryUsedGiB).toFixed(1) + " GiB available"
            : "Reading /proc/meminfo"

        Timer {
            interval: 2000; repeat: true; running: monitorWindow.visible
            onTriggered: root.processModel = systemBackend.topProcesses()
        }

        Rectangle {
            anchors.fill: parent
            color: "#0C1117"
            border.color: "#31404D"
            border.width: 1
            radius: 18
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Native-style title bar. Keep this deliberately quiet: the monitor
            // should feel like an OS utility, not another dashboard surface.
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 58
                color: "#111820"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 17; anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        width: 29; height: 29; radius: 9
                        color: "#173A46"
                        Text { anchors.centerIn: parent; text: "▥"; color: accent; font.pixelSize: 14 }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "System Monitor"; color: textPrimary; font.family: uiFont; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: "Performance and running processes"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 82; height: 30; radius: 10
                        color: monitorRefreshMouse.containsMouse ? "#202B35" : "#172029"
                        border.color: hairline
                        Row { anchors.centerIn: parent; spacing: 5
                            Text { text: "↻"; color: accent; font.pixelSize: 12 }
                            Text { text: "Refresh"; color: textSecondary; font.family: uiFont; font.pixelSize: 9 }
                        }
                        MouseArea {
                            id: monitorRefreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.processModel = systemBackend.topProcesses()
                        }
                    }
                    Rectangle { width: 34; height: 32; radius: 10; color: minMonitorMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: textSecondary; font.pixelSize: 13 }
                        MouseArea { id: minMonitorMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: monitorWindow.showMinimized() } }
                    Rectangle { width: 34; height: 32; radius: 10; color: maxMonitorMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: monitorWindow.visibility === Window.Maximized ? "◇" : "□"; color: textSecondary; font.pixelSize: 12 }
                        MouseArea { id: maxMonitorMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (monitorWindow.visibility === Window.Maximized) monitorWindow.showNormal(); else monitorWindow.showMaximized() } } }
                    Rectangle { width: 34; height: 32; radius: 10; color: closeMonitorMouse.containsMouse ? "#4B2B2B" : "transparent"; Text { anchors.centerIn: parent; text: "×"; color: textPrimary; font.pixelSize: 16 }
                        MouseArea { id: closeMonitorMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: monitorWindow.hide() } }
                }
                MouseArea { anchors.fill: parent; z: -1; onPressed: monitorWindow.startSystemMove() }
            }

            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 0

                // Task-Manager-inspired navigation: simple, native and familiar.
                Rectangle {
                    Layout.preferredWidth: 154; Layout.fillHeight: true
                    color: "#0E141B"
                    border.color: "#26333E"; border.width: 1
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6
                        Text { text: "MONITOR"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; font.weight: Font.DemiBold; Layout.leftMargin: 8; Layout.topMargin: 6; Layout.bottomMargin: 4 }
                        Repeater {
                            model: [
                                {label:"Overview", glyph:"◫", index:0},
                                {label:"Processes", glyph:"≡", index:1}
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 39; radius: 11
                                color: monitorWindow.page === modelData.index ? "#1B2933" : (monitorNavMouse.containsMouse ? "#151E26" : "transparent")
                                border.color: monitorWindow.page === modelData.index ? "#38505E" : "transparent"
                                Row { anchors.verticalCenter: parent.verticalCenter; x: 11; spacing: 9
                                    Text { text: modelData.glyph; color: monitorWindow.page === modelData.index ? accent : textTertiary; font.pixelSize: 13; width: 18; horizontalAlignment: Text.AlignHCenter }
                                    Text { text: modelData.label; color: monitorWindow.page === modelData.index ? textPrimary : textSecondary; font.family: uiFont; font.pixelSize: 10 }
                                }
                                MouseArea { id: monitorNavMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: monitorWindow.page = modelData.index }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 72; radius: 12
                            color: "#121B23"; border.color: hairline
                            Column { anchors.centerIn: parent; spacing: 3
                                Text { text: systemBackend.coreOnline ? "Nexora Core" : "Recovery telemetry"; color: textSecondary; font.family: uiFont; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 5
                                    Rectangle { width: 6; height: 6; radius: 3; color: systemBackend.coreOnline ? success : warning; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: systemBackend.coreOnline ? "Live" : "Fallback"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                }
                                Text { text: "Updates every 2 s"; color: textTertiary; font.family: uiFont; font.pixelSize: 7; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: monitorWindow.page

                    // ---- Overview ----
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true; Layout.preferredHeight: 190
                                spacing: 12

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 18
                                    color: "#121A22"; border.color: "#263743"
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 18; spacing: 9
                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout { spacing: 1
                                                Text { text: "CPU"; color: textSecondary; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                                                Text { text: "Processor utilization"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text { text: Math.round(monitorWindow.cpuPercent) + "%"; color: accent; font.family: uiFont; font.pixelSize: 30; font.weight: Font.DemiBold }
                                        }
                                        Item { Layout.fillHeight: true }
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 10; radius: 5; color: "#202A33"
                                            Rectangle {
                                                height: parent.height; radius: parent.radius; color: accent
                                                width: parent.width * monitorWindow.cpuPercent / 100.0
                                                Behavior on width { NumberAnimation { duration: 220 } }
                                            }
                                        }
                                        Text { text: "Live system CPU usage"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 18
                                    color: "#121A22"; border.color: "#263743"
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 18; spacing: 8
                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout { spacing: 1
                                                Text { text: "Memory"; color: textSecondary; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                                                Text { text: monitorWindow.ramAvailableText; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text { text: Math.round(monitorWindow.ramPercent) + "%"; color: blue; font.family: uiFont; font.pixelSize: 30; font.weight: Font.DemiBold }
                                        }
                                        Text { text: monitorWindow.ramUsedText; color: textPrimary; font.family: uiFont; font.pixelSize: 13; font.weight: Font.Medium }
                                        Item { Layout.fillHeight: true }
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 10; radius: 5; color: "#202A33"
                                            Rectangle {
                                                height: parent.height; radius: parent.radius; color: blue
                                                width: parent.width * monitorWindow.ramPercent / 100.0
                                                Behavior on width { NumberAnimation { duration: 220 } }
                                            }
                                        }
                                        Text { text: systemBackend.memoryTotalGiB > 0.01 ? "Physical RAM detected correctly" : "Waiting for memory telemetry…"; color: systemBackend.memoryTotalGiB > 0.01 ? textTertiary : warning; font.family: uiFont; font.pixelSize: 8 }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true; Layout.preferredHeight: 92
                                spacing: 12
                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 16; color: "#101820"; border.color: hairline
                                    Column { anchors.centerIn: parent; spacing: 4
                                        Text { text: "Network"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; anchors.horizontalCenter: parent.horizontalCenter }
                                        Text { text: systemBackend.networkConnected ? "Online" : "Offline"; color: systemBackend.networkConnected ? success : warning; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 16; color: "#101820"; border.color: hairline
                                    Column { anchors.centerIn: parent; spacing: 4
                                        Text { text: "Uptime"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; anchors.horizontalCenter: parent.horizontalCenter }
                                        Text { text: systemBackend.uptimeText; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 16; color: "#101820"; border.color: hairline
                                    Column { anchors.centerIn: parent; spacing: 4
                                        Text { text: "Processes shown"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; anchors.horizontalCenter: parent.horizontalCenter }
                                        Text { text: root.processModel.length; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true; radius: 18
                                color: "#0F161D"; border.color: hairline
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Largest memory users"; color: textSecondary; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                                        Item { Layout.fillWidth: true }
                                        Text { text: "Open Processes for full list"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                    }
                                    ListView {
                                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                                        model: root.processModel.slice(0, 6)
                                        delegate: Rectangle {
                                            width: ListView.view.width; height: 35; radius: 9
                                            color: index % 2 ? "#111A22" : "#0D151C"
                                            RowLayout { anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 11; spacing: 8
                                                Text { text: modelData.name; color: textPrimary; font.family: uiFont; font.pixelSize: 9; Layout.preferredWidth: 240; elide: Text.ElideRight }
                                                Text { text: "PID " + modelData.pid; color: textTertiary; font.family: uiFont; font.pixelSize: 8; Layout.fillWidth: true }
                                                Text { text: Number(modelData.memoryMiB).toFixed(1) + " MiB"; color: blue; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Medium }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Processes ----
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout { spacing: 1
                                    Text { text: "Processes"; color: textPrimary; font.family: uiFont; font.pixelSize: 18; font.weight: Font.DemiBold }
                                    Text { text: "Current-user processes sorted by memory"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                }
                                Item { Layout.fillWidth: true }
                                ColumnLayout { spacing: 0
                                    Text { text: monitorWindow.ramUsedText; color: blue; font.family: uiFont; font.pixelSize: 11; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignRight }
                                    Text { text: "RAM · " + Math.round(monitorWindow.ramPercent) + "%"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignRight }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 34; radius: 9
                                color: "#111A22"; border.color: hairline
                                RowLayout { anchors.fill: parent; anchors.leftMargin: 13; anchors.rightMargin: 13
                                    Text { text: "NAME"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; Layout.preferredWidth: 300 }
                                    Text { text: "PID"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; Layout.fillWidth: true }
                                    Text { text: "MEMORY"; color: textTertiary; font.family: uiFont; font.pixelSize: 8; Layout.preferredWidth: 120; horizontalAlignment: Text.AlignRight }
                                }
                            }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                clip: true; spacing: 4
                                model: root.processModel
                                delegate: Rectangle {
                                    width: ListView.view.width; height: 43; radius: 10
                                    color: processMouse.containsMouse ? "#18232C" : (index % 2 ? "#101820" : "#0D151C")
                                    border.color: processMouse.containsMouse ? "#334958" : "transparent"
                                    RowLayout { anchors.fill: parent; anchors.leftMargin: 13; anchors.rightMargin: 13; spacing: 8
                                        Text { text: modelData.name; color: textPrimary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Medium; Layout.preferredWidth: 300; elide: Text.ElideRight }
                                        Text { text: modelData.pid; color: textTertiary; font.family: uiFont; font.pixelSize: 9; Layout.fillWidth: true }
                                        ColumnLayout { Layout.preferredWidth: 120; spacing: 2
                                            Text { text: Number(modelData.memoryMiB).toFixed(1) + " MiB"; color: textSecondary; font.family: uiFont; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; Layout.fillWidth: true }
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: 3; radius: 2; color: "#202A33"
                                                Rectangle {
                                                    height: parent.height; radius: 2; color: blue
                                                    width: parent.width * Math.min(1.0, Number(modelData.memoryMiB) / 1024.0)
                                                }
                                            }
                                        }
                                    }
                                    MouseArea { id: processMouse; anchors.fill: parent; hoverEnabled: true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Settings ----------
    Window {
        id: settingsWindow
        width: 940; height: 620
        minimumWidth: 760; minimumHeight: 500
        visible: false
        title: "Settings"
        color: bg1
        flags: Qt.Window | Qt.FramelessWindowHint

        Rectangle { anchors.fill: parent; color: "#10151B"; border.color: "#3D4C5966"; border.width: 1; radius: 16 }
        RowLayout {
            anchors.fill: parent; spacing: 0

            Rectangle {
                Layout.preferredWidth: 210; Layout.fillHeight: true; color: "#0D1217"; radius: 16
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 6
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: 44
                        Rectangle { width: 27; height: 27; radius: 9; color: "#8C9AAA"; Text { anchors.centerIn: parent; text: "S"; color: "#0A0C0E"; font.family: uiFont; font.weight: Font.Bold } }
                        Text { text: "Settings"; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                    }
                    Repeater {
                        model: ["General", "Appearance", "Privacy", "Tony", "System"]
                        delegate: Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 12
                            color: root.settingsPage === index ? "#283247" : (settingsNavMouse.containsMouse ? "#1B232C" : "transparent")
                            Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: root.settingsPage === index ? textPrimary : textSecondary; font.family: uiFont; font.pixelSize: 11; font.weight: root.settingsPage === index ? Font.DemiBold : Font.Normal }
                            MouseArea { id: settingsNavMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsPage = index }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text { text: "Nexora OS V1"; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 58; color: "#151B22"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 12
                        Text { text: ["General", "Appearance", "Privacy", "Tony", "System"][root.settingsPage]; color: textPrimary; font.family: uiFont; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Rectangle { width: 34; height: 32; radius: 10; color: minSettingsMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: "—"; color: textSecondary; font.pixelSize: 13 }
                            MouseArea { id: minSettingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsWindow.showMinimized() } }
                        Rectangle { width: 34; height: 32; radius: 10; color: maxSettingsMouse.containsMouse ? glassHover : "transparent"; Text { anchors.centerIn: parent; text: settingsWindow.visibility === Window.Maximized ? "◇" : "□"; color: textSecondary; font.pixelSize: 12 }
                            MouseArea { id: maxSettingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (settingsWindow.visibility === Window.Maximized) settingsWindow.showNormal(); else settingsWindow.showMaximized() } } }
                        Rectangle { width: 34; height: 32; radius: 10; color: closeSettingsMouse.containsMouse ? "#4B2B2B" : "transparent"; Text { anchors.centerIn: parent; text: "×"; color: textPrimary; font.pixelSize: 16 }
                    MouseArea { id: closeSettingsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: settingsWindow.hide() } }
                    }
                    MouseArea { anchors.fill: parent; z: -1; onPressed: settingsWindow.startSystemMove() }
                }

                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ColumnLayout {
                        width: settingsWindow.width - 250
                        spacing: 12
                        x: 22; y: 20

                        // GENERAL
                        Text { visible: root.settingsPage === 0; text: "Workspace"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                        Rectangle {
                            visible: root.settingsPage === 0
                            Layout.fillWidth: true; Layout.preferredHeight: 90; radius: 18; color: "#171E26"; border.color: hairline
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 16
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Projects directory"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    Text { text: systemBackend.projectsDirectory; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                                    Text { text: "Project internals stay engineering-aware; the desktop stays simple."; color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                                }
                                Rectangle { width: 72; height: 34; radius: 12; color: "#222B35"; Text { anchors.centerIn: parent; text: "Open"; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openCoreApp("files:" + systemBackend.projectsDirectory) } }
                            }
                        }
                        Text { visible: root.settingsPage === 0; text: "Engineering defaults"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold; Layout.topMargin: 6 }
                        Rectangle {
                            visible: root.settingsPage === 0
                            Layout.fillWidth: true; Layout.preferredHeight: 78; radius: 18; color: "#171E26"; border.color: hairline
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 16
                                ColumnLayout { Layout.fillWidth: true; Text { text: "Units"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Text { text: "SI / metric · project-aware defaults"; color: textTertiary; font.family: uiFont; font.pixelSize: 9 } }
                                Text { text: "SI"; color: accent; font.family: uiFont; font.pixelSize: 11; font.weight: Font.DemiBold }
                            }
                        }

                        // APPEARANCE
                        Text { visible: root.settingsPage === 1; text: "Interface"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                        Rectangle {
                            visible: root.settingsPage === 1
                            Layout.fillWidth: true; Layout.preferredHeight: 106; radius: 18; color: "#171E26"; border.color: hairline
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16; spacing: 8
                                Text { text: "Accent"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Row { spacing: 10
                                    Repeater {
                                        model: ["#62E7D5", "#69B7FF", "#A58CFF", "#FFBF69"]
                                        delegate: Rectangle {
                                            width: 34; height: 34; radius: 12; color: modelData; border.width: root.accent.toString().toUpperCase() === modelData ? 3 : 0; border.color: textPrimary
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.accent = modelData }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: root.settingsPage === 1
                            Layout.fillWidth: true; Layout.preferredHeight: 82; radius: 18; color: "#171E26"; border.color: hairline
                            Column { anchors.fill: parent; anchors.margins: 16; spacing: 5; Text { text: "Motion"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Text { text: "Subtle transitions are enabled. We keep motion informative rather than decorative."; color: textTertiary; font.family: uiFont; font.pixelSize: 9; wrapMode: Text.WordWrap; width: parent.width } }
                        }

                        // PRIVACY
                        Text { visible: root.settingsPage === 2; text: "Context awareness"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                        Rectangle {
                            visible: root.settingsPage === 2
                            Layout.fillWidth: true; Layout.preferredHeight: 92; radius: 18; color: "#171E26"; border.color: hairline
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 16
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Local system context"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    Text { text: systemBackend.privateMode ? "Paused. Tony receives no new work context." : "Active locally. Tony uses this as system and project awareness."; color: textTertiary; font.family: uiFont; font.pixelSize: 9; wrapMode: Text.WordWrap }
                                }
                                Rectangle {
                                    width: 46; height: 26; radius: 13; color: systemBackend.privateMode ? "#37414B" : accent
                                    Rectangle { width: 20; height: 20; radius: 10; color: textPrimary; y: 3; x: systemBackend.privateMode ? 3 : 23; Behavior on x { NumberAnimation { duration: 120 } } }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setPrivateMode(!systemBackend.privateMode) }
                                }
                            }
                        }

                        // TONY
                        Text { visible: root.settingsPage === 3; text: "Local intelligence"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                        Rectangle {
                            visible: root.settingsPage === 3
                            Layout.fillWidth: true; Layout.preferredHeight: 154; radius: 18; color: "#171E26"; border.color: hairline
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16; spacing: 7
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle { width: 9; height: 9; radius: 5; color: systemBackend.tonyModelOnline ? accent : (systemBackend.tonyOnline ? warning : danger) }
                                    Text { text: systemBackend.tonyStatus; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { width: 76; height: 30; radius: 10; color: openTonySettingsMouse.containsMouse ? "#78F4DD" : accent
                                        Text { anchors.centerIn: parent; text: "Open Tony"; color: "#07100F"; font.family: uiFont; font.pixelSize: 9; font.weight: Font.Bold }
                                        MouseArea { id: openTonySettingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openCoreApp("tony") }
                                    }
                                }
                                Text { text: "Inference: llama.cpp · local loopback only"; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                                Text { text: "Memory: ~/.local/share/nexora/tony/memory.db"; color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                                Text { text: "Tony is not root. File deletion, terminal commands, package installs, process termination and power actions require explicit approval."; color: textTertiary; font.family: uiFont; font.pixelSize: 9; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }
                        Rectangle {
                            visible: root.settingsPage === 3
                            Layout.fillWidth: true; Layout.preferredHeight: 118; radius: 18; color: "#171E26"; border.color: hairline
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16; spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { text: "AI memory profile"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        Text { text: systemBackend.tonyModelPolicy === "eco" ? "Eco · unload after ~90 s idle" : (systemBackend.tonyModelPolicy === "always" ? "Always ready · highest RAM use" : "Balanced · unload after ~10 min idle"); color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                                    }
                                    Rectangle {
                                        width: 70; height: 28; radius: 10; color: unloadTonyMouse.containsMouse ? "#303944" : "#242B33"
                                        Text { anchors.centerIn: parent; text: systemBackend.tonyModelOnline ? "Unload" : "Load"; color: textSecondary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                                        MouseArea { id: unloadTonyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.tonyModelOnline ? systemBackend.unloadTonyModel() : systemBackend.loadTonyModel() }
                                    }
                                }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            {label:"Eco", value:"eco"},
                                            {label:"Balanced", value:"balanced"},
                                            {label:"Always", value:"always"}
                                        ]
                                        delegate: Rectangle {
                                            width: modelData.value === "balanced" ? 86 : 68; height: 30; radius: 10
                                            color: systemBackend.tonyModelPolicy === modelData.value ? accent : "#242B33"
                                            border.color: systemBackend.tonyModelPolicy === modelData.value ? accent : hairline
                                            Text { anchors.centerIn: parent; text: modelData.label; color: systemBackend.tonyModelPolicy === modelData.value ? "#07100F" : textSecondary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setTonyModelPolicy(modelData.value) }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: root.settingsPage === 3
                            Layout.fillWidth: true; Layout.preferredHeight: 148; radius: 18; color: "#171E26"; border.color: hairline
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16; spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle { width: 9; height: 9; radius: 5; color: systemBackend.voiceOnline ? (systemBackend.voiceSttReady ? accent : warning) : danger }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 1
                                        Text { text: "Tony Voice"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        Text { text: systemBackend.voiceStatus + " · " + systemBackend.voiceTtsBackend; color: textTertiary; font.family: uiFont; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                    Rectangle { width: 72; height: 30; radius: 10; color: systemBackend.voiceListening ? accent : "#242B33"
                                        Text { anchors.centerIn: parent; text: systemBackend.voiceRequestBusy ? "Starting" : (systemBackend.voiceTranscribing ? "Working" : (systemBackend.voiceListening ? "Stop" : (systemBackend.voiceSpeaking ? "Quiet" : "Listen"))); color: systemBackend.voiceListening ? "#07100F" : textSecondary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                                        MouseArea { anchors.fill: parent; enabled: !systemBackend.voiceRequestBusy && !systemBackend.voiceTranscribing; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.voiceSpeaking ? systemBackend.stopSpeaking() : systemBackend.toggleVoiceListening() }
                                    }
                                }
                                RowLayout { Layout.fillWidth: true
                                    ColumnLayout { Layout.fillWidth: true; spacing: 1
                                        Text { text: "Speak voice replies"; color: textSecondary; font.family: uiFont; font.pixelSize: 10; font.weight: Font.Medium }
                                        Text { text: "Only replies to microphone requests are spoken automatically."; color: textTertiary; font.family: uiFont; font.pixelSize: 8 }
                                    }
                                    Rectangle { width: 44; height: 24; radius: 12; color: systemBackend.voiceSpeakReplies ? accent : "#37414B"
                                        Rectangle { width: 18; height: 18; radius: 9; color: textPrimary; y: 3; x: systemBackend.voiceSpeakReplies ? 23 : 3; Behavior on x { NumberAnimation { duration: 110 } } }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setVoiceSpeakReplies(!systemBackend.voiceSpeakReplies) }
                                    }
                                }
                                RowLayout { Layout.fillWidth: true; spacing: 8
                                    Text { text: "Voice quality"; color: textSecondary; font.family: uiFont; font.pixelSize: 9; Layout.fillWidth: true }
                                    Rectangle { width: 72; height: 28; radius: 9; color: systemBackend.voiceTtsBackend.indexOf("Piper") >= 0 ? accent : "#242B33"
                                        Text { anchors.centerIn: parent; text: "Natural"; color: systemBackend.voiceTtsBackend.indexOf("Piper") >= 0 ? "#07100F" : textSecondary; font.family: uiFont; font.pixelSize: 8; font.weight: Font.DemiBold }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setVoiceTtsBackend("natural") }
                                    }
                                    Rectangle { width: 72; height: 28; radius: 9; color: systemBackend.voiceTtsBackend.indexOf("eSpeak") >= 0 ? accent : "#242B33"
                                        Text { anchors.centerIn: parent; text: "Light"; color: systemBackend.voiceTtsBackend.indexOf("eSpeak") >= 0 ? "#07100F" : textSecondary; font.family: uiFont; font.pixelSize: 8; font.weight: Font.DemiBold }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemBackend.setVoiceTtsBackend("system") }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.settingsPage === 3
                            Layout.fillWidth: true; Layout.preferredHeight: 86; radius: 18; color: "#171E26"; border.color: hairline
                            RowLayout { anchors.fill: parent; anchors.margins: 16
                                ColumnLayout { Layout.fillWidth: true
                                    Text { text: "Always-on awareness"; color: textPrimary; font.family: uiFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    Text { text: systemBackend.privateMode ? "Paused by Private Mode" : "Event-driven · no continuous LLM inference"; color: systemBackend.privateMode ? warning : textTertiary; font.family: uiFont; font.pixelSize: 9 }
                                }
                                Text { text: systemBackend.privateMode ? "OFF" : "ON"; color: systemBackend.privateMode ? warning : accent; font.family: uiFont; font.pixelSize: 10; font.weight: Font.Bold }
                            }
                        }

                        // SYSTEM
                        Text { visible: root.settingsPage === 4; text: "This device"; color: textTertiary; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                        Rectangle {
                            visible: root.settingsPage === 4
                            Layout.fillWidth: true; Layout.preferredHeight: 142; radius: 18; color: "#171E26"; border.color: hairline
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16
                                Text { text: systemBackend.hostname; color: textPrimary; font.family: uiFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Text { text: "Nexora OS " + systemBackend.osVersion; color: accent; font.family: uiFont; font.pixelSize: 10; font.weight: Font.DemiBold }
                                Text { text: "CPU " + Math.round(systemBackend.cpuUsage) + "%   ·   RAM " + systemBackend.memoryUsedGiB.toFixed(1) + " / " + systemBackend.memoryTotalGiB.toFixed(1) + " GiB"; color: textSecondary; font.family: uiFont; font.pixelSize: 10 }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: systemBackend.coreOnline ? "Core services · online" : "Core services · recovery mode"; color: systemBackend.coreOnline ? accent : warning; font.family: uiFont; font.pixelSize: 9; font.weight: Font.DemiBold }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "Kernel " + systemBackend.kernelVersion; color: textTertiary; font.family: uiFont; font.pixelSize: 9 }
                                }
                                Text { text: "Nexora Core now sits between the shell and Linux services, so the desktop can restart without taking system controls, projects, or Tony down with it."; color: textTertiary; font.family: uiFont; font.pixelSize: 9; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
