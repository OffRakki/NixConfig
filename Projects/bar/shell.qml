//@ pragma ShellId ciel-bar
//@ pragma StateDir $BASE/quickshell/bar
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell

    readonly property list<string> positions: ["left", "right", "top", "bottom"]

    function setPosition(position: string): bool {
        if (!positions.includes(position))
            return false
        settings.position = position
        return true
    }

    function cyclePosition(): string {
        const index = positions.indexOf(settings.position)
        settings.position = positions[(index + 1) % positions.length]
        return settings.position
    }

    SystemStats {
        id: systemStats
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Timer {
        id: saveTimer
        interval: 120
        onTriggered: settingsFile.writeAdapter()
    }

    FileView {
        id: settingsFile
        path: Quickshell.statePath("settings.json")
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                saveTimer.restart()
        }

        JsonAdapter {
            id: settings
            property string position: "left"
            onPositionChanged: {
                if (!shell.positions.includes(position))
                    position = "left"
            }
        }
    }

    IpcHandler {
        target: "bar"
        function position(): string { return settings.position }
        function setPosition(position: string): bool { return shell.setPosition(position) }
        function cyclePosition(): string { return shell.cyclePosition() }
    }

    Variants {
        model: Quickshell.screens

        BarWindow {
            required property ShellScreen modelData
            screen: modelData
            position: settings.position
            stats: systemStats
            now: clock.date
        }
    }
}
