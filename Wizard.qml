import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Guided service creator. Three/what → details → options → done.
// Emits finished(unit, message) on success, cancelled() on back-out.
Item {
  id: root

  property var bar: null
  property string bridgePath: ""
  property bool active: false

  signal cancelled()
  signal finished(string unit, string message)

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: bar ? Qt.darker(bar.foreground, 1.4) : Color.muted
  readonly property color bad: bar ? bar.urgent : Color.urgent
  readonly property color good: Color.accent
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property bool inputFocused: kindSearch.activeFocus || cmdField.activeFocus
    || pathField.activeFocus || nameField.activeFocus || descField.activeFocus
    || appSearch.activeFocus

  property int step: 0 // 0 kind, 1 details, 2 options, 3 result
  property string kind: "" // app | command | appimage

  // app picking
  property var apps: []
  property var appsFiltered: []
  property string appQuery: ""
  property var pickedApp: null
  property string pickedLabel: ""

  // command
  property string command: ""
  property bool needTerminal: false

  // appimage
  property string appPath: ""

  // options
  property string svcName: ""
  property string svcDesc: ""
  property bool boot: true
  property bool restart: true
  property bool watchdog: false

  // result
  property bool creating: false
  property var result: null

  implicitHeight: wizardCol.implicitHeight

  function reset() {
    step = 0
    kind = ""
    apps = []
    appsFiltered = []
    appQuery = ""
    pickedApp = null
    pickedLabel = ""
    command = ""
    needTerminal = false
    appPath = ""
    svcName = ""
    svcDesc = ""
    boot = true
    restart = true
    watchdog = false
    creating = false
    result = null
  }

  onActiveChanged: if (active) reset()

  // ---------- apps ----------

  function loadApps() {
    if (appsProc.running || apps.length > 0) { filterApps(); return }
    appsProc.command = [bridgePath, "apps"]
    appsProc.running = true
  }

  function filterApps() {
    var q = appQuery.toLowerCase()
    var out = []
    for (var i = 0; i < apps.length; i++) {
      var a = apps[i]
      if (!q || a.name.toLowerCase().indexOf(q) >= 0
          || (a.exec && a.exec.toLowerCase().indexOf(q) >= 0)) out.push(a)
    }
    appsFiltered = out
  }

  function handleApps(text) {
    var d = null
    try { d = JSON.parse(String(text)) } catch (e) { d = null }
    apps = Array.isArray(d) ? d : []
    filterApps()
  }

  function pickApp(a) {
    pickedApp = a
    pickedLabel = a ? ("Picked: " + a.name) : ""
    if (!svcName) svcName = Model.suggestName(a.name)
    if (!svcDesc) svcDesc = a.name + " (starts at login)"
  }

  function appWantsTerminal() {
    return kind === "app" && pickedApp && pickedApp.terminal === true
  }

  // ---------- create ----------

  function execValue() {
    if (kind === "app" && pickedApp) return pickedApp.exec
    if (kind === "command") return command
    if (kind === "appimage") return appPath
    return ""
  }

  function detailsDone() {
    if (kind === "app") return pickedApp !== null
    if (kind === "command") return command.trim() !== ""
    if (kind === "appimage") return appPath.trim() !== ""
    return false
  }

  function canCreate() {
    return detailsDone() && Model.validServiceName(svcName) && !creating
  }

  function doCreate() {
    if (!canCreate() || createProc.running) return
    creating = true
    createProc.command = [bridgePath, "create",
      "--name", svcName.trim(),
      "--desc", svcDesc.trim(),
      "--kind", kind,
      "--exec", execValue(),
      "--boot", boot ? "yes" : "no",
      "--restart", restart ? "yes" : "no",
      "--watchdog", watchdog ? "yes" : "no",
      "--terminal", ((kind === "command" && needTerminal) || appWantsTerminal()) ? "yes" : "no"]
    createProc.running = true
  }

  function handleCreate(text) {
    creating = false
    var d = null
    try { d = JSON.parse(String(text)) } catch (e) { d = null }
    result = d || { ok: false, error: "No answer from helper" }
    step = 3
  }

  function docsPath() {
    return (Quickshell.env("HOME") || "~") + "/Documents/" + svcName.trim() + "/watchdogdata.txt"
  }

  function openDocs() {
    if (result && result.docs) Util.execArgv(["xdg-open", result.docs])
  }

  Process {
    id: appsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleApps(text) }
  }
  Process {
    id: createProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleCreate(text) }
    onExited: root.creating = false
  }

  FileDialog {
    id: imgPick
    title: "Choose an AppImage"
    fileMode: FileDialog.OpenFile
    nameFilters: ["AppImages (*.AppImage *.appimage)", "All files (*)"]
    onAccepted: {
      var u = String(selectedFile)
      var p = decodeURIComponent(u.replace(/^file:\/\//, ""))
      root.appPath = p
      if (!root.svcName) {
        var base = p.split("/").pop().replace(/\.[Aa]pp[Ii]mage$/, "").replace(/-x86_64$/, "")
        root.svcName = Model.suggestName(base)
      }
    }
  }

  Column {
    id: wizardCol
    width: parent.width
    spacing: Style.space(8)

    // step header
    Row {
      width: parent.width
      spacing: Style.space(8)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.step === 0 ? "Step 1 of 3 — what should it run?"
          : root.step === 1 ? "Step 2 of 3 — pick it"
          : root.step === 2 ? "Step 3 of 3 — name it"
          : "Done"
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Item { width: Style.space(4); height: 1 }
      Button {
        text: root.step === 0 ? "✕ Cancel" : "‹ Back"
        fontSize: Style.font.caption
        foreground: root.fg
        fontFamily: root.family
        anchors.verticalCenter: parent.verticalCenter
        onClicked: {
          if (root.step === 0) root.cancelled()
          else if (root.step === 3) root.finished(result && result.ok ? result.unit : "", result ? (result.message || result.error || "") : "")
          else root.step--
        }
      }
    }

    // ===== step 0: kind =====
    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: root.step === 0

      Repeater {
        model: [
          { v: "app", t: "An installed app", d: "Pick from every app on your system — we wire up the launch command for you." },
          { v: "command", t: "A command", d: "Anything you could type in a terminal, like “btop” or “python ~/notes.py”." },
          { v: "appimage", t: "An AppImage file", d: "Point at the .AppImage file — we make it executable if needed." }
        ]
        delegate: Rectangle {
          required property var modelData
          width: wizardCol.width
          height: cardCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: cardHover.containsMouse
            ? Style.hoverFillFor(root.fg)
            : Style.normalFillFor(root.fg)
          border.width: Math.max(1, Style.space(1))
          border.color: cardHover.containsMouse
            ? Style.hoverBorderFor(root.fg)
            : Style.normalBorderFor(root.fg)

          Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "▸ " + modelData.t
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: modelData.d
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.kind = modelData.v
              if (modelData.v === "app") root.loadApps()
              root.step = 1
            }
          }
        }
      }
    }

    // ===== step 1: details =====
    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.step === 1

      // --- app ---
      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.kind === "app"

        TextField {
          id: kindSearch
          width: parent.width
          placeholderText: "Type to filter…"
          foreground: root.fg
          visible: false
        }

        TextField {
          id: appSearch
          width: parent.width
          placeholderText: "Search your apps…"
          foreground: root.fg
          font.pixelSize: Style.font.body
          onTextChanged: { root.appQuery = text; root.filterApps() }
        }

        Rectangle {
          width: parent.width
          height: Style.space(220)
          radius: Style.cornerRadius
          color: "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
          clip: true

          ListView {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            clip: true
            spacing: Style.space(2)
            model: root.appsFiltered

            delegate: Item {
              required property var modelData
              width: parent ? parent.width : 0
              height: Style.space(34)

              readonly property bool sel: root.pickedApp && root.pickedApp.file === modelData.file

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: parent.sel ? Qt.rgba(root.good.r, root.good.g, root.good.b, 0.18) : "transparent"
                border.width: parent.sel ? Math.max(1, Style.space(1)) : 0
                border.color: root.good
              }
              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(8)
                textFormat: Text.PlainText
                text: (parent.sel ? "✓ " : "") + modelData.name
                elide: Text.ElideRight
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickApp(modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.pickedApp !== null
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.pickedLabel
          color: root.good
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.appWantsTerminal()
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "This app asks for a terminal — we'll open one for it automatically."
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }

      // --- command ---
      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.kind === "command"

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Type the full command, exactly as you'd run it in a terminal."
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
        TextField {
          id: cmdField
          width: parent.width
          placeholderText: "e.g. btop   or   python3 ~/scripts/notes.py"
          foreground: root.fg
          font.pixelSize: Style.font.body
          onTextChanged: root.command = text
        }
        Row {
          width: parent.width
          spacing: Style.space(8)
          ToggleSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.needTerminal
            foreground: root.fg
            onToggled: root.needTerminal = !root.needTerminal
          }
          Text {
            width: parent.width - x
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Needs a terminal window (for tools like btop, yazi, strata)"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // --- appimage ---
      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.kind === "appimage"

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Choose the .AppImage file. It will be made executable automatically."
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: pathField
            width: parent.width - browseBtn.width - Style.space(6)
            placeholderText: "/home/you/Apps/cool.AppImage"
            foreground: root.fg
            font.pixelSize: Style.font.bodySmall
            text: root.appPath
            onTextChanged: root.appPath = text
          }
          Button {
            id: browseBtn
            text: "Browse…"
            fontSize: Style.font.caption
            foreground: root.fg
            fontFamily: root.family
            bordered: true
            onClicked: imgPick.open()
          }
        }
      }

      Button {
        text: "Continue ›"
        fontSize: Style.font.bodySmall
        foreground: root.fg
        fontFamily: root.family
        bordered: true
        opacity: root.detailsDone() ? 1 : 0.4
        onClicked: if (root.detailsDone()) root.step = 2
      }
    }

    // ===== step 2: options =====
    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.step === 2

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Name your service (letters, numbers, dash — no spaces):"
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }
      TextField {
        id: nameField
        width: parent.width
        placeholderText: "e.g. my-notes"
        foreground: root.fg
        font.pixelSize: Style.font.body
        text: root.svcName
        onTextChanged: root.svcName = text
      }
      Text {
        width: parent.width
        visible: root.svcName !== "" && !Model.validServiceName(root.svcName)
        textFormat: Text.PlainText
        text: "That name won't work — use only letters, numbers, dot, dash, underscore."
        color: root.bad
        font.family: root.family
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Description (optional, just for you):"
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }
      TextField {
        id: descField
        width: parent.width
        placeholderText: "e.g. my notes app at login"
        foreground: root.fg
        font.pixelSize: Style.font.body
        text: root.svcDesc
        onTextChanged: root.svcDesc = text
      }

      PanelSeparator { foreground: root.fg }

      Row {
        width: parent.width
        spacing: Style.space(8)
        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: root.boot
          foreground: root.fg
          onToggled: root.boot = !root.boot
        }
        Text {
          width: parent.width - x
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Start automatically when I log in (recommended)"
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: root.restart
          foreground: root.fg
          onToggled: root.restart = !root.restart
        }
        Text {
          width: parent.width - x
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Restart it if it crashes"
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Rectangle {
        width: parent.width
        height: watchCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

        Column {
          id: watchCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(8)
            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.watchdog
              foreground: root.fg
              onToggled: root.watchdog = !root.watchdog
            }
            Text {
              width: parent.width - x
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Watch over it (watchdog)"
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "If yes, we check it every minute and keep a diary here:\n"
              + root.docsPath()
              + "\nIf it ever fails: stop it, open that file, hand it to your AI agent."
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Button {
        text: root.creating ? "Creating…" : "✓ Create service"
        fontSize: Style.font.bodySmall
        foreground: root.fg
        fontFamily: root.family
        bordered: true
        opacity: root.canCreate() ? 1 : 0.4
        onClicked: root.doCreate()
      }
    }

    // ===== step 3: result =====
    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.step === 3

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.result && root.result.ok ? "✓ All set!" : "✕ Something went wrong"
        color: root.result && root.result.ok ? root.good : root.bad
        font.family: root.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.result ? (root.result.message || root.result.error || "") : ""
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        width: parent.width
        visible: root.result && root.result.ok && root.result.watchdog
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Watchdog diary: " + (root.result ? (root.result.docs || "") : "")
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Row {
        width: parent.width
        spacing: Style.space(6)
        Button {
          text: "Open diary folder"
          fontSize: Style.font.caption
          foreground: root.fg
          fontFamily: root.family
          bordered: true
          visible: root.result && root.result.ok && root.result.watchdog
          onClicked: root.openDocs()
        }
        Button {
          text: "Done"
          fontSize: Style.font.bodySmall
          foreground: root.fg
          fontFamily: root.family
          bordered: true
          onClicked: root.finished(root.result && root.result.ok ? root.result.unit : "",
            root.result ? (root.result.message || root.result.error || "") : "")
        }
      }
    }
  }
}
