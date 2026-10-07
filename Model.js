// Shared, dependency-free helpers for the Systemd Ease plugin.
// Pure functions only — no Qt imports, no state.
.pragma library

// "vendor"  = preinstalled system files (/usr/...) — hands off by default.
// "custom"  = dropped in by downloaded software or admin tweaks (/etc, /run).
// "mine"    = yours: your user units + anything this plugin created.
function originLabel(origin) {
  if (origin === "mine") return "Mine"
  if (origin === "custom") return "Added"
  return "System"
}

function scopeLabel(scope) {
  return scope === "user" ? "User" : "System"
}

// Beginner-friendly state words. active/sub come straight from systemd.
function runWord(u) {
  if (!u) return "unknown"
  if (u.active === "failed") return "crashed"
  if (u.active === "active") return u.sub === "exited" ? "done" : "running"
  if (u.active === "activating") return "starting"
  if (u.active === "deactivating") return "stopping"
  return "stopped"
}

function runKey(u) {
  if (!u) return "stopped"
  if (u.active === "failed") return "failed"
  if (u.active === "active") return "running"
  return "stopped"
}

// Beginner-friendly boot words. enabled comes from the unit file state.
function bootWord(enabled) {
  if (enabled === "enabled" || enabled === "generated") return "on"
  if (enabled === "indirect") return "on (via another service)"
  if (enabled === "masked") return "blocked"
  if (enabled === "static" || enabled === "alias") return "manual only"
  if (enabled === "disabled") return "off"
  return enabled || "off"
}

function bootOn(enabled) {
  return enabled === "enabled" || enabled === "generated" || enabled === "indirect"
}

function canToggleBoot(enabled) {
  return enabled !== "static" && enabled !== "alias" && enabled !== "masked"
}

function matchesQuery(u, q) {
  if (!q) return true
  q = String(q).toLowerCase()
  return u.name.toLowerCase().indexOf(q) >= 0
      || (u.description || "").toLowerCase().indexOf(q) >= 0
}

function passFilters(u, origin, scope, state) {
  if (origin === "mine" && !(u.origin === "mine" || u.origin === "custom")) return false
  if (origin === "vendor" && u.origin !== "vendor") return false
  if (scope !== "all" && u.scope !== scope) return false
  if (state === "running" && runKey(u) !== "running") return false
  if (state === "failed" && runKey(u) !== "failed") return false
  if (state === "boot" && !bootOn(u.enabled)) return false
  return true
}

function suggestName(text) {
  var s = String(text || "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .substr(0, 48)
  return s
}

function validServiceName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9_.\-]{0,63}$/.test(String(name || ""))
}

function shortName(unit) {
  var s = String(unit || "")
  return s.substr(0, s.length - (s.endsWith(".service") ? 8 : 0))
}

function agoText(ms) {
  var s = Math.max(0, Math.round(ms / 1000))
  if (s < 5) return "just now"
  if (s < 60) return s + "s ago"
  return Math.floor(s / 60) + "m ago"
}
