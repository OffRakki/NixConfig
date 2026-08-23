import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: settingsWindow

    required property var settings
    required property var positions

    signal closeRequested
    signal resetRequested

    readonly property var fontFamilies: Qt.fontFamilies().sort((a, b) => a.localeCompare(b))
    readonly property color panelSurface: Qt.rgba(theme.surfaceBase.r, theme.surfaceBase.g, theme.surfaceBase.b, 0.98)
    readonly property color panelRaised: Qt.rgba(theme.raisedBase.r, theme.raisedBase.g, theme.raisedBase.b, 0.98)

    Theme {
        id: theme
        settings: settingsWindow.settings
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "#9907080b"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bar-settings"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible)
            focusScope.forceActiveFocus()
    }

    Shortcut {
        enabled: settingsWindow.visible
        sequence: "Escape"
        onActivated: settingsWindow.closeRequested()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: settingsWindow.closeRequested()
    }

    component SectionCard: Rectangle {
        id: card
        required property string title
        default property alias contents: body.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: body.implicitHeight + 82
        radius: 16
        color: settingsWindow.panelRaised
        border.width: 1
        border.color: theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Text {
                text: card.title
                color: theme.text
                font.family: theme.sans
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: theme.border
            }

            ColumnLayout {
                id: body
                Layout.fillWidth: true
                spacing: 8
            }
        }
    }

    component ToggleRow: Item {
        id: toggleRow
        required property string label
        required property bool checked
        signal changed(bool value)

        Layout.fillWidth: true
        implicitHeight: 38

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: toggleRow.label
            color: theme.text
            font.family: theme.sans
            font.pixelSize: 12
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            height: 22
            radius: 11
            color: toggleRow.checked ? theme.accent : theme.surfaceHover
            border.width: 1
            border.color: toggleRow.checked ? theme.accent : theme.border

            Rectangle {
                x: toggleRow.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: toggleRow.checked ? theme.surfaceBase : theme.textMuted
                Behavior on x { NumberAnimation { duration: theme.animationFast } }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: toggleRow.changed(!toggleRow.checked)
        }
    }

    component SliderRow: ColumnLayout {
        id: sliderRow
        required property string label
        required property real value
        property real from: 0
        property real to: 1
        property real stepSize: 1
        property int decimals: 0
        property string suffix: ""
        signal changed(real value)

        Layout.fillWidth: true
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: sliderRow.label
                color: theme.text
                font.family: theme.sans
                font.pixelSize: 12
            }
            Text {
                text: sliderRow.value.toFixed(sliderRow.decimals) + sliderRow.suffix
                color: theme.textMuted
                font.family: theme.mono
                font.pixelSize: 11
            }
        }

        Item {
            id: slider
            Layout.fillWidth: true
            Layout.preferredHeight: 22

            readonly property real visualPosition: (sliderRow.value - sliderRow.from) / (sliderRow.to - sliderRow.from)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: 2
                color: theme.surfaceHover

                Rectangle {
                    width: Math.max(0, Math.min(1, slider.visualPosition)) * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: theme.accent
                }
            }

            Rectangle {
                x: Math.max(0, Math.min(slider.width - width, slider.visualPosition * slider.width - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: sliderMouse.pressed ? theme.text : theme.accent
                border.width: 2
                border.color: theme.surfaceBase
            }

            MouseArea {
                id: sliderMouse
                anchors.fill: parent
                preventStealing: true

                function updateValue(mouseX: real): void {
                    const ratio = Math.max(0, Math.min(1, mouseX / width))
                    const raw = sliderRow.from + ratio * (sliderRow.to - sliderRow.from)
                    const stepped = sliderRow.from + Math.round((raw - sliderRow.from) / sliderRow.stepSize) * sliderRow.stepSize
                    sliderRow.changed(Math.max(sliderRow.from, Math.min(sliderRow.to, stepped)))
                }

                onPressed: mouse => updateValue(mouse.x)
                onClicked: mouse => updateValue(mouse.x)
                onPositionChanged: mouse => {
                    if (pressed)
                        updateValue(mouse.x)
                }
            }
        }
    }

    component ColorRow: Item {
        id: colorRow
        required property string label
        required property string value
        signal changed(string value)

        Layout.fillWidth: true
        implicitHeight: 40

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: colorRow.label
            color: theme.text
            font.family: theme.sans
            font.pixelSize: 12
        }

        Rectangle {
            anchors.right: field.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 7
            color: colorRow.value
            border.width: 1
            border.color: theme.border
        }

        Controls.TextField {
            id: field
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 108
            height: 34
            color: theme.text
            selectionColor: theme.accent
            selectedTextColor: theme.surfaceBase
            font.family: theme.mono
            font.pixelSize: 11
            horizontalAlignment: TextInput.AlignHCenter
            validator: RegularExpressionValidator { regularExpression: /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/ }
            onEditingFinished: {
                if (acceptableInput)
                    colorRow.changed(text)
                else
                    text = colorRow.value
            }
            background: Rectangle {
                radius: 9
                color: theme.surfaceBase
                border.width: field.activeFocus ? 2 : 1
                border.color: field.activeFocus ? theme.accent : theme.border
            }

            Binding {
                target: field
                property: "text"
                value: colorRow.value
                when: !field.activeFocus
            }
        }
    }

    component ActionButton: Rectangle {
        id: actionButton
        required property string label
        property bool primary: false
        signal clicked

        implicitWidth: buttonLabel.implicitWidth + 30
        implicitHeight: 38
        radius: 11
        color: primary
            ? theme.accent
            : buttonMouse.containsMouse ? theme.surfaceHover : theme.surfaceRaised
        border.width: 1
        border.color: primary ? theme.accent : theme.border
        Behavior on color { ColorAnimation { duration: theme.animationFast } }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: actionButton.label
            color: actionButton.primary ? theme.surfaceBase : theme.text
            font.family: theme.sans
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: actionButton.clicked()
        }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true

        Rectangle {
            id: dashboard
            anchors.centerIn: parent
            width: Math.min(settingsWindow.width - 80, 1240)
            height: Math.min(settingsWindow.height - 80, 900)
            radius: 22
            color: settingsWindow.panelSurface
            border.width: 1
            border.color: theme.border

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Bar settings"
                            color: theme.text
                            font.family: theme.sans
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Appearance, modules, behavior, and theme"
                            color: theme.textMuted
                            font.family: theme.sans
                            font.pixelSize: 11
                        }
                    }

                    ActionButton {
                        label: "Reset defaults"
                        onClicked: settingsWindow.resetRequested()
                    }
                    ActionButton {
                        label: "Done"
                        primary: true
                        onClicked: settingsWindow.closeRequested()
                    }
                }

                Controls.ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth

                    Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded

                    GridLayout {
                        width: scroll.availableWidth
                        columns: width >= 820 ? 2 : 1
                        columnSpacing: 14
                        rowSpacing: 14

                        SectionCard {
                            title: "Appearance"

                            Text {
                                text: "Font family"
                                color: theme.text
                                font.family: theme.sans
                                font.pixelSize: 12
                            }
                            Controls.ComboBox {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                model: settingsWindow.fontFamilies
                                currentIndex: Math.max(0, settingsWindow.fontFamilies.indexOf(settings.fontFamily))
                                onActivated: settings.fontFamily = currentText
                                font.family: settings.fontFamily
                                font.pixelSize: 12
                                palette.text: theme.text
                                palette.buttonText: theme.text
                                palette.button: theme.surfaceBase
                                palette.base: theme.surfaceBase
                                palette.window: theme.surfaceRaised
                                palette.highlight: theme.surfaceHover
                                palette.highlightedText: theme.text
                            }
                            SliderRow {
                                label: "Font size"
                                value: settings.fontScale
                                from: 0.75
                                to: 1.5
                                stepSize: 0.05
                                decimals: 2
                                suffix: "×"
                                onChanged: value => settings.fontScale = value
                            }
                            SliderRow {
                                label: "Horizontal height"
                                value: settings.horizontalSize
                                from: 44
                                to: 96
                                suffix: " px"
                                onChanged: value => settings.horizontalSize = Math.round(value)
                            }
                            SliderRow {
                                label: "Vertical width"
                                value: settings.verticalSize
                                from: 54
                                to: 110
                                suffix: " px"
                                onChanged: value => settings.verticalSize = Math.round(value)
                            }
                            SliderRow {
                                label: "Opacity"
                                value: settings.opacity
                                from: 0.55
                                to: 1
                                stepSize: 0.01
                                decimals: 2
                                onChanged: value => settings.opacity = value
                            }
                            SliderRow {
                                label: "Corner radius"
                                value: settings.radius
                                from: 0
                                to: 30
                                suffix: " px"
                                onChanged: value => settings.radius = Math.round(value)
                            }
                            SliderRow {
                                label: "Outer margin"
                                value: settings.outerMargin
                                from: 0
                                to: 16
                                suffix: " px"
                                onChanged: value => settings.outerMargin = Math.round(value)
                            }
                        }

                        SectionCard {
                            title: "Widget visibility"

                            ToggleRow { label: "App launcher"; checked: settings.showLauncher; onChanged: value => settings.showLauncher = value }
                            ToggleRow { label: "Workspaces"; checked: settings.showWorkspaces; onChanged: value => settings.showWorkspaces = value }
                            ToggleRow { label: "Active window"; checked: settings.showTitle; onChanged: value => settings.showTitle = value }
                            ToggleRow { label: "Media controls"; checked: settings.showMedia; onChanged: value => settings.showMedia = value }
                            ToggleRow { label: "System metrics"; checked: settings.showMetrics; onChanged: value => settings.showMetrics = value }
                            ToggleRow { label: "System tray"; checked: settings.showTray; onChanged: value => settings.showTray = value }
                            ToggleRow { label: "Volume"; checked: settings.showVolume; onChanged: value => settings.showVolume = value }
                            ToggleRow { label: "Clock"; checked: settings.showClock; onChanged: value => settings.showClock = value }
                            ToggleRow { label: "Settings button"; checked: settings.showSettingsButton; onChanged: value => settings.showSettingsButton = value }
                        }

                        SectionCard {
                            title: "Behavior"

                            Text {
                                text: "Screen edge"
                                color: theme.text
                                font.family: theme.sans
                                font.pixelSize: 12
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: settingsWindow.positions
                                    Rectangle {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: 10
                                        color: settings.position === modelData ? theme.accent : theme.surfaceBase
                                        border.width: 1
                                        border.color: settings.position === modelData ? theme.accent : theme.border
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData[0].toUpperCase() + modelData.slice(1)
                                            color: settings.position === modelData ? theme.surfaceBase : theme.text
                                            font.family: theme.sans
                                            font.pixelSize: 11
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: settings.position = modelData }
                                    }
                                }
                            }
                            SliderRow {
                                label: "Metrics refresh"
                                value: settings.metricsInterval
                                from: 1
                                to: 10
                                suffix: " s"
                                onChanged: value => settings.metricsInterval = Math.round(value)
                            }
                            ToggleRow { label: "Network speed in bits"; checked: settings.networkBits; onChanged: value => settings.networkBits = value }
                            ToggleRow { label: "24-hour clock"; checked: settings.clock24Hour; onChanged: value => settings.clock24Hour = value }
                            ToggleRow { label: "Show date"; checked: settings.showDate; onChanged: value => settings.showDate = value }
                        }

                        SectionCard {
                            title: "Theme colors"

                            ColorRow { label: "Bar"; value: settings.surfaceColor; onChanged: value => settings.surfaceColor = value }
                            ColorRow { label: "Cards"; value: settings.raisedColor; onChanged: value => settings.raisedColor = value }
                            ColorRow { label: "Hover"; value: settings.hoverColor; onChanged: value => settings.hoverColor = value }
                            ColorRow { label: "Border"; value: settings.borderColor; onChanged: value => settings.borderColor = value }
                            ColorRow { label: "Text"; value: settings.textColor; onChanged: value => settings.textColor = value }
                            ColorRow { label: "Muted text"; value: settings.mutedColor; onChanged: value => settings.mutedColor = value }
                            ColorRow { label: "Accent"; value: settings.accentColor; onChanged: value => settings.accentColor = value }
                        }
                    }
                }
            }
        }
    }
}
