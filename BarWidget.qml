import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Ui
import "Model.js" as Model

/// Bar-widget entry point: compact indicator dot + optional failed count.
Item {
    id: root
    implicitWidth: 24
    implicitHeight: 24

    // ── Dot indicator ──────────────────────────────────────────────────
    Rectangle {
        id: dot
        anchors.centerIn: parent
        width: 10
        height: 10
        radius: 5
        color: {
            var key = Model.indicatorColor(Service.failedCount, Service.lastError);
            if (key === "error") return Color.error;
            if (key === "warn") return Color.warn;
            return Color.success;
        }

        // Pulse animation on failure
        SequentialAnimation {
            loops: Service.failedCount > 0 ? Animation.Infinite : 0
            running: loops > 0
            NumberAnimation {
                target: dot; property: "scale"
                from: 1.0; to: 1.3; duration: 600
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: dot; property: "scale"
                from: 1.3; to: 1.0; duration: 600
                easing.type: Easing.InOutQuad
            }
        }
    }

    // ── Failed count badge (visible only when > 0) ────────────────────
    Text {
        id: countLabel
        anchors.left: dot.right
        anchors.leftMargin: 2
        anchors.verticalCenter: dot.verticalCenter
        visible: Service.failedCount > 0
        text: String(Service.failedCount)
        font.pixelSize: Style.fontSizeSmall
        font.bold: true
        color: Color.error
    }

    // ── Tooltip on hover ───────────────────────────────────────────────
    ToolTip {
        id: tooltip
        visible: hoverArea.containsMouse
        text: Model.indicatorTooltip(Service.failedCount, Service.scope, Service.lastError)
        delay: 400
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Service.togglePanel()
    }
}
