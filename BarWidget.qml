import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Store.js" as Store

Panel {
  id: root
  moduleName: "osystemd"
  ipcTarget: "osystemd"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ── Settings (injected by omarchy shell) ─────────────────────
  property var settings: ({})

  readonly property bool showFailedCount: settings.showFailedCount !== false
  readonly property string defaultScope: String(settings.defaultScope || "user")
  readonly property int pollIntervalSec: Number(settings.pollIntervalSec) || 4
  readonly property int journalLines: Number(settings.journalLines) || 120
  readonly property bool showSubState: settings.showSubState !== false

  // ── State from Store ─────────────────────────────────────────
  property int _userRevision: 0
  property int _systemRevision: 0
  property var _storeState: Store.get()

  readonly property int userFailed: _storeState.userSummary.failed || 0
  readonly property int systemFailed: _storeState.systemSummary.failed || 0
  readonly property int userActive: _storeState.userSummary.active || 0
  readonly property int systemActive: _storeState.systemSummary.active || 0
  readonly property bool userAvailable: _storeState.userAvailable || false
  readonly property bool systemAvailable: _storeState.systemAvailable || false
  readonly property int totalFailed: userFailed + systemFailed
  readonly property bool hasFailed: totalFailed > 0

  // ── Poll Store revisions ─────────────────────────────────────
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      var s = Store.get();
      if (s.userRevision !== root._userRevision) {
        root._userRevision = s.userRevision;
      }
      if (s.systemRevision !== root._systemRevision) {
        root._systemRevision = s.systemRevision;
      }
      root._storeState = s;
    }
  }

  // ── Icon button ──────────────────────────────────────────────
  BarIconButton {
    id: button
    bar: root.bar
    // Inline SVG gear icon — renders regardless of font configuration.
    // iconComponent bypasses OpticalGlyph entirely; the Loader in
    // BarIconButton renders this Image inside the optical-canvas Item.
    iconComponent: Component {
      Image {
        source: Qt.resolvedUrl("icon.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(button.opticalSize, button.opticalSize)
      }
    }

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.toggle();
      }
    }
  }

  // ── Keyboard panel popup ─────────────────────────────────────
  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: 520
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight, 600)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.switchPanel(direction);
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height
                                  ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.spacing.panelGap
          topPadding: Style.spacing.popupPadding
          bottomPadding: Style.spacing.popupPadding
          leftPadding: Style.spacing.popupPadding
          rightPadding: Style.spacing.popupPadding

          // ── Hero / title row ─────────────────────────────────
          PanelHero {
            width: parent.width - parent.leftPadding - parent.rightPadding

            Row {
              spacing: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter

              Image {
        source: Qt.resolvedUrl("icon.svg")
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(Style.font.iconLarge, Style.font.iconLarge)
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  text: "Systemd"
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  color: Color.foreground
                }

                Text {
                  text: {
                    var parts = [];
                    if (root.userAvailable) parts.push(root.userActive + " user");
                    if (root.systemAvailable) parts.push(root.systemActive + " sys");
                    if (root.hasFailed) parts.push(root.totalFailed + " failed");
                    return parts.length > 0 ? parts.join(" · ") : "loading…";
                  }
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.hasFailed ? Color.urgent : Color.muted

                }
              }
            }
          }

          // ── Error banner ─────────────────────────────────────
          Rectangle {
            width: parent.width - parent.leftPadding - parent.rightPadding
            height: root._storeState.lastError ? errorLabel.implicitHeight + Style.spacing.md * 2 : 0
            visible: root._storeState.lastError !== ""
            color: Util.alpha(Color.urgent, 0.15)
            radius: Style.cornerRadius

            Text {
              id: errorLabel
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              text: root._storeState.lastError
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              color: Color.urgent
              wrapMode: Text.Wrap
            }
          }

          // ── Separator ────────────────────────────────────────
          PanelSeparator {
            width: parent.width - parent.leftPadding - parent.rightPadding
          }

          // ── Panel content (heavy lifting) ────────────────────
          Loader {
            id: contentLoader
            width: parent.width - parent.leftPadding - parent.rightPadding
            active: root.opened
            sourceComponent: Component {
              PanelContent {
                bar: root.bar
                shellPath: root._shellPath()
                showSubState: root.showSubState
                defaultScope: root.defaultScope
                journalLines: root.journalLines
                onActionRequested: function(action, unitName, scope) {
                  Quickshell.execDetached(["qs", "ipc", "-p", root._shellPath(), "call", "osystemd", action, unitName, scope]);
                }
                onRefreshRequested: function() {
                  Quickshell.execDetached(["qs", "ipc", "-p", root._shellPath(), "call", "osystemd", "refresh"]);
                }
              }
            }
          }
        }
      }
    }
  }

  // ── Shell path helper ────────────────────────────────────────
  function _shellPath() {
    var envPath = Quickshell.env("OMARCHY_PATH");
    if (envPath) return envPath + "/shell";
    return Qt.homedir + "/.local/share/omarchy/shell";
  }
}
