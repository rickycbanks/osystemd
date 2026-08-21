import QtQuick
import Quickshell

/// PopupWindow shell for the systemd management panel.
/// Hosts PanelContent and handles Escape to close.
PopupWindow {
    id: panelRoot
    visible: Service.panelVisible
    width: 920
    height: 640
    title: "Systemd — " + Model.scopeLabel(Service.scope)

    PanelContent {
        anchors.fill: parent
    }

    Keys.onEscapePressed: Service.closePanel()
}
