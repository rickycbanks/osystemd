import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

Singleton {
    id: root

    // ── Persisted settings ────────────────────────────────────────────
    property string scope: "user"
    property int refreshIntervalMs: 30000
    property int journalLines: 100
    property list<string> typeFilter: [
        "service", "timer", "socket", "mount",
        "automount", "path", "swap", "target"
    ]
    property list<string> stateFilter: ["active", "inactive", "failed"]
    property list<string> pinned: []

    // ── Persistence via FileView + JsonAdapter ─────────────────────────
    FileView {
        id: fileView
        path: Quickshell.stateDir
              + "/plugins/io.github.rickycbanks.osystemd/settings.json"
        watchChanges: true

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter

            // Map QML properties → JSON keys
            property string scope: root.scope
            property int refreshIntervalMs: root.refreshIntervalMs
            property int journalLines: root.journalLines
            property var typeFilter: root.typeFilter
            property var stateFilter: root.stateFilter
            property var pinned: root.pinned

            onScopeChanged: root.scope = scope
            onRefreshIntervalMsChanged: root.refreshIntervalMs = refreshIntervalMs
            onJournalLinesChanged: root.journalLines = journalLines
            onTypeFilterChanged: root.typeFilter = typeFilter
            onStateFilterChanged: root.stateFilter = stateFilter
            onPinnedChanged: root.pinned = pinned
        }
    }

    // ── Public methods ────────────────────────────────────────────────

    /// Toggle a unit name in the pinned list.
    function togglePin(unitName) {
        var idx = root.pinned.indexOf(unitName);
        var updated = root.pinned.slice();  // shallow copy
        if (idx >= 0) {
            updated.splice(idx, 1);
        } else {
            updated.push(unitName);
        }
        root.pinned = updated;
    }

    // ── Bootstrap ─────────────────────────────────────────────────────
    Component.onCompleted: {
        // Ensure the settings file exists so adapter defaults are written.
        fileView.reload();
    }
}
