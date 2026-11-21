//@ pragma ShellId app-launcher
//@ pragma StateDir $BASE/quickshell/appLauncher

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: root

        FileView {
            id: themeFile
            path: Quickshell.env("APP_LAUNCHER_THEME")
                || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                    + "/noctalia/app-launcher.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()

            JsonAdapter {
                id: launcherPalette
                property color primary: "#64e7be"
                property color primaryText: "#00382b"
                property color primaryContainer: "#00513e"
                property color primaryContainerText: "#8ff7d7"
                property color surfaceContainer: "#181c1b"
                property color surfaceContainerLow: "#141817"
                property color surfaceContainerHigh: "#222725"
                property color surfaceText: "#e1e3df"
                property color mutedText: "#bfc9c2"
                property color outlineVariant: "#3f4943"
            }
        }

        FileView {
            id: configFile
            path: Quickshell.env("APP_LAUNCHER_CONFIG")
                || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                    + "/app-launcher/config.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()

            JsonAdapter {
                id: launcherConfig
                property list<string> pinned: []
            }
        }

        property bool passwordMode: false
        PasswordSession {
            id: passwords
            onListed: root.showPasswordStatus()
            onHideForAction: { root.opened = false; root.visible = false }
            onFinished: success => {
                if (success) { passwords.close(); root.passwordMode = false }
                else root.showPasswordStatus()
            }
        }
        function showPasswordStatus(): void {
            opened = true
            const target = focusedScreen()
            if (target) screen = target
            visible = true
            Qt.callLater(() => search.forceActiveFocus())
        }
        function openPasswords(captured: string): void {
            if (passwords.acting) return
            if (passwordMode && opened) { hide(); return }
            if (!passwords.open(captured)) return
            passwordMode = true
            // rbw may open pinentry: never hold layer-shell focus while loading.
            opened = true
            visible = false
            list.currentIndex = 0
            search.text = passwords.context.host || ""
        }
        function appsMode(): void {
            if (passwords.acting) return
            if (passwordMode) {
                passwords.close()
                passwordMode = false
                show()
            } else toggle()
        }
        readonly property var passwordMatches: {
            if (passwords.selected) return passwords.actions.map(name => ({entry: {name: name, genericName: passwords.selected.name, id: "", icon: "dialog-password"}, favorite: false, launches: 0}))
            const query = search.text.trim().toLowerCase()
            return passwords.entries.map(entry => ({
                entry: {name: entry.name, genericName: [entry.username, entry.folder].filter(Boolean).join(" · "), id: entry.id, icon: "dialog-password"},
                metadata: entry, favorite: false, launches: 0,
                score: query ? fuzzyScoreText([entry.name, entry.username, entry.folder].join(" ").toLowerCase(), query) : 0
            })).filter(item => item.score > -Infinity).sort((a, b) => b.score - a.score)
        }
        property bool opened: false
        readonly property var focusedMonitor: Hyprland.focusedMonitor
        onFocusedMonitorChanged: {
            if (opened && !visible && !passwordMode)
                show()
        }
        readonly property bool mouseEnabled: false
        property bool favoritesOnly: false
        property string sortMode: "smart"
        readonly property var apps: DesktopEntries.applications.values.slice()
        readonly property var orderedFavorites: {
            const pinned = [...launcherConfig.pinned]
            const runtime = [...state.favorites]
            return [...pinned, ...runtime.filter(id => !pinned.includes(id))]
        }
        readonly property var matchingApps: {
            const query = search.text.trim().toLowerCase()
            const favorites = orderedFavorites
            const counts = state.launches
            let matches = apps
                .filter(app => !favoritesOnly || favorites.includes(app.id))
                .map(app => {
                    const favoriteIndex = favorites.indexOf(app.id)
                    return {
                        entry: app,
                        favorite: favoriteIndex >= 0,
                        favoriteIndex: favoriteIndex,
                        launches: counts[app.id] || 0,
                        score: query ? fuzzyScore(app, query) : 0
                    }
                })
                .filter(item => !query || item.score > -Infinity)

            matches.sort((a, b) => {
                if (query && a.score !== b.score)
                    return b.score - a.score
                if (sortMode === "smart") {
                    if (a.favorite !== b.favorite)
                        return a.favorite ? -1 : 1
                    if (a.favorite && b.favorite && a.favoriteIndex !== b.favoriteIndex)
                        return a.favoriteIndex - b.favoriteIndex
                    if (a.launches !== b.launches)
                        return b.launches - a.launches
                } else if (sortMode === "used" && a.launches !== b.launches) {
                    return b.launches - a.launches
                }
                return a.entry.name.localeCompare(b.entry.name)
            })
            return matches
        }
        readonly property var results: (passwordMode ? passwordMatches : matchingApps).slice(0, 10)

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
            if (!focusedMonitor)
                return null
            for (const candidate of Quickshell.screens) {
                if (candidate.name === focusedMonitor.name)
                    return candidate
            }
            return null
        }

        function show(): void {
            opened = true
            const targetScreen = focusedScreen()
            if (!targetScreen)
                return
            screen = targetScreen
            visible = true
            search.text = ""
            list.currentIndex = 0
            Qt.callLater(() => search.forceActiveFocus())
        }

        function hide(): void {
            if (passwords.acting) return
            passwords.close()
            passwordMode = false
            opened = false
            visible = false
        }

        function toggle(): void {
            opened ? hide() : show()
        }

        function launchAt(index: int): void {
            if (passwordMode) {
                if (passwords.busy || results.length === 0) return
                if (passwords.selected) passwords.submit(index)
                else {
                    passwords.selected = results[Math.max(0, index)].metadata
                    search.text = ""
                    list.currentIndex = 0
                }
                return
            }
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
            if ([...launcherConfig.pinned].includes(app.id))
                return
            state.favorites = state.favorites.includes(app.id)
                ? state.favorites.filter(id => id !== app.id)
                : [...state.favorites, app.id]
        }

        function toggleSelectedFavorite(): void {
            if (passwordMode || results.length === 0)
                return
            const index = Math.max(0, list.currentIndex)
            toggleFavorite(results[index].entry)
            Qt.callLater(() => list.currentIndex = Math.min(index, results.length - 1))
        }

        function moveSelectedFavorite(delta: int): void {
            if (passwordMode || sortMode !== "smart" || search.text.trim() !== "" || results.length === 0)
                return
            const index = Math.max(0, list.currentIndex)
            const targetIndex = index + delta
            if (index >= results.length || targetIndex < 0 || targetIndex >= results.length)
                return
            const current = results[index]
            const neighbor = results[targetIndex]
            const pinned = [...launcherConfig.pinned]
            if (!current.favorite || !neighbor.favorite || pinned.includes(current.entry.id) || pinned.includes(neighbor.entry.id))
                return
            const next = [...state.favorites]
            const from = next.indexOf(current.entry.id)
            const to = next.indexOf(neighbor.entry.id)
            if (from < 0 || to < 0 || from === to)
                return
            next.splice(from, 1)
            next.splice(to, 0, current.entry.id)
            state.favorites = next
            Qt.callLater(() => list.currentIndex = targetIndex)
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
        mask: Region {}
        visible: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "app-launcher"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Component.onCompleted: {
            console.assert(fuzzyScoreText("firefox", "ffx") > -Infinity, "fuzzy matching failed")
            console.assert(fuzzyScoreText("firefox", "zzz") === -Infinity, "fuzzy rejection failed")
            if (Quickshell.env("APP_LAUNCHER_HIDDEN") !== "1")
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
            function open(): void { if (!passwords.acting) { passwords.close(); root.passwordMode = false; root.show() } }
            function close(): void { root.hide() }
            function toggle(): void { root.appsMode() }
            function passwordMode(context: string): void { root.openPasswords(context) }
            function theme(): string {
                return JSON.stringify({
                    primary: launcherPalette.primary.toString(),
                    selection: launcherPalette.primaryContainer.toString(),
                    text: launcherPalette.surfaceText.toString(),
                    background: card.color.toString()
                })
            }
        }

        GlobalShortcut {
            appid: "ciel-launcher"
            name: "toggle"
            description: "Toggle the application launcher"
            onPressed: root.appsMode()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)

            MouseArea {
                anchors.fill: parent
                enabled: root.mouseEnabled
                onClicked: root.hide()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(760, root.width - 48)
            height: Math.min(610, root.height - 48)
            radius: 0
            color: Qt.rgba(0, 0, 0, 0.60)
            border.width: 1
            border.color: launcherPalette.outlineVariant
            clip: true

            MouseArea {
                anchors.fill: parent
                enabled: root.mouseEnabled
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
                        radius: 0
                        color: launcherPalette.surfaceContainer
                        border.color: launcherPalette.outlineVariant

                        Text {
                            anchors.centerIn: parent
                            text: "󰀻"
                            color: launcherPalette.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: root.passwordMode ? (passwords.selected ? "Choose action" : "Passwords") : "Applications"
                            color: launcherPalette.surfaceText
                            font.family: "Noto Sans"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.passwordMode ? (passwords.message || passwords.entries.length + " logins · metadata only") : root.apps.length + " installed"
                            elide: Text.ElideRight
                            Layout.maximumWidth: 570
                            color: launcherPalette.mutedText
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 42
                        height: 28
                        radius: 0
                        color: launcherPalette.surfaceContainer
                        border.color: launcherPalette.outlineVariant
                        Text {
                            anchors.centerIn: parent
                            text: "ESC"
                            color: launcherPalette.mutedText
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 0
                    color: launcherPalette.surfaceContainerLow
                    border.width: 1
                    border.color: search.activeFocus ? launcherPalette.primary : launcherPalette.outlineVariant
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 13

                        Text {
                            text: "󰍉"
                            color: launcherPalette.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: launcherPalette.surfaceText
                            selectionColor: launcherPalette.primary
                            selectedTextColor: launcherPalette.primaryText
                            font.family: "Noto Sans"
                            font.pixelSize: 17
                            clip: true
                            readOnly: root.passwordMode && (passwords.selected !== null || passwords.busy)
                            onTextChanged: list.currentIndex = 0

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.passwordMode ? (passwords.selected ? "Enter to execute · Escape to go back" : "Search login name, username, or folder…") : "Search by name, description, or keyword..."
                                color: launcherPalette.mutedText
                                font: search.font
                                visible: !search.text
                            }

                            Keys.onPressed: event => {
                                const ctrl = event.modifiers & Qt.ControlModifier
                                const shift = event.modifiers & Qt.ShiftModifier
                                if (root.passwordMode && passwords.busy) { event.accepted = true; return }
                                if (root.passwordMode && ctrl && [Qt.Key_Space, Qt.Key_F, Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_S].includes(event.key)) { event.accepted = true; return }
                                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true
                                    return
                                }
                                if (ctrl && shift && (event.key === Qt.Key_Down || event.key === Qt.Key_J)) root.moveSelectedFavorite(1)
                                else if (ctrl && shift && (event.key === Qt.Key_Up || event.key === Qt.Key_K)) root.moveSelectedFavorite(-1)
                                else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) root.moveSelection(1)
                                else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) root.moveSelection(-1)
                                else if (event.key === Qt.Key_PageDown) root.moveSelection(5)
                                else if (event.key === Qt.Key_PageUp) root.moveSelection(-5)
                                else if (ctrl && event.key === Qt.Key_Home) list.currentIndex = 0
                                else if (ctrl && event.key === Qt.Key_End && root.results.length) list.currentIndex = root.results.length - 1
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
                            Keys.onReleased: event => {
                                if (event.isAutoRepeat) { event.accepted = true; return }
                                if (event.key === Qt.Key_Escape) {
                                    if (root.passwordMode && passwords.selected && !passwords.busy) {
                                        passwords.selected = null
                                        search.text = ""
                                        list.currentIndex = 0
                                    } else root.hide()
                                }
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    root.launchAt(list.currentIndex)
                                else
                                    return
                                event.accepted = true
                            }
                        }

                        Text {
                            text: root.results.length + " / " + (root.passwordMode ? root.passwordMatches.length : root.matchingApps.length)
                            color: launcherPalette.mutedText
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }
                    }
                }

                RowLayout {
                    visible: !root.passwordMode
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
                            radius: 0
                            color: root.sortMode === modelData.key ? launcherPalette.primaryContainer : "transparent"
                            border.width: 1
                            border.color: root.sortMode === modelData.key ? launcherPalette.primary : launcherPalette.outlineVariant
                            Behavior on color { ColorAnimation { duration: 90 } }

                            Text {
                                id: sortText
                                anchors.centerIn: parent
                                text: modelData.label
                                color: root.sortMode === modelData.key ? launcherPalette.primaryContainerText : launcherPalette.mutedText
                                font.family: "Noto Sans"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.mouseEnabled
                                onClicked: root.sortMode = modelData.key
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: favoritesText.width + 26
                        height: 30
                        radius: 0
                        color: root.favoritesOnly ? launcherPalette.primaryContainer : "transparent"
                        border.width: 1
                        border.color: root.favoritesOnly ? launcherPalette.primary : launcherPalette.outlineVariant

                        Text {
                            id: favoritesText
                            anchors.centerIn: parent
                            text: (root.favoritesOnly ? "󰓎  " : "󰓏  ") + "Favorites"
                            color: root.favoritesOnly ? launcherPalette.primaryContainerText : launcherPalette.mutedText
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.mouseEnabled
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
                    interactive: false
                    highlightMoveDuration: 110
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 56
                        radius: 0
                        color: index === list.currentIndex ? launcherPalette.primaryContainer : rowMouse.containsMouse ? launcherPalette.surfaceContainerHigh : "transparent"
                        border.width: index === list.currentIndex ? 1 : 0
                        border.color: launcherPalette.primary
                        Behavior on color { ColorAnimation { duration: 90 } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            enabled: root.mouseEnabled
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
                                radius: 0
                                color: launcherPalette.surfaceContainerHigh
                                border.color: launcherPalette.outlineVariant

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
                                    textFormat: Text.PlainText
                                    text: row.modelData.entry.name
                                    color: launcherPalette.surfaceText
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: row.modelData.entry.genericName || row.modelData.entry.id
                                    color: launcherPalette.mutedText
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 10
                                }
                            }

                            Text {
                                visible: row.modelData.launches > 0
                                text: row.modelData.launches + "×"
                                color: launcherPalette.mutedText
                                font.family: "Noto Sans"
                                font.pixelSize: 10
                            }

                            Rectangle {
                                visible: !root.passwordMode
                                width: 34
                                height: 34
                                radius: 0
                                color: favoriteMouse.containsMouse ? launcherPalette.surfaceContainerHigh : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.favorite ? "󰓎" : "󰓏"
                                    color: row.modelData.favorite ? launcherPalette.primaryContainerText : launcherPalette.mutedText
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 16
                                }

                                MouseArea {
                                    id: favoriteMouse
                                    anchors.fill: parent
                                    enabled: root.mouseEnabled
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
                        text: root.passwordMode ? (passwords.message || "No matching logins. Edit the search to see all entries.") : root.favoritesOnly ? "No favorites yet" : "No matching applications"
                        width: parent.width
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        color: launcherPalette.mutedText
                        font.family: "Noto Sans"
                        font.pixelSize: 14
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.passwordMode ? "↑↓ navigate   ↵ " + (passwords.selected ? "execute" : "actions") + "   esc back / close" : "↑↓ / ctrl+jk navigate   ↵ launch   ctrl+space fav   ctrl+shift+↑↓ reorder"
                        color: launcherPalette.mutedText
                        font.family: "Noto Sans"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.passwordMode ? "Fill never submits" : "ctrl+1/2/3 sort   ctrl+f filter"
                        color: launcherPalette.mutedText
                        font.family: "Noto Sans"
                        font.pixelSize: 10
                    }
                }
            }
        }

    }
}
