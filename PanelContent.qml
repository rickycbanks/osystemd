import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Store.js" as Store

Item {
  id: root

  property var bar: null
  property string shellPath: ""
  property bool showSubState: true
  property string defaultScope: "user"
  property int journalLines: 120
  signal actionRequested(string action, string unitName, string scope)
  signal refreshRequested()

  width: parent ? parent.width : 500

  // ── Internal state ───────────────────────────────────────────
  property string searchText: ""
  property string scope: root.defaultScope
  property var typeFilters: []      // e.g. ["service", "timer"]
  property var stateFilters: []     // e.g. ["active", "failed"]
  property var favorites: []
  property string expandedName: ""
  property string expandedScope: ""
  property var units: []
  property var displayUnits: []
  property string lastError: Store.get().lastError
  property int _lastUserRevision: 0
  property int _lastSystemRevision: 0
  property bool _loading: false

  property bool userAvailable: false
  property bool systemAvailable: false
  property int userRevision: 0
  property int systemRevision: 0

  // ── Poll Store revisions for bar icon updates ────────────────
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      var s = Store.get();
      if (s.userRevision !== root._lastUserRevision) {
        root._lastUserRevision = s.userRevision;
      }
      if (s.systemRevision !== root._lastSystemRevision) {
        root._lastSystemRevision = s.systemRevision;
      }
      root.lastError = s.lastError;
      root.favorites = s.favorites || [];
      root.userAvailable = s.userAvailable || false;
      root.systemAvailable = s.systemAvailable || false;
      root.userRevision = s.userRevision || 0;
      root.systemRevision = s.systemRevision || 0;
    }
  }

  // ── Auto-refresh while panel is open ─────────────────────────
  Timer {
    interval: 4000
    repeat: true
    running: true
    onTriggered: {
      root.refreshFromService();
    }
  }

  Component.onCompleted: {
    root.favorites = Store.get().favorites || [];
    root.refreshFromService();
  }

  // ── Fetch units via IPC ──────────────────────────────────────
  function refreshFromService() {
    if (root._loading) return;
    root._loading = true;
    fetchProc.command = ["qs", "ipc", "-p", root.shellPath, "call", "osystemd", "listUnits", root.scope];
    fetchProc.running = true;
  }

  Process {
    id: fetchProc
    running: false
    property string _output: ""

    onRunningChanged: {
      if (!running) {
        root._loading = false;
        if (exitCode === 0 && _output.trim()) {
          try {
            var parsed = JSON.parse(_output.trim());
            if (Array.isArray(parsed)) {
              root.units = parsed;
              // Tag scope
              for (var i = 0; i < parsed.length; i++) {
                parsed[i].scope = root.scope;
              }
              root._applyFilters();
            }
          } catch (e) {
            // JSON parse error, ignore
          }
        }
        _output = "";
      }
    }

    stdout: SplitParser {
      onRead: function(line) {
        fetchProc._output += line + "\n";
      }
    }
    stderr: SplitParser {
      onRead: function(line) {}
    }
  }

  function _applyFilters() {
    var filters = {
      search: root.searchText,
      types: root.typeFilters,
      states: root.stateFilters,
      favorites: root.favorites,
      scope: root.scope
    };
    root.displayUnits = Model.filterUnits(root.units, filters, function(u) {
      return u.name + ":" + (u.scope || root.scope);
    });
  }

  // ── Layout ───────────────────────────────────────────────────
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    width: parent.width
    spacing: Style.spacing.md

    // ── Error banner ───────────────────────────────────────────
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.lastError ? errorText.implicitHeight + Style.spacing.md * 2 : 0
      visible: root.lastError !== ""
      color: Util.alpha(Color.urgent, 0.15)
      radius: Style.cornerRadius

      Row {
        anchors.fill: parent
        anchors.margins: Style.spacing.md
        spacing: Style.spacing.sm

        Text {
          text: "\uf071"  // warning icon
          font.family: "Symbols Nerd Font"
          font.pixelSize: Style.font.body
          color: Color.urgent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: errorText
          text: root.lastError
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          color: Color.urgent
          wrapMode: Text.Wrap
          width: parent.width - Style.spacing.md - 30
        }
      }
    }

    // ── Scope selector ─────────────────────────────────────────
    Row {
      spacing: Style.spacing.xs
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: ["user", "system", "all"]

        Toggle {
          property string scopeValue: modelData
          text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
          checked: root.scope === scopeValue
          enabled: scopeValue === "all" || (scopeValue === "user" && root.userAvailable)
                   || (scopeValue === "system" && root.systemAvailable)
          opacity: enabled ? 1.0 : 0.4
          onClicked: {
            root.scope = scopeValue;
            root.refreshFromService();
          }
        }
      }
    }

    // ── Search field ───────────────────────────────────────────
    TextField {
      id: searchField
      anchors.left: parent.left
      anchors.right: parent.right
      placeholderText: "Search units…"
      onTextChanged: {
        root.searchText = text;
        root._applyFilters();
      }
    }

    // ── Type filter chips ──────────────────────────────────────
    Row {
      spacing: Style.spacing.xs

      Repeater {
        model: ["service", "timer", "socket", "path"]

        Toggle {
          property string typeValue: modelData
          text: modelData
          checked: root.typeFilters.indexOf(typeValue) >= 0
          onClicked: {
            var idx = root.typeFilters.indexOf(typeValue);
            var arr = root.typeFilters.slice();
            if (idx >= 0) arr.splice(idx, 1);
            else arr.push(typeValue);
            root.typeFilters = arr;
            root._applyFilters();
          }
        }
      }
    }

    // ── State filter chips ─────────────────────────────────────
    Row {
      spacing: Style.spacing.xs

      Repeater {
        model: ["active", "failed", "inactive"]

        Toggle {
          property string stateValue: modelData
          text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
          checked: root.stateFilters.indexOf(stateValue) >= 0
          onClicked: {
            var idx = root.stateFilters.indexOf(stateValue);
            var arr = root.stateFilters.slice();
            if (idx >= 0) arr.splice(idx, 1);
            else arr.push(stateValue);
            root.stateFilters = arr;
            root._applyFilters();
          }
        }
      }
    }

    // ── Loading indicator ──────────────────────────────────────
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root._loading
      text: "Loading…"
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      color: Color.muted
    }

    // ── Unit list ──────────────────────────────────────────────
    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.spacing.xxs

      Repeater {
        model: root.displayUnits

        UnitRow {
          anchors.left: parent.left
          anchors.right: parent.right
          bar: root.bar
          unitData: modelData
          showSubState: root.showSubState
          isExpanded: root.expandedName === modelData.name && root.expandedScope === (modelData.scope || root.scope)
          isFavorite: (modelData.__isFavorite === true)
          onToggleExpand: {
            if (root.expandedName === modelData.name && root.expandedScope === (modelData.scope || root.scope)) {
              root.expandedName = "";
              root.expandedScope = "";
            } else {
              root.expandedName = modelData.name;
              root.expandedScope = modelData.scope || root.scope;
            }
          }
          onActionRequested: function(action, unitName, scope) {
            root.actionRequested(action, unitName, scope);
          }
          onToggleFavoriteRequested: function(unitName, scope) {
            Quickshell.execDetached(["qs", "ipc", "-p", root.shellPath, "call", "osystemd", "toggleFavorite", unitName, scope]);
          }

          // ── Expanded detail ──────────────────────────────────
          UnitDetail {
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.expandedName === modelData.name && root.expandedScope === (modelData.scope || root.scope)
            bar: root.bar
            shellPath: root.shellPath
            unitName: modelData.name
            unitScope: modelData.scope || root.scope
            journalLines: root.journalLines
            onActionRequested: function(action, unitName, scope) {
              root.actionRequested(action, unitName, scope);
            }
          }
        }
      }

      // Empty state
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.displayUnits.length === 0 && !root._loading
        text: "No units match filters"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        color: Color.muted
        topPadding: Style.spacing.xl
        bottomPadding: Style.spacing.xl
      }
    }

    // ── Footer ─────────────────────────────────────────────────
    PanelSeparator {
      anchors.left: parent.left
      anchors.right: parent.right
    }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.spacing.sm

      Text {
        text: root.displayUnits.length + " units"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        color: Color.muted
        anchors.verticalCenter: parent.verticalCenter
      }

      Item { width: 1; height: 1 } // spacer

      Text {
        text: "\uf021"  // refresh icon
        font.family: "Symbols Nerd Font"
        font.pixelSize: Style.font.body
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter

        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: root.refreshFromService()
        }
      }

      Text {
        text: "auto " + (Number(root.userRevision) > 0 ? "on" : "off")
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        color: Color.muted
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Inline components
  // ══════════════════════════════════════════════════════════════

  // ── UnitRow ──────────────────────────────────────────────────
  component UnitRow: CursorSurface {
    id: row

    property var bar: null
    property var unitData: ({})
    property bool showSubState: true
    property bool isExpanded: false
    property bool isFavorite: false
    signal toggleExpand()
    signal actionRequested(string action, string unitName, string scope)
    signal toggleFavoriteRequested(string unitName, string scope)

    implicitHeight: rowContent.implicitHeight + Style.spacing.sm * 2

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.spacing.xxs
      radius: Style.cornerRadius
      color: row.pressed ? Util.alpha(Color.accent, 0.15)
           : row.hovered ? Util.alpha(Color.accent, 0.08)
           : "transparent"
      border.width: row.isExpanded ? 1 : 0
      border.color: Util.alpha(Color.accent, 0.3)

      Row {
        id: rowContent
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        spacing: Style.spacing.sm

        // Status dot
        Rectangle {
          width: 8
          height: 8
          radius: 4
          anchors.verticalCenter: parent.verticalCenter
          color: row.unitData.isFailed ? Color.urgent
               : row.unitData.isActive ? Color.accent
               : Color.muted
        }

        // Name + caption
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 120

          Text {
            text: row.unitData.name || ""
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: row.unitData.isActive
            color: row.unitData.isFailed ? Color.urgent : Color.foreground
            elide: Text.ElideMiddle
            width: parent.width
          }

          Text {
            visible: row.showSubState && (row.unitData.subState || row.unitData.description)
            text: {
              var parts = [];
              if (row.unitData.subState) parts.push(row.unitData.subState);
              if (row.unitData.unitFileState) parts.push(row.unitData.unitFileState);
              if (row.unitData.scope) parts.push(row.unitData.scope);
              return parts.join(" · ");
            }
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            color: Color.muted
            elide: Text.ElideRight
            width: parent.width
          }
        }

        // Favorite star
        Text {
          text: row.isFavorite ? "\uf005" : "\uf006"  // star filled / empty
          font.family: "Symbols Nerd Font"
          font.pixelSize: Style.font.body
          color: row.isFavorite ? Color.accent : Color.muted
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggleFavoriteRequested(row.unitData.name, row.unitData.scope || "user")
          }
        }

        // Quick actions (visible on hover)
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs
          visible: row.hovered && !row.isExpanded

          Text {
            text: "\uf04b"  // play (start)
            font.family: "Symbols Nerd Font"
            font.pixelSize: Style.font.bodySmall
            color: Color.accent
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: row.actionRequested("startUnit", row.unitData.name, row.unitData.scope || "user")
            }
          }

          Text {
            text: "\uf04d"  // stop
            font.family: "Symbols Nerd Font"
            font.pixelSize: Style.font.bodySmall
            color: Color.urgent
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: row.actionRequested("stopUnit", row.unitData.name, row.unitData.scope || "user")
            }
          }

          Text {
            text: "\uf021"  // restart
            font.family: "Symbols Nerd Font"
            font.pixelSize: Style.font.bodySmall
            color: Color.accent
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: row.actionRequested("restartUnit", row.unitData.name, row.unitData.scope || "user")
            }
          }
        }

        // Expand arrow
        Text {
          text: row.isExpanded ? "\uf106" : "\uf107"  // chevron up/down
          font.family: "Symbols Nerd Font"
          font.pixelSize: Style.font.body
          color: Color.muted
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: row.toggleExpand()
      }
    }
  }

  // ── UnitDetail ───────────────────────────────────────────────
  component UnitDetail: Item {
    id: detail

    property var bar: null
    property string shellPath: ""
    property string unitName: ""
    property string unitScope: "user"
    property int journalLines: 120
    signal actionRequested(string action, string unitName, string scope)

    implicitHeight: detailColumn.implicitHeight + Style.spacing.md * 2
    height: visible ? implicitHeight : 0

    onVisibleChanged: {
      if (visible) {
        loadProperties();
        loadJournal();
        loadUnitFile();
      }
    }

    // Properties state
    property var unitProps: ({})
    property bool propsLoaded: false

    // Journal state
    property string journalText: ""
    property bool journalLoaded: false

    // Unit file state
    property string unitFileText: ""
    property bool unitFileLoaded: false

    function loadProperties() {
      if (propsLoaded) return;
      var argv = ["systemctl"];
      if (detail.unitScope === "user") argv.push("--user");
      argv.push("show", detail.unitName);
      argv.push("--property=Id,Description,LoadState,ActiveState,SubState,UnitFileState,FragmentPath,ActiveEnterTimestamp,CanStart,CanStop,CanReload");
      detailPropsProc.command = argv;
      detailPropsProc.running = true;
    }

    function loadJournal() {
      if (journalLoaded) return;
      var argv = ["journalctl"];
      if (detail.unitScope === "user") argv.push("--user");
      argv.push("-u", detail.unitName);
      argv.push("-n", String(detail.journalLines));
      argv.push("--no-pager", "-o", "short", "--output-fields=MESSAGE");
      detailJournalProc.command = argv;
      detailJournalProc.running = true;
    }

    function loadUnitFile() {
      if (unitFileLoaded) return;
      var argv = ["systemctl"];
      if (detail.unitScope === "user") argv.push("--user");
      argv.push("cat", detail.unitName);
      detailFileProc.command = argv;
      detailFileProc.running = true;
    }

    // ── Direct command fetchers for detail ──────────────────────
    Process {
      id: detailPropsProc
      running: false
      property string _output: ""
      stdout: SplitParser { onRead: function(line) { detailPropsProc._output += line + "\n"; } }
      stderr: SplitParser { onRead: function(line) {} }
      onRunningChanged: {
        if (!running) {
          if (exitCode === 0 && _output.trim()) {
            detail.unitProps = Model.parseShowOutput(_output);
            detail.propsLoaded = true;
          }
          _output = "";
        }
      }
    }

    Process {
      id: detailJournalProc
      running: false
      property string _output: ""
      stdout: SplitParser { onRead: function(line) { detailJournalProc._output += line + "\n"; } }
      stderr: SplitParser { onRead: function(line) {} }
      onRunningChanged: {
        if (!running) {
          if (_output.trim()) {
            detail.journalText = _output.trim();
          }
          detail.journalLoaded = true;
          _output = "";
        }
      }
    }

    Process {
      id: detailFileProc
      running: false
      property string _output: ""
      stdout: SplitParser { onRead: function(line) { detailFileProc._output += line + "\n"; } }
      stderr: SplitParser { onRead: function(line) {} }
      onRunningChanged: {
        if (!running) {
          if (_output.trim()) {
            detail.unitFileText = _output.trim();
          }
          detail.unitFileLoaded = true;
          _output = "";
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.spacing.xxs
      color: Util.alpha(Color.foreground, 0.03)
      radius: Style.cornerRadius

      Column {
        id: detailColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.spacing.md
        spacing: Style.spacing.md

        // ── STATUS section ─────────────────────────────────────
        PanelSectionHeader {
          text: "STATUS"
          width: parent.width
        }

        Column {
          width: parent.width
          spacing: Style.spacing.xxs

          // Description
          Text {
            text: detail.unitProps.Description || "—"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            color: Color.foreground
            width: parent.width
            wrapMode: Text.Wrap
          }

          // Key-value grid
          Grid {
            columns: 2
            columnSpacing: Style.spacing.lg
            rowSpacing: Style.spacing.xxs

            Repeater {
              model: [
                ["Load", detail.unitProps.LoadState],
                ["Active", detail.unitProps.ActiveState],
                ["Sub", detail.unitProps.SubState],
                ["File state", detail.unitProps.UnitFileState],
                ["Since", detail.unitProps.ActiveEnterTimestamp],
                ["Fragment", detail.unitProps.FragmentPath]
              ]

              Row {
                spacing: Style.spacing.sm
                visible: modelData[1] && modelData[1] !== ""

                Text {
                  text: modelData[0] + ":"
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                  width: 80
                }

                Text {
                  text: modelData[1]
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Color.foreground
                  elide: Text.ElideMiddle
                  width: detail.width - 100
                }
              }
            }
          }
        }

        // ── ACTIONS section ────────────────────────────────────
        PanelSectionHeader {
          text: "ACTIONS"
          width: parent.width
        }

        Grid {
          columns: 5
          columnSpacing: Style.spacing.sm
          rowSpacing: Style.spacing.sm

          PanelActionButton {
            text: "Start"
            onClicked: detail.actionRequested("startUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Stop"
            onClicked: detail.actionRequested("stopUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Restart"
            onClicked: detail.actionRequested("restartUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Reload"
            visible: detail.unitProps.CanReload !== "no"
            onClicked: detail.actionRequested("reloadUnit", detail.unitName, detail.unitScope)
          }

          Item { width: 1; height: 1 } // spacer

          PanelActionButton {
            text: "Enable"
            onClicked: detail.actionRequested("enableUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Disable"
            onClicked: detail.actionRequested("disableUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Reenable"
            onClicked: detail.actionRequested("reenableUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Mask"
            onClicked: detail.actionRequested("maskUnit", detail.unitName, detail.unitScope)
          }

          PanelActionButton {
            text: "Unmask"
            onClicked: detail.actionRequested("unmaskUnit", detail.unitName, detail.unitScope)
          }
        }

        // ── JOURNAL section ────────────────────────────────────
        PanelSectionHeader {
          text: "JOURNAL"
          width: parent.width
        }

        JournalView {
          width: parent.width
          bar: root.bar
          journalText: detail.journalText
          loaded: detail.journalLoaded
          onLoadMore: {
            detail.journalLoaded = false;
            detail.journalText = "";
            detail.loadJournal();
          }
        }

        // ── FILE section ───────────────────────────────────────
        PanelSectionHeader {
          text: "UNIT FILE"
          width: parent.width
        }

        UnitFileView {
          width: parent.width
          bar: root.bar
          fileText: detail.unitFileText
          loaded: detail.unitFileLoaded
          onLoadMore: {
            detail.unitFileLoaded = false;
            detail.unitFileText = "";
            detail.loadUnitFile();
          }
        }
      }
    }
  }

  // ── JournalView ──────────────────────────────────────────────
  component JournalView: Item {
    id: journalView

    property var bar: null
    property string journalText: ""
    property bool loaded: false
    signal loadMore()

    implicitHeight: Math.min(200, Math.max(60, journalText ? journalContent.implicitHeight + Style.spacing.md * 2 : 40))

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.foreground, 0.03)
      radius: Style.cornerRadius

      // Loading state
      Text {
        anchors.centerIn: parent
        visible: !journalView.loaded
        text: "Loading journal…"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        color: Color.muted
      }

      // Empty state
      Text {
        anchors.centerIn: parent
        visible: journalView.loaded && !journalView.journalText
        text: "No journal entries"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        color: Color.muted
      }

      // Journal content
      ScrollView {
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        clip: true
        visible: journalView.loaded && journalView.journalText
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        TextEdit {
          id: journalContent
          width: parent.width
          text: journalView.journalText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          color: Color.foreground
          background: Rectangle { color: "transparent" }
        }
      }

      // Reload button
      Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.xs
        text: "\uf021"
        font.family: "Symbols Nerd Font"
        font.pixelSize: Style.font.bodySmall
        color: Color.accent
        visible: journalView.loaded

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          onClicked: journalView.loadMore()
        }
      }
    }
  }

  // ── UnitFileView ─────────────────────────────────────────────
  component UnitFileView: Item {
    id: fileView

    property var bar: null
    property string fileText: ""
    property bool loaded: false
    signal loadMore()

    implicitHeight: Math.min(200, Math.max(60, fileText ? fileContent.implicitHeight + Style.spacing.md * 2 : 40))

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.foreground, 0.03)
      radius: Style.cornerRadius

      // Loading state
      Text {
        anchors.centerIn: parent
        visible: !fileView.loaded
        text: "Loading unit file…"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        color: Color.muted
      }

      // Empty state
      Text {
        anchors.centerIn: parent
        visible: fileView.loaded && !fileView.fileText
        text: "Unit file not available"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        color: Color.muted
      }

      // File content
      ScrollView {
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        clip: true
        visible: fileView.loaded && fileView.fileText
        ScrollBar.horizontal.policy: ScrollBar.AsNeeded

        TextEdit {
          id: fileContent
          width: parent.width
          text: fileView.fileText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.NoWrap
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          color: Color.foreground
          background: Rectangle { color: "transparent" }
        }
      }

      // Reload button
      Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.xs
        text: "\uf021"
        font.family: "Symbols Nerd Font"
        font.pixelSize: Style.font.bodySmall
        color: Color.accent
        visible: fileView.loaded

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          onClicked: fileView.loadMore()
        }
      }
    }
  }
}
