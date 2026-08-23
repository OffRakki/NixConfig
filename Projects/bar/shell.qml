//@ pragma ShellId bar
//@ pragma StateDir $BASE/quickshell/bar
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: shell

    readonly property list<string> positions: ["left", "right", "top", "bottom"]
    property var settingsScreen: Quickshell.screens[0] ?? null
    property bool settingsVisible: false
    readonly property var barSettings: settings

    function focusedScreen(): var {
        for (const candidate of Quickshell.screens) {
            if (Hyprland.monitorFor(candidate) === Hyprland.focusedMonitor)
                return candidate
        }
        return Quickshell.screens.includes(settingsScreen) ? settingsScreen : Quickshell.screens[0]
    }

    function validColor(value: string, fallback: string): string {
        return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value) ? value : fallback
    }

    function validateSettings(): void {
        settings.position = positions.includes(settings.position) ? settings.position : "left"
        settings.fontFamily = settings.fontFamily.trim() || "Noto Sans"
        settings.fontScale = Math.max(0.75, Math.min(1.5, settings.fontScale))
        settings.horizontalSize = Math.max(44, Math.min(96, settings.horizontalSize))
        settings.verticalSize = Math.max(54, Math.min(110, settings.verticalSize))
        settings.opacity = Math.max(0.55, Math.min(1, settings.opacity))
        settings.radius = Math.max(0, Math.min(30, settings.radius))
        settings.outerMargin = Math.max(0, Math.min(16, settings.outerMargin))
        settings.metricsInterval = Math.max(1, Math.min(10, settings.metricsInterval))
        settings.surfaceColor = validColor(settings.surfaceColor, "#101115")
        settings.raisedColor = validColor(settings.raisedColor, "#191a1f")
        settings.hoverColor = validColor(settings.hoverColor, "#24262c")
        settings.borderColor = validColor(settings.borderColor, "#34363d")
        settings.textColor = validColor(settings.textColor, "#eeeeef")
        settings.mutedColor = validColor(settings.mutedColor, "#777a83")
        settings.accentColor = validColor(settings.accentColor, "#e4e5e8")
    }

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

    function showSettings(targetScreen: var): void {
        settingsScreen = targetScreen ?? focusedScreen()
        settingsVisible = true
    }

    function toggleSettings(targetScreen: var): bool {
        if (settingsVisible) {
            settingsVisible = false
        } else {
            showSettings(targetScreen)
        }
        return settingsVisible
    }

    function resetSettings(): void {
        settings.position = "left"
        settings.fontFamily = "Noto Sans"
        settings.fontScale = 1.0
        settings.horizontalSize = 58
        settings.verticalSize = 70
        settings.opacity = 0.96
        settings.radius = 16
        settings.outerMargin = 5
        settings.showLauncher = true
        settings.showWorkspaces = true
        settings.showTitle = true
        settings.showMedia = true
        settings.showMetrics = true
        settings.showTray = true
        settings.showVolume = true
        settings.showClock = true
        settings.showSettingsButton = true
        settings.metricsInterval = 2
        settings.networkBits = false
        settings.clock24Hour = true
        settings.showDate = true
        settings.surfaceColor = "#101115"
        settings.raisedColor = "#191a1f"
        settings.hoverColor = "#24262c"
        settings.borderColor = "#34363d"
        settings.textColor = "#eeeeef"
        settings.mutedColor = "#777a83"
        settings.accentColor = "#e4e5e8"
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            if (!Quickshell.screens.includes(shell.settingsScreen))
                shell.settingsScreen = shell.focusedScreen()
            if (Quickshell.screens.length === 0)
                shell.settingsVisible = false
        }
    }

    SystemStats {
        id: systemStats
        refreshSeconds: shell.barSettings.metricsInterval
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
        onLoaded: {
            shell.validateSettings()
            saveTimer.restart()
        }
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                saveTimer.restart()
        }

        JsonAdapter {
            id: settings
            property string position: "left"
            property string fontFamily: "Noto Sans"
            property real fontScale: 1.0
            property int horizontalSize: 58
            property int verticalSize: 70
            property real opacity: 0.96
            property int radius: 16
            property int outerMargin: 5
            property bool showLauncher: true
            property bool showWorkspaces: true
            property bool showTitle: true
            property bool showMedia: true
            property bool showMetrics: true
            property bool showTray: true
            property bool showVolume: true
            property bool showClock: true
            property bool showSettingsButton: true
            property int metricsInterval: 2
            property bool networkBits: false
            property bool clock24Hour: true
            property bool showDate: true
            property string surfaceColor: "#101115"
            property string raisedColor: "#191a1f"
            property string hoverColor: "#24262c"
            property string borderColor: "#34363d"
            property string textColor: "#eeeeef"
            property string mutedColor: "#777a83"
            property string accentColor: "#e4e5e8"

            onPositionChanged: {
                if (!shell.positions.includes(position))
                    position = "left"
            }
            onFontScaleChanged: fontScale = Math.max(0.75, Math.min(1.5, fontScale))
            onHorizontalSizeChanged: horizontalSize = Math.max(44, Math.min(96, horizontalSize))
            onVerticalSizeChanged: verticalSize = Math.max(54, Math.min(110, verticalSize))
            onOpacityChanged: opacity = Math.max(0.55, Math.min(1, opacity))
            onRadiusChanged: radius = Math.max(0, Math.min(30, radius))
            onOuterMarginChanged: outerMargin = Math.max(0, Math.min(16, outerMargin))
            onMetricsIntervalChanged: metricsInterval = Math.max(1, Math.min(10, metricsInterval))
            onSurfaceColorChanged: surfaceColor = shell.validColor(surfaceColor, "#101115")
            onRaisedColorChanged: raisedColor = shell.validColor(raisedColor, "#191a1f")
            onHoverColorChanged: hoverColor = shell.validColor(hoverColor, "#24262c")
            onBorderColorChanged: borderColor = shell.validColor(borderColor, "#34363d")
            onTextColorChanged: textColor = shell.validColor(textColor, "#eeeeef")
            onMutedColorChanged: mutedColor = shell.validColor(mutedColor, "#777a83")
            onAccentColorChanged: accentColor = shell.validColor(accentColor, "#e4e5e8")
        }
    }

    IpcHandler {
        target: "bar"
        function position(): string { return settings.position }
        function setPosition(position: string): bool { return shell.setPosition(position) }
        function cyclePosition(): string { return shell.cyclePosition() }
        function showSettings(): void { shell.showSettings(null) }
        function hideSettings(): void { shell.settingsVisible = false }
        function toggleSettings(): bool { return shell.toggleSettings(null) }
        function settingsOpen(): bool { return shell.settingsVisible }
        function resetSettings(): void { shell.resetSettings() }
        function saveSettings(): void { settingsFile.writeAdapter() }
    }

    SettingsWindow {
        screen: shell.settingsScreen ?? Quickshell.screens[0]
        visible: shell.settingsVisible
        settings: shell.barSettings
        positions: shell.positions
        onCloseRequested: shell.settingsVisible = false
        onResetRequested: shell.resetSettings()
    }

    Variants {
        model: Quickshell.screens

        BarWindow {
            required property ShellScreen modelData
            screen: modelData
            position: shell.barSettings.position
            settings: shell.barSettings
            stats: systemStats
            now: clock.date
            onSettingsRequested: shell.toggleSettings(modelData)
        }
    }
}
