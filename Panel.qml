import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Systemd Ease: the manager panel. Four views, one panel:
//   list   — search + filters + every service with plain-word actions
//   logs   — journal output for one service (view/save/copy)
//   boot   — slowest units at startup
//   create — the guided service creator (Wizard.qml)
Panel {
  id: root
  moduleName: "io.github.proadmin.systemd-ease"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string bridgePath: ""

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: bar ? Qt.darker(bar.foreground, 1.4) : Color.muted
  readonly property color bad: bar ? bar.urgent : Color.urgent
  readonly property color good: Color.accent
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // ---- views ----
  property string view: "list" // list | logs | boot | create

  // ---- data ----
  property var services: []
  property var filtered: []
  property int nRunning: 0
  property int nFailed: 0
  property int nBoot: 0
  property double lastUpdated: 0
  property int clockTick: 0

  // ---- filters ----
  property string search: ""
  property string originFilter: "all" // all | mine | vendor
  property string scopeFilter: "all" // all | system | user
  property string stateFilter: "all" // all | running | failed | boot

  // ---- selection ----
  property string expandedKey: ""
  property string logUnit: ""
  property string logScope: ""
  property string logText: "Loading…"
  property string lastSaved: ""
  property string bootText: "Loading…"

  // ---- activity ----
  property bool busy: false
  property string toast: ""
  property var pendingAction: null
  property var pendingLogs: null
  property var confirmRequest: null // {message, op, unit, scope, label}

  function unitKey(u) { return u.scope + "/" + u.name }

  function showToast(msg) {
    toast = msg
    toastTimer.restart()
  }

  // ================= data loading =================

  function refresh() {
    if (listProc.running || !bridgePath) return
    busy = true
    listProc.command = [bridgePath, "list"]
    listProc.running = true
  }

  function handleList(text) {
    busy = false
    var parsed = null
    try { parsed = JSON.parse(String(text)) } catch (e) { parsed = null }
    if (!Array.isArray(parsed)) {
      showToast("Could not read services — is systemd running?")
      return
    }
    services = parsed
    lastUpdated = Date.now()
    applyFilters()
  }

  function applyFilters() {
    var out = []
    var r = 0, f = 0, b = 0
    for (var i = 0; i < services.length; i++) {
      var u = services[i]
      var k = Model.runKey(u)
      if (k === "running") r++
      if (k === "failed") f++
      if (Model.bootOn(u.enabled)) b++
      if (Model.matchesQuery(u, search) && Model.passFilters(u, originFilter, scopeFilter, stateFilter))
        out.push(u)
    }
    nRunning = r
    nFailed = f
    nBoot = b
    filtered = out
  }

  // ================= actions =================

  function runAction(op, unit, scope, label, needsConfirm) {
    if (needsConfirm) {
      confirmRequest = { message: label + "\n\n" + unit + " (" + scope + ")",
                         op: op, unit: unit, scope: scope, label: label }
      return
    }
    if (actProc.running) return
    busy = true
    pendingAction = { op: op, unit: unit, scope: scope, label: label }
    actProc.command = [bridgePath, "action", op, unit, scope]
    actProc.running = true
  }

  function handleAction(text) {
    busy = false
    var p = pendingAction
    pendingAction = null
    var d = null
    try { d = JSON.parse(String(text)) } catch (e) { d = null }
    if (d && d.ok) {
      showToast((p ? p.label : "Done") + " ✓" + (d.elevated ? " (password asked once)" : ""))
      if (p && p.op === "delete") expandedKey = ""
      refreshTimer.restart()
    } else {
      showToast("Didn't work: " + ((d && d.error) || "unknown error"))
    }
  }

  function toggleBoot(u, wantOn) {
    runAction(wantOn ? "enable" : "disable", u.name, u.scope,
      (wantOn ? "Boot on for " : "Boot off for ") + u.name,
      (!wantOn && u.scope === "system"))
  }

  function copyText(t, what) {
    Util.execArgv(["wl-copy", String(t)])
    showToast((what || "Copied") + " ✓ — paste it anywhere")
  }

  function openPath(path) {
    if (!path) return
    Util.execArgv(["xdg-open", String(path)])
  }

  // ================= logs view =================

  function openLogs(unit, scope) {
    logUnit = unit
    logScope = scope
    logText = "Loading…"
    lastSaved = ""
    view = "logs"
    if (logsProc.running) return
    pendingLogs = { unit: unit, scope: scope }
    logsProc.command = [bridgePath, "logs", unit, scope, "200"]
    logsProc.running = true
  }

  function handleLogs(text) {
    var t = String(text || "").trim()
    logText = t ? t : "(No journal entries for this service yet.)"
  }

  function saveLogs() {
    if (saveProc.running || !logUnit) return
    var path = (Quickshell.env("HOME") || "/tmp") + "/Documents/" + Model.shortName(logUnit) + "-logs.txt"
    saveProc.savePath = path
    saveProc.command = [bridgePath, "save-logs", logUnit, logScope, path]
    saveProc.running = true
  }

  // ================= boot view =================

  function openBoot() {
    bootText = "Loading…"
    view = "boot"
    if (blameProc.running) return
    blameProc.command = [bridgePath, "blame"]
    blameProc.running = true
  }

  // ================= lifecycle =================

  function open() { root.controller.show() }
  function close() {
    confirmRequest = null
    root.controller.hide()
  }
  function toggle() { root.opened ? root.close() : root.open() }
  function backToList() {
    if (view === "create") return // wizard owns its own cancel
    view = "list"
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onOpenedChanged: {
    if (opened) {
      view = "list"
      expandedKey = ""
      refresh()
      Qt.callLater(function() { if (root.opened) searchField.forceActiveFocus() })
    }
  }

  Timer { id: toastTimer; interval: 4200; onTriggered: root.toast = "" }
  Timer { id: refreshTimer; interval: 700; onTriggered: root.refresh() }
  Timer { interval: 10000; running: true; repeat: true; onTriggered: { root.clockTick++; if (root.opened && root.view === "list") root.refresh() } }

  // ================= backend processes =================

  Process {
    id: listProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleList(text) }
    onExited: root.busy = false
  }
  Process {
    id: actProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleAction(text) }
    onExited: root.busy = false
  }
  Process {
    id: logsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleLogs(text) }
  }
  Process {
    id: saveProc
    property string savePath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = null
        try { d = JSON.parse(String(text)) } catch (e) { d = null }
        if (d && d.ok) {
          root.lastSaved = saveProc.savePath
          root.showToast("Logs saved ✓")
        } else {
          root.showToast("Couldn't save: " + ((d && d.error) || "unknown error"))
        }
      }
    }
  }
  Process {
    id: blameProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.bootText = String(text || "").trim() || "(No boot data.)" }
  }

  // ================= panel chrome =================

  implicitWidth: 0
  implicitHeight: 0

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: (searchField.activeFocus && root.view === "list")
        || (wizard.active && wizard.inputFocused)

      onCloseRequested: {
        if (root.confirmRequest) { root.confirmRequest = null; return }
        if (root.expandedKey !== "") { root.expandedKey = ""; return }
        if (root.view === "logs" || root.view === "boot") { root.backToList(); return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.confirmRequest) return
        if (t === "/" && root.view === "list" && !searchField.activeFocus) {
          searchField.forceActiveFocus()
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(titleText.implicitHeight, headerBtns.implicitHeight)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.view === "list" ? "Services"
              : root.view === "logs" ? "Logs · " + Model.shortName(root.logUnit)
              : root.view === "boot" ? "Slowest at boot"
              : "New service"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width - headerBtns.width - Style.space(8)
          }

          Row {
            id: headerBtns
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              visible: root.view === "list"
              text: root.busy ? "Working…" : "↻ Refresh"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.family
              bordered: true
              onClicked: root.refresh()
            }
            Button {
              visible: root.view === "list"
              text: "Boot times"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.family
              bordered: true
              onClicked: root.openBoot()
            }
            Button {
              visible: root.view === "list"
              text: "+ New"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.family
              bordered: true
              onClicked: root.view = "create"
            }
            Button {
              visible: root.view !== "list" && root.view !== "create"
              text: "‹ Back"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.family
              bordered: true
              onClicked: root.backToList()
            }
          }
        }

        // ---------- LIST VIEW ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "list"

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search services…  ( / to jump here )"
            foreground: root.fg
            font.pixelSize: Style.font.body
            onTextChanged: { root.search = text; root.applyFilters() }
            Keys.onEscapePressed: {
              if (text !== "") text = ""
              else keyCatcher.forceActiveFocus()
            }
          }

          // Filter 1: whose services? (the one the user asked for)
          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Show:"
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
            ButtonGroup {
              options: [
                { value: "all", label: "Everything" },
                { value: "mine", label: "Mine + added" },
                { value: "vendor", label: "Preinstalled" }
              ]
              value: root.originFilter
              foreground: root.fg
              fontFamily: root.family
              fontSize: Style.font.caption
              focusable: false
              onChanged: function(v) { root.originFilter = v; root.applyFilters() }
            }
          }

          // Filter 2: scope + state
          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Scope:"
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
            ButtonGroup {
              options: [
                { value: "all", label: "Both" },
                { value: "system", label: "System" },
                { value: "user", label: "User" }
              ]
              value: root.scopeFilter
              foreground: root.fg
              fontFamily: root.family
              fontSize: Style.font.caption
              focusable: false
              onChanged: function(v) { root.scopeFilter = v; root.applyFilters() }
            }
            ButtonGroup {
              options: [
                { value: "all", label: "Any state" },
                { value: "running", label: "Running" },
                { value: "failed", label: "Crashed" },
                { value: "boot", label: "At boot" }
              ]
              value: root.stateFilter
              foreground: root.fg
              fontFamily: root.family
              fontSize: Style.font.caption
              focusable: false
              onChanged: function(v) { root.stateFilter = v; root.applyFilters() }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              root.clockTick // re-evaluate on tick
              return root.filtered.length + " shown · " + root.nRunning + " running · "
                + root.nFailed + " crashed · updated "
                + (root.lastUpdated > 0 ? Model.agoText(Date.now() - root.lastUpdated) : "never")
            }
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
          }

          // The list itself.
          Rectangle {
            width: parent.width
            height: Style.space(340)
            radius: Style.cornerRadius
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
            clip: true

            Text {
              visible: root.filtered.length === 0
              anchors.centerIn: parent
              width: parent.width - Style.space(32)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.busy ? "Reading services…" : "Nothing matches — try clearing the search or choosing “Everything”."
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }

            ListView {
              id: serviceList
              anchors.fill: parent
              anchors.margins: Style.space(6)
              clip: true
              spacing: Style.space(4)
              model: root.filtered

              delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: serviceList.width
                height: body.implicitHeight + Style.space(8)

                readonly property var unit: modelData
                readonly property bool isExp: root.expandedKey === root.unitKey(modelData)
                readonly property string rkey: Model.runKey(modelData)
                readonly property bool running: rkey === "running"
                readonly property bool failed: rkey === "failed"
                readonly property color dot: row.failed ? root.bad : (row.running ? root.good : root.dim)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: row.isExp ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                    : (row.failed ? Qt.rgba(root.bad.r, root.bad.g, root.bad.b, 0.08) : "transparent")
                }

                Column {
                  id: body
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(4)
                  spacing: Style.space(6)

                  // main row
                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(9)
                      height: Style.space(9)
                      radius: height / 2
                      color: row.dot
                    }

                    Column {
                      width: Math.max(0, parent.width - x - actionBox.width - Style.space(8))
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: row.unit.name
                        elide: Text.ElideRight
                        color: row.failed ? root.bad : root.fg
                        font.family: root.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: row.failed
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: (row.unit.description || Model.runWord(row.unit))
                          + "  ·  " + Model.scopeLabel(row.unit.scope)
                          + "  ·  " + Model.originLabel(row.unit.origin)
                      elide: Text.ElideRight
                        color: root.dim
                        font.family: root.family
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Row {
                      id: actionBox
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      Button {
                        text: row.running ? "Stop" : "Start"
                        fontSize: Style.font.caption
                        foreground: root.fg
                        fontFamily: root.family
                        bordered: true
                        onClicked: {
                          if (row.running) root.runAction("stop", row.unit.name, row.unit.scope, "Stopped " + row.unit.name, false)
                          else root.runAction("start", row.unit.name, row.unit.scope, "Started " + row.unit.name, false)
                        }
                      }

                      Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)
                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          textFormat: Text.PlainText
                          text: "Boot"
                          color: root.dim
                          font.family: root.family
                          font.pixelSize: Style.font.caption
                        }
                        ToggleSwitch {
                          anchors.verticalCenter: parent.verticalCenter
                          checked: Model.bootOn(row.unit.enabled)
                          enabled: Model.canToggleBoot(row.unit.enabled) && !root.busy
                          foreground: root.fg
                          onToggled: root.toggleBoot(row.unit, !Model.bootOn(row.unit.enabled))
                        }
                      }

                      Button {
                        text: row.isExp ? "▾" : "▸"
                        fontSize: Style.font.caption
                        foreground: root.fg
                        fontFamily: root.family
                        onClicked: root.expandedKey = row.isExp ? "" : root.unitKey(row.unit)
                      }
                    }
                  }

                  // expanded details
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: row.isExp

                    PanelSeparator { foreground: root.fg }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: "Now: " + Model.runWord(row.unit) + "  ·  Boot: " + Model.bootWord(row.unit.enabled)
                        + (row.unit.fragment ? "\n" + row.unit.fragment : "\n(no file — built into systemd)")
                      wrapMode: Text.Wrap
                      color: root.dim
                      font.family: root.family
                      font.pixelSize: Style.font.caption
                    }

                    // watchdog banner for plugin-managed services
                    Row {
                      width: parent.width
                      spacing: Style.space(6)
                      visible: row.unit.managed
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "♥ Watched — debug file ready if it ever crashes"
                        color: root.good
                        font.family: root.family
                        font.pixelSize: Style.font.caption
                      }
                      Button {
                        text: "Open folder"
                        fontSize: Style.font.caption
                        foreground: root.fg
                        fontFamily: root.family
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.openPath(Quickshell.env("HOME") + "/Documents/" + Model.shortName(row.unit.name))
                      }
                    }

                    Text {
                      width: parent.width
                      visible: !row.unit.deletable
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      text: "Preinstalled service: you can't delete it, but Stop / Boot-off / Block all work."
                      color: root.dim
                      font.family: root.family
                      font.pixelSize: Style.font.caption
                    }

                    Flow {
                      width: parent.width
                      spacing: Style.space(6)
                      Button { text: "Restart"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
                        onClicked: root.runAction("restart", row.unit.name, row.unit.scope, "Restarted " + row.unit.name, false) }
                      Button { text: "Logs"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
                        onClicked: root.openLogs(row.unit.name, row.unit.scope) }
                      Button { text: row.unit.enabled === "masked" ? "Unblock" : "Block"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
                        onClicked: {
                          if (row.unit.enabled === "masked") root.runAction("unmask", row.unit.name, row.unit.scope, "Unblocked " + row.unit.name, false)
                          else root.runAction("mask", row.unit.name, row.unit.scope, "Blocked " + row.unit.name + " (can't start at all now)", true)
                        } }
                      Button { text: "Copy name"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
                        onClicked: root.copyText(row.unit.name, "Name copied") }
                      Button { text: "Open file"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
                        visible: row.unit.fragment !== ""; onClicked: root.openPath(row.unit.fragment) }
                      Button { text: "Delete"; fontSize: Style.font.caption; foreground: root.bad; fontFamily: root.family; bordered: true
                        visible: row.unit.deletable
                        onClicked: root.runAction("delete", row.unit.name, row.unit.scope, "Delete " + row.unit.name + " forever?", true) }
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Boot = starts with your login. Changing System services may ask for your password once."
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- LOGS VIEW ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "logs"

          Row {
            width: parent.width
            spacing: Style.space(6)
            Button { text: "↻ Reload"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
              onClicked: root.openLogs(root.logUnit, root.logScope) }
            Button { text: "Save to file"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
              onClicked: root.saveLogs() }
            Button { text: "Copy"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
              onClicked: root.copyText(root.logText, "Logs copied") }
            Button { text: "Open file"; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.family; bordered: true
              visible: root.lastSaved !== ""; onClicked: root.openPath(root.lastSaved) }
          }

          Rectangle {
            width: parent.width
            height: Style.space(380)
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
            clip: true

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentHeight: logBody.implicitHeight
              contentWidth: width
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: logBody
                width: parent.width
                textFormat: Text.PlainText
                text: root.logText
                wrapMode: Text.Wrap
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Something broken? Copy the logs and hand them to your AI agent — that's exactly what they're for."
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- BOOT VIEW ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "boot"

          Rectangle {
            width: parent.width
            height: Style.space(380)
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
            clip: true

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentHeight: bootBody.implicitHeight
              contentWidth: width
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: bootBody
                width: parent.width
                textFormat: Text.PlainText
                text: root.bootText
                wrapMode: Text.Wrap
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Button {
            text: "↻ Reload"
            fontSize: Style.font.caption
            foreground: root.fg
            fontFamily: root.family
            bordered: true
            onClicked: root.openBoot()
          }
        }

        // ---------- CREATE VIEW ----------
        Wizard {
          id: wizard
          width: parent.width
          visible: root.view === "create"
          bar: root.bar
          bridgePath: root.bridgePath
          active: root.view === "create" && root.opened
          onCancelled: root.backToListCreate()
          onFinished: function(unit, message) {
            root.showToast(message)
            root.backToListCreate()
            root.refresh()
          }
        }

        // ---------- toast ----------
        Rectangle {
          width: parent.width
          height: toastText.implicitHeight + Style.space(12)
          visible: root.toast !== ""
          radius: Style.cornerRadius
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
          border.width: Math.max(1, Style.space(1))
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)

          Text {
            id: toastText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(8)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.toast
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // confirm dialog overlays the whole panel (sibling of the content,
      // never a Column child, so it never disturbs the layout)
      ConfirmDialog {
        anchors.fill: parent
        opened: root.confirmRequest !== null
        message: root.confirmRequest ? root.confirmRequest.message : ""
        confirmText: "Yes, do it"
        background: Color.popups.background
        foreground: root.fg
        onCanceled: root.confirmRequest = null
        onConfirmed: {
          var r = root.confirmRequest
          root.confirmRequest = null
          if (r) root.runAction(r.op, r.unit, r.scope, r.label, false)
        }
      }
    }
  }

  function backToListCreate() {
    view = "list"
  }
}
