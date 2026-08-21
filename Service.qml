import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model
import "Store.js" as Store

Item {
  id: root

  property var shell: null

  // ── Signals ──────────────────────────────────────────────────
  signal unitsChanged(string scope)
  signal actionFinished(string scope, string unitName, string action, bool success, string message)
  signal propertiesLoaded(string unitName, string scope, var properties)
  signal journalLoaded(string unitName, string scope, string text)
  signal unitFileLoaded(string unitName, string scope, string text)

  // ── Internal state ───────────────────────────────────────────
  property var userUnits: []
  property var systemUnits: []
  property string lastError: ""
  property var preferences: ({
    showFailedCount: true,
    defaultScope: "user",
    defaultTypeFilter: "all",
    defaultStateFilter: "all",
    pollIntervalSec: 4,
    journalLines: 120,
    showSubState: true,
    favorites: []
  })

  readonly property string configPath: Qt.homedir + "/.config/omarchy/osystemd.json"

  // ── Preferences persistence ──────────────────────────────────
  FileView {
    id: prefsFile
    path: root.configPath
    printErrors: false

    onLoaded: {
      try {
        var data = JSON.parse(text());
        for (var k in data) {
          if (k === "favorites") {
            root.preferences.favorites = data[k];
          } else if (k in root.preferences) {
            root.preferences[k] = data[k];
          }
        }
      } catch (e) {
        // corrupt file, ignore
      }
    }
  }

  function savePreferences() {
    var json = JSON.stringify(root.preferences, null, 2);
    // Write via Process to avoid FileView read-write conflicts
    var dir = root.configPath.substring(0, root.configPath.lastIndexOf("/"));
    prefsWriteProc.command = ["sh", "-c", "mkdir -p \"" + dir + "\" && cat > \"" + root.configPath + "\""];
    prefsWriteProc.stdinData = json;
    prefsWriteProc.running = true;
  }

  Process {
    id: prefsWriteProc
    running: false
    stdout: SplitParser { onRead: {} }
    stderr: SplitParser { onRead: {} }
  }

  Component.onCompleted: {
    prefsFile.reload();
    Store.setFavorites(root.preferences.favorites);
    scheduleRefresh("user");
    scheduleRefresh("system");
  }

  Component.onDestruction: {
    pollTimer.stop();
    userPollTimer.stop();
    systemPollTimer.stop();
    actionWatchdog.stop();
    actionTimeoutTimer.stop();
  }

  // ── Polling ──────────────────────────────────────────────────
  property int _pollInterval: Math.max(2, Math.min(60, Number(root.preferences.pollIntervalSec) || 4))

  Timer {
    id: pollTimer
    interval: root._pollInterval * 1000
    repeat: true
    running: true
    onTriggered: {
      scheduleRefresh("user");
      scheduleRefresh("system");
    }
  }

  // Debounce timers per scope
  property bool _userRefreshPending: false
  property bool _systemRefreshPending: false

  Timer {
    id: userPollTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (root._userRefreshPending) {
        root._userRefreshPending = false;
        root.processPoll("user");
      }
    }
  }

  Timer {
    id: systemPollTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (root._systemRefreshPending) {
        root._systemRefreshPending = false;
        root.processPoll("system");
      }
    }
  }

  function scheduleRefresh(scope) {
    if (scope === "user") {
      root._userRefreshPending = true;
      userPollTimer.restart();
    } else {
      root._systemRefreshPending = true;
      systemPollTimer.restart();
    }
  }

  function triggerRefresh() {
    scheduleRefresh("user");
    scheduleRefresh("system");
  }

  // ── Action queue ─────────────────────────────────────────────
  property var _actionQueue: []
  property bool _actionRunning: false
  property string _currentActionScope: ""
  property string _currentActionUnit: ""
  property string _currentActionName: ""

  // Watchdog timers for action timeouts
  Timer {
    id: actionWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      // Action timed out — kill the process
      actionProc.kill();
      root._finishAction(false, "Action timed out");
    }
  }

  Timer {
    id: actionTimeoutTimer
    interval: 120000
    repeat: false
    onTriggered: {
      actionProc.kill();
      root._finishAction(false, "System action timed out");
    }
  }

  function _finishAction(success, message) {
    actionWatchdog.stop();
    actionTimeoutTimer.stop();
    var scope = root._currentActionScope;
    var unitName = root._currentActionUnit;
    var action = root._currentActionName;
    root._actionRunning = false;

    if (!success && message) {
      root.lastError = message;
      Store.setError(message);
    }

    root.actionFinished(scope, unitName, action, success, message || "");

    // Debounced refresh after action
    scheduleRefresh(scope);

    // Process next queued action
    if (root._actionQueue.length > 0) {
      var next = root._actionQueue.shift();
      Qt.callLater(function() { root.processAction(next.scope, next.action, next.unit); });
    }
  }

  function processAction(scope, action, unitName) {
    if (!Model.isValidUnitName(unitName)) {
      root._finishAction(false, "Invalid unit name: " + unitName);
      return;
    }

    if (root._actionRunning) {
      root._actionQueue.push({ scope: scope, action: action, unit: unitName });
      return;
    }

    root._actionRunning = true;
    root._currentActionScope = scope;
    root._currentActionUnit = unitName;
    root._currentActionName = action;

    var argv = ["systemctl"];
    if (scope === "user") argv.push("--user");
    argv.push(action);
    argv.push(unitName);

    actionProc.command = argv;
    actionProc.running = true;

    // Set appropriate timeout
    if (scope === "system") {
      if (action === "enable" || action === "disable" || action === "mask" || action === "unmask") {
        actionTimeoutTimer.interval = 30000;
      } else {
        actionTimeoutTimer.interval = 120000;
      }
      actionTimeoutTimer.start();
    } else {
      if (action === "enable" || action === "disable" || action === "mask" || action === "unmask") {
        actionWatchdog.interval = 30000;
      } else {
        actionWatchdog.interval = 15000;
      }
      actionWatchdog.start();
    }
  }

  Process {
    id: actionProc
    running: false

    stdout: SplitParser {
      onRead: function(line) {}
    }

    stderr: SplitParser {
      onRead: function(line) {
        if (line) actionProc._lastActionStderr += line + "\n";
      }
    }

    property string _lastActionStderr: ""

    onRunningChanged: {
      if (!running) {
        var ok = exitCode === 0;
        var msg = ok ? "" : (_lastActionStderr.trim() || ("Exit code " + exitCode));
        _lastActionStderr = "";
        root._finishAction(ok, msg);
      }
    }
  }

  // ── Poll fetching ────────────────────────────────────────────
  // Combined fetch: runs list-units + list-unit-files in a single bash
  // command, separated by a marker line, then merges both JSON outputs.

  Process {
    id: userFetchProc
    running: false
    property string _unitsOutput: ""
    property string _filesOutput: ""
    property string _currentSection: "units"

    onRunningChanged: {
      if (!running) {
        if (exitCode === 0 || exitCode === 1) {
          var unitsJson = Model.parseJsonLines(_unitsOutput);
          var filesJson = Model.parseJsonLines(_filesOutput);
          var merged = Model.mergeUnits(unitsJson, filesJson);
          for (var i = 0; i < merged.length; i++) merged[i].scope = "user";
          root.userUnits = merged;
          var summary = Model.summarize(merged);
          Store.update("user", summary, true);
          Store.setError("");
          root.lastError = "";
        } else {
          Store.update("user", { total: 0, loaded: 0, active: 0, failed: 0, failedNames: [] }, false);
          Store.setError("Failed to list user units (exit " + exitCode + ")");
          root.lastError = Store.get().lastError;
        }
        root.unitsChanged("user");
        _unitsOutput = "";
        _filesOutput = "";
        _currentSection = "units";
      }
    }

    stdout: SplitParser {
      onRead: function(line) {
        if (line === "===UNITFILES===") {
          userFetchProc._currentSection = "files";
          return;
        }
        if (userFetchProc._currentSection === "units") {
          userFetchProc._unitsOutput += line + "\n";
        } else {
          userFetchProc._filesOutput += line + "\n";
        }
      }
    }
    stderr: SplitParser { onRead: function(line) {} }
  }

  Process {
    id: systemFetchProc
    running: false
    property string _unitsOutput: ""
    property string _filesOutput: ""
    property string _currentSection: "units"

    onRunningChanged: {
      if (!running) {
        if (exitCode === 0 || exitCode === 1) {
          var unitsJson = Model.parseJsonLines(_unitsOutput);
          var filesJson = Model.parseJsonLines(_filesOutput);
          var merged = Model.mergeUnits(unitsJson, filesJson);
          for (var i = 0; i < merged.length; i++) merged[i].scope = "system";
          root.systemUnits = merged;
          var summary = Model.summarize(merged);
          Store.update("system", summary, true);
          Store.setError("");
          root.lastError = "";
        } else {
          Store.update("system", { total: 0, loaded: 0, active: 0, failed: 0, failedNames: [] }, false);
          Store.setError("Failed to list system units (exit " + exitCode + ")");
          root.lastError = Store.get().lastError;
        }
        root.unitsChanged("system");
        _unitsOutput = "";
        _filesOutput = "";
        _currentSection = "units";
      }
    }

    stdout: SplitParser {
      onRead: function(line) {
        if (line === "===UNITFILES===") {
          systemFetchProc._currentSection = "files";
          return;
        }
        if (systemFetchProc._currentSection === "units") {
          systemFetchProc._unitsOutput += line + "\n";
        } else {
          systemFetchProc._filesOutput += line + "\n";
        }
      }
    }
    stderr: SplitParser { onRead: function(line) {} }
  }

  function processPoll(scope) {
    var isUser = scope === "user";
    var proc = isUser ? userFetchProc : systemFetchProc;
    var flags = isUser ? "--user" : "";
    var cmd = "LC_ALL=C systemctl " + flags + " list-units --type=service,timer,socket,path --all --no-pager --output=json"
            + "; echo ===UNITFILES==="
            + "; systemctl " + flags + " list-unit-files --type=service,timer,socket,path --no-pager --output=json";
    proc._unitsOutput = "";
    proc._filesOutput = "";
    proc._currentSection = "units";
    proc.command = ["bash", "-c", cmd];
    proc.running = true;
  }

  // ── Show properties ──────────────────────────────────────────
  property var _showCache: ({})

  function processShow(unitName, scope) {
    if (!Model.isValidUnitName(unitName)) return;

    var cached = root._showCache[unitName + ":" + scope];
    if (cached) {
      root.propertiesLoaded(unitName, scope, cached);
      return;
    }

    var argv = ["systemctl"];
    if (scope === "user") argv.push("--user");
    argv.push("show", unitName);
    argv.push("--property=Id,Description,LoadState,ActiveState,SubState,UnitFileState,FragmentPath,ActiveEnterTimestamp,CanStart,CanStop,CanReload");

    showProc._unitName = unitName;
    showProc._scope = scope;
    showProc._output = "";
    showProc.command = argv;
    showProc.running = true;
  }

  Process {
    id: showProc
    running: false
    property string _unitName: ""
    property string _scope: ""
    property string _output: ""

    stdout: SplitParser {
      onRead: function(line) {
        showProc._output += line + "\n";
      }
    }
    stderr: SplitParser {
      onRead: function(line) {}
    }

    onRunningChanged: {
      if (!running) {
        var props = {};
        if (exitCode === 0) {
          props = Model.parseShowOutput(_output);
        }
        root._showCache[_unitName + ":" + _scope] = props;
        root.propertiesLoaded(_unitName, _scope, props);
        _output = "";
      }
    }
  }

  // ── Journal ──────────────────────────────────────────────────
  function processJournal(unitName, scope, lines) {
    if (!Model.isValidUnitName(unitName)) return;

    var numLines = Math.max(50, Math.min(1000, lines || Number(root.preferences.journalLines) || 120));
    var argv = ["journalctl"];
    if (scope === "user") argv.push("--user");
    argv.push("-u", unitName);
    argv.push("-n", String(numLines));
    argv.push("--no-pager", "-o", "short", "--output-fields=MESSAGE");

    journalProc._unitName = unitName;
    journalProc._scope = scope;
    journalProc._output = "";
    journalProc.command = argv;
    journalProc.running = true;
  }

  Process {
    id: journalProc
    running: false
    property string _unitName: ""
    property string _scope: ""
    property string _output: ""

    stdout: SplitParser {
      onRead: function(line) {
        journalProc._output += line + "\n";
      }
    }
    stderr: SplitParser {
      onRead: function(line) {}
    }

    onRunningChanged: {
      if (!running) {
        root.journalLoaded(_unitName, _scope, _output);
        _output = "";
      }
    }
  }

  // ── Unit file (cat) ─────────────────────────────────────────
  function processUnitFile(unitName, scope) {
    if (!Model.isValidUnitName(unitName)) return;

    var argv = ["systemctl"];
    if (scope === "user") argv.push("--user");
    argv.push("cat", unitName);

    unitFileProc._unitName = unitName;
    unitFileProc._scope = scope;
    unitFileProc._output = "";
    unitFileProc._lineCount = 0;
    unitFileProc.command = argv;
    unitFileProc.running = true;
  }

  Process {
    id: unitFileProc
    running: false
    property string _unitName: ""
    property string _scope: ""
    property string _output: ""
    property int _lineCount: 0
    readonly property int _maxLines: 4000
    readonly property int _maxBytes: 262144  // 256KB

    stdout: SplitParser {
      onRead: function(line) {
        if (unitFileProc._lineCount >= unitFileProc._maxLines) return;
        if (unitFileProc._output.length >= unitFileProc._maxBytes) return;
        unitFileProc._output += line + "\n";
        unitFileProc._lineCount++;
      }
    }
    stderr: SplitParser {
      onRead: function(line) {}
    }

    onRunningChanged: {
      if (!running) {
        var text = _output;
        if (_lineCount >= _maxLines || _output.length >= _maxBytes) {
          text += "\n--- Truncated (output too large) ---\n";
        }
        root.unitFileLoaded(_unitName, _scope, text);
        _output = "";
        _lineCount = 0;
      }
    }
  }

  // ── Edit unit file ───────────────────────────────────────────
  function editUnitFile(unitName, scope) {
    if (!Model.isValidUnitName(unitName)) return;

    var argv = ["systemctl"];
    if (scope === "user") argv.push("--user");
    argv.push("edit", "--full", unitName);

    Util.execDetached(argv);
  }

  // ── IPC Handler ──────────────────────────────────────────────
  IpcHandler {
    target: "osystemd"

    function ping(): string {
      return "ok";
    }

    function status(): string {
      var s = Store.get();
      return JSON.stringify({
        user: {
          available: s.userAvailable,
          summary: s.userSummary
        },
        system: {
          available: s.systemAvailable,
          summary: s.systemSummary
        },
        lastError: s.lastError,
        favorites: s.favorites,
        preferences: root.preferences
      });
    }

    function listUnits(scope: string): string {
      var units = scope === "system" ? root.systemUnits : root.userUnits;
      return JSON.stringify(units || []);
    }

    function unit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ error: "Invalid unit name" });
      var units = scope === "system" ? root.systemUnits : root.userUnits;
      for (var i = 0; i < units.length; i++) {
        if (units[i].name === name) return JSON.stringify(units[i]);
      }
      return JSON.stringify({ error: "Unit not found" });
    }

    function unitProperties(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ error: "Invalid unit name" });
      // Synchronous cache check — if cached, return immediately
      var cached = root._showCache[name + ":" + scope];
      if (cached) return JSON.stringify(cached);
      // Otherwise trigger async fetch
      root.processShow(name, scope);
      return JSON.stringify({ loading: true });
    }

    function journal(name: string, scope: string, lines: int): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ error: "Invalid unit name" });
      root.processJournal(name, scope, lines);
      return JSON.stringify({ loading: true });
    }

    function unitFile(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ error: "Invalid unit name" });
      root.processUnitFile(name, scope);
      return JSON.stringify({ loading: true });
    }

    function startUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "start", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function stopUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "stop", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function restartUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "restart", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function reloadUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "reload", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function enableUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "enable", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function disableUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "disable", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function reenableUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "reenable", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function maskUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "mask", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function unmaskUnit(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.processAction(scope || "user", "unmask", name);
      return JSON.stringify({ ok: true, queued: true });
    }

    function editUnitFile(name: string, scope: string): string {
      if (!Model.isValidUnitName(name)) return JSON.stringify({ ok: false, error: "Invalid unit name" });
      root.editUnitFile(name, scope || "user");
      return JSON.stringify({ ok: true });
    }

    function refresh(): string {
      root.triggerRefresh();
      return JSON.stringify({ ok: true });
    }

    function favorites(): string {
      return JSON.stringify(root.preferences.favorites || []);
    }

    function toggleFavorite(name: string, scope: string): string {
      var key = name + ":" + scope;
      var favs = root.preferences.favorites || [];
      var idx = favs.indexOf(key);
      if (idx >= 0) {
        favs.splice(idx, 1);
      } else {
        favs.push(key);
      }
      root.preferences.favorites = favs;
      Store.setFavorites(favs);
      savePreferences();
      return JSON.stringify({ ok: true, favorites: favs });
    }

    function setFilterPref(key: string, value: string): string {
      if (key in root.preferences) {
        root.preferences[key] = value;
        savePreferences();
        return JSON.stringify({ ok: true });
      }
      return JSON.stringify({ ok: false, error: "Unknown preference key" });
    }
  }
}
