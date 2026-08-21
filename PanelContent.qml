import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import "Model.js" as Model

/// Main management panel content: header filters + split unit list / detail.
ColumnLayout {
    id: root
    spacing: 0

    readonly property color _warnColor: "#e0a040"
    readonly property color _successColor: "#80c080"

    // ── State ──────────────────────────────────────────────────────────
    property int currentTab: 0  // 0=Status, 1=Actions, 2=UnitFile, 3=Journal

    // ───────────────────────────────────────────────────────────────────
    //  HEADER
    // ───────────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 56
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
                        color: Service.scope === modelData ? Color.accent : "transparent"
                        border.color: Service.scope === modelData ? Color.accent : Color.muted
                        border.width: 1
                        Text {
                            id: scopeLabelTxt
                            anchors.centerIn: parent
                            text: Model.scopeLabel(modelData)
                            font.pixelSize: Style.font.body
                            color: Service.scope === modelData ? "#ffffff" : Color.foreground
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Service.setScope(modelData)
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
                    text: Service.searchQuery
                    onTextChanged: Service.setSearch(text)
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
                    onClicked: Service.refresh()
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

    // ── Filter chips row ───────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Layout.margins: 4
        spacing: 4

        Text {
            text: "Type:"
            font.pixelSize: Style.font.bodySmall
            color: Color.muted
        }
        Repeater {
            model: Settings.typeFilter
            delegate: Rectangle {
                width: chipText.implicitWidth + 12
                height: 22
                radius: 4
                color: Service.typeFilter.indexOf(modelData) >= 0 ? Color.accent : "transparent"
                border.color: Service.typeFilter.indexOf(modelData) >= 0 ? Color.accent : Color.muted
                border.width: 1
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: Style.font.bodySmall
                    color: Service.typeFilter.indexOf(modelData) >= 0 ? "#ffffff" : Color.muted
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var arr = Service.typeFilter.slice();
                        var idx = arr.indexOf(modelData);
                        if (idx >= 0) arr.splice(idx, 1);
                        else arr.push(modelData);
                        Service.setTypeFilter(arr);
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
            model: Settings.stateFilter
            delegate: Rectangle {
                width: stateChipText.implicitWidth + 12
                height: 22
                radius: 4
                color: Service.stateFilter.indexOf(modelData) >= 0 ? Color.accent : "transparent"
                border.color: Service.stateFilter.indexOf(modelData) >= 0 ? Color.accent : Color.muted
                border.width: 1
                Text {
                    id: stateChipText
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: Style.font.bodySmall
                    color: Service.stateFilter.indexOf(modelData) >= 0 ? "#ffffff" : Color.muted
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var arr = Service.stateFilter.slice();
                        var idx = arr.indexOf(modelData);
                        if (idx >= 0) arr.splice(idx, 1);
                        else arr.push(modelData);
                        Service.setStateFilter(arr);
                    }
                }
            }
        }

        Item { Layout.fillWidth: true } // spacer

        // Busy indicator
        Text {
            visible: Service.busy
            text: "Loading..."
            font.pixelSize: Style.font.bodySmall
            color: Color.accent
        }

        // Summary
        Text {
            text: Model.failedSummary(Service.failedCount, Service.scope)
            font.pixelSize: Style.font.bodySmall
            color: Service.failedCount > 0 ? Color.urgent : Color.muted
        }
    }

    // ───────────────────────────────────────────────────────────────────
    //  BODY — split: left list | right detail
    // ───────────────────────────────────────────────────────────────────
    SplitView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        orientation: Qt.Horizontal

        // ── LEFT: Unit list ────────────────────────────────────────────
        Rectangle {
            SplitView.preferredWidth: 360
            color: Color.background
            radius: Style.cornerRadius

            ListView {
                id: unitList
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                model: Service.filteredUnits
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

                        // Type icon (Unicode by suffix)
                        Text {
                            text: _typeIcon(modelData.type)
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
                                text: modelData.name
                                font.pixelSize: Style.font.body
                                font.bold: unitList.currentIndex === unitDelegate.index
                                color: Color.foreground
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.description || ""
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
                                    Model.normalizeState(modelData.active, modelData.sub));
                                if (key === "success") return _successColor;
                                if (key === "error") return Color.urgent;
                                if (key === "warn") return _warnColor;
                                return Color.muted;
                            }
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: Model.stateBadge(modelData.active, modelData.sub)
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
                            Service.selectUnit(modelData.name);
                        }
                    }
                }

                // Scrollbar
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }
        }

        // ── RIGHT: Detail pane ─────────────────────────────────────────
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
                                onClicked: root.currentTab = index
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

                // ── Tab content ────────────────────────────────────────
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
                                visible: !Service.selectedUnit
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
                            visible: !Service.selectedUnit
                            text: "Select a unit from the list"
                            font.pixelSize: Style.font.body
                            color: Color.muted
                        }

                        Text {
                            visible: Service.selectedUnit !== ""
                            text: Service.selectedUnit
                            font.pixelSize: Style.font.body
                            font.bold: true
                            color: Color.foreground
                        }

                        // Warning for system scope without elevation
                        Text {
                            visible: Service.scope === "system" && !Service.canElevate
                            text: "pkexec not available \u2014 system mutations will fail"
                            font.pixelSize: Style.font.bodySmall
                            color: _warnColor
                        }

                        // Action buttons in a grid
                        GridLayout {
                            visible: Service.selectedUnit !== ""
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
                                        if (!btnEnabled) return Qt.rgba(1, 1, 1, 0.05);
                                        return btnMouseArea.containsMouse ? Color.accent : Color.popups.background;
                                    }
                                    border.color: Color.muted
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: model.label
                                        font.pixelSize: Style.font.body
                                        color: btnEnabled ? Color.foreground : Color.muted
                                    }
                                    MouseArea {
                                        id: btnMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: btnEnabled
                                        onClicked: Service.mutate(model.action, Service.selectedUnit)
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
                                visible: !Service.selectedUnit
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
                                visible: Service.selectedUnit !== "" && _fileSections().length === 0
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
                                    enabled: Service.selectedUnit !== ""
                                    onClicked: Service.loadDetailTab("journal")
                                }
                            }
                            Text {
                                text: "Journal \u2014 " + (Service.selectedUnit || "(none)")
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
                                required property var model
                                required property int index
                                width: journalList.width
                                text: modelData
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

    // ───────────────────────────────────────────────────────────────────
    //  Helper functions
    // ───────────────────────────────────────────────────────────────────

    /// Unicode icon for unit type
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

    /// Build key/value pairs for the status tab
    function _statusFields() {
        var d = Service.detail;
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

    /// Build file sections for the Unit File tab
    function _fileSections() {
        var d = Service.detail;
        if (!d || !d.files) return [];
        if (d.files.length > 0) return d.files;
        if (d.raw) return [{ path: Service.selectedUnit, content: d.raw }];
        return [];
    }

    /// Get journal lines, truncating each
    function _journalLines() {
        var d = Service.detail;
        if (!d || !d.journal || !d.journal.lines) return [];
        var out = [];
        var lines = d.journal.lines;
        for (var i = 0; i < lines.length; i++) {
            out.push(Model.truncateJournalLine(lines[i], 2000));
        }
        return out;
    }

    /// Determine if an action button should be enabled
    function _actionEnabled(action, needsActive) {
        if (needsActive) {
            var st = Service.detail;
            return st && st.ActiveState === "active";
        }
        // System mutations need elevation
        if (Service.scope === "system" && !Service.canElevate) {
            return false;
        }
        return true;
    }

    // ── Keyboard shortcuts ─────────────────────────────────────────────
    Shortcut { sequence: "Escape"; onActivated: Service.closePanel() }
    Shortcut { sequence: "Ctrl+R"; onActivated: Service.refresh() }
    Shortcut { sequence: "Ctrl+1"; onActivated: root.currentTab = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.currentTab = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.currentTab = 2 }
    Shortcut { sequence: "Ctrl+4"; onActivated: root.currentTab = 3 }
}
