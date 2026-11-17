--[[
  ForeverDeck — core bootstrap for WoW Forever (Interface 16001).
  Detect Forever via interface in [16000, 17000). Mainline-style API.

  Diagnostics are first-class: install/debug on Steam Deck must surface
  exact missing frames/APIs and module+function failure context.
]]

local ADDON_NAME, ns = ...
ForeverDeck = ns

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.2.0"
ns.FOREVER_INTERFACE_MIN = 16000
ns.FOREVER_INTERFACE_MAX = 17000 -- exclusive upper bound

-- Module load / diagnostic state (dumped by /foreverdeck status|debug)
ns.moduleState = ns.moduleState or {}
ns.lastErrors = ns.lastErrors or {}
ns.MAX_LAST_ERRORS = 12
ns._softDepWarned = ns._softDepWarned or {}

local defaults = {
  profile = {
    hudEnabled = true,
    restedXPPathEnabled = true,
    shamanPvEEnabled = true,
    hudScale = 1.0,
    hud = {
      clearCenterFOV = true,
      panels = {
        player = true,
        target = true,
        bagsMicro = true,
        questGlance = true,
      },
      player = {
        scale = 0.85,
        point = "TOPLEFT",
        relativeTo = "UIParent",
        relativePoint = "TOPLEFT",
        x = 24,
        y = -24,
      },
      target = {
        scale = 0.85,
        point = "TOPRIGHT",
        relativeTo = "UIParent",
        relativePoint = "TOPRIGHT",
        x = -24,
        y = -24,
      },
      bagsMicro = {
        scale = 1.05,
        point = "BOTTOMRIGHT",
        relativeTo = "UIParent",
        relativePoint = "BOTTOMRIGHT",
        x = -12,
        y = 12,
      },
      questGlance = {
        scale = 0.9,
        point = "RIGHT",
        relativeTo = "UIParent",
        relativePoint = "RIGHT",
        x = -16,
        y = 40,
      },
    },
  },
}

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------

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

local function deepMerge(dst, src)
  if type(dst) ~= "table" then
    dst = {}
  end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = deepMerge(type(dst[k]) == "table" and dst[k] or {}, v)
    elseif dst[k] == nil then
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

function ns.GetInterfaceBuild()
  local version, build, dateStr, toc = GetBuildInfo()
  return {
    version = version,
    build = build,
    date = dateStr,
    interface = toc,
  }
end

local RED = "|cffff4444"
local AMBER = "|cffffcc00"
local RESET = "|r"

function ns.Print(msg)
  local prefix = "|cff66ccffForeverDeck|r: "
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
  end
end

