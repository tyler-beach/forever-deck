--[[
  ForeverDeck.RestedXPPath — Phase 2 stub.

  Intent: draw highlighted point-to-point paths between RestedXP Forever
  guide steps (not only an arrow). Consume public hooks/API/events only.
  Do NOT vendor or copy RestedXP source.

  Integration notes (fill in once Forever + RestedXP Forever are probed in-game):
  - OptionalDeps: RestedXP (see TOC).
  - Detect addon: C_AddOns.IsAddOnLoaded("RestedXP") / GetAddOnInfo variants per Forever API.
  - Candidate surfaces to inspect at runtime (names may differ — verify, do not assume):
      * Guide step change events or callbacks exposed by RestedXP Forever
      * Current/next step world coordinates or map pins
      * Active guide ID / step index globals if documented by the author
  - Rendering approach (planned):
      1. On step change, resolve coords for current + next step.
      2. Draw world overlay and/or minimap/map line segments between points.
      3. Keep Blizzard arrow (if present) as secondary; paths are the primary cue.
  - If RestedXP is missing or exposes no coordinates: no-op + chat status.
  - Never ship RestedXP internals inside this repo.
]]

local _, ns = ...
local RestedXPPath = {}
ns.RestedXPPath = RestedXPPath

local function isRestedXPLoaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("RestedXP")
  end
  if IsAddOnLoaded then
    return IsAddOnLoaded("RestedXP")
  end
  return false
end

function RestedXPPath:Init()
  if not (ns.db and ns.db.profile.restedXPPathEnabled) then
    return
  end
  if isRestedXPLoaded() then
    ns.Print("RestedXP detected — path overlay stub idle (awaiting public step coords/hooks)")
  else
    ns.Print("RestedXP not loaded — path overlay idle")
  end
end

function RestedXPPath:Toggle()
  if not ns.db then
    return
  end
  ns.db.profile.restedXPPathEnabled = not ns.db.profile.restedXPPathEnabled
  ns.Print("path overlay " .. (ns.db.profile.restedXPPathEnabled and "enabled" or "disabled") .. " (stub)")
end

-- Placeholder for future: ns.RestedXPPath:RefreshPath(fromXYZ, toXYZ)
function RestedXPPath:RefreshPath(_from, _to)
  -- Stub: no drawing until RestedXP Forever integration points are confirmed.
end
