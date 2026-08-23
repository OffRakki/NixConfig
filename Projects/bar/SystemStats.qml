import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property int refreshSeconds

    property real cpuPercent: 0
    property real memoryPercent: 0
    property real temperature: 0
    property real downloadBytes: 0
    property real uploadBytes: 0
    property bool available: false

    function parseLine(line: string): void {
        const fields = line.trim().split("\t")
        if (fields.length !== 5)
            return
        const values = fields.map(value => Number(value))
        if (values.some(value => !Number.isFinite(value)))
            return
        cpuPercent = values[0]
        memoryPercent = values[1]
        temperature = values[2]
        downloadBytes = values[3]
        uploadBytes = values[4]
        available = true
    }

    onRefreshSecondsChanged: {
        statsProcess.running = false
        restartTimer.restart()
    }

    Process {
        id: statsProcess
        command: ["sh", Quickshell.shellPath("scripts/system-stats"), root.refreshSeconds.toString()]
        running: true
        stdout: SplitParser {
            onRead: line => root.parseLine(line)
        }
        onExited: {
            root.available = false
            restartTimer.start()
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: statsProcess.running = true
    }
}
