import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
    id: root
    moduleName: "io.github.rickycbanks.osystemd"

    // ── Service lookup (mirrors Sandman pattern) ──────────────────────
    readonly property var service: bar && bar.shell
        ? bar.shell.serviceFor("io.github.rickycbanks.osystemd") : null
    readonly property bool hasService: service !== null
    readonly property int failedCount: service ? service.failedCount : 0

    readonly property color _warnColor: "#e0a040"
    readonly property color _successColor: "#80c080"

    // ── Panel open/close/toggle ───────────────────────────────────────
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

    // ── Inject properties into the loaded panel ───────────────────────
    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
        panelLoader.item.service = root.service
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onServiceChanged: injectPanel()

    // ── Panel loader ──────────────────────────────────────────────────
    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("./Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    // ── Bar button ────────────────────────────────────────────────────
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "\u2699"
        tooltipText: service
            ? Model.indicatorTooltip(service.failedCount, service.scope, service.lastError)
            : "osystemd"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle()
        }
    }
}
