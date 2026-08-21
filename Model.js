.pragma library

// ── Unit type extraction ──────────────────────────────────────────────
// "sshd.service" → "service", "foo.timer" → "timer"
function unitType(name) {
    var dot = name.lastIndexOf(".");
    return dot >= 0 ? name.substring(dot + 1) : "";
}

// ── Canonicalize active/sub states ────────────────────────────────────
// Merges active + sub into a single display string.
// "active" + "running" → "active.running"
// "failed" + "failed"  → "failed"
// "inactive" + "dead"  → "inactive.dead"
function normalizeState(active, sub) {
    if (!active) return "unknown";
    if (active === sub) return active;
    return active + "." + (sub || "");
}

// ── State → color key ─────────────────────────────────────────────────
// Returns one of: "success" | "warn" | "error" | "neutral"
function stateColorKey(canonicalState) {
    if (!canonicalState) return "neutral";
    if (canonicalState.indexOf("failed") === 0) return "error";
    if (canonicalState.indexOf("active") === 0) return "success";
    if (canonicalState.indexOf("error") >= 0) return "error";
    if (canonicalState.indexOf("activating") >= 0) return "warn";
    if (canonicalState.indexOf("deactivating") >= 0) return "warn";
    return "neutral";
}

// ── Scope display label ──────────────────────────────────────────────
function scopeLabel(scope) {
    if (scope === "system") return "System";
    if (scope === "user") return "User";
    return scope || "Unknown";
}

// ── Search scoring ────────────────────────────────────────────────────
// Higher score = better match.  0 = no match.
// Name matches score higher than description matches.
// Prefix matches score higher than substring matches.
function searchScore(query, unit) {
    if (!query || query.length === 0) return 1; // no filter → everything matches
    var q = query.toLowerCase();
    var name = (unit.name || "").toLowerCase();
    var desc = (unit.description || "").toLowerCase();

    if (name === q) return 100;            // exact match
    if (name.indexOf(q) === 0) return 80;  // prefix
    if (name.indexOf(q) >= 0) return 60;   // substring
    if (desc.indexOf(q) >= 0) return 30;   // description hit
    return 0;
}

// ── Journal truncation ────────────────────────────────────────────────
function truncateJournalLine(line, maxLen) {
    if (typeof maxLen === "undefined") maxLen = 2000;
    if (!line) return "";
    if (line.length <= maxLen) return line;
    return line.substring(0, maxLen - 1) + "…";
}

// ── Bar indicator color key ───────────────────────────────────────────
// Derives a traffic-light color from the unit-level failed count
// and the last error state.  Returns "success" | "warn" | "error".
function indicatorColor(failedCount, lastError) {
    if (failedCount > 0) return "error";
    if (lastError && lastError !== "") return "warn";
    return "success";
}

// ── Bar indicator tooltip ─────────────────────────────────────────────
function indicatorTooltip(failedCount, scope, lastError) {
    var scopeStr = scopeLabel(scope);
    if (failedCount > 0) {
        return failedCount + " failed unit" + (failedCount !== 1 ? "s" : "")
               + " (" + scopeStr + ")";
    }
    if (lastError && lastError !== "") {
        return "Last error: " + lastError + " (" + scopeStr + ")";
    }
    return "All " + scopeStr.toLowerCase() + " units healthy";
}

// ── Short failed summary ─────────────────────────────────────────────
// "3 failed (system)" or "all healthy"
function failedSummary(failedCount, scope) {
    if (failedCount > 0) {
        return failedCount + " failed (" + scopeLabel(scope) + ")";
    }
    return "all healthy";
}

// ── Short badge label ─────────────────────────────────────────────────
// Maps active+sub to a short string for the unit-list badge.
// "RUN", "FAIL", "DEAD", "WAIT", "ACTV", "INAC", "ERR", …
function stateBadge(active, sub) {
    if (!active) return "…";
    var a = active.toLowerCase();
    var s = (sub || "").toLowerCase();

    if (a === "failed") return "FAIL";
    if (a === "active" && s === "running") return "RUN";
    if (a === "active" && s === "waiting") return "WAIT";
    if (a === "active" && s === "mounted") return "MNT";
    if (a === "active") return "ACTV";
    if (a === "inactive") return "INAC";
    if (a === "activating") return "UP";
    if (a === "deactivating") return "DN";
    if (a === "error") return "ERR";
    if (s === "dead") return "DEAD";
    return a.substring(0, 4).toUpperCase();
}
