import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: root

        property bool opened: false
        property bool mouseArmed: false
        property bool favoritesOnly: false
        property string sortMode: "smart"
        readonly property var apps: DesktopEntries.applications.values.slice()
        readonly property var matchingApps: {
            const query = search.text.trim().toLowerCase()
            const favorites = state.favorites
            const counts = state.launches
            let matches = apps
                .filter(app => !favoritesOnly || favorites.includes(app.id))
                .map(app => ({
                    entry: app,
                    favorite: favorites.includes(app.id),
                    launches: counts[app.id] || 0,
                    score: query ? fuzzyScore(app, query) : 0
                }))
                .filter(item => !query || item.score > -Infinity)

            matches.sort((a, b) => {
                if (query && a.score !== b.score)
                    return b.score - a.score
                if (sortMode === "smart") {
                    if (a.favorite !== b.favorite)
                        return a.favorite ? -1 : 1
                    if (a.launches !== b.launches)
                        return b.launches - a.launches
                } else if (sortMode === "used" && a.launches !== b.launches) {
                    return b.launches - a.launches
                }
                return a.entry.name.localeCompare(b.entry.name)
            })
            return matches
        }
        readonly property var results: matchingApps.slice(0, 10)

        function fuzzyScoreText(text: string, query: string): real {
            let position = -1
            let streak = 0
            let score = 0
            for (const character of query) {
                const next = text.indexOf(character, position + 1)
                if (next < 0)
                    return -Infinity
                streak = next === position + 1 ? streak + 1 : 0
                score += 10 + streak * 8 - (next - position - 1)
                if (next === 0 || " -_/".includes(text[next - 1]))
                    score += 18
                position = next
            }
            return score - text.length * 0.02
        }

        function fuzzyScore(app: var, query: string): real {
            const name = app.name.toLowerCase()
            const text = [name, app.genericName, ...(app.keywords ?? [])].join(" ").toLowerCase()
            return fuzzyScoreText(text, query) + (name.startsWith(query) ? 120 : 0)
        }

        function focusedScreen(): var {
            for (const candidate of Quickshell.screens) {
                if (Hyprland.monitorFor(candidate) === Hyprland.focusedMonitor)
                    return candidate
            }
            return root.screen ?? Quickshell.screens[0]
        }

        function show(): void {
            const targetScreen = focusedScreen()
            if (targetScreen)
                screen = targetScreen
            mouseArmed = false
            visible = true
            opened = true
            search.text = ""
            list.currentIndex = 0
            Qt.callLater(() => search.forceActiveFocus())
        }

        function hide(): void {
            opened = false
            visible = false
        }

        function toggle(): void {
            opened ? hide() : show()
        }

        function launchAt(index: int): void {
            if (results.length === 0)
                return
            const app = results[Math.max(0, Math.min(index, results.length - 1))].entry
            const launches = Object.assign({}, state.launches)
            launches[app.id] = (launches[app.id] || 0) + 1
            state.launches = launches
            app.execute()
            hide()
        }

        function toggleFavorite(app: var): void {
            state.favorites = state.favorites.includes(app.id)
                ? state.favorites.filter(id => id !== app.id)
                : [...state.favorites, app.id]
        }

        function toggleSelectedFavorite(): void {
            if (results.length === 0)
                return
            const index = Math.max(0, list.currentIndex)
            toggleFavorite(results[index].entry)
            Qt.callLater(() => list.currentIndex = Math.min(index, results.length - 1))
        }

        function moveSelection(amount: int): void {
            if (results.length)
                list.currentIndex = Math.max(0, Math.min(results.length - 1, list.currentIndex + amount))
        }

        function cycleSort(): void {
            sortMode = sortMode === "smart" ? "name" : sortMode === "name" ? "used" : "smart"
        }

        anchors { top: true; right: true; bottom: true; left: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ciel-app-launcher"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Component.onCompleted: {
            console.assert(fuzzyScoreText("firefox", "ffx") > -Infinity, "fuzzy matching failed")
            console.assert(fuzzyScoreText("firefox", "zzz") === -Infinity, "fuzzy rejection failed")
            Qt.callLater(() => root.show())
        }

        Timer {
            id: saveTimer
            interval: 120
            onTriggered: stateFile.writeAdapter()
        }

        FileView {
            id: stateFile
            path: Quickshell.statePath("launcher.json")
            onAdapterUpdated: saveTimer.restart()
            onLoadFailed: error => {
                if (error === FileViewError.FileNotFound)
                    saveTimer.restart()
            }

            JsonAdapter {
                id: state
                property list<string> favorites: []
                property var launches: ({})
            }
        }

        IpcHandler {
            target: "launcher"
            function open(): void { root.show() }
            function close(): void { root.hide() }
            function toggle(): void { root.toggle() }
        }

        GlobalShortcut {
            appid: "ciel-launcher"
            name: "toggle"
            description: "Toggle the application launcher"
            onPressed: root.toggle()
        }

        Rectangle {
            anchors.fill: parent
            color: "#80090a0d"

            MouseArea {
                anchors.fill: parent
                enabled: root.mouseArmed
                onClicked: root.hide()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(760, root.width - 48)
            height: Math.min(610, root.height - 48)
            radius: 24
            color: "#f5101115"
            border.width: 1
            border.color: "#34363d"
            clip: true

            MouseArea {
                anchors.fill: parent
                enabled: root.mouseArmed
                onClicked: event => event.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 12
                        color: "#202126"
                        border.color: "#34363d"

                        Text {
                            anchors.centerIn: parent
                            text: "󰀻"
                            color: "#e7e8ec"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Applications"
                            color: "#f2f3f5"
                            font.family: "Noto Sans"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.apps.length + " installed"
                            color: "#777a83"
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 42
                        height: 28
                        radius: 8
                        color: "#1c1d22"
                        border.color: "#30323a"
                        Text {
                            anchors.centerIn: parent
                            text: "ESC"
                            color: "#777a83"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 16
                    color: "#191a1f"
                    border.width: 1
                    border.color: search.activeFocus ? "#6d707b" : "#30323a"
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 13

                        Text {
                            text: "󰍉"
                            color: "#8b8e98"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: "#eeeeef"
                            selectionColor: "#555861"
                            selectedTextColor: "white"
                            font.family: "Noto Sans"
                            font.pixelSize: 17
                            clip: true
                            onTextChanged: list.currentIndex = 0

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search by name, description, or keyword..."
                                color: "#62656e"
                                font: search.font
                                visible: !search.text
                            }

                            Keys.onPressed: event => {
                                const ctrl = event.modifiers & Qt.ControlModifier
                                if (event.key === Qt.Key_Escape) root.hide()
                                else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) root.moveSelection(1)
                                else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) root.moveSelection(-1)
                                else if (event.key === Qt.Key_PageDown) root.moveSelection(5)
                                else if (event.key === Qt.Key_PageUp) root.moveSelection(-5)
                                else if (ctrl && event.key === Qt.Key_Home) list.currentIndex = 0
                                else if (ctrl && event.key === Qt.Key_End && root.results.length) list.currentIndex = root.results.length - 1
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.launchAt(list.currentIndex)
                                else if (ctrl && event.key === Qt.Key_Space) root.toggleSelectedFavorite()
                                else if (ctrl && event.key === Qt.Key_F) root.favoritesOnly = !root.favoritesOnly
                                else if (ctrl && event.key === Qt.Key_1) root.sortMode = "smart"
                                else if (ctrl && event.key === Qt.Key_2) root.sortMode = "name"
                                else if (ctrl && event.key === Qt.Key_3) root.sortMode = "used"
                                else if (ctrl && event.key === Qt.Key_S) root.cycleSort()
                                else if (ctrl && event.key === Qt.Key_L) search.text = ""
                                else return
                                event.accepted = true
                            }
                        }

                        Text {
                            text: root.results.length + " / " + root.matchingApps.length
                            color: "#70737c"
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { key: "smart", label: "1  Smart" },
                            { key: "name", label: "2  A–Z" },
                            { key: "used", label: "3  Most used" }
                        ]

                        Rectangle {
                            required property var modelData
                            width: sortText.width + 24
                            height: 30
                            radius: 9
                            color: root.sortMode === modelData.key ? "#2a2c32" : "transparent"
                            border.width: 1
                            border.color: root.sortMode === modelData.key ? "#474a53" : "#292b31"
                            Behavior on color { ColorAnimation { duration: 90 } }

                            Text {
                                id: sortText
                                anchors.centerIn: parent
                                text: modelData.label
                                color: root.sortMode === modelData.key ? "#e4e5e8" : "#797c85"
                                font.family: "Noto Sans"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.mouseArmed
                                onClicked: root.sortMode = modelData.key
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: favoritesText.width + 26
                        height: 30
                        radius: 9
                        color: root.favoritesOnly ? "#2a2c32" : "transparent"
                        border.width: 1
                        border.color: root.favoritesOnly ? "#474a53" : "#292b31"

                        Text {
                            id: favoritesText
                            anchors.centerIn: parent
                            text: (root.favoritesOnly ? "󰓎  " : "󰓏  ") + "Favorites"
                            color: root.favoritesOnly ? "#e4e5e8" : "#797c85"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.mouseArmed
                            onClicked: root.favoritesOnly = !root.favoritesOnly
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.results
                    spacing: 5
                    clip: true
                    currentIndex: 0
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 110
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 56
                        radius: 14
                        color: index === list.currentIndex ? "#24262c" : rowMouse.containsMouse ? "#1b1c21" : "transparent"
                        border.width: index === list.currentIndex ? 1 : 0
                        border.color: "#3b3d45"
                        Behavior on color { ColorAnimation { duration: 90 } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            enabled: root.mouseArmed
                            hoverEnabled: true
                            onEntered: list.currentIndex = row.index
                            onClicked: {
                                list.currentIndex = row.index
                                root.launchAt(row.index)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 12
                            spacing: 13

                            Rectangle {
                                width: 40
                                height: 40
                                radius: 11
                                color: "#1b1c21"
                                border.color: "#2c2e34"

                                Image {
                                    anchors.centerIn: parent
                                    width: 27
                                    height: 27
                                    source: Quickshell.iconPath(row.modelData.entry.icon, "application-x-executable")
                                    sourceSize.width: 54
                                    sourceSize.height: 54
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.entry.name
                                    color: "#eeeeef"
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.entry.genericName || row.modelData.entry.id
                                    color: "#70737c"
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 10
                                }
                            }

                            Text {
                                visible: row.modelData.launches > 0
                                text: row.modelData.launches + "×"
                                color: "#686b74"
                                font.family: "Noto Sans"
                                font.pixelSize: 10
                            }

                            Rectangle {
                                width: 34
                                height: 34
                                radius: 10
                                color: favoriteMouse.containsMouse ? "#303239" : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.favorite ? "󰓎" : "󰓏"
                                    color: row.modelData.favorite ? "#e4e5e8" : "#666972"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 16
                                }

                                MouseArea {
                                    id: favoriteMouse
                                    anchors.fill: parent
                                    enabled: root.mouseArmed
                                    hoverEnabled: true
                                    onClicked: event => {
                                        root.toggleFavorite(row.modelData.entry)
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.results.length === 0
                        text: root.favoritesOnly ? "No favorites yet" : "No matching applications"
                        color: "#747780"
                        font.family: "Noto Sans"
                        font.pixelSize: 14
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "↑↓ / ctrl+jk navigate   ↵ launch   ctrl+space favorite"
                        color: "#5f626b"
                        font.family: "Noto Sans"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "ctrl+1/2/3 sort   ctrl+f filter"
                        color: "#5f626b"
                        font.family: "Noto Sans"
                        font.pixelSize: 10
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.visible && !root.mouseArmed
            hoverEnabled: true
            onPositionChanged: root.mouseArmed = true
            onWheel: wheel => wheel.accepted = true
        }
    }
}
