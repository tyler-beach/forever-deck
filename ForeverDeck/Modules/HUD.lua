--[[
  ForeverDeck.HUD — Phase 1 compact Steam Deck HUD.

  Strategy: scale/reposition stock Blizzard frames (not a full restyle).
  Keep center FOV clear for OLED + gamepad beta; larger edge hit targets
  where we touch bags/micro. Soft-fail individual attaches via Core.Error.
]]

local _, ns = ...
local HUD = {}
ns.HUD = HUD

local MODULE = "HUD"

-- Original layout snapshots so Toggle/disable can restore.
local originals = {}
local applied = false
local watcher

local function dbHud()
  return ns.db and ns.db.profile and ns.db.profile.hud
end

local function panelEnabled(key)
  local h = dbHud()
  if not h or not h.panels then
    return true
  end
  return h.panels[key] ~= false
end

local function snapshot(frame)
  if not frame or originals[frame] then
    return
  end
  local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
  originals[frame] = {
    scale = frame:GetScale() or 1,
    point = point,
    relativeTo = relativeTo and relativeTo.GetName and relativeTo:GetName() or relativeTo,
    relativePoint = relativePoint,
    x = x,
    y = y,
    numPoints = frame:GetNumPoints() or 0,
  }
end

local function resolveRelative(nameOrFrame)
  if type(nameOrFrame) == "table" then
    return nameOrFrame
  end
  if type(nameOrFrame) == "string" then
    return _G[nameOrFrame] or UIParent
  end
  return UIParent
end

local function applyLayout(frame, cfg, globalScale)
  if not frame or not cfg then
    return
  end
  snapshot(frame)
  local scale = (tonumber(cfg.scale) or 1) * (tonumber(globalScale) or 1)
  frame:SetScale(scale)
  if cfg.point and cfg.relativePoint then
    frame:ClearAllPoints()
    frame:SetPoint(
      cfg.point,
      resolveRelative(cfg.relativeTo),
      cfg.relativePoint,
      tonumber(cfg.x) or 0,
      tonumber(cfg.y) or 0
    )
  end
end

local function restoreFrame(frame)
  local o = originals[frame]
  if not frame or not o then
    return
  end
  frame:SetScale(o.scale or 1)
  if o.point then
    frame:ClearAllPoints()
    frame:SetPoint(
      o.point,
      resolveRelative(o.relativeTo),
      o.relativePoint or o.point,
      o.x or 0,
      o.y or 0
    )
  end
end

---------------------------------------------------------------------------
-- Compact player / target essentials (edge layout, clear center)
---------------------------------------------------------------------------

local function attachPlayer()
  local cfg = dbHud() and dbHud().player
  local frame = _G.PlayerFrame
  ns.Error:Assert(frame, MODULE, "attachPlayer", "PlayerFrame missing")
  applyLayout(frame, cfg, ns.db.profile.hudScale)

  -- Slightly enlarge clickable status region for Deck thumbs if present.
  if frame.PlayerFrameContainer and frame.PlayerFrameContainer.FrameTexture then
    -- Intentionally leave textures alone — Blizzard-native look.
  end
end

local function attachTarget()
  local cfg = dbHud() and dbHud().target
  local frame = _G.TargetFrame
  ns.Error:Assert(frame, MODULE, "attachTarget", "TargetFrame missing")
  applyLayout(frame, cfg, ns.db.profile.hudScale)
end

---------------------------------------------------------------------------
-- Bags / micro (light touch — larger scale near corner)
---------------------------------------------------------------------------

local function findBagsMicroFrame()
  -- Forever/Mainline naming varies; probe known candidates.
  local candidates = {
    "MicroButtonAndBagsBar",
    "BagsBar",
    "MainMenuBarBackpackButton",
    "CharacterMicroButton",
  }
  for _, name in ipairs(candidates) do
    local f = _G[name]
    if f and f.SetPoint then
      return f, name
    end
  end
  return nil, nil
end

