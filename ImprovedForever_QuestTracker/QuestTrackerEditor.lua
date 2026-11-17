-- The Quest Tracker tab, a tab of settings (IF.SettingsPage, SettingsPage.lua):
-- how the quest tracker sorts (Sort.lua) and the objective sound
-- (ObjectiveSound.lua). The same as the tracker's own sort menu (the filter
-- button on its Quests header, or R3 while it has the controller).
local IF = ImprovedForever

local IQT = IF.QuestTracker
local menu = IF.Menu
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

-- One of a list of { id, text } (IQT.SORTS, IQT.COMPLETED) on a setting
local function Choice(list, key, label, set)
    return {
        value = function() return IQT.Settings()[key] end,
        text = function()
            for _, e in ipairs(list) do
                if e.id == IQT.Settings()[key] then return e.text end
            end
            return tostring(IQT.Settings()[key])
        end,
        options = function()
            local options = {}
            for _, e in ipairs(list) do options[#options + 1] = { action = e.id, name = e.text } end
            return options
        end,
        choose = function(id)
            set(id)
            for _, e in ipairs(list) do
                if e.id == id then menu.Toast(label .. ": " .. e.text) end
            end
        end,
    }
end

local ITEMS = {
    Item({
        key = "sort", group = "sort", label = "Sort quests",
        tip = "The order of the tracked quests. Off keeps the game's own. By distance (WoW Forever) keeps the"
            .. " nearest on top as you move. When the tracker is full, the quests it shows are the top-sorted ones.",
    }, Choice(IQT.SORTS, "sort", "Sort quests", function(id) IQT.SetSort(id) end)),
    Item({
        key = "zoneFirst", group = "sort", label = "Current zone first",
        tip = "Quests in the zone you are in come before the others, whatever the sort.",
    }, OnOff(function() return IQT.Settings().currentZoneFirst end,
        function(on) IQT.SetCurrentZoneFirst(on) end, "Current zone first")),
    Item({
        key = "focusFirst", group = "sort", label = "Focused quest on top",
        tip = "The quest you focus (super-track) is always first.",
    }, OnOff(function() return IQT.Settings().focusFirst end,
        function(on) IQT.SetFocusFirst(on) end, "Focused quest on top")),
    Item({
        key = "completed", group = "sort", label = "Completed quests",
        tip = "Where quests ready to turn in go.",
    }, Choice(IQT.COMPLETED, "sortCompleted", "Completed quests", function(id) IQT.SetSortCompleted(id) end)),
    Item({
        key = "sound", group = "sound", label = "Objective complete",
        tip = "Plays a sound when an objective of a tracked quest completes.",
    }, OnOff(function() return IQT.Settings().objectiveSound end,
        function(on) IQT.SetObjectiveSound(on) end, "Objective sound")),
    Item({
        key = "rxpGuide", group = "rxp", label = "RestedXP leveling steps",
        tip = "When RXPGuides is loaded, show active leveling steps as tracker blocks above Blizzard quest watches. Soft dependency: safe if RestedXP is missing.",
    }, OnOff(function() return IQT.Settings().rxpGuide end,
        function(on) IQT.SetRXPGuide(on) end, "RestedXP leveling steps")),
    Item({
        key = "rxpProfession", group = "rxp", label = "RestedXP profession steps",
        tip = "Profession guides (#guideKind profession / Profession group): active steps or saved-progress glance. Soft-deps on RXPGuides + optional profession packs.",
    }, OnOff(function() return IQT.Settings().rxpProfession end,
        function(on) IQT.SetRXPProfession(on) end, "RestedXP profession steps")),
    Item({
        key = "rxpDungeon", group = "rxp", label = "RestedXP dungeon steps",
        tip = "Dungeon guides (e.g. RestedXP Forever Dungeon Guide group, #guideKind dungeon, .enabledungeon steps): active or progress glance.",
    }, OnOff(function() return IQT.Settings().rxpDungeon end,
        function(on) IQT.SetRXPDungeon(on) end, "RestedXP dungeon steps")),
    Item({
        key = "rxpLegacy", group = "rxp", label = "RestedXP legacy steps",
        tip = "Legacy guides (group/name contains Legacy, or #guideKind legacy) when RXP ships or you import them.",
    }, OnOff(function() return IQT.Settings().rxpLegacy end,
        function(on) IQT.SetRXPLegacy(on) end, "RestedXP legacy steps")),
    Item({
        key = "rxpWaypoint", group = "rxp", label = "Sync Blizzard waypoint",
        tip = "Mirror the RestedXP arrow target into the Blizzard user waypoint so Forever gamepad navigation points at the same place.",
    }, OnOff(function() return IQT.Settings().rxpWaypoint end,
        function(on) IQT.SetRXPWaypoint(on) end, "RestedXP waypoint sync")),
    Item({
        key = "rxpQuestFocus", group = "rxp", label = "SuperTrack matching quest",
        tip = "When an RXP step exposes a questId that is in your log, SuperTrack that quest so Immersion / quest focus stay aligned. Off by default to avoid fighting manual focus.",
    }, OnOff(function() return IQT.Settings().rxpQuestFocus end,
        function(on) IQT.SetRXPQuestFocus(on) end, "RestedXP quest SuperTrack")),
}

local GROUPS = {
    { key = "sort", label = "Sorting" },
    { key = "sound", label = "Sound" },
    { key = "rxp", label = "RestedXP" },
}

IF.QuestTrackerEditor = IF.SettingsPage({ key = "quests", label = "Quest Tracker", module = "quests", order = 45 },
    GROUPS, ITEMS)
