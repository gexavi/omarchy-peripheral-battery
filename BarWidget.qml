import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// Displays the readings published by the peripheral-battery system service
// (see service/), plus the Bluetooth device batteries UPower gets from BlueZ.
// The widget itself never touches the devices: it reads a world-readable JSON
// file and UPower, so it needs no permission and spawns nothing.
BarWidget {
  id: root
  moduleName: "gexavi.peripheral-battery"

  readonly property string statusPath: "/run/peripheral-battery/status.json"
  readonly property string serviceVersion: "1.5.0"
  readonly property int lowThreshold: 20
  // The service runs every 30 s by default (configurable, see README); data
  // older than this means it stopped running.
  readonly property int staleAfter: 600

  // "missing" | "invalid" | "ok"
  property string fileState: "missing"
  property var status: ({ devices: [] })
  property real now: Date.now() / 1000

  readonly property var serviceDevices: fileState === "ok" ? (status.devices || []) : []

  // Bluetooth devices whose battery only BlueZ knows (headphones, earbuds…).
  // Everything else UPower lists comes from /sys/class/power_supply, which the
  // service already reads, often with more detail.
  readonly property var bluetoothDevices: {
    var known = {}
    for (var i = 0; i < serviceDevices.length; i++) known[serviceDevices[i].name] = true
    var list = UPower.devices ? UPower.devices.values : []
    var out = []
    for (var j = 0; j < list.length; j++) {
      var d = list[j]
      if (!d || !d.ready || !d.isPresent || d.isLaptopBattery || d.powerSupply) continue
      if (String(d.nativePath).indexOf("/org/bluez/") !== 0) continue
      var name = d.model || "Bluetooth device"
      if (known[name]) continue
      out.push({
        name: name,
        kind: upowerKind(d.type),
        level: Math.round(Number(d.percentage || 0) * 100),
        state: d.state === UPowerDeviceState.Charging ? "charging"
             : d.state === UPowerDeviceState.FullyCharged ? "full" : "discharging",
        online: true,
        bluetooth: true
      })
    }
    return out
  }

  readonly property var devices: serviceDevices.concat(bluetoothDevices)
  readonly property bool stale: fileState === "ok" && now - (status.updated || 0) > staleAfter
  readonly property bool outdated: fileState === "ok" && status.version !== serviceVersion

  function icon(kind) {
    if (kind === "mouse") return "󰍽"
    if (kind === "keyboard") return "󰌌"
    if (kind === "headset") return "󰋎"
    if (kind === "gamepad") return "󰊴"
    return "󰂄"
  }

  function upowerKind(type) {
    if (type === UPowerDeviceType.Mouse || type === UPowerDeviceType.Touchpad) return "mouse"
    if (type === UPowerDeviceType.Keyboard) return "keyboard"
    if (type === UPowerDeviceType.Headset || type === UPowerDeviceType.Headphones) return "headset"
    if (type === UPowerDeviceType.GamingInput) return "gamepad"
    return "other"
  }

  // The service publishes a null level when a charging device gives none
  // and no earlier reading exists.
  function levelText(d) {
    return (typeof d.level === "number" ? d.level + "%" : "?") + (d.state === "charging" ? "⚡" : "")
  }

  function ago(seconds) {
    var minutes = Math.round(seconds / 60)
    if (minutes < 1) return "just now"
    if (minutes < 60) return minutes + " min ago"
    return Math.round(minutes / 60) + " h ago"
  }

  function isLow(d) {
    return typeof d.level === "number" && d.level <= lowThreshold && d.state === "discharging"
  }

  readonly property string tooltip: {
    var lines = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      var line = d.name + ": " + (typeof d.level === "number" ? d.level + "%" : "level unknown")
      if (d.state === "charging") line += " (charging)"
      else if (d.state === "full") line += " (full)"
      if (d.measured && d.online && d.state === "charging")
        line += ", measured " + ago(now - d.measured) + " before charging"
      if (!d.online) line += " (asleep, last read " + ago(now - d.seen) + ")"
      if (d.bluetooth) line += " (Bluetooth)"
      lines.push(line)
    }
    if (fileState === "missing")
      lines.push((lines.length ? "\n" : "") + "Wireless Peripheral Battery: service not installed.\nRun: sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/install.sh")
    else if (fileState === "invalid")
      lines.push((lines.length ? "\n" : "") + "Wireless Peripheral Battery: unreadable " + statusPath)
    else if (lines.length === 0)
      lines.push("No supported wireless device found")
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
    // The built-in label has a single color, so the readings are drawn below
    // instead: each device can then be dimmed (asleep) or highlighted (low)
    // on its own. The label only shows the "nothing to show" icon.
    text: "󰂑"
    labelVisible: root.devices.length === 0
    fixedWidth: labelVisible || vertical ? -1 : readings.implicitWidth + scaledHorizontalMargin * 2
    fontSize: Style.font.caption
    horizontalMargin: 6
    dimmed: root.devices.length === 0 ? root.fileState !== "ok" : root.stale && root.bluetoothDevices.length === 0
    pressable: false
    tooltipText: root.tooltip

    Row {
      id: readings
      anchors.centerIn: parent
      visible: !button.labelVisible
      spacing: button.fontSize

      Repeater {
        model: root.devices

        Text {
          required property var modelData
          textFormat: Text.PlainText
          text: root.icon(modelData.kind) + " " + root.levelText(modelData)
          color: root.isLow(modelData) ? button.activeColor : button.foreground
          opacity: modelData.online ? 1 : 0.4
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
