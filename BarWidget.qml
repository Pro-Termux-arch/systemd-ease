import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget: a cog with a failed-service alarm. Left click opens the
// manager panel; the panel (not this widget) owns the heavy lifting.
BarWidget {
  id: root
  moduleName: "io.github.pro-termux-arch.systemd-ease"

  readonly property string bridgePath: String(Qt.resolvedUrl("bin/systemd-ease")).replace(/^file:\/\//, "")
  property int failedCount: 0

  // ---- panel plumbing (same contract as the built-in clock widget) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("bridgePath" in target) target.bridgePath = root.bridgePath
  }

  function refreshBadge() {
    if (badgeProc.running) return
    badgeProc.command = [root.bridgePath, "failed-count"]
    badgeProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  Component.onCompleted: refreshBadge()

  // Cheap poll: two `--state=failed` calls, ~50ms. The full list only
  // loads while the panel is open.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refreshBadge()
  }

  Process {
    id: badgeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text))
          root.failedCount = d.failed || 0
        } catch (e) { /* keep last value */ }
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.pro-termux-arch.systemd-ease"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refreshBadge() }
    function status(): string { return root.failedCount + " failed" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.failedCount > 0
      ? root.failedCount + (root.failedCount === 1 ? " service crashed" : " services crashed") + " — click to fix"
      : "Systemd services — click to manage"

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "\u{f013}"
        color: root.failedCount > 0
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.failedCount > 0 && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.failedCount > 99 ? "99+" : String(root.failedCount)
        color: root.bar ? root.bar.urgent : Color.urgent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        renderType: Text.NativeRendering
      }
    }
  }
}
