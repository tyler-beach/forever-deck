-- Improved Forever's core: the namespace every module shares. The core
-- addon (this folder) holds what more than one feature needs: the pad's
-- glyphs, ConfigKit, the bindings (Binds.lua), the window (Window.lua) and
-- the configuration panel (Menu.lua). Each feature is its own addon
-- (ImprovedForever_Wheel, ImprovedForever_Auction...), loaded after this
-- one, reaching it through the global ImprovedForever:
--   local IF = ImprovedForever
-- A module says it is there with IF.AddModule; one asks after another with
-- IF.Has("Auction") (or by the table it leaves, IF.Auction) before using it.
local addonName, IF = ...

ImprovedForever = IF
IF.name = addonName
IF.TITLE = "Improved Forever"
IF.TEX = "Interface\\AddOns\\ImprovedForever\\textures\\"

-- The R3 combos: what the wheels open on (ImprovedForever_Wheel), and the
-- bindings' shape for "a shoulder / trigger held + R3" (Binds.lua)
IF.COMBOS = { "R3", "L1", "L2", "R1", "R2" }
IF.COMBO_LABELS = { R3 = "R3", L1 = "L1 + R3", L2 = "L2 + R3", R1 = "R1 + R3", R2 = "R2 + R3" }

function IF.Print(msg)
    print("|cff33ccffImprovedForever|r: " .. tostring(msg))
end

function IF.InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

-- Called after anything that changes what the rings hold (the Wheel
-- module answers it)
function IF.RefreshRings()
    if IF.QueueRingRebuild then
        IF.QueueRingRebuild()
    end
end

---------------------------------------------------------------------------
-- Modules: { key, label, icon, addon } in the order they loaded
---------------------------------------------------------------------------
IF.modules = {}
local byKey = {}

-- The Controller module is the core's since 0.8.0 (its tab: Bindings): an
-- old copy still installed is turned off for the next login, said once;
-- loaded meanwhile, its module and tab are left out (Menu.lua, Binds.lua)
local OLD_CONTROLLER = "ImprovedForever_Controller"
IF.OLD_CONTROLLER = OLD_CONTROLLER
local addons = _G.C_AddOns
if addons and addons.DoesAddOnExist and addons.DoesAddOnExist(OLD_CONTROLLER) and addons.DisableAddOn then
    pcall(addons.DisableAddOn, OLD_CONTROLLER)
    IF.oldController = true
end

