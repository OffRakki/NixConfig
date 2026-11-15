import QtQuick
import Quickshell
import Quickshell.Io

// Only helper-allowlisted metadata and status codes cross this boundary.
Item {
    id: session
    property bool active: false
    property bool busy: false
    property bool acting: false
    property int generation: 0
    property var pending: null
    property var entries: []
    property var selected: null
    property var context: ({address: "", pid: 0, class: "", host: ""})
    property string message: ""
    readonly property var actions: ["Password", "Username", "OTP", "URL", "Fill"]
    signal finished(bool success)
    signal listed()
    signal hideForAction()

    function close(): void {
        if (acting) return // Explicitly submitted work cannot be undone by Escape.
        generation++
        active = false
        busy = false
        if (pending) pending.running = false
        pending = null
        entries = []
        selected = null
        context = {address: "", pid: 0, class: "", host: ""}
        message = ""
    }
    function open(captured: string): bool {
        if (acting) return false
        close()
        try { context = JSON.parse(captured) } catch (_) { context = {address: "", pid: 0, class: "", host: ""} }
        active = true
        busy = true
        message = "Unlocking / loading logins…"
        start(["list"], false)
        return true
    }
    function start(args: var, action: bool): void {
        const helper = Quickshell.env("APP_LAUNCHER_PASSWORD_HELPER") || "app-launcher-passwords"
        const process = operation.createObject(session, {
            command: [helper, ...args], token: generation, action: action,
            input: action ? JSON.stringify(context) + "\n" : ""
        })
        pending = process
        process.running = true
    }
    function submit(index: int): void {
        if (busy || !selected || index < 0 || index >= actions.length) return
        busy = true
        acting = true
        message = "Working…"
        hideForAction()
        // Give layer-shell time to release exclusive focus before pinentry/input.
        actionTimer.actionName = actions[index].toLowerCase()
        actionTimer.restart()
    }
    Timer {
        id: actionTimer
        property string actionName
        interval: 200
        onTriggered: session.start(["act", session.selected.id, actionName], true)
    }
    function errorText(code: string): string {
        const errors = {
            missing_field: "Field unavailable; clipboard unchanged.",
            missing_otp: "No OTP configured; clipboard unchanged.",
            missing_url: "No stored HTTP(S) URL; clipboard unchanged.",
            unsupported_text: "Fill supports printable ASCII only. Use Copy instead.",
            unsupported_keymap: "Fill requires plain English (US), Caps Lock off. Use Copy instead.",
            input_unavailable: "Cannot verify released keys; Fill aborted. Use Copy instead.",
            keys_held: "Release Enter and modifiers, then retry.",
            focus_changed: "Target focus changed; Fill aborted.",
            focus_failed: "Could not restore target focus; Fill aborted. Reopen from the intended field.",
            target_unavailable: "Original window unavailable; Fill aborted.",
            partial_fill: "Fill interrupted: some characters may have been typed. Inspect the form; do not retry blindly.",
            timed_out: "Operation timed out. Unlock or retry.",
            tool_unavailable: "Password helper dependency unavailable.",
            command_failed: "Unlock cancelled or backend command failed. Retry after unlocking rbw."
        }
        return errors[code] || "Operation failed safely. Check rbw availability and retry."
    }
    Component {
        id: operation
        Process {
            id: process
            property int token
            property bool action
            property string input
            property bool received: false
            property bool disposed: false
            function dispose(): void {
                if (disposed) return
                disposed = true
                Qt.callLater(() => process.destroy())
            }
            function failed(): void {
                if (token === session.generation && session.active && !received) {
                    received = true
                    session.pending = null
                    session.busy = false
                    session.acting = false
                    session.message = "Password helper failed to start or was interrupted. Inspect any partially filled form."
                    if (action) session.finished(false)
                    else session.listed()
                }
                dispose()
            }
            // Quickshell 0.3.2 does not emit exited on FailedToStart.
            property Timer startCheck: Timer {
                interval: 500
                running: true
                onTriggered: { if (!process.running && !process.received) process.failed() }
            }
            stdinEnabled: action
            onStarted: { if (action) write(input) }
            stdout: StdioCollector {
                onStreamFinished: {
                    if (process.token !== session.generation || !session.active) return
                    process.received = true
                    session.pending = null
                    session.busy = false
                    session.acting = false
                    let result
                    try { result = JSON.parse(text) } catch (_) { result = {status: "error", code: "invalid_schema"} }
                    if (process.action) {
                        const success = ["copied", "filled", "filled_otp_copied"].includes(result.status)
                        if (result.status === "filled_otp_unavailable")
                            session.message = "Credentials filled without Enter; OTP could not be copied."
                        else if (success) session.message = ""
                        else session.message = session.errorText(result.code)
                        session.finished(success)
                    } else {
                        session.entries = result.status === "listed" ? result.entries : []
                        session.message = result.status === "listed" ? (session.entries.length ? "" : "No login entries.") : session.errorText(result.code)
                        session.listed()
                    }
                }
            }
            // Never forward child stderr or command payloads to a logger.
            stderr: StdioCollector {}
            onExited: { if (!received) failed(); else dispose() }
        }
    }
}
