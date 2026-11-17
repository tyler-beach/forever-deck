--[[
  ForeverDeck.HUD — Phase 1 lead module.
  Compact Blizzard-looking Steam Deck overlays on top of default UI.
  No full UI replacement; scale/reposition stock-adjacent frames.
]]

local _, ns = ...
local HUD = {}
ns.HUD = HUD

local root

local function ensureRoot()
  if root then
    return root
  end
  root = CreateFrame("Frame", "ForeverDeckHUDRoot", UIParent)
  root:SetSize(320, 48)
  root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 96)
  root:SetScale((ns.db and ns.db.profile.hudScale) or 1.0)

  -- Placeholder strip: Blizzard-adjacent backdrop for Deck-safe layout iteration.
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.08, 0.55)

  local label = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER")
  label:SetText("ForeverDeck HUD (scaffold)")
  root.label = label

  root:Hide()
  return root
end

function HUD:Init()
  ensureRoot()
  if ns.db and ns.db.profile.hudEnabled then
    root:Show()
    ns.Print("HUD module ready (scaffold — compact Deck layout TBD)")
  end
end

function HUD:Toggle()
  if not ns.db then
    return
  end
  ns.db.profile.hudEnabled = not ns.db.profile.hudEnabled
  local f = ensureRoot()
  if ns.db.profile.hudEnabled then
    f:Show()
  else
    f:Hide()
  end
  ns.Print("HUD " .. (ns.db.profile.hudEnabled and "enabled" or "disabled"))
end
