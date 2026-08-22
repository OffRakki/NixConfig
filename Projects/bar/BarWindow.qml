import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland

PanelWindow {
    id: bar

    required property string position
    required property var stats
    required property date now

    readonly property bool horizontal: position === "top" || position === "bottom"
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var workspaceModel: (Hyprland.workspaces.values ?? [])
        .filter(workspace => workspace.id > 0 && workspace.monitor === monitor)
        .sort((a, b) => a.id - b.id)
    readonly property var activeWindow: Hyprland.activeToplevel?.monitor === monitor
        ? Hyprland.activeToplevel
        : null
    readonly property var player: {
        const players = Mpris.players.values ?? []
        return players.find(candidate => candidate.isPlaying) ?? players[0] ?? null
    }
    readonly property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    function bytes(value: real): string {
        if (value >= 1048576)
            return (value / 1048576).toFixed(value >= 10485760 ? 0 : 1) + "M"
        if (value >= 1024)
            return (value / 1024).toFixed(0) + "K"
        return value.toFixed(0) + "B"
    }

    Theme { id: theme }

    Process {
        id: launcherProcess
        command: ["app-launcher"]
    }

    PwObjectTracker {
        objects: bar.sink ? [bar.sink] : []
    }

    anchors {
        top: position !== "bottom"
        bottom: position !== "top"
        left: position !== "right"
        right: position !== "left"
    }
    implicitWidth: horizontal ? 0 : 70
    implicitHeight: horizontal ? 58 : 0
    color: theme.window
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
        item: surface
        radius: surface.radius
    }
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "bar-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: surface
        anchors.fill: parent
        anchors.margins: 5
        radius: theme.radius
        color: theme.surface
        border.width: 1
        border.color: theme.border

        GridLayout {
            anchors.fill: parent
            anchors.margins: 7
            flow: bar.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            columns: bar.horizontal ? 9 : 1
            rows: bar.horizontal ? 1 : 9
            rowSpacing: 6
            columnSpacing: 6

            Rectangle {
                Layout.preferredWidth: bar.horizontal ? 40 : 48
                Layout.preferredHeight: bar.horizontal ? 40 : 48
                radius: theme.chipRadius
                color: launcherMouse.containsMouse ? theme.surfaceHover : theme.surfaceRaised
                border.color: theme.border
                Behavior on color { ColorAnimation { duration: theme.animationFast } }

                Text {
                    anchors.centerIn: parent
                    text: "󰀻"
                    color: theme.accent
                    font.family: theme.mono
                    font.pixelSize: 19
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: launcherProcess.running = true
                }
            }

            Rectangle {
                Layout.preferredWidth: bar.horizontal ? workspaceLayout.implicitWidth + 14 : 48
                Layout.preferredHeight: bar.horizontal ? 40 : workspaceLayout.implicitHeight + 14
                radius: theme.chipRadius
                color: theme.surfaceRaised
                border.color: theme.border

                GridLayout {
                    id: workspaceLayout
                    anchors.centerIn: parent
                    flow: bar.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                    columns: bar.horizontal ? Math.max(1, bar.workspaceModel.length) : 1
                    rows: bar.horizontal ? 1 : Math.max(1, bar.workspaceModel.length)
                    rowSpacing: 4
                    columnSpacing: 4

                    Repeater {
                        model: bar.workspaceModel

                        Rectangle {
                            id: workspaceButton
                            required property var modelData
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 8
                            color: modelData.focused || workspaceMouse.containsMouse
                                ? theme.surfaceHover
                                : "transparent"
                            border.width: 1
                            border.color: modelData.urgent
                                ? "#b66b72"
                                : modelData.focused ? theme.borderActive : theme.border
                            Behavior on color { ColorAnimation { duration: theme.animationFast } }

                            Text {
                                anchors.centerIn: parent
                                text: workspaceButton.modelData.name
                                color: workspaceButton.modelData.focused ? theme.accent : theme.textMuted
                                font.family: theme.sans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: workspaceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: workspaceButton.modelData.activate()
                            }
                        }
                    }

                    Text {
                        visible: bar.workspaceModel.length === 0
                        text: "—"
                        color: theme.textMuted
                        font.family: theme.sans
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: bar.horizontal ? 280 : 48
                Layout.preferredHeight: 40
                radius: theme.chipRadius
                color: theme.surfaceRaised
                border.color: theme.border
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: bar.horizontal ? 11 : 6
                    spacing: 8

                    Text {
                        text: "󰖯"
                        color: theme.textMuted
                        font.family: theme.mono
                        font.pixelSize: 15
                    }

                    Text {
                        visible: bar.horizontal
                        Layout.fillWidth: true
                        text: bar.activeWindow?.title || "Desktop"
                        color: bar.activeWindow ? theme.text : theme.textMuted
                        elide: Text.ElideRight
                        maximumLineCount: bar.horizontal ? 1 : 3
                        wrapMode: bar.horizontal ? Text.NoWrap : Text.Wrap
                        horizontalAlignment: bar.horizontal ? Text.AlignLeft : Text.AlignHCenter
                        font.family: theme.sans
                        font.pixelSize: bar.horizontal ? 12 : 9
                    }
                }
            }

            Item {
                Layout.fillWidth: bar.horizontal
                Layout.fillHeight: !bar.horizontal
                Layout.minimumWidth: bar.horizontal ? 16 : 0
                Layout.minimumHeight: bar.horizontal ? 0 : 16
            }

            Rectangle {
                visible: bar.player !== null
                Layout.preferredWidth: visible ? (bar.horizontal ? 250 : 48) : 0
                Layout.preferredHeight: visible ? (bar.horizontal ? 40 : 112) : 0
                radius: theme.chipRadius
                color: mediaMouse.containsMouse ? theme.surfaceHover : theme.surfaceRaised
                border.color: theme.border
                clip: true
                Behavior on color { ColorAnimation { duration: theme.animationFast } }

                MouseArea {
                    id: mediaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (bar.player?.canTogglePlaying)
                            bar.player.togglePlaying()
                    }
                }

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    flow: bar.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                    columns: bar.horizontal ? 3 : 1
                    rows: bar.horizontal ? 1 : 3
                    rowSpacing: 4
                    columnSpacing: 7

                    Text {
                        text: "󰒮"
                        visible: bar.player?.canGoPrevious ?? false
                        color: theme.textMuted
                        font.family: theme.mono
                        font.pixelSize: 13
                        MouseArea { anchors.fill: parent; onClicked: bar.player.previous() }
                    }
                    ColumnLayout {
                        Layout.fillWidth: bar.horizontal
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: bar.player?.trackTitle || bar.player?.identity || "Media"
                            color: theme.text
                            elide: Text.ElideRight
                            horizontalAlignment: bar.horizontal ? Text.AlignLeft : Text.AlignHCenter
                            font.family: theme.sans
                            font.pixelSize: bar.horizontal ? 11 : 9
                            font.weight: Font.Medium
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: bar.horizontal
                            text: bar.player?.trackArtist || bar.player?.identity || ""
                            color: theme.textMuted
                            elide: Text.ElideRight
                            font.family: theme.sans
                            font.pixelSize: 9
                        }
                    }
                    Text {
                        text: "󰒭"
                        visible: bar.player?.canGoNext ?? false
                        color: theme.textMuted
                        font.family: theme.mono
                        font.pixelSize: 13
                        MouseArea { anchors.fill: parent; onClicked: bar.player.next() }
                    }
                }

            }

            Rectangle {
                Layout.preferredWidth: bar.horizontal ? 260 : 48
                Layout.preferredHeight: bar.horizontal ? 40 : 148
                radius: theme.chipRadius
                color: theme.surfaceRaised
                border.color: theme.border

                GridLayout {
                    anchors.centerIn: parent
                    flow: bar.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                    columns: bar.horizontal ? 4 : 1
                    rows: bar.horizontal ? 1 : 4
                    rowSpacing: 5
                    columnSpacing: 12

                    Text {
                        text: "󰍛 " + (bar.stats.available ? bar.stats.cpuPercent.toFixed(0) + "%" : "—")
                        color: theme.textMuted
                        font.family: theme.mono
                        font.pixelSize: 10
                    }
                    Text {
                        text: "󰘚 " + (bar.stats.available ? bar.stats.memoryPercent.toFixed(0) + "%" : "—")
                        color: theme.textMuted
                        font.family: theme.mono
                        font.pixelSize: 10
                    }
                    Text {
                        text: "󰔄 " + (bar.stats.available ? bar.stats.temperature.toFixed(0) + "°" : "—")
                        color: theme.textMuted
                        font.family: theme.mono
                        font.pixelSize: 10
                    }
                    Text {
                        text: !bar.stats.available
                            ? "󰇚 —  󰕒 —"
                            : bar.horizontal
                                ? "󰇚 " + bar.bytes(bar.stats.downloadBytes) + "  󰕒 " + bar.bytes(bar.stats.uploadBytes)
                                : "󰇚 " + bar.bytes(bar.stats.downloadBytes) + "\n󰕒 " + bar.bytes(bar.stats.uploadBytes)
                        color: theme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.family: theme.mono
                        font.pixelSize: 9
                    }
                }
            }

            Rectangle {
                readonly property int itemCount: SystemTray.items.values?.length ?? 0
                Layout.preferredWidth: bar.horizontal ? Math.max(40, trayLayout.implicitWidth + 12) : 48
                Layout.preferredHeight: bar.horizontal ? 40 : Math.max(40, trayLayout.implicitHeight + 12)
                visible: itemCount > 0
                radius: theme.chipRadius
                color: theme.surfaceRaised
                border.color: theme.border

                GridLayout {
                    id: trayLayout
                    anchors.centerIn: parent
                    flow: bar.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                    columns: bar.horizontal ? Math.max(1, SystemTray.items.values?.length ?? 0) : 1
                    rows: bar.horizontal ? 1 : Math.max(1, SystemTray.items.values?.length ?? 0)
                    rowSpacing: 3
                    columnSpacing: 3

                    Repeater {
                        model: SystemTray.items

                        Rectangle {
                            id: trayItem
                            required property var modelData
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 8
                            color: trayMouse.containsMouse ? theme.surfaceHover : "transparent"

                            Image {
                                anchors.centerIn: parent
                                width: 17
                                height: 17
                                source: trayItem.modelData.icon
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: event => {
                                    if (event.button === Qt.RightButton && trayItem.modelData.hasMenu) {
                                        const point = trayItem.mapToItem(null, 0, trayItem.height)
                                        trayItem.modelData.display(bar, point.x, point.y)
                                    } else if (event.button === Qt.MiddleButton)
                                        trayItem.modelData.secondaryActivate()
                                    else
                                        trayItem.modelData.activate()
                                }
                                onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: bar.horizontal ? 74 : 48
                Layout.preferredHeight: 40
                radius: theme.chipRadius
                color: volumeMouse.containsMouse ? theme.surfaceHover : theme.surfaceRaised
                border.color: theme.border
                Behavior on color { ColorAnimation { duration: theme.animationFast } }

                Text {
                    anchors.centerIn: parent
                    text: (bar.muted ? "󰝟" : bar.volume > 0.55 ? "󰕾" : bar.volume > 0 ? "󰖀" : "󰕿")
                        + (bar.horizontal ? "  " + Math.round(bar.volume * 100) : "")
                    color: bar.muted ? theme.textDim : theme.text
                    font.family: theme.mono
                    font.pixelSize: 12
                }

                MouseArea {
                    id: volumeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (bar.sink?.audio)
                            bar.sink.audio.muted = !bar.sink.audio.muted
                    }
                    onWheel: wheel => {
                        if (bar.sink?.audio)
                            bar.sink.audio.volume = Math.max(0, Math.min(1, bar.sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: bar.horizontal ? 124 : 48
                Layout.preferredHeight: bar.horizontal ? 40 : 66
                radius: theme.chipRadius
                color: theme.surfaceRaised
                border.color: theme.border

                Text {
                    anchors.centerIn: parent
                    text: bar.horizontal
                        ? Qt.formatDateTime(bar.now, "ddd  dd MMM  HH:mm")
                        : Qt.formatDateTime(bar.now, "HH:mm\ndd/MM")
                    color: theme.text
                    horizontalAlignment: Text.AlignHCenter
                    font.family: theme.sans
                    font.pixelSize: bar.horizontal ? 11 : 10
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
