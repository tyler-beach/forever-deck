--[[
  ForeverDeck.ShamanPvE — Phase 3 stub.
  Lightweight Tauren Shaman PvE helpers (totem/shield reminders, simple prompts).
  Deferred until HUD + RestedXP path MVP are stable on Steam Deck.
]]

local _, ns = ...
local ShamanPvE = {}
ns.ShamanPvE = ShamanPvE

local function isShaman()
  local _, classFile = UnitClass("player")
  return classFile == "SHAMAN"
end

function ShamanPvE:Init()
  if not (ns.db and ns.db.profile.shamanPvEEnabled) then
    return
  end
  if isShaman() then
    ns.Print("Shaman PvE helper stub ready (disabled UI until Phase 3)")
  end
end

function ShamanPvE:Toggle()
  if not ns.db then
    return
  end
  ns.db.profile.shamanPvEEnabled = not ns.db.profile.shamanPvEEnabled
  ns.Print("Shaman PvE " .. (ns.db.profile.shamanPvEEnabled and "enabled" or "disabled") .. " (stub)")
end
