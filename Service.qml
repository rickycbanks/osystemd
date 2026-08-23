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
        detail = {};
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
        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                root.busy = false;
                try {
                    var envelope = JSON.parse(listCollector.text);
                    if (envelope.ok) {
                        root.units = envelope.data.units || [];
                        root.unloadedUnits = envelope.data.unloaded || [];
                        root.lastUpdated = new Date();
                    } else {
                        root.lastError = envelope.error ? envelope.error.message : "list failed";
                    }
                } catch (e) {
                    root.lastError = "Failed to parse list response";
                }
            }
        }
    }

    // ── Process: detail (status / show / cat) ──────────────────────────
    Process {
        id: detailProc
        running: false
        stdout: StdioCollector {
            id: detailCollector
            onStreamFinished: {
                root.busy = false;
                try {
                    var envelope = JSON.parse(detailCollector.text);
                    if (envelope.ok) {
                        root.detail = envelope.data || {};
                    } else {
                        root.lastError = envelope.error ? envelope.error.message : "detail failed";
                    }
                } catch (e) {
                    root.lastError = "Failed to parse detail response";
                }
            }
        }
    }

    // ── Process: journal ───────────────────────────────────────────────
    Process {
        id: journalProc
        running: false
        stdout: StdioCollector {
            id: journalCollector
            onStreamFinished: {
                root.busy = false;
                try {
                    var envelope = JSON.parse(journalCollector.text);
                    if (envelope.ok) {
                        var d = envelope.data || {};
                        root.detail = Object.assign({}, root.detail, {
                            journal: { lines: d.lines || [] }
                        });
                    } else {
                        root.lastError = envelope.error ? envelope.error.message : "journal failed";
                    }
                } catch (e) {
                    root.lastError = "Failed to parse journal response";
                }
            }
        }
    }

    // ── Process: mutate (start/stop/enable/etc.) ───────────────────────
    Process {
        id: mutateProc
        running: false
        stdout: StdioCollector {
            id: mutateCollector
            onStreamFinished: {
                root.busy = false;
                try {
                    var envelope = JSON.parse(mutateCollector.text);
                    if (envelope.ok) {
                        root.refresh();
                    } else {
                        root.lastError = envelope.error ? envelope.error.message : "mutate failed";
                    }
                } catch (e) {
                    root.lastError = "Failed to parse mutate response";
                }
            }
        }
    }

    // ── Process: diagnose ──────────────────────────────────────────────
    Process {
        id: diagnoseProc
        running: false
        stdout: StdioCollector {
            id: diagnoseCollector
            onStreamFinished: {
                try {
                    var envelope = JSON.parse(diagnoseCollector.text);
                    if (envelope.ok) {
                        root.canElevate = envelope.data.canElevate === true;
                    }
                } catch (e) {
                    // silently ignore — canElevate stays false
                }
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