local function attachBagsMicro()
  if not panelEnabled("bagsMicro") then
    return
  end
  local frame, name = findBagsMicroFrame()
  if not frame then
    ns.Error:Warn(MODULE, "attachBagsMicro", "no bags/micro bar frame found (Forever API gap?)")
    return
  end
  -- Only reposition composite bars; avoid yanking a single micro button alone.
  if name == "MainMenuBarBackpackButton" or name == "CharacterMicroButton" then
    -- Scale parent if available for larger hit targets without re-anchoring singles.
    local parent = frame:GetParent()
    if parent and parent ~= UIParent then
      snapshot(parent)
      local cfg = dbHud() and dbHud().bagsMicro
      local scale = (cfg and tonumber(cfg.scale) or 1.05) * (ns.db.profile.hudScale or 1)
      parent:SetScale(scale)
      return
    end
    ns.Error:Warn(MODULE, "attachBagsMicro", "only single micro/bag control found; skip re-anchor")
    return
  end
  local cfg = dbHud() and dbHud().bagsMicro
  applyLayout(frame, cfg, ns.db.profile.hudScale)
end

---------------------------------------------------------------------------
-- Quest / objective glance (edge, keep FOV clear)
---------------------------------------------------------------------------

local function findObjectiveFrame()
  local candidates = {
    "ObjectiveTrackerFrame",
    "QuestObjectiveTracker",
    "ObjectiveTrackerBlocksFrame",
    "WatchFrame",
  }
  for _, name in ipairs(candidates) do
    local f = _G[name]
    if f and f.SetPoint then
      return f, name
    end
  end
  return nil, nil
end

local function attachQuestGlance()
  if not panelEnabled("questGlance") then
    return
  end
  local frame, name = findObjectiveFrame()
  if not frame then
    ns.Error:Warn(MODULE, "attachQuestGlance", "no objective/quest tracker frame found (Forever API gap?)")
    return
  end
  local cfg = dbHud() and dbHud().questGlance
  -- Prefer scale-only if the tracker is tightly coupled to Edit Mode; still try edge anchor.
  local ok = ns.Error:SafeAttach(MODULE, name, function()
    applyLayout(frame, cfg, ns.db.profile.hudScale)
  end)
  if not ok then
    -- Fallback: scale only.
    ns.Error:SafeAttach(MODULE, name .. ":scaleOnly", function()
      snapshot(frame)
      local scale = (cfg and tonumber(cfg.scale) or 0.9) * (ns.db.profile.hudScale or 1)
      frame:SetScale(scale)
    end)
  end
end

---------------------------------------------------------------------------
-- Clear center FOV: nudge casting bar / buffs off dead-center if needed
---------------------------------------------------------------------------

local function clearCenterFOV()
  local h = dbHud()
  if not h or h.clearCenterFOV == false then
    return
  end

  local cast = _G.PlayerCastingBarFrame or _G.CastingBarFrame
  if cast and cast.GetPoint then
    ns.Error:SafeAttach(MODULE, "CastingBar", function()
      snapshot(cast)
      -- Keep Blizzard look; drop slightly so it sits under center crosshair band.
      local scale = 0.95 * (ns.db.profile.hudScale or 1)
      cast:SetScale(scale)
      cast:ClearAllPoints()
      cast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end)
  end

  -- Buffs: prefer top-right adjacent to target, not center.
  local buffs = _G.BuffFrame
  if buffs and buffs.SetPoint then
    ns.Error:SafeAttach(MODULE, "BuffFrame", function()
      snapshot(buffs)
      buffs:ClearAllPoints()
      buffs:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -28, -72)
      buffs:SetScale(0.95 * (ns.db.profile.hudScale or 1))
    end)
  end
end

---------------------------------------------------------------------------
-- Compact essentials strip (HP/power readouts) — Blizzard fonts only
---------------------------------------------------------------------------

local strip

local function ensureStrip()
  if strip then
    return strip
  end
  strip = CreateFrame("Frame", "ForeverDeckHUDStrip", UIParent)
  strip:SetSize(280, 36)
  strip:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 88)
  strip:SetFrameStrata("MEDIUM")

  local bg = strip:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.02, 0.02, 0.04, 0.45)

  local playerFS = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  playerFS:SetPoint("LEFT", 10, 0)
  playerFS:SetJustifyH("LEFT")
  strip.playerFS = playerFS

  local targetFS = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  targetFS:SetPoint("RIGHT", -10, 0)
  targetFS:SetJustifyH("RIGHT")
  strip.targetFS = targetFS

  strip:Hide()
  return strip
end

