import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.rickycbanks.osystemd"
    manageIpc: false

    // ── Injected properties (set by BarWidget via injectPanel) ────────
    property var anchorItem: null
    property var hostWidget: null
    property var service: null

    // ── Helpers ───────────────────────────────────────────────────────
    readonly property var barIdentity: hostWidget || root
    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

    // ── Safe local shorthands (null-guarded) ──────────────────────────
    readonly property string panelScope: service ? service.scope : "user"
    readonly property string panelSearch: service ? service.searchQuery : ""
    readonly property var panelTypeFilter: service ? service.typeFilter : ["service","timer","socket","mount","automount","path","swap","target"]
    readonly property var panelStateFilter: service ? service.stateFilter : ["active","inactive","failed"]
    readonly property string panelSelectedUnit: service ? service.selectedUnit : ""
    readonly property var panelDetail: service ? service.detail : ({})
    readonly property int panelFailedCount: service ? service.failedCount : 0
    readonly property bool panelBusy: service ? service.busy : false
    readonly property string panelLastError: service ? service.lastError : ""
    readonly property bool panelCanElevate: service ? service.canElevate : false
    readonly property var panelUnits: service ? service.units : []
    readonly property var panelUnloadedUnits: service ? service.unloadedUnits : []
    readonly property var panelFilteredUnits: service ? service.filteredUnits : []
    readonly property var panelFilteredUnloaded: {
        var list = [];
        for (var i = 0; i < panelUnloadedUnits.length; i++) {
            var u = panelUnloadedUnits[i];
            if (panelTypeFilter.indexOf(u.type) < 0) continue;
            if (panelSearch !== "" && Model.searchScore(panelSearch, u) === 0) continue;
            list.push(u);
        }
        list.sort(function (a, b) { return a.name.localeCompare(b.name); });
        return list;
    }

    // All available filter options for chip repeaters
    readonly property var _allTypeFilters: ["service","timer","socket","mount","automount","path","swap","target"]
    readonly property var _allStateFilters: ["active","inactive","failed"]

    readonly property color _warnColor: "#e0a040"
    readonly property color _successColor: "#80c080"

    // ── Panel-local state ─────────────────────────────────────────────
    property int currentTab: 0  // 0=Status, 1=Actions, 2=UnitFile, 3=Journal
    property bool showUnloaded: true

    // ── Functions to invoke Service from the UI ──────────────────────
    function setScope(s) { if (service) service.setScope(s) }
    function setSearch(q) { if (service) service.setSearch(q) }
    function setTypeFilter(t) { if (service) service.setTypeFilter(t) }
    function setStateFilter(s) { if (service) service.setStateFilter(s) }
    function refresh() { if (service) service.refresh() }
    function selectUnit(name) { if (service) service.selectUnit(name) }
    function mutate(action, unit) { if (service) service.mutate(action, unit) }
    function loadDetailTab(tab) { if (service) service.loadDetailTab(tab) }
    function togglePin(name) { if (service) service.togglePin(name) }
    function scopeLabel(s) { return Model.scopeLabel(s) }

    // Map panel tab index → helper subcommand and switch to it, fetching
    // the data for that tab if a unit is selected. Without this, clicking
    // "Unit File" or "Journal" switched the view but never issued the
    // `cat` / `journal` command — so the tab looked "disabled".
    function _selectTab(index) {
        root.currentTab = index;
        if (root.panelSelectedUnit === "") return;
        var sub = ["status", "status", "cat", "journal"][index];
        if (sub) root.loadDetailTab(sub);
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction)
        return false
    }

    function scrollPanel(delta) {
        panelFlick.contentY = Math.max(0, Math.min(
            panelFlick.contentY + delta,
            Math.max(0, panelFlick.contentHeight - panelFlick.height)))
    }

    // ──────────────────────────────────────────────────────────────────
    //  KEYBOARD PANEL
    // ──────────────────────────────────────────────────────────────────
    KeyboardPanel {
        id: panelWindow
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panelWindow.fittedContentWidth(Style.space(920))
        contentHeight: panelWindow.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }
            onMoveRequested: function(dx, dy) {
                if (dy !== 0) root.scrollPanel(dy * Style.space(56))
            }

            Flickable {
                id: panelFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                WheelHandler {
                    onWheel: function(event) {
                        if (event.angleDelta.y === 0) return
                        root.scrollPanel(event.angleDelta.y > 0 ? -Style.space(56) : Style.space(56))
                        event.accepted = true
                    }
                }

                // ──────────────────────────────────────────────────────
                //  INLINED CONTENT (from old PanelContent.qml)
                // ──────────────────────────────────────────────────────
                Column {
                    id: content
                    width: panelFlick.width
                    spacing: Style.space(12)

                    // ── HEADER ───────────────────────────────────────
                    Rectangle {
                        width: parent.width
                        height: 56
                        color: Color.popups.background
                        radius: Style.cornerRadius

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Style.spacing.panelPadding
                            spacing: Style.spacing.panelPadding

                            // Scope toggle
                            Row {
                                spacing: 4
                                Repeater {
                                    model: ["user", "system"]
                                    delegate: Rectangle {
                                        width: scopeLabelTxt.implicitWidth + 16
                                        height: 28
                                        radius: 4
                                        color: root.panelScope === modelData ? Color.accent : "transparent"
                                        border.color: root.panelScope === modelData ? Color.accent : Color.muted
                                        border.width: 1
                                        Text {
                                            id: scopeLabelTxt
                                            anchors.centerIn: parent
                                            text: Model.scopeLabel(modelData)
                                            font.pixelSize: Style.font.body
                                            color: root.panelScope === modelData ? "#ffffff" : Color.foreground
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.setScope(modelData)
                                        }
                                    }
                                }
                            }

                            // Search field
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 4
                                color: Color.background
                                border.color: Color.muted
                                border.width: 1
                                TextInput {
                                    id: searchInput
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    font.pixelSize: Style.font.body
                                    color: Color.foreground
                                    clip: true
                                    selectByMouse: true
                                    text: root.panelSearch
                                    onTextChanged: root.setSearch(text)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !searchInput.text && !searchInput.activeFocus
                                        text: "Search units..."
                                        font.pixelSize: Style.font.body
                                        color: Color.muted
                                    }
                                }
                            }

                            // Refresh button
                            Rectangle {
                                width: 28; height: 28; radius: 4
                                color: refreshArea.containsMouse ? Color.popups.background : "transparent"
                                border.color: Color.muted; border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u21BB"
                                    font.pixelSize: Style.font.body
                                    color: Color.foreground
                                }
                                MouseArea {
                                    id: refreshArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.refresh()
                                }
                            }

                            // Settings button (placeholder)
                            Rectangle {
                                width: 28; height: 28; radius: 4
                                color: settingsArea.containsMouse ? Color.popups.background : "transparent"
                                border.color: Color.muted; border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u2699"
                                    font.pixelSize: Style.font.body
                                    color: Color.foreground
                                }
                                MouseArea {
                                    id: settingsArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                            }
                        }
                    }

                    // ── FILTER CHIPS ROW ─────────────────────────────
                    RowLayout {
                        width: parent.width
                        height: 32
                        Layout.margins: 4
                        spacing: 4

                        Text {
                            text: "Type:"
                            font.pixelSize: Style.font.bodySmall
                            color: Color.muted
                        }
                        Repeater {
                            model: root._allTypeFilters
                            delegate: Rectangle {
                                width: chipText.implicitWidth + 12
                                height: 22
                                radius: 4
                                color: root.panelTypeFilter.indexOf(modelData) >= 0 ? Color.accent : "transparent"
                                border.color: root.panelTypeFilter.indexOf(modelData) >= 0 ? Color.accent : Color.muted
                                border.width: 1
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: Style.font.bodySmall
                                    color: root.panelTypeFilter.indexOf(modelData) >= 0 ? "#ffffff" : Color.muted
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        var arr = root.panelTypeFilter.slice();
                                        var idx = arr.indexOf(modelData);
                                        if (idx >= 0) arr.splice(idx, 1);
                                        else arr.push(modelData);
                                        root.setTypeFilter(arr);
                                    }
                                }
                            }
                        }

                        Item { width: 12; height: 1 } // spacer

                        Text {
                            text: "State:"
                            font.pixelSize: Style.font.bodySmall
                            color: Color.muted
                        }
                        Repeater {
                            model: root._allStateFilters
                            delegate: Rectangle {
                                width: stateChipText.implicitWidth + 12
                                height: 22
                                radius: 4
                                color: root.panelStateFilter.indexOf(modelData) >= 0 ? Color.accent : "transparent"
                                border.color: root.panelStateFilter.indexOf(modelData) >= 0 ? Color.accent : Color.muted
                                border.width: 1
                                Text {
                                    id: stateChipText
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: Style.font.bodySmall
                                    color: root.panelStateFilter.indexOf(modelData) >= 0 ? "#ffffff" : Color.muted
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        var arr = root.panelStateFilter.slice();
                                        var idx = arr.indexOf(modelData);
                                        if (idx >= 0) arr.splice(idx, 1);
                                        else arr.push(modelData);
                                        root.setStateFilter(arr);
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true } // spacer

                        // Busy indicator
                        Text {
                            visible: root.panelBusy
                            text: "Loading..."
                            font.pixelSize: Style.font.bodySmall
                            color: Color.accent
                        }

                        // Summary
                        Text {
                            text: Model.failedSummary(root.panelFailedCount, root.panelScope)
                            font.pixelSize: Style.font.bodySmall
                            color: root.panelFailedCount > 0 ? Color.urgent : Color.muted
                        }
                    }

                    // ── BODY: split list | detail ────────────────────
                    SplitView {
                        width: parent.width
                        height: 540
                        orientation: Qt.Horizontal

                        // ── LEFT: Unit list ──────────────────────────
                        Rectangle {
                            SplitView.preferredWidth: 360
                            color: Color.background
                            radius: Style.cornerRadius

                            ListView {
                                id: unitList
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                model: root.panelFilteredUnits
                                currentIndex: -1

                                delegate: Rectangle {
                                    id: unitDelegate
                                    required property var model
                                    required property int index
                                    width: unitList.width
                                    height: 48
                                    radius: 4
                                    color: unitList.currentIndex === index
                                           ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                                           : delegateArea.containsMouse
                                             ? Qt.rgba(1, 1, 1, 0.05)
                                             : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 8

                                        // Type icon
                                        Text {
                                            text: _typeIcon(unitDelegate.model.type)
                                            font.pixelSize: Style.font.body
                                            color: Color.muted
                                            Layout.preferredWidth: 20
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        // Name + description
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: unitDelegate.model.name
                                                font.pixelSize: Style.font.body
                                                font.bold: unitList.currentIndex === unitDelegate.index
                                                color: Color.foreground
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: unitDelegate.model.description || ""
                                                font.pixelSize: Style.font.bodySmall
                                                color: Color.muted
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                maximumLineCount: 1
                                            }
                                        }

                                        // State badge
                                        Rectangle {
                                            width: badgeText.implicitWidth + 10
                                            height: 18
                                            radius: 4
                                            color: {
                                                var key = Model.stateColorKey(
                                                    Model.normalizeState(unitDelegate.model.active, unitDelegate.model.sub));
                                                if (key === "success") return _successColor;
                                                if (key === "error") return Color.urgent;
                                                if (key === "warn") return _warnColor;
                                                return Color.muted;
                                            }
                                            Text {
                                                id: badgeText
                                                anchors.centerIn: parent
                                                text: Model.stateBadge(unitDelegate.model.active, unitDelegate.model.sub)
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: "#ffffff"
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: delegateArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            unitList.currentIndex = unitDelegate.index;
                                            root.selectUnit(unitDelegate.model.name);
                                        }
                                    }
                                }

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                }
                            }
                        }

                        // ── RIGHT: Detail pane ───────────────────────
                        Rectangle {
                            SplitView.fillWidth: true
                            color: Color.background
                            radius: Style.cornerRadius

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 0

                                // Tab bar
                                Row {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Repeater {
                                        model: ["Status", "Actions", "Unit File", "Journal"]
                                        delegate: Rectangle {
                                            width: tabLabel.implicitWidth + 20
                                            height: 32
                                            radius: 4
                                            color: root.currentTab === index ? Color.popups.background : "transparent"
                                            Text {
                                                id: tabLabel
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.pixelSize: Style.font.body
                                                font.bold: root.currentTab === index
                                                color: root.currentTab === index ? Color.accent : Color.muted
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: root._selectTab(index)
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Color.muted
                                }

                                // ── Tab content ────────────────────────
                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: root.currentTab

                                    // 0: Status tab
                                    ScrollView {
                                        id: statusScroll
                                        clip: true

                                        ColumnLayout {
                                            width: statusScroll.width
                                            spacing: 4

                                            Text {
                                                visible: !root.panelSelectedUnit
                                                text: "Select a unit from the list"
                                                font.pixelSize: Style.font.body
                                                color: Color.muted
                                                Layout.margins: 8
                                            }

                                            Repeater {
                                                model: _statusFields()
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.margins: 4
                                                    spacing: 8

                                                    Text {
                                                        text: modelData.key
                                                        font.pixelSize: Style.font.bodySmall
                                                        font.bold: true
                                                        color: Color.muted
                                                        Layout.preferredWidth: 140
                                                    }
                                                    Text {
                                                        text: modelData.value || "\u2014"
                                                        font.pixelSize: Style.font.body
                                                        color: Color.foreground
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.Wrap
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // 1: Actions tab
                                    ColumnLayout {
                                        spacing: 8
                                        Layout.margins: 8

                                        Text {
                                            visible: !root.panelSelectedUnit
                                            text: "Select a unit from the list"
                                            font.pixelSize: Style.font.body
                                            color: Color.muted
                                        }

                                        Text {
                                            visible: root.panelSelectedUnit !== ""
                                            text: root.panelSelectedUnit
                                            font.pixelSize: Style.font.body
                                            font.bold: true
                                            color: Color.foreground
                                        }

                                        // Warning for system scope without elevation
                                        Text {
                                            visible: root.panelScope === "system" && !root.panelCanElevate
                                            text: "pkexec not available \u2014 system mutations will fail"
                                            font.pixelSize: Style.font.bodySmall
                                            color: _warnColor
                                        }

                                        // Action buttons in a grid
                                        GridLayout {
                                            visible: root.panelSelectedUnit !== ""
                                            columns: 3
                                            columnSpacing: 8
                                            rowSpacing: 4

                                            Repeater {
                                                model: ListModel {
                                                    ListElement { label: "Start"; action: "start"; needsActive: false }
                                                    ListElement { label: "Stop"; action: "stop"; needsActive: true }
                                                    ListElement { label: "Restart"; action: "restart"; needsActive: false }
                                                    ListElement { label: "Enable"; action: "enable"; needsActive: false }
                                                    ListElement { label: "Disable"; action: "disable"; needsActive: false }
                                                    ListElement { label: "Mask"; action: "mask"; needsActive: false }
                                                    ListElement { label: "Unmask"; action: "unmask"; needsActive: false }
                                                    ListElement { label: "Reload"; action: "daemon-reload"; needsActive: false }
                                                }
                                                delegate: Rectangle {
                                                    Layout.preferredWidth: 120
                                                    Layout.preferredHeight: 32
                                                    radius: 4
                                                    property bool btnEnabled: _actionEnabled(
                                                        model.action, model.needsActive)
                                                    color: {
                                                        if (!btnEnabled) return Qt.rgba(0.4, 0.4, 0.4, 0.18);
                                                        return btnMouseArea.containsMouse ? Color.accent : Color.popups.background;
                                                    }
                                                    border.color: btnEnabled ? Color.muted : Qt.rgba(0.5, 0.5, 0.5, 0.4)
                                                    border.width: 1
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: btnEnabled ? model.label : "\uD83D\uDD12 " + model.label
                                                        font.pixelSize: Style.font.body
                                                        color: btnEnabled ? Color.foreground : Color.muted
                                                    }
                                                    MouseArea {
                                                        id: btnMouseArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        enabled: btnEnabled
                                                        onClicked: root.mutate(model.action, root.panelSelectedUnit)
                                                        ToolTip.visible: btnMouseArea.containsMouse
                                                        ToolTip.delay: 400
                                                        ToolTip.text: {
                                                            if (!btnEnabled) {
                                                                if (model.action === "stop") return "Unit is not active \u2014 nothing to stop";
                                                                if (root.panelScope === "system" && !root.panelCanElevate)
                                                                    return "Requires polkit authentication \u2014 install polkit-gnome and start it via Hyprland exec-once";
                                                                return "Not available";
                                                            }
                                                            return model.label + " \u2014 " + (model.action === "daemon-reload" ? "reload systemd manager configuration" : model.action + " this unit");
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // 2: Unit File tab
                                    ScrollView {
                                        id: fileScroll
                                        clip: true

                                        ColumnLayout {
                                            width: fileScroll.width
                                            spacing: 4

                                            Text {
                                                visible: !root.panelSelectedUnit
                                                text: "Select a unit from the list"
                                                font.pixelSize: Style.font.body
                                                color: Color.muted
                                                Layout.margins: 8
                                            }

                                            Repeater {
                                                model: _fileSections()
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    Text {
                                                        text: modelData.path
                                                        font.pixelSize: Style.font.bodySmall
                                                        font.family: "monospace"
                                                        color: Color.accent
                                                    }
                                                    Text {
                                                        text: modelData.content
                                                        font.pixelSize: Style.font.bodySmall
                                                        font.family: "monospace"
                                                        color: Color.foreground
                                                        wrapMode: Text.Wrap
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                            }

                                            // Fallback: raw cat output
                                            Text {
                                                visible: root.panelSelectedUnit !== "" && _fileSections().length === 0
                                                text: "No unit file content available"
                                                font.pixelSize: Style.font.body
                                                color: Color.muted
                                            }
                                        }
                                    }

                                    // 3: Journal tab
                                    ColumnLayout {
                                        spacing: 4

                                        // Journal header bar
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.margins: 4
                                            spacing: 8

                                            Rectangle {
                                                width: 24; height: 24; radius: 4
                                                color: journalRefreshArea.containsMouse ? Color.popups.background : "transparent"
                                                border.color: Color.muted; border.width: 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "\u21BB"
                                                    font.pixelSize: Style.font.body
                                                    color: Color.foreground
                                                }
                                                MouseArea {
                                                    id: journalRefreshArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: root.panelSelectedUnit !== ""
                                                    onClicked: root.loadDetailTab("journal")
                                                }
                                            }
                                            Text {
                                                text: "Journal \u2014 " + (root.panelSelectedUnit || "(none)")
                                                font.pixelSize: Style.font.bodySmall
                                                color: Color.muted
                                            }
                                            Item { Layout.fillWidth: true }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: Color.muted
                                        }

                                        ListView {
                                            id: journalList
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            model: _journalLines()

                                            delegate: Text {
                                                id: journalLine
                                                required property var model
                                                required property int index
                                                width: journalList.width
                                                text: journalLine.model
                                                font.pixelSize: Style.font.bodySmall
                                                font.family: "monospace"
                                                color: Color.foreground
                                                wrapMode: Text.Wrap
                                            }

                                            ScrollBar.vertical: ScrollBar {
                                                policy: ScrollBar.AsNeeded
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── UNLOADED UNITS SECTION ────────────────────────
                    Column {
                        width: parent.width
                        visible: root.panelFilteredUnloaded.length > 0

                        // Header bar
                        Rectangle {
                            width: parent.width
                            height: 32
                            radius: 4
                            color: Color.popups.background

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 6

                                Text {
                                    text: "Unloaded units"
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                    color: Color.foreground
                                }
                                Text {
                                    text: "(" + root.panelFilteredUnloaded.length + ")"
                                    font.pixelSize: Style.font.bodySmall
                                    color: Color.muted
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.showUnloaded ? "\u25BE" : "\u25B8"
                                    font.pixelSize: Style.font.body
                                    color: Color.foreground
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.showUnloaded = !root.showUnloaded
                            }
                        }

                        // Unloaded unit list
                        Rectangle {
                            width: parent.width
                            height: root.showUnloaded ? 180 : 0
                            color: Color.background
                            radius: Style.cornerRadius
                            clip: true
                            visible: root.showUnloaded

                            ListView {
                                id: unloadedList
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                model: root.panelFilteredUnloaded

                                delegate: Rectangle {
                                    id: unloadedDelegate
                                    required property var model
                                    required property int index
                                    width: unloadedList.width
                                    height: 40
                                    radius: 4
                                    color: unloadedDelegateArea.containsMouse
                                           ? Qt.rgba(1, 1, 1, 0.05)
                                           : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 6

                                        // Type icon
                                        Text {
                                            text: _typeIcon(unloadedDelegate.model.type)
                                            font.pixelSize: Style.font.bodySmall
                                            color: Color.muted
                                            Layout.preferredWidth: 18
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        // Name
                                        Text {
                                            text: unloadedDelegate.model.name
                                            font.pixelSize: Style.font.bodySmall
                                            color: Color.foreground
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // File-state badge
                                        Rectangle {
                                            width: fsBadge.implicitWidth + 8
                                            height: 16
                                            radius: 3
                                            color: {
                                                var key = Model.fileStateColorKey(unloadedDelegate.model.fileState);
                                                if (key === "success") return _successColor;
                                                if (key === "error") return Color.urgent;
                                                if (key === "warn") return _warnColor;
                                                return Color.muted;
                                            }
                                            Text {
                                                id: fsBadge
                                                anchors.centerIn: parent
                                                text: Model.fileStateBadge(unloadedDelegate.model.fileState)
                                                font.pixelSize: 8
                                                font.bold: true
                                                color: "#ffffff"
                                            }
                                        }

                                        // Inline action buttons
                                        Row {
                                            spacing: 2
                                            visible: unloadedDelegateArea.containsMouse

                                            Repeater {
                                                model: _unloadedActions(unloadedDelegate.model.fileState)
                                                Rectangle {
                                                    width: actionText.implicitWidth + 8
                                                    height: 20
                                                    radius: 3
                                                    color: actionArea.containsMouse ? Color.accent : Color.popups.background
                                                    border.color: Color.muted
                                                    border.width: 1
                                                    Text {
                                                        id: actionText
                                                        anchors.centerIn: parent
                                                        text: modelData.label
                                                        font.pixelSize: 8
                                                        color: Color.foreground
                                                    }
                                                    MouseArea {
                                                        id: actionArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: root.mutate(modelData.action, unloadedDelegate.model.name)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: unloadedDelegateArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectUnit(unloadedDelegate.model.name)
                                    }
                                }

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                }
                            }
                        }
                    }

                    // ── Error banner ─────────────────────────────────
                    Text {
                        visible: root.panelLastError !== ""
                        width: parent.width
                        text: root.panelLastError
                        color: Color.urgent
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  HELPER FUNCTIONS
    // ──────────────────────────────────────────────────────────────────

    function _typeIcon(type) {
        switch (type) {
            case "service":   return "\u2699";
            case "timer":     return "\u23F1";
            case "socket":    return "\uD83D\uDD0C";
            case "mount":     return "\uD83D\uDCC1";
            case "automount": return "\uD83D\uDCC2";
            case "path":      return "\uD83D\uDD17";
            case "swap":      return "\uD83D\uDCBE";
            case "target":    return "\uD83C\uDFAF";
            default:          return "\u2022";
        }
    }

    function _statusFields() {
        var d = root.panelDetail;
        if (!d || !d.unit) return [];
        var fields = [
            { key: "Unit",          value: d.unit },
            { key: "Description",   value: d.Description },
            { key: "Load State",    value: d.LoadState },
            { key: "Active State",  value: d.ActiveState },
            { key: "Sub State",     value: d.SubState },
            { key: "Main PID",      value: d.MainPID },
            { key: "Fragment",      value: d.FragmentPath },
            { key: "File State",    value: d.UnitFileState },
            { key: "File Preset",   value: d.UnitFilePreset },
            { key: "Active Since",  value: d.ActiveEnterTimestamp }
        ];
        return fields;
    }

    function _fileSections() {
        var d = root.panelDetail;
        if (!d || !d.files) return [];
        if (d.files.length > 0) return d.files;
        if (d.raw) return [{ path: root.panelSelectedUnit, content: d.raw }];
        return [];
    }

    function _journalLines() {
        var d = root.panelDetail;
        if (!d || !d.journal || !d.journal.lines) return [];
        var out = [];
        var lines = d.journal.lines;
        for (var i = 0; i < lines.length; i++) {
            out.push(Model.truncateJournalLine(lines[i], 2000));
        }
        return out;
    }

    function _actionEnabled(action, needsActive) {
        if (needsActive) {
            var st = root.panelDetail;
            return st && st.ActiveState === "active";
        }
        if (root.panelScope === "system" && !root.panelCanElevate) {
            return false;
        }
        return true;
    }

    function _unloadedActions(fileState) {
        var s = (fileState || "").toLowerCase();
        if (s === "static" || s === "disabled" || s === "generated" || s === "indirect") {
            return [
                { label: "Start",  action: "start" },
                { label: "Enable", action: "enable" },
                { label: "Mask",   action: "mask" }
            ];
        }
        if (s === "enabled") {
            return [
                { label: "Start",   action: "start" },
                { label: "Disable", action: "disable" },
                { label: "Mask",    action: "mask" }
            ];
        }
        if (s === "masked") {
            return [
                { label: "Unmask", action: "unmask" }
            ];
        }
        return [];
    }
}
