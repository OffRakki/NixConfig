import QtQuick

QtObject {
    required property var settings

    readonly property color window: "#00ffffff"
    readonly property color surfaceBase: settings.surfaceColor
    readonly property color raisedBase: settings.raisedColor
    readonly property color hoverBase: settings.hoverColor
    readonly property color surface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, settings.opacity)
    readonly property color surfaceRaised: Qt.rgba(raisedBase.r, raisedBase.g, raisedBase.b, settings.opacity)
    readonly property color surfaceHover: Qt.rgba(hoverBase.r, hoverBase.g, hoverBase.b, settings.opacity)
    readonly property color border: settings.borderColor
    readonly property color borderActive: Qt.lighter(settings.borderColor, 1.55)
    readonly property color text: settings.textColor
    readonly property color textMuted: settings.mutedColor
    readonly property color textDim: Qt.darker(settings.mutedColor, 1.2)
    readonly property color accent: settings.accentColor
    readonly property string sans: settings.fontFamily
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property real fontScale: settings.fontScale
    readonly property int radius: settings.radius
    readonly property int chipRadius: Math.max(4, Math.round(settings.radius * 0.69))
    readonly property int animationFast: 100
}