local function unitLine(unit)
  if not UnitExists(unit) then
    return unit == "target" and "no target" or "—"
  end
  local name = UnitName(unit) or unit
  local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
  local pct = (hpMax and hpMax > 0) and math.floor((hp / hpMax) * 100 + 0.5) or 0
  local powerType = UnitPowerType and UnitPowerType(unit) or 0
  local power, powerMax = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
  local ppct = (powerMax and powerMax > 0) and math.floor((power / powerMax) * 100 + 0.5) or 0
  return string.format("%s  %d%% hp  %d%% res", name, pct, ppct)
end

local function updateStrip()
  if not strip or not strip:IsShown() then
    return
  end
  strip.playerFS:SetText(unitLine("player"))
  strip.targetFS:SetText(unitLine("target"))
end

local function startWatcher()
  if watcher then
    return
  end
  watcher = CreateFrame("Frame", "ForeverDeckHUDWatcher")
  watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
  watcher:RegisterEvent("UNIT_HEALTH")
  watcher:RegisterEvent("UNIT_POWER_UPDATE")
  watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
  watcher.elapsed = 0
  watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" then
      if unit ~= "player" and unit ~= "target" then
        return
      end
    end
    updateStrip()
  end)
  watcher:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.25 then
      return
    end
    self.elapsed = 0
    updateStrip()
  end)
end

---------------------------------------------------------------------------
-- Apply / restore
---------------------------------------------------------------------------

local function restoreAll()
  for frame in pairs(originals) do
    ns.Error:SafeAttach(MODULE, "restore", function()
      restoreFrame(frame)
    end)
  end
  if strip then
    strip:Hide()
  end
  applied = false
end

local function applyAll()
  ns.Error:Assert(ns.db and ns.db.profile, MODULE, "applyAll", "SavedVariables profile missing")

  -- Required frames: validate then attach under pcall.
  ns.ValidateHUDFrames("HUD:applyAll")

  if panelEnabled("player") then
    ns.Error:SafeAttach(MODULE, "PlayerFrame", attachPlayer)
  end
  if panelEnabled("target") then
    ns.Error:SafeAttach(MODULE, "TargetFrame", attachTarget)
  end

  ns.Error:SafeAttach(MODULE, "bagsMicro", attachBagsMicro)
  ns.Error:SafeAttach(MODULE, "questGlance", attachQuestGlance)
  ns.Error:SafeAttach(MODULE, "clearCenterFOV", clearCenterFOV)

  local s = ensureStrip()
  s:SetScale(ns.db.profile.hudScale or 1)
  s:Show()
  startWatcher()
  updateStrip()

  applied = true
  ns.SetModuleState(MODULE, "ok", "compact Deck layout applied")
end

function HUD:Init()
  ns.Error:Assert(ns.db, MODULE, "Init", "db not ready — Core ADDON_LOADED failed?")

  if not ns.db.profile.hudEnabled then
    ns.SetModuleState(MODULE, "disabled", "hudEnabled=false")
    return
  end

  local ok, err = pcall(applyAll)
  if not ok then
    ns.SetModuleState(MODULE, "failed", tostring(err))
    -- Re-raise with module context for geterrorhandler.
    ns.Error:Raise(MODULE, "Init", err)
  end

  ns.Print(string.format(
    "HUD ready (scale=%.2f, FOV-clear=%s)",
    tonumber(ns.db.profile.hudScale) or 1,
    tostring(dbHud() and dbHud().clearCenterFOV ~= false)
  ))
end

function HUD:Toggle()
  if not ns.db then
    ns.Error:Warn(MODULE, "Toggle", "db not ready")
    return
  end
  ns.db.profile.hudEnabled = not ns.db.profile.hudEnabled
  if ns.db.profile.hudEnabled then
    local ok, err = pcall(applyAll)
    if not ok then
      ns.SetModuleState(MODULE, "failed", tostring(err))
      ns.PrintError("HUD enable failed: " .. tostring(err))
      return
    end
  else
    restoreAll()
    ns.SetModuleState(MODULE, "disabled", "toggled off")
  end
  ns.Print("HUD " .. (ns.db.profile.hudEnabled and "enabled" or "disabled"))
end

function HUD:IsApplied()
  return applied
end

function HUD:Refresh()
  if ns.db and ns.db.profile.hudEnabled then
    applyAll()
  end
end
