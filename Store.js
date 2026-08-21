.pragma library

var _state = {
  userRevision: 0,
  systemRevision: 0,
  userSummary: { total: 0, loaded: 0, active: 0, failed: 0, failedNames: [] },
  systemSummary: { total: 0, loaded: 0, active: 0, failed: 0, failedNames: [] },
  userAvailable: false,
  systemAvailable: false,
  lastError: "",
  favorites: []
};

function get() {
  return _state;
}

function update(scope, summary, available) {
  if (scope === "user") {
    _state.userSummary = summary;
    _state.userAvailable = available;
    _state.userRevision++;
  } else if (scope === "system") {
    _state.systemSummary = summary;
    _state.systemAvailable = available;
    _state.systemRevision++;
  }
}

function setError(msg) {
  _state.lastError = msg || "";
}

function setFavorites(favs) {
  _state.favorites = favs || [];
}

function revision(scope) {
  return scope === "user" ? _state.userRevision : _state.systemRevision;
}
