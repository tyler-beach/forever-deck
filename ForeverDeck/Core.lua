--[[
  ForeverDeck — core bootstrap for WoW Forever (Interface 16001).
  Detect Forever via interface in [16000, 17000). Mainline-style API.
]]

local ADDON_NAME, ns = ...
ForeverDeck = ns

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"
ns.FOREVER_INTERFACE_MIN = 16000
ns.FOREVER_INTERFACE_MAX = 17000 -- exclusive upper bound

local defaults = {
  profile = {
    hudEnabled = true,
    restedXPPathEnabled = true,
    shamanPvEEnabled = true,
    hudScale = 1.0,
  },
}

local function copyDefaults(src)
  local dst = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = copyDefaults(v)
    else
      dst[k] = v
    end
  end
  return dst
end

function ns.IsForeverClient()
  local iface = select(4, GetBuildInfo())
  if type(iface) ~= "number" then
    return false
  end
  return iface >= ns.FOREVER_INTERFACE_MIN and iface < ns.FOREVER_INTERFACE_MAX
end

function ns.Print(msg)
  local prefix = "|cff66ccffForeverDeck|r: "
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
  end
end

local frame = CreateFrame("Frame", "ForeverDeckEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    ForeverDeckDB = ForeverDeckDB or copyDefaults(defaults)
    ns.db = ForeverDeckDB
    ns.Print(string.format("loaded v%s (scaffold)", ns.VERSION))
  elseif event == "PLAYER_LOGIN" then
    if not ns.IsForeverClient() then
      ns.Print("warning: interface not in Forever range [16000, 17000); modules may misbehave")
    end
    if ns.HUD and ns.HUD.Init then
      ns.HUD:Init()
    end
    if ns.RestedXPPath and ns.RestedXPPath.Init then
      ns.RestedXPPath:Init()
    end
    if ns.ShamanPvE and ns.ShamanPvE.Init then
      ns.ShamanPvE:Init()
    end
  end
end)

SLASH_FOREVERDECK1 = "/foreverdeck"
SLASH_FOREVERDECK2 = "/fdeck"
SlashCmdList.FOREVERDECK = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "" or msg == "help" then
    ns.Print("/foreverdeck status | hud | path | shaman")
    return
  end
  if msg == "status" then
    local iface = select(4, GetBuildInfo())
    ns.Print(string.format(
      "v%s iface=%s forever=%s hud=%s path=%s shaman=%s",
      ns.VERSION,
      tostring(iface),
      tostring(ns.IsForeverClient()),
      tostring(ns.db and ns.db.profile.hudEnabled),
      tostring(ns.db and ns.db.profile.restedXPPathEnabled),
      tostring(ns.db and ns.db.profile.shamanPvEEnabled)
    ))
    return
  end
  if msg == "hud" and ns.HUD and ns.HUD.Toggle then
    ns.HUD:Toggle()
    return
  end
  if msg == "path" and ns.RestedXPPath and ns.RestedXPPath.Toggle then
    ns.RestedXPPath:Toggle()
    return
  end
  if msg == "shaman" and ns.ShamanPvE and ns.ShamanPvE.Toggle then
    ns.ShamanPvE:Toggle()
    return
  end
  ns.Print("unknown command; try /foreverdeck help")
end
