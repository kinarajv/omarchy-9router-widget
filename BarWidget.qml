import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "kinara.9router"
  ipcTarget: "kinara.9router"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var statusData: ({})
  readonly property string barText: statusData.barText ? statusData.barText : ""
  readonly property string tooltipText: statusData.tooltip ? statusData.tooltip : "9Router AI Infrastructure"
  readonly property var totals: statusData.totals || {}
  readonly property var accounts: statusData.accounts || []

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  FileView {
    id: statusWatcher
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/9router/usage.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.statusData = JSON.parse(text())
      } catch (e) {}
    }
  }

  function pluginFile(relative) {
    var url = String(Qt.resolvedUrl(relative))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    try { url = decodeURIComponent(url) } catch (e) {}
    return url
  }
  readonly property string fetchExecutable: pluginFile("fetch")

  readonly property var childEnvironment: ({
    "HOME": null,
    "PATH": "/usr/bin:/bin",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8"
  })

  function triggerFetch() {
    if (!fetchProcess.running) {
      fetchProcess.bytesRead = 0
      fetchProcess.running = true
      fetchWatchdog.restart()
    }
  }

  Process {
    id: fetchProcess
    command: [root.fetchExecutable]
    environment: root.childEnvironment
    clearEnvironment: true
    property int bytesRead: 0
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        fetchProcess.bytesRead += chunk.length
        if (fetchProcess.bytesRead > 4096) {
          fetchProcess.running = false
        }
      }
    }
    onExited: {
      fetchWatchdog.stop()
      fetchProcess.bytesRead = 0
    }
  }

  Timer {
    id: fetchWatchdog
    interval: 8000
    repeat: false
    onTriggered: {
      if (fetchProcess.running) fetchProcess.running = false
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.triggerFetch()
  }

  onOpenedChanged: if (opened) {
    root.triggerFetch()
  }

  Component.onCompleted: {
    try {
      var content = statusWatcher.text()
      if (content) root.statusData = JSON.parse(content)
    } catch (e) {}
    root.triggerFetch()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string {
      root.triggerFetch()
      return "ok"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒋 " + root.barText
    tooltipText: root.tooltipText
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.bar) root.bar.run("xdg-open " + (root.statusData.dashboardUrl || "http://localhost:20128/dashboard"))
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(620))

    Item {
      anchors.fill: parent

      Flickable {
        id: panelFlick
        anchors.fill: parent
        anchors.margins: Style.spacing.xl
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true

        Column {
          id: mainColumn
          width: parent.width
          spacing: Style.spacing.lg

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Rectangle {
              width: Style.space(36)
              height: Style.space(36)
              radius: Style.space(8)
              color: "#f97815"
              Text {
                anchors.centerIn: parent
                text: "9"
                color: "white"
                font.bold: true
                font.pixelSize: Style.font.title
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: "9Router"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: (root.statusData.gatewayHost ? root.statusData.gatewayHost : "9Router Gateway") + " · " + (root.statusData.online ? "Online" : "Connecting...")
                color: root.statusData.online ? "#44cc66" : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Rectangle {
              width: (parent.width - Style.spacing.md * 2) / 3
              height: Style.space(64)
              radius: Style.cornerRadius
              color: root.alpha(root.foreground, 0.06)
              Column {
                anchors.centerIn: parent
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: String(root.totals.requests || 0)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Requests"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Rectangle {
              width: (parent.width - Style.spacing.md * 2) / 3
              height: Style.space(64)
              radius: Style.cornerRadius
              color: root.alpha(root.foreground, 0.06)
              Column {
                anchors.centerIn: parent
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.totals.totalTokensFormatted ? root.totals.totalTokensFormatted : "0"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Tokens"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Rectangle {
              width: (parent.width - Style.spacing.md * 2) / 3
              height: Style.space(64)
              radius: Style.cornerRadius
              color: root.alpha(root.foreground, 0.06)
              Column {
                anchors.centerIn: parent
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: String(root.totals.activeAccounts || 0)
                  color: (root.totals.quotaLimitedAccounts > 0) ? "#f5a623" : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Enabled"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Row {
            width: parent.width
            Text {
              text: "ENABLED ACCOUNTS (" + root.accounts.length + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.accounts.slice(0, 30)

              Rectangle {
                required property var modelData
                width: parent.width
                height: Style.space(44)
                radius: Style.cornerRadius
                color: root.alpha(root.foreground, 0.04)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.md
                  width: parent.width - Style.space(160)

                  Rectangle {
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    color: !modelData.isActive ? "#777777" : (modelData.isQuotaLimited ? "#ff4455" : "#44cc66")
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: modelData.email
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                      width: Style.space(240)
                    }
                    Text {
                      text: modelData.provider + (modelData.priority ? " · P" + modelData.priority : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                Column {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.right: parent.right
                    text: modelData.requests > 0 ? (modelData.requests + " reqs · " + modelData.tokensFormatted) : (modelData.isActive ? "Ready" : "Disabled")
                    color: modelData.requests > 0 ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    anchors.right: parent.right
                    text: modelData.isQuotaLimited ? "Quota 429" : (modelData.isActive ? "Active" : "Off")
                    color: modelData.isQuotaLimited ? "#ff4455" : (modelData.isActive ? "#44cc66" : root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: modelData.isQuotaLimited
                  }
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Button {
              width: (parent.width - Style.spacing.md) / 2
              text: "Open Web Dashboard"
              onClicked: {
                if (root.bar) root.bar.run("xdg-open " + (root.statusData.dashboardUrl || "http://localhost:20128/dashboard"))
                root.close()
              }
            }

            Button {
              width: (parent.width - Style.spacing.md) / 2
              text: "Refresh Data"
              onClicked: {
                root.triggerFetch()
              }
            }
          }
        }
      }
    }
  }
}
