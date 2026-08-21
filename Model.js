.pragma library

// Parse JSON Lines (one JSON object per line). Skips blank lines.
function parseJsonLines(text) {
  var out = [];
  if (!text) return out;
  var lines = String(text).split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line) continue;
    try {
      out.push(JSON.parse(line));
    } catch (e) {
      // skip unparseable lines (systemctl occasionally emits warnings)
    }
  }
  return out;
}

// Extract unit type from name suffix (e.g. "docker.service" -> "service")
function unitType(name) {
  if (!name) return "";
  var idx = name.lastIndexOf(".");
  if (idx < 0) return "";
  return name.substring(idx + 1);
}

// Build a stable fingerprint of units for change detection.
// Sort by name so order-changes don't trigger re-renders.
function fingerprint(units) {
  if (!units || units.length === 0) return "";
  var sorted = units.slice().sort(function(a, b) {
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
  });
  var parts = [];
  for (var i = 0; i < sorted.length; i++) {
    var u = sorted[i];
    parts.push(u.name + "|" + (u.activeState || "") + "|" + (u.subState || "") + "|" + (u.unitFileState || ""));
  }
  return parts.join(";");
}

// Merge list-units (runtime) + list-unit-files (installed) into unified UnitEntry objects.
// inputs: unitsArray (from list-units --all), filesArray (from list-unit-files)
function mergeUnits(unitsArray, filesArray) {
  var byName = {};

  // Start with unit files (the universe of installed units)
  if (filesArray) {
    for (var i = 0; i < filesArray.length; i++) {
      var f = filesArray[i];
      var name = f.unit_file || f.UnitFile || "";
      if (!name) continue;
      byName[name] = {
        name: name,
        scope: "",
        type: unitType(name),
        description: "",
        loadState: "",
        activeState: "",
        subState: "",
        unitFileState: f.state || f.State || "",
        isLoaded: false,
        isActive: false,
        isFailed: false
      };
    }
  }

  // Overlay runtime state from list-units
  if (unitsArray) {
    for (var j = 0; j < unitsArray.length; j++) {
      var u = unitsArray[j];
      var uname = u.unit || u.Unit || "";
      if (!uname) continue;
      var active = u.active || u.Active || "";
      var sub = u.sub || u.Sub || "";
      var entry = byName[uname];
      if (!entry) {
        // Transient unit (e.g. session-scope runtime unit)
        entry = {
          name: uname,
          scope: "",
          type: unitType(uname),
          description: u.description || u.Description || "",
          loadState: u.load || u.Load || "",
          activeState: active,
          subState: sub,
          unitFileState: "transient",
          isLoaded: true,
          isActive: active === "active",
          isFailed: active === "failed"
        };
        byName[uname] = entry;
      } else {
        entry.description = u.description || u.Description || "";
        entry.loadState = u.load || u.Load || "";
        entry.activeState = active;
        entry.subState = sub;
        entry.isLoaded = true;
        entry.isActive = active === "active";
        entry.isFailed = active === "failed";
      }
    }
  }

  return Object.values(byName);
}

// Compute summary stats: {total, loaded, active, failed, failedNames}
function summarize(units) {
  var s = { total: 0, loaded: 0, active: 0, failed: 0, failedNames: [] };
  if (!units) return s;
  s.total = units.length;
  for (var i = 0; i < units.length; i++) {
    var u = units[i];
    if (u.isLoaded) s.loaded++;
    if (u.isActive) s.active++;
    if (u.isFailed) {
      s.failed++;
      if (s.failedNames.length < 5) s.failedNames.push(u.name);
    }
  }
  return s;
}

// Filter & sort units for display.
// filters: { search: string, types: [string], states: [string], favorites: [string], scope: string }
// favoriteKey: function(u) -> "name:scope"
function filterUnits(units, filters, favoriteKey) {
  if (!units) return [];
  var search = (filters.search || "").trim().toLowerCase();
  var types = filters.types || [];
  var states = filters.states || [];
  var favorites = filters.favorites || [];
  var scope = filters.scope || "all";

  var favSet = {};
  for (var i = 0; i < favorites.length; i++) favSet[favorites[i]] = true;

  var result = [];
  for (var j = 0; j < units.length; j++) {
    var u = units[j];
    // Scope filter
    if (scope === "user" && u.scope !== "user") continue;
    if (scope === "system" && u.scope !== "system") continue;

    // Type filter
    if (types.length > 0 && types.indexOf(u.type) === -1) continue;

    // State filter
    if (states.length > 0) {
      var matches = false;
      for (var k = 0; k < states.length; k++) {
        var st = states[k];
        if (st === "active" && u.isActive) { matches = true; break; }
        if (st === "failed" && u.isFailed) { matches = true; break; }
        if (st === "inactive" && !u.isActive && !u.isFailed) { matches = true; break; }
      }
      if (!matches) continue;
    }

    // Search filter (name, description)
    if (search) {
      var hay = (u.name + " " + (u.description || "")).toLowerCase();
      if (hay.indexOf(search) === -1) continue;
    }

    var key = favoriteKey ? favoriteKey(u) : (u.name + ":" + u.scope);
    u.__isFavorite = favSet[key] === true;
    result.push(u);
  }

  // Sort: failed first, then favorites, then active, then alphabetical
  result.sort(function(a, b) {
    if (a.isFailed !== b.isFailed) return a.isFailed ? -1 : 1;
    if (a.__isFavorite !== b.__isFavorite) return a.__isFavorite ? -1 : 1;
    if (a.isActive !== b.isActive) return a.isActive ? -1 : 1;
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
  });

  return result;
}

// Validate a unit name (prevent shell injection)
var VALID_NAME = /^[A-Za-z0-9_.:@\-]+$/;
function isValidUnitName(name) {
  return name && typeof name === "string" && VALID_NAME.test(name);
}

// Friendly humanization of a state value
function humanState(state) {
  if (!state) return "";
  return state.replace(/^./, function(c) { return c.toUpperCase(); });
}

// Parse "systemctl show" output (KEY=value lines) into an object
function parseShowOutput(text) {
  var out = {};
  if (!text) return out;
  var lines = String(text).split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var idx = line.indexOf("=");
    if (idx < 0) continue;
    var key = line.substring(0, idx).trim();
    var val = line.substring(idx + 1).trim();
    out[key] = val;
  }
  return out;
}

// LRU cache with bounded size
function LruCache(maxSize) {
  this._max = maxSize || 10;
  this._map = {};
  this._keys = [];
}
LruCache.prototype.get = function(k) {
  if (!(k in this._map)) return undefined;
  // Move to end (most recent)
  var idx = this._keys.indexOf(k);
  if (idx >= 0) this._keys.splice(idx, 1);
  this._keys.push(k);
  return this._map[k];
};
LruCache.prototype.put = function(k, v) {
  if (k in this._map) {
    var idx = this._keys.indexOf(k);
    if (idx >= 0) this._keys.splice(idx, 1);
  } else if (this._keys.length >= this._max) {
    var evict = this._keys.shift();
    delete this._map[evict];
  }
  this._keys.push(k);
  this._map[k] = v;
  return v;
};
LruCache.prototype.invalidate = function(predicate) {
  var remove = [];
  for (var k in this._map) {
    if (!predicate || predicate(k)) remove.push(k);
  }
  for (var i = 0; i < remove.length; i++) {
    delete this._map[remove[i]];
    var idx = this._keys.indexOf(remove[i]);
    if (idx >= 0) this._keys.splice(idx, 1);
  }
};
