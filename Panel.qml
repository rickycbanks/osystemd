import QtQuick
import Quickshell
import Quickshell.Hyprland
import osystemd

/// PopupWindow shell for the systemd management panel.
/// Hosts PanelContent and handles Escape to close.
PopupWindow {
    id: panelRoot
    visible: Service.panelVisible
    color: "transparent"
    width: 920
    height: 640
    title: "Systemd — " + Model.scopeLabel(Service.scope)

    anchor {
        window: Service.panelAnchor ? Service.panelAnchor.QsWindow.window : null
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
            var target = Service.panelAnchor;
            if (!target) return;
            var window = target.QsWindow.window;
            if (!window) return;

            var popupWidth = panelRoot.width;
            var popupHeight = panelRoot.height;
            var localX = target.width / 2 - popupWidth / 2;
            var localY = target.height + 4;

            var point = window.contentItem.mapFromItem(target, localX, localY);
            point.x = Math.max(4, Math.min(point.x, window.width - popupWidth - 4));

            anchor.rect.x = Math.round(point.x);
            anchor.rect.y = Math.round(point.y);
        }
    }

    PanelContent {
        anchors.fill: parent
    }

    Keys.onEscapePressed: Service.closePanel()
}