-- Gather became Minimap in 0.7.0: an old Gather still installed beside it is
-- turned off for the next login, said once; loaded meanwhile, its module,
-- tab and binding are left out (Menu.lua, Binds.lua). (Without Minimap
-- installed, it's left alone, its settings too.)
local OLD_GATHER = "ImprovedForever_Gather"
if addons and addons.DoesAddOnExist and addons.DoesAddOnExist(OLD_GATHER)
    and addons.DoesAddOnExist("ImprovedForever_Minimap") and addons.DisableAddOn then
    pcall(addons.DisableAddOn, OLD_GATHER)
    IF.oldGather = true
end

-- Immersion spell diamonds: after a mid-load abort WoW leaves Immersion
-- unchecked at character select, and Deck users stay on Blizzard's radial
-- bar. Re-enable Immersion (and Journal when present) as soon as Core loads
-- so the next login / our one-shot reload picks them up without a slash.
local IMMERSION_ADDON = "ImprovedForever_Immersion"
local JOURNAL_ADDON = "ImprovedForever_Journal"
local function EnableAddonFolder(name)
    if not (addons and addons.DoesAddOnExist and addons.DoesAddOnExist(name) and addons.EnableAddOn) then
        return false
    end
    pcall(addons.EnableAddOn, name)
    local player = UnitName and UnitName("player")
    if type(player) == "string" and player ~= "" then
        pcall(addons.EnableAddOn, player, name)
    end
    return true
end
if addons then
    EnableAddonFolder(JOURNAL_ADDON)
    EnableAddonFolder(IMMERSION_ADDON)
end

function IF.AddModule(def)
    if def.addon == OLD_CONTROLLER or (IF.oldGather and def.addon == OLD_GATHER) then return def end
    if byKey[def.key] then return byKey[def.key] end
    IF.modules[#IF.modules + 1] = def
    byKey[def.key] = def
    return def
end

function IF.Has(key)
    return byKey[key] ~= nil
end

function IF.Module(key)
    return byKey[key]
end

---------------------------------------------------------------------------
-- Slash commands: /if <command> ...; a module adds its own
---------------------------------------------------------------------------
local commands, commandOrder = {}, {}

-- fn(args, msg): args the words after the command (lower case), msg the
-- whole line as typed (its links intact)
function IF.AddCommand(name, fn, help)
    if not commands[name] then commandOrder[#commandOrder + 1] = name end
    commands[name] = { fn = fn, help = help }
end

function IF.RunCommand(msg)
    local words = { strsplit(" ", strtrim(msg or ""):lower()) }
    local name = table.remove(words, 1)
    local command = commands[name or ""]
    if command then return command.fn(words, msg) end
    if name == "help" then
        for _, key in ipairs(commandOrder) do
            local help = commands[key].help
            if help then IF.Print("/if " .. key .. ((help == "" or help:sub(1, 1) == ":") and "" or " ") .. help) end
        end
        return
    end
    if IF.Menu then IF.Menu.Toggle() end
end

SLASH_IMPROVEDFOREVER1 = "/if"
SLASH_IMPROVEDFOREVER2 = "/improvedforever"
SLASH_IMPROVEDFOREVER3 = "/improvedcontroller" -- its name before 0.3.0
SlashCmdList.IMPROVEDFOREVER = IF.RunCommand

-- A protected call of ours the game blocked: which one, said in chat (the
-- game's own dialog doesn't). Any of our addons.
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, event, addon, func)
    if type(addon) == "string" and addon:find("^ImprovedForever") then
        IF.Print((event == "ADDON_ACTION_FORBIDDEN" and "forbidden: " or "blocked: ") .. tostring(func)
            .. (addon ~= addonName and (" (" .. addon .. ")") or ""))
    end
end)

---------------------------------------------------------------------------
-- Saved variables: ImprovedForeverDB (account), ImprovedForeverCharDB (per
-- character); a module keeps its settings in a table of its own in them
---------------------------------------------------------------------------
local loginCallbacks = {}

-- Runs after saved variables are ready (every module has loaded by then).
function IF.OnLogin(fn)
    table.insert(loginCallbacks, fn)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    -- (no saved file yet: a first install, told apart from an update; WhatsNew.lua)
    IF.freshInstall = ImprovedForeverDB == nil
    ImprovedForeverDB = ImprovedForeverDB or {}
    IF.db = ImprovedForeverDB
    ImprovedForeverCharDB = ImprovedForeverCharDB or {}
    IF.charDB = ImprovedForeverCharDB
    -- The Library module became the Wiki, and Gather the Minimap (when it's
    -- installed): their settings and key bindings, and the places a binding
    -- is kept (wheels, combos), move over
    local db = IF.db
    local renames = { library = "wiki" }
    local A = _G.C_AddOns
    if A and A.DoesAddOnExist and A.DoesAddOnExist("ImprovedForever_Minimap") then
        renames.gather = "minimap"
        -- (an old Gather loaded with it writes its own again: dropped next time)
        if db.gather ~= nil then
            if db.minimap == nil then db.minimap = db.gather end
            db.gather = nil
        end
        if db.gatherKey ~= nil then
            if db.minimapKey == nil then db.minimapKey = db.gatherKey end
            db.gatherKey = nil
        end
    end
    if db.library ~= nil and db.wiki == nil then db.wiki, db.library = db.library, nil end
    local function Rename(t, seen)
        if type(t) ~= "table" or seen[t] then return end
        seen[t] = true
        for old, new in pairs(renames) do
            if t[old] ~= nil and t[new] == nil then t[new], t[old] = t[old], nil end
        end
        for k, v in pairs(t) do
            if type(v) == "string" and renames[v] then t[k] = renames[v] else Rename(v, seen) end
        end
    end
    Rename(db.keyBinds, {}); Rename(db.combos, {}); Rename(db.wheelKeys, {})
    Rename(IF.charDB.wheels, {}); Rename(IF.charDB.recent, {})
    for _, fn in ipairs(loginCallbacks) do
        fn()
    end
    if IF.oldController then
        IF.Print("Improved Forever: Controller is now part of the core (its tab: Bindings) and has been"
            .. " turned off; remove it from your AddOns folder or CurseForge.")
    end
    if IF.oldGather then
        IF.Print("Improved Forever: Gather is now Improved Forever: Minimap and has been turned off;"
            .. " remove it from your AddOns folder or CurseForge.")
    end
    -- Auto-recover Immersion so Deck gets spell diamonds without /if immersion enable.
    do
        local A = _G.C_AddOns
        local name = IMMERSION_ADDON
        if A and A.DoesAddOnExist and A.DoesAddOnExist(name)
            and A.IsAddOnLoaded and not A.IsAddOnLoaded(name) then
            EnableAddonFolder(JOURNAL_ADDON)
            EnableAddonFolder(name)
            local loaded = false
            if A.LoadAddOn then
                pcall(A.LoadAddOn, name)
                loaded = A.IsAddOnLoaded(name)
            elseif _G.LoadAddOn then
                pcall(_G.LoadAddOn, name)
                loaded = A.IsAddOnLoaded(name)
            end
            if loaded then
                IF.Print("Immersion loaded - spell diamonds should appear.")
            else
                -- One reload per core version after EnableAddOn (disabled addons
                -- cannot LoadAddOn mid-session). Stops reload loops.
                local stamp = "0.19.2"
                if IF.db.immersionAutoFix ~= stamp then
                    IF.db.immersionAutoFix = stamp
                    IF.Print("Immersion was disabled; enabling spell diamonds and reloading once...")
                    if C_Timer and C_Timer.After and ReloadUI then
                        C_Timer.After(0.4, ReloadUI)
                    elseif ReloadUI then
                        ReloadUI()
                    end
                else
                    IF.Print("Immersion still not loaded after auto-enable. Character select > AddOns > ImprovedForever_Immersion. /if immersion")
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- /if immersion [status|enable]: why diamonds are missing; enable + reload
---------------------------------------------------------------------------
local function AddonState(name)
    local A = _G.C_AddOns
    if not (A and A.DoesAddOnExist) then return "no C_AddOns" end
    if not A.DoesAddOnExist(name) then return "missing (not installed)" end
    local loaded = A.IsAddOnLoaded and A.IsAddOnLoaded(name)
    if loaded then return "loaded" end
    local enabled
    if A.GetAddOnEnableState then
        -- 0 = disabled, 1/2 = enabled for some/all characters (API varies by client)
        local ok, state = pcall(A.GetAddOnEnableState, name, UnitName("player"))
        if not ok then ok, state = pcall(A.GetAddOnEnableState, UnitName("player"), name) end
        if ok and type(state) == "number" then enabled = state > 0 end
    end
    if enabled == false then return "installed, DISABLED at character select" end
    local reason
    if A.GetAddOnMetadata then
        -- LoadReason / reason string when enable fails (missing dep)
        local ok, why = pcall(function()
            if A.IsAddOnLoadOnDemand then
                -- GetAddOnInfo returns reason as 5th/6th depending on client
            end
            local info = { A.GetAddOnInfo(name) }
            return info[5] or info[6]
        end)
        if ok and type(why) == "string" and why ~= "" and why ~= "ENABLED" then reason = why end
    end
    if reason then return "installed, not loaded (" .. reason .. ")" end
    return "installed, not loaded"
end

IF.AddCommand("immersion", function(args)
    local sub = args[1] and args[1]:lower() or "status"
    local A = _G.C_AddOns
    local name = IMMERSION_ADDON
    if sub == "enable" or sub == "on" or sub == "fix" then
        if not (A and A.DoesAddOnExist and A.DoesAddOnExist(name)) then
            return IF.Print("Immersion folder missing - update forever-deck (All-forever zip).")
        end
        EnableAddonFolder(JOURNAL_ADDON)
        EnableAddonFolder(name)
        if A and A.DoesAddOnExist("Spoken") then EnableAddonFolder("Spoken") end
        IF.db.immersionAutoFix = nil
        IF.Print("Immersion enabled. Reloading...")
        if ReloadUI then ReloadUI() end
        return
    end
    IF.Print("Immersion: " .. AddonState(name))
    IF.Print("Journal (optional): " .. AddonState(JOURNAL_ADDON))
    IF.Print("Spoken (optional): " .. AddonState("Spoken"))
    if IF.Interface and IF.Interface.GamepadBar then
        local main = _G.GamepadMainActionBarFrame
        local holder = _G.ImprovedForeverGamepadBar
        IF.Print(("GamepadBar loaded | GamepadMain visible=%s | diamondsShown=%s"):format(
            tostring(main and main:IsVisible() or false),
            tostring(holder and holder:IsShown() or false)
        ))
        IF.Print("/if pad diamond to force diamonds")
    else
        IF.Print("Diamonds need Immersion loaded. Update forever-deck; Core auto-enables Immersion on login.")
    end
end, "[status|enable]: Immersion load state; enable + /reload for spell diamonds")