function ns.PrintError(msg)
  local text = RED .. "ForeverDeck|r: " .. tostring(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(text)
  end
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(tostring(msg), 1.0, 0.25, 0.25)
  end
end

function ns.PrintWarn(msg)
  ns.Print(AMBER .. tostring(msg) .. RESET)
end

---------------------------------------------------------------------------
-- ForeverDeck.Error — structured, geterrorhandler()-friendly diagnostics
---------------------------------------------------------------------------

ns.Error = {}

local function recordError(kind, moduleName, funcName, message, fatal)
  local entry = {
    time = (GetServerTime and GetServerTime()) or time(),
    kind = kind,
    module = moduleName or "Core",
    func = funcName or "?",
    message = tostring(message or "unknown"),
    fatal = not not fatal,
  }
  table.insert(ns.lastErrors, entry)
  while #ns.lastErrors > ns.MAX_LAST_ERRORS do
    table.remove(ns.lastErrors, 1)
  end
  return entry
end

--- Format a message suitable for error() / geterrorhandler().
function ns.Error:Format(moduleName, funcName, message)
  return string.format(
    "ForeverDeck[%s]:%s — %s",
    tostring(moduleName or "Core"),
    tostring(funcName or "?"),
    tostring(message or "unknown error")
  )
end

--- Fatal raise: records last-error and calls error() (never silent).
function ns.Error:Raise(moduleName, funcName, message)
  local formatted = self:Format(moduleName, funcName, message)
  recordError("raise", moduleName, funcName, message, true)
  ns.PrintError(formatted)
  error(formatted, 2)
end

--- Assert condition; on failure Raise (fatal).
function ns.Error:Assert(cond, moduleName, funcName, message)
  if not cond then
    self:Raise(moduleName, funcName, message)
  end
  return cond
end

--- Soft warning: record + chat, do not crash.
function ns.Error:Warn(moduleName, funcName, message)
  local formatted = self:Format(moduleName, funcName, message)
  recordError("warn", moduleName, funcName, message, false)
  ns.PrintWarn(formatted)
  return formatted
end

--- Capture a pcall failure for a Blizzard frame hook / attach.
--- Surfaces: "ForeverDeck: HUD failed to attach X because Y"
function ns.Error:AttachFailed(moduleName, targetName, err)
  local why = tostring(err or "unknown")
  local chat = string.format(
    "ForeverDeck: %s failed to attach %s because %s",
    tostring(moduleName or "HUD"),
    tostring(targetName or "?"),
    why
  )
  recordError("attach", moduleName, "attach:" .. tostring(targetName), why, false)
  ns.PrintError(chat)
  return chat
end

--- Run fn under pcall; on failure AttachFailed and return false, err.
function ns.Error:SafeAttach(moduleName, targetName, fn)
  local ok, err = pcall(fn)
  if not ok then
    self:AttachFailed(moduleName, targetName, err)
    return false, err
  end
  return true
end

---------------------------------------------------------------------------
-- Module state helpers
---------------------------------------------------------------------------

function ns.SetModuleState(name, status, detail)
  ns.moduleState[name] = {
    status = status, -- "pending" | "ok" | "disabled" | "failed" | "soft-missing"
    detail = detail,
    at = (GetServerTime and GetServerTime()) or time(),
  }
end

function ns.GetModuleState(name)
  return ns.moduleState[name]
end

---------------------------------------------------------------------------
-- Client / Blizzard API validation
---------------------------------------------------------------------------

-- Frames/APIs the Deck HUD expects on Forever (Mainline-family).
local REQUIRED_GLOBALS = {
  { name = "UIParent", kind = "frame" },
  { name = "CreateFrame", kind = "api" },
  { name = "GetBuildInfo", kind = "api" },
  { name = "UnitHealth", kind = "api" },
  { name = "UnitExists", kind = "api" },
}

local REQUIRED_FRAMES_FOR_HUD = {
  "PlayerFrame",
  "TargetFrame",
}

local OPTIONAL_FRAMES = {
  "MicroButtonAndBagsBar",
  "BagsBar",
  "MainMenuBar",
  "ObjectiveTrackerFrame",
  "QuestObjectiveTracker",
  "MinimapCluster",
  "BuffFrame",
  "PlayerCastingBarFrame",
  "CastingBarFrame",
}

local function resolveGlobal(name)
  return _G[name]
end

function ns.ValidateClient(phase)
  phase = phase or "ValidateClient"
  local missing = {}
  local build = ns.GetInterfaceBuild()
  local iface = build.interface

  if type(iface) ~= "number" then
    table.insert(missing, "GetBuildInfo() interface (toc version)")
  elseif iface < ns.FOREVER_INTERFACE_MIN or iface >= ns.FOREVER_INTERFACE_MAX then
    ns.Error:Warn(
      "Core",
      phase,
      string.format(
        "interface %s outside Forever range [%d, %d); modules may misbehave",
        tostring(iface),
        ns.FOREVER_INTERFACE_MIN,
        ns.FOREVER_INTERFACE_MAX
      )
    )
  end

  for _, item in ipairs(REQUIRED_GLOBALS) do
    local g = resolveGlobal(item.name)
    if g == nil then
      table.insert(missing, string.format("%s (%s)", item.name, item.kind))
    end
  end

  if #missing > 0 then
    local list = table.concat(missing, ", ")
    ns.Error:Raise(
      "Core",
      phase,
      "missing required Blizzard piece(s): " .. list
    )
  end

  return true, build
end

function ns.ValidateHUDFrames(phase)
  phase = phase or "ValidateHUDFrames"
  local missing = {}
  for _, name in ipairs(REQUIRED_FRAMES_FOR_HUD) do
    if resolveGlobal(name) == nil then
      table.insert(missing, name)
    end
  end
  if #missing > 0 then
    local list = table.concat(missing, ", ")
    ns.PrintError(
      string.format(
        "HUD validation failed — missing frame(s): %s",
        list
      )
    )
    recordError("validate", "HUD", phase, "missing: " .. list, true)
    -- Fatal for HUD init path: raise so geterrorhandler sees module+cause.
    ns.Error:Raise("HUD", phase, "missing required Blizzard frame(s): " .. list)
  end

  local optionalMissing = {}
  for _, name in ipairs(OPTIONAL_FRAMES) do
    if resolveGlobal(name) == nil then
      table.insert(optionalMissing, name)
    end
  end
  return true, optionalMissing
end

---------------------------------------------------------------------------
-- Soft dependencies (warn once; never hard-crash HUD)
---------------------------------------------------------------------------

local function isAddOnLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if ok then
      return loaded
    end
  end
  if IsAddOnLoaded then
    local ok, loaded = pcall(IsAddOnLoaded, name)
    if ok then
      return loaded
    end
  end
  return false
end

function ns.WarnSoftDepOnce(addonName, purpose)
  if ns._softDepWarned[addonName] then
    return
  end
  if isAddOnLoaded(addonName) then
    return
  end
  ns._softDepWarned[addonName] = true
  ns.Error:Warn(
    "Core",
    "SoftDep",
    string.format(
      "%s not loaded — %s will idle (HUD continues)",
      addonName,
      purpose or "dependent feature"
    )
  )
end

---------------------------------------------------------------------------
-- Safe module init wrapper
---------------------------------------------------------------------------

local function initModule(name, mod, enabled)
  if not mod then
    ns.SetModuleState(name, "failed", "module table missing")
    ns.Error:Warn("Core", "InitModule", name .. " module table missing")
    return
  end
  if not enabled then
    ns.SetModuleState(name, "disabled", "profile flag off")
    return
  end
  if type(mod.Init) ~= "function" then
    ns.SetModuleState(name, "failed", "Init missing")
    ns.Error:Warn("Core", "InitModule", name .. ".Init missing")
    return
  end

  ns.SetModuleState(name, "pending", "Init starting")
  local ok, err = pcall(function()
    mod:Init()
  end)
  if not ok then
    ns.SetModuleState(name, "failed", tostring(err))
    -- Surface clearly; do not rethrow into other modules.
    ns.PrintError(string.format("%s Init failed: %s", name, tostring(err)))
    recordError("init", name, "Init", err, true)
    return
  end

  local state = ns.moduleState[name]
  if not state or state.status == "pending" then
    ns.SetModuleState(name, "ok", "Init completed")
  end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function dumpStatus(verbose)
  local build = ns.GetInterfaceBuild()
  ns.Print(string.format(
    "v%s iface=%s build=%s forever=%s",
    ns.VERSION,
    tostring(build.interface),
    tostring(build.build),
    tostring(ns.IsForeverClient())
  ))
  if ns.db and ns.db.profile then
    local p = ns.db.profile
    ns.Print(string.format(
      "flags hud=%s path=%s shaman=%s scale=%.2f",
      tostring(p.hudEnabled),
      tostring(p.restedXPPathEnabled),
      tostring(p.shamanPvEEnabled),
      tonumber(p.hudScale) or 1
    ))
  else
    ns.Print("db not loaded")
  end

  local names = { "HUD", "RestedXPPath", "ShamanPvE" }
  for _, name in ipairs(names) do
    local st = ns.moduleState[name]
    if st then
      ns.Print(string.format(
        "module %s: %s%s",
        name,
        tostring(st.status),
        st.detail and (" — " .. tostring(st.detail)) or ""
      ))
    else
      ns.Print(string.format("module %s: (no state)", name))
    end
  end

  if verbose then
    ns.Print(string.format("lastErrors=%d (newest last)", #ns.lastErrors))
    for i, e in ipairs(ns.lastErrors) do
      ns.Print(string.format(
        "  [%d] %s %s:%s %s%s",
        i,
        tostring(e.kind),
        tostring(e.module),
        tostring(e.func),
        tostring(e.message),
        e.fatal and " [fatal]" or ""
      ))
    end
    if #ns.lastErrors == 0 then
      ns.Print("  (none)")
    end

    -- Optional frame presence (Forever API gap probe)
    local present, absent = {}, {}
    for _, name in ipairs(OPTIONAL_FRAMES) do
      if resolveGlobal(name) ~= nil then
        table.insert(present, name)
      else
        table.insert(absent, name)
      end
    end
    ns.Print("optional frames present: " .. (#present > 0 and table.concat(present, ", ") or "(none)"))
    ns.Print("optional frames absent: " .. (#absent > 0 and table.concat(absent, ", ") or "(none)"))
    ns.Print("RestedXP loaded: " .. tostring(isAddOnLoaded("RestedXP")))
  end
end

local function handleSlash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "" or msg == "help" then
    ns.Print("/foreverdeck status | debug | hud | path | shaman")
    ns.Print("aliases: /fdeck /fd")
    return
  end
  if msg == "status" then
    dumpStatus(false)
    return
  end
  if msg == "debug" then
    dumpStatus(true)
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

SLASH_FOREVERDECK1 = "/foreverdeck"
SLASH_FOREVERDECK2 = "/fdeck"
SLASH_FOREVERDECK3 = "/fd"
SlashCmdList.FOREVERDECK = handleSlash

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "ForeverDeckEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    local ok, err = pcall(function()
      ForeverDeckDB = ForeverDeckDB or copyDefaults(defaults)
      ForeverDeckDB = deepMerge(ForeverDeckDB, defaults)
      ns.db = ForeverDeckDB
      ns.ValidateClient("ADDON_LOADED")
      ns.Print(string.format("loaded v%s", ns.VERSION))
    end)
    if not ok then
      -- Never silent on init failure.
      ns.PrintError("ADDON_LOADED init failed: " .. tostring(err))
      recordError("lifecycle", "Core", "ADDON_LOADED", err, true)
      -- Re-raise for geterrorhandler / BugGrabber-style tools.
      error(ns.Error:Format("Core", "ADDON_LOADED", err), 0)
    end
  elseif event == "PLAYER_LOGIN" then
    local ok, err = pcall(function()
      ns.ValidateClient("PLAYER_LOGIN")

      -- Soft-deps: warn once, never block HUD.
      ns.WarnSoftDepOnce("RestedXP", "path overlay (Phase 2)")

      local profile = ns.db and ns.db.profile
      initModule("HUD", ns.HUD, profile and profile.hudEnabled)
      initModule("RestedXPPath", ns.RestedXPPath, profile and profile.restedXPPathEnabled)
      initModule("ShamanPvE", ns.ShamanPvE, profile and profile.shamanPvEEnabled)
    end)
    if not ok then
      ns.PrintError("PLAYER_LOGIN init failed: " .. tostring(err))
      recordError("lifecycle", "Core", "PLAYER_LOGIN", err, true)
      error(ns.Error:Format("Core", "PLAYER_LOGIN", err), 0)
    end
  end
end)
