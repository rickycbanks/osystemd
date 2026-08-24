import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
    id: root

    // ── Property defaults (formerly in Settings.qml) ─────────────────
    property string scope: "user"
    property int refreshIntervalMs: 30000
    property int journalLines: 100
    property var typeFilter: ["service", "timer", "socket", "mount", "automount", "path", "swap", "target"]
    property var stateFilter: ["active", "inactive", "failed"]
    property var pinned: []

    // ── Model state ───────────────────────────────────────────────────
    property var units: []
    property var unloadedUnits: []
    property string searchQuery: ""
    property string selectedUnit: ""
    property var detail: ({})
    property int failedCount: 0
    property bool busy: false
    property string lastError: ""
    property bool canElevate: false
    property var lastUpdated: null
    property string helperPath: ""

    // ── Helper-to-QML protocol budget (must match units.py JSON_LIMIT) ──
    readonly property int _jsonCap: 524288       // 512 KiB
    readonly property int _errorCap: 4096        // retained error text cap

    // ── Set lastError with truncation cap ──────────────────────────────
    function _setError(msg) {
        if (!msg) { lastError = ""; return; }
        lastError = msg.length > _errorCap ? msg.substring(0, _errorCap) : msg;
    }

    // ── Toggle a unit name in the pinned list ────────────────────────
    function togglePin(unitName) {
        var idx = root.pinned.indexOf(unitName);
        var updated = root.pinned.slice();
        if (idx >= 0) {
            updated.splice(idx, 1);
        } else {
            updated.push(unitName);
        }
        root.pinned = updated;
    }

    // ── Derived: filtered + sorted unit list ───────────────────────────
    property var filteredUnits: {
        var list = [];
        for (var i = 0; i < units.length; i++) {
            var u = units[i];

            // Type filter
            if (typeFilter.indexOf(u.type) < 0) continue;

            // State filter
            if (stateFilter.indexOf(u.active) < 0) continue;

            // Search / name match
            if (searchQuery !== "" && Model.searchScore(searchQuery, u) === 0) continue;

            list.push(u);
        }

        // Pin pinned units to top, then alphabetical
        list.sort(function (a, b) {
            var pa = pinned.indexOf(a.name) >= 0 ? -1 : 0;
            var pb = pinned.indexOf(b.name) >= 0 ? -1 : 0;
            if (pa !== pb) return pa - pb;
            return a.name.localeCompare(b.name);
        });
        return list;
    }

    // ── Update failed count when units change ──────────────────────────
    // Note: unloaded units don't have a runtime state and are not counted here.
    onUnitsChanged: {
        var count = 0;
        for (var i = 0; i < units.length; i++) {
            if (units[i].active === "failed") count++;
        }
        failedCount = count;
    }

    // ── IPC: Refresh unit list ────────────────────────────────────────
    function refresh() {
        busy = true;
        lastError = "";
        var args = ["list", "--scope", scope];
        if (typeFilter.length > 0) {
            args.push("--types");
            args.push(typeFilter.join(","));
        }
        if (stateFilter.length > 0) {
            args.push("--states");
            args.push(stateFilter.join(","));
        }
        if (searchQuery !== "") {
            args.push("--filter");
            args.push(searchQuery);
        }
        listProc.command = ["python3", helperPath].concat(args);
        listProc.running = true;
    }

    // ── IPC: Select a unit and load its status ─────────────────────────
    function selectUnit(name) {
        selectedUnit = name;
        detail = {};          // clear previous unit's detail (incl. journal/files)
        loadDetailTab("status");
    }

    // ── IPC: Load a detail tab ────────────────────────────────────────
    function loadDetailTab(tab) {
        if (!selectedUnit) return;
        busy = true;
        lastError = "";

        var args = [tab, selectedUnit, "--scope", scope];
        if (tab === "journal") {
            args.push("--lines");
            args.push(String(journalLines));
        }
        var procs = {
            "status": detailProc,
            "show":   detailProc,
            "cat":    detailProc,
            "journal": journalProc
        };
        var proc = procs[tab] || detailProc;
        detailProc.pendingTab = tab;  // track which subcommand is in flight
        proc.command = ["python3", helperPath].concat(args);
        proc.running = true;
    }

    // ── IPC: Scope toggle ──────────────────────────────────────────────
    function setScope(s) {
        scope = s;
        refresh();
    }

    // ── IPC: Client-side filters (no round-trip) ──────────────────────
    function setSearch(q)     { searchQuery = q; }
    function setTypeFilter(t) { typeFilter = t; }
    function setStateFilter(s) { stateFilter = s; }

    // ── IPC: Mutation actions ──────────────────────────────────────────
    function mutate(action, unit) {
        busy = true;
        lastError = "";
        var args = [action, unit, "--scope", scope];
        mutateProc.command = ["python3", helperPath].concat(args);
        mutateProc.running = true;
    }

    // ── IPC: Reload systemd daemon ─────────────────────────────────────
    function reloadDaemon() {
        busy = true;
        lastError = "";
        var args = ["daemon-reload", "--scope", scope];
        mutateProc.command = ["python3", helperPath].concat(args);
        mutateProc.running = true;
    }

    // ── Process: list ──────────────────────────────────────────────────
    Process {
        id: listProc
        running: false
        property string _buf: ""
        property bool _overflow: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (listProc._overflow) return;
                listProc._buf += data;
                if (listProc._buf.length > root._jsonCap) {
                    listProc._overflow = true;
                    listProc._buf = "";
                    listProc.running = false;
                    root.busy = false;
                    root._setError("Helper response exceeded the protocol budget");
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                root.busy = false;
                if (!_overflow && _buf.length > 0) {
                    try {
                        var envelope = JSON.parse(_buf);
                        if (envelope.ok) {
                            root.units = envelope.data.units || [];
                            root.unloadedUnits = envelope.data.unloaded || [];
                            root.lastUpdated = new Date();
                        } else {
                            root._setError(envelope.error ? envelope.error.message : "list failed");
                        }
                    } catch (e) {
                        root._setError("Failed to parse list response");
                    }
                }
                _buf = "";
                _overflow = false;
            }
        }
    }

    // ── Process: detail (status / show / cat) ──────────────────────────
    Process {
        id: detailProc
        running: false
        property string pendingTab: ""
        property string _buf: ""
        property bool _overflow: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (detailProc._overflow) return;
                detailProc._buf += data;
                if (detailProc._buf.length > root._jsonCap) {
                    detailProc._overflow = true;
                    detailProc._buf = "";
                    detailProc.running = false;
                    root.busy = false;
                    root._setError("Helper response exceeded the protocol budget");
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                root.busy = false;
                if (!_overflow && _buf.length > 0) {
                    try {
                        var envelope = JSON.parse(_buf);
                        if (envelope.ok) {
                            var d = envelope.data || {};
                            // Merge rather than replace so the Actions tab still
                            // sees ActiveState (from a prior `status` call) after
                            // the user visits Unit File (`cat`) — and vice versa.
                            var merged = Object.assign({}, root.detail, d);
                            // A `cat` response carries `files`/`raw`; a `status`
                            // response carries scalar fields. Don't let stale
                            // `files` from a previous unit leak across selections.
                            if (detailProc.pendingTab === "status" || detailProc.pendingTab === "show") {
                                delete merged.files;
                                delete merged.raw;
                            }
                            root.detail = merged;
                        } else {
                            root._setError(envelope.error ? envelope.error.message : "detail failed");
                        }
                    } catch (e) {
                        root._setError("Failed to parse detail response");
                    }
                }
                _buf = "";
                _overflow = false;
            }
        }
    }

    // ── Process: journal ───────────────────────────────────────────────
    Process {
        id: journalProc
        running: false
        property string _buf: ""
        property bool _overflow: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (journalProc._overflow) return;
                journalProc._buf += data;
                if (journalProc._buf.length > root._jsonCap) {
                    journalProc._overflow = true;
                    journalProc._buf = "";
                    journalProc.running = false;
                    root.busy = false;
                    root._setError("Helper response exceeded the protocol budget");
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                root.busy = false;
                if (!_overflow && _buf.length > 0) {
                    try {
                        var envelope = JSON.parse(_buf);
                        if (envelope.ok) {
                            var d = envelope.data || {};
                            root.detail = Object.assign({}, root.detail, {
                                journal: { lines: d.lines || [] }
                            });
                        } else {
                            root._setError(envelope.error ? envelope.error.message : "journal failed");
                        }
                    } catch (e) {
                        root._setError("Failed to parse journal response");
                    }
                }
                _buf = "";
                _overflow = false;
            }
        }
    }

    // ── Process: mutate (start/stop/enable/etc.) ───────────────────────
    Process {
        id: mutateProc
        running: false
        property string _buf: ""
        property bool _overflow: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (mutateProc._overflow) return;
                mutateProc._buf += data;
                if (mutateProc._buf.length > root._jsonCap) {
                    mutateProc._overflow = true;
                    mutateProc._buf = "";
                    mutateProc.running = false;
                    root.busy = false;
                    root._setError("Helper response exceeded the protocol budget");
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                root.busy = false;
                if (!_overflow && _buf.length > 0) {
                    try {
                        var envelope = JSON.parse(_buf);
                        if (envelope.ok) {
                            root.refresh();
                        } else {
                            root._setError(envelope.error ? envelope.error.message : "mutate failed");
                        }
                    } catch (e) {
                        root._setError("Failed to parse mutate response");
                    }
                }
                _buf = "";
                _overflow = false;
            }
        }
    }

    // ── Process: diagnose ──────────────────────────────────────────────
    Process {
        id: diagnoseProc
        running: false
        property string _buf: ""
        property bool _overflow: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (diagnoseProc._overflow) return;
                diagnoseProc._buf += data;
                if (diagnoseProc._buf.length > root._jsonCap) {
                    diagnoseProc._overflow = true;
                    diagnoseProc._buf = "";
                    diagnoseProc.running = false;
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                if (!_overflow && _buf.length > 0) {
                    try {
                        var envelope = JSON.parse(_buf);
                        if (envelope.ok) {
                            root.canElevate = envelope.data.canElevate === true;
                        }
                    } catch (e) {
                        // silently ignore — canElevate stays false
                    }
                }
                _buf = "";
                _overflow = false;
            }
        }
    }

    // ── Polling timer ──────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: refreshIntervalMs
        repeat: true
        onTriggered: root.refresh()
    }

    // ── Bootstrap ──────────────────────────────────────────────────────
    Component.onCompleted: {
        var url = String(Qt.resolvedUrl("./units.py"))
        helperPath = decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)

        // Run diagnose once to populate canElevate
        diagnoseProc.command = ["python3", helperPath, "diagnose"];
        diagnoseProc.running = true;

        // Start periodic refresh
        pollTimer.start();
        root.refresh();
    }

    // ── IPC ────────────────────────────────────────────────────────────
    IpcHandler {
        target: "io.github.rickycbanks.osystemd"

        function status(): string {
            return JSON.stringify({
                failedCount: root.failedCount,
                scope: root.scope,
                lastError: root.lastError,
                busy: root.busy,
                canElevate: root.canElevate
            })
        }

        function refresh(): void { root.refresh() }
    }
}
