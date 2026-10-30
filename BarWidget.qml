import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Displays the readings published by the peripheral-battery system service
// (see service/). The widget itself never touches the devices: it only reads
// a world-readable JSON file, so it needs no permission and spawns nothing.
BarWidget {
  id: root
  moduleName: "gexavi.peripheral-battery"

  readonly property string statusPath: "/run/peripheral-battery/status.json"
  readonly property string serviceVersion: "1.0.1"
  readonly property int lowThreshold: 20
  // The service runs every 2 minutes; older data means it stopped running.
  readonly property int staleAfter: 600

  // "missing" | "invalid" | "ok"
  property string fileState: "missing"
  property var status: ({ devices: [] })
  property real now: Date.now() / 1000

  readonly property var devices: status.devices || []
  readonly property bool stale: fileState === "ok" && now - (status.updated || 0) > staleAfter
  readonly property bool outdated: fileState === "ok" && status.version !== serviceVersion

  function icon(kind) {
    if (kind === "mouse") return "󰍽"
    if (kind === "keyboard") return "󰌌"
    if (kind === "headset") return "󰋎"
    return "󰂄"
  }

  function ago(seconds) {
    var minutes = Math.round(seconds / 60)
    if (minutes < 60) return minutes + " min ago"
    return Math.round(minutes / 60) + " h ago"
  }

  readonly property string label: {
    if (fileState !== "ok") return "󰂑"
    var parts = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      parts.push(icon(d.kind) + " " + d.level + "%" + (d.state === "charging" ? "⚡" : ""))
    }
    return parts.length > 0 ? parts.join("  ") : "󰂑"
  }

  readonly property bool anyLow: {
    for (var i = 0; i < devices.length; i++)
      if (devices[i].level <= lowThreshold && devices[i].state === "discharging") return true
    return false
  }

  readonly property string tooltip: {
    if (fileState === "missing")
      return "Peripheral battery: service not installed.\nRun: sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/install.sh"
    if (fileState === "invalid")
      return "Peripheral battery: unreadable " + statusPath

    var lines = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      var line = d.name + ": " + d.level + "%"
      if (d.state === "charging") line += " (charging)"
      else if (d.state === "full") line += " (full)"
      if (!d.online) line += " (asleep, last read " + ago(now - d.seen) + ")"
      lines.push(line)
    }
    if (lines.length === 0) lines.push("No supported wireless device found")
    if (stale) lines.push("\n⚠ Not updated since " + ago(now - status.updated) + ": is peripheral-battery.timer running?")
    if (outdated) lines.push("\n⚠ Service " + status.version + " does not match widget " + serviceVersion + ": re-run service/install.sh")
    return lines.join("\n")
  }

  function load(text) {
    try {
      var parsed = JSON.parse(text)
      root.status = parsed && parsed.devices ? parsed : { devices: [] }
      root.fileState = "ok"
    } catch (e) {
      root.fileState = "invalid"
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    // text() is stale inside the change signal; reload and parse in onLoaded.
    onFileChanged: reload()
    onLoaded: root.load(text())
    onLoadFailed: root.fileState = "missing"
  }

  // The service replaces the file atomically, which a file watch can miss,
  // so also re-read it periodically. Reading a small file costs nothing.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      root.now = Date.now() / 1000
      statusFile.reload()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: 6
    active: root.anyLow
    dimmed: root.stale || root.fileState !== "ok"
    pressable: false
    tooltipText: root.tooltip
  }
}
