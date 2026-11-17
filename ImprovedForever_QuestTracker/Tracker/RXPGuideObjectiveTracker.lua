-- RestedXP → ImprovedForever Quest Tracker bridge.
-- Soft-depends on RXPGuides (+ optional profession packs): active leveling
-- steps and profession-guide steps appear as native IF objective-tracker
-- modules above Blizzard quest watches.
-- Does not write into IFQuestCache / Blizzard quest objects (taint-safe).
-- Guide step text is display-only at runtime; never persisted to SavedVariables.

local addonName, IQT = ...
local IF = ImprovedForever

local MODULE = "RXPGuide"
local MODULE_PROF = "RXPProfession"
local MAX_STEPS = 3
local MAX_OBJECTIVES = 8
local MAX_PROF_GUIDES = 2
local TICK_SECONDS = 0.5

-- Soft-dep folder names for profession guide packs (plus RXPGuides itself,
-- which ships free Herbalism/Mining/Skinning on Classic TOC; Forever packs
-- often arrive via /rxp import into RXPGuides or a shop zip).
local PROFESSION_PACK_ADDONS = {
	"RXPGuides",
	"RXPGuides_Professions",
	"RXPGuides_Profession",
	"RXP_Professions",
	"RXP_Profession",
	"RestedXP_Professions",
	"RestedXP_Profession",
	"RXPProfessionGuides",
	"RXPGuides_ProfessionLeveling",
}

local levelSettings = {
	headerText = "RestedXP Guide",
	events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
	blockTemplate = "IFObjectiveTrackerAnimBlockTemplate",
	lineTemplate = "IFObjectiveTrackerAnimLineTemplate",
	hasDisplayPriority = true,
}

local profSettings = {
	headerText = "RestedXP Profession",
	events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW" },
	blockTemplate = "IFObjectiveTrackerAnimBlockTemplate",
	lineTemplate = "IFObjectiveTrackerAnimLineTemplate",
	hasDisplayPriority = true,
}

IFRXPGuideObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, levelSettings)
IFRXPProfessionObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, profSettings)

local reportedMissing
local reportedApi
local reportedProfApi
local lastLevelSignature
local lastProfSignature
local lastWaypointKey
local ticker
local detectedPacksCache
local detectedPacksAt

local function ChatError(moduleName, cause, hint)
	local msg = ("|cffff6666Improved Forever Quest Tracker [%s]:|r %s"):format(moduleName, cause)
	if hint then
		msg = msg .. " — " .. hint
	end
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function IsAddOnLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	if _G.IsAddOnLoaded then
		return _G.IsAddOnLoaded(name)
	end
	return false
end

function IQT.RXPAvailable()
	return _G.RXPFrame ~= nil or _G.RXPGuides ~= nil or _G.RXPG_ARROW ~= nil or _G.RXP ~= nil
end

function IQT.RXPHasApi()
	local frame = _G.RXPFrame
	return type(frame) == "table" and type(frame.activeSteps) == "table"
end

-- Private RXP addon table (Ace); exposed as _G.RXP for debug in upstream.
local function GetRXPAddon()
	if type(_G.RXP) == "table" and (type(_G.RXP.guides) == "table" or _G.RXP.currentGuide) then
		return _G.RXP
	end
	local pub = _G.RXPGuides
	if type(pub) == "table" and type(pub.guides) == "table" then
		return pub
	end
	return nil
end

local function GuideEnabled()
	return IQT.Settings().rxpGuide ~= false
end

local function ProfessionEnabled()
	return IQT.Settings().rxpProfession ~= false
end

local function StripNewlines(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:gsub("[\r\n]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
	if not text or text == "" or text == " " then
		return nil
	end
	return text
end

local function ElementLineText(element)
	if not element or element.hideTooltip then
		return nil
	end
	local text = element.tooltipText or element.rawtext or element.text
	return StripNewlines(text)
end

local function StepTitle(step, index)
	if type(step.title) == "string" and step.title ~= "" then
		return step.title
	end
	local idx = tonumber(step.index) or index
	return ("Step %d"):format(idx or index)
end

local function StepIsShown(step)
	if type(step) ~= "table" then
		return false
	end
	if step.hidewindow or step.hidetip or step.inactive then
		return false
	end
	return true
end

local function GuideIsProfession(guide)
	if type(guide) ~= "table" then
		return false
	end
	local kind = guide.guideKind or guide.kind
	if type(kind) == "string" and kind:lower() == "profession" then
		return true
	end
	local group = guide.group or guide.groupdisplayname or ""
	if type(group) == "string" and group:lower():find("profession", 1, true) then
		return true
	end
	return false
end

local function StepIsProfession(step)
	if type(step) ~= "table" then
		return false
	end
	if step.profession or step.professionskip then
		return true
	end
	return GuideIsProfession(step.guide)
end

function IQT.RXPDetectProfessionPacks(force)
	local now = GetTime and GetTime() or 0
	if not force and detectedPacksCache and detectedPacksAt and (now - detectedPacksAt) < 5 then
		return detectedPacksCache
	end
	local found = {}
	for _, name in ipairs(PROFESSION_PACK_ADDONS) do
		if IsAddOnLoaded(name) then
			found[#found + 1] = name
		end
	end
	-- Guides registered in RXP with #guideKind profession (bundled or /rxp import).
	local rxp = GetRXPAddon()
	local registered = 0
	if rxp and type(rxp.guides) == "table" then
		for _, guide in pairs(rxp.guides) do
			if GuideIsProfession(guide) then
				registered = registered + 1
			end
		end
	end
	detectedPacksCache = {
		addons = found,
		registeredProfessionGuides = registered,
		rxpAddonTable = rxp ~= nil,
		hasGuideProgressApi = rxp ~= nil and type(rxp.GetGuideProgress) == "function",
	}
	detectedPacksAt = now
	return detectedPacksCache
end

local function MaybeReportMissing()
	if reportedMissing or not (GuideEnabled() or ProfessionEnabled()) then
		return
	end
	if IQT.RXPAvailable() then
		return
	end
	reportedMissing = true
	ChatError(
		MODULE,
		"RXPGuides is not loaded",
		"Enable RXPGuides in the AddOns list, or disable with /if quests rxp off"
	)
end

local function MaybeReportApi()
	if reportedApi or not GuideEnabled() or not IQT.RXPAvailable() then
		return
	end
	if IQT.RXPHasApi() then
		return
	end
	reportedApi = true
	ChatError(
		MODULE,
		"RXPGuides is loaded but RXPFrame.activeSteps is missing",
		"Update RestedXP Guides, or disable with /if quests rxp off"
	)
end

local function MaybeReportProfApi()
	if reportedProfApi or not ProfessionEnabled() or not IQT.RXPAvailable() then
		return
	end
	local det = IQT.RXPDetectProfessionPacks()
	if det.rxpAddonTable and det.hasGuideProgressApi then
		return
	end
	-- Profession glance needs the private addon table; activeSteps still works for a loaded profession guide.
	if IQT.RXPHasApi() then
		return
	end
	reportedProfApi = true
	ChatError(
		MODULE_PROF,
		"Profession glance API missing (RXP.guides / GetGuideProgress)",
		"Load a profession guide in RXP, or update RestedXP; /if quests rxp profession off to hide"
	)
end

local function CollectActiveStepsFiltered(wantProfession)
	local frame = _G.RXPFrame
	if type(frame) ~= "table" or type(frame.activeSteps) ~= "table" then
		return nil, "api"
	end
	local out = {}
	for i, step in ipairs(frame.activeSteps) do
		if StepIsShown(step) and StepIsProfession(step) == wantProfession then
			out[#out + 1] = step
			if #out >= MAX_STEPS then
				break
			end
		end
	end
	return out
end

-- When leveling is the current guide, also surface the current step of any
-- profession guide that has saved progress (RXPCData.guideProgress).
local function CollectProfessionGlanceSteps(excludeKeys)
	excludeKeys = excludeKeys or {}
	local rxp = GetRXPAddon()
	if not rxp or type(rxp.guides) ~= "table" then
		MaybeReportProfApi()
		return {}
	end
	if type(rxp.GetGuideProgress) ~= "function" then
		MaybeReportProfApi()
		return {}
	end

	local progressDB = type(RXPCData) == "table" and type(RXPCData.guideProgress) == "table" and RXPCData.guideProgress
	local out = {}
	local seen = 0

	for _, guide in pairs(rxp.guides) do
		if seen >= MAX_PROF_GUIDES then
			break
		end
		if GuideIsProfession(guide) and guide.key and not excludeKeys[guide.key] and not guide.empty and not guide.disabled then
			local hasProgress = progressDB and progressDB[guide.key]
			local isCurrent = rxp.currentGuide == guide
			if hasProgress or isCurrent then
				local stepIndex = rxp.GetGuideProgress(guide)
				stepIndex = tonumber(stepIndex) or 1
				local step = guide.steps and guide.steps[stepIndex]
				if type(step) == "table" and StepIsShown(step) then
					-- Attach guide ref if missing so titles/headers work.
					if not step.guide then
						step.guide = guide
					end
					out[#out + 1] = step
					seen = seen + 1
				end
			end
		end
	end
	return out
end

local function CollectProfessionSteps()
	local fromActive, err = CollectActiveStepsFiltered(true)
	if err == "api" then
		return nil, "api"
	end
	fromActive = fromActive or {}

	local exclude = {}
	for _, step in ipairs(fromActive) do
		local g = step.guide
		if g and g.key then
			exclude[g.key] = true
		end
	end

	-- If the loaded guide is already a profession guide, activeSteps cover it.
	local rxp = GetRXPAddon()
	if rxp and GuideIsProfession(rxp.currentGuide) then
		return fromActive
	end

	local glance = CollectProfessionGlanceSteps(exclude)
	for _, step in ipairs(glance) do
		if #fromActive >= MAX_STEPS then
			break
		end
		fromActive[#fromActive + 1] = step
	end
	return fromActive
end

local function CollectLevelingSteps()
	return CollectActiveStepsFiltered(false)
end

local function StepSignature(steps, prefix)
	if not steps then
		return (prefix or "") .. "none"
	end
	local parts = { prefix or "" }
	for i, step in ipairs(steps) do
		local idx = tostring(step.index or step.stepId or i)
		local title = tostring(step.title or "")
		local gkey = step.guide and tostring(step.guide.key or step.guide.name or "") or ""
		local n = 0
		for _, el in ipairs(step.elements or {}) do
			if ElementLineText(el) then
				n = n + 1
			end
		end
		parts[#parts + 1] = idx .. ":" .. title .. ":" .. gkey .. ":" .. n
	end
	return table.concat(parts, "|")
end

local function SyncBlizzardWaypoint()
	local db = IQT.Settings()
	if not db.rxpWaypoint then
		return
	end
	local arrow = _G.RXPG_ARROW
	local el = arrow and arrow.element
	if type(el) ~= "table" then
		return
	end
	local zone, x, y = el.zone, el.x, el.y
	if type(zone) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	if not (C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(zone)) then
		return
	end
	local nx, ny = x / 100, y / 100
	local key = ("%d:%.3f:%.3f"):format(zone, nx, ny)
	if key == lastWaypointKey then
		return
	end
	lastWaypointKey = key
	if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return
	end
	local ok, err = pcall(function()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(zone, nx, ny))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
	if not ok then
		ChatError(MODULE, "Failed to set Blizzard user waypoint", tostring(err))
	end
end

local function SyncQuestFocus(steps)
	local db = IQT.Settings()
	if not db.rxpQuestFocus then
		return
	end
	if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then
		return
	end
	for _, step in ipairs(steps or {}) do
		for _, el in ipairs(step.elements or {}) do
			local qid = el.questId or el.questID
			if type(qid) == "number" and qid > 0 and C_QuestLog.GetLogIndexForQuestID(qid) then
				if C_SuperTrack.GetSuperTrackedQuestID() ~= qid then
					C_SuperTrack.SetSuperTrackedQuestID(qid)
				end
				return
			end
		end
	end
end

local function AddStepToModule(self, step, index, idOffset)
	idOffset = idOffset or 0
	local blockID = step.stepId or step.index or index
	if type(blockID) ~= "number" then
		blockID = 100000 + index + idOffset
	else
		blockID = blockID + (step.sticky and 500000 or 0) + idOffset
	end

	local block = self:GetBlock(blockID)
	local title = StepTitle(step, index)
	block.name = title
	block:SetHeader(title)

	local added = 0
	local guideName
	if type(step.guide) == "table" and type(step.guide.name) == "string" then
		guideName = step.guide.displayname or step.guide.name
	elseif type(RXPCData) == "table" and type(RXPCData.currentGuideName) == "string" then
		guideName = RXPCData.currentGuideName
	end
	if guideName and guideName ~= "" and index == 1 then
		block:AddObjective("guide", guideName, nil, nil, IF_OBJECTIVE_DASH_STYLE_HIDE, IF_OBJECTIVE_TRACKER_COLOR["Normal"])
		added = added + 1
	end

	for j, element in ipairs(step.elements or {}) do
		if added >= MAX_OBJECTIVES then
			break
		end
		local text = ElementLineText(element)
		if text then
			local complete = element.completed or element.textOnly
			local dash = complete and IF_OBJECTIVE_DASH_STYLE_HIDE or IF_OBJECTIVE_DASH_STYLE_SHOW
			local color = IF_OBJECTIVE_TRACKER_COLOR[complete and "Complete" or "Normal"]
			local line = block:AddObjective(j, text, nil, nil, dash, color)
			if line and line.Icon then
				line.Icon:SetShown(complete and true or false)
				if complete and line.Icon.SetAtlas then
					line.Icon:SetAtlas("ui-questtracker-tracker-check", false)
				end
			end
			added = added + 1
		end
	end

	if added == 0 then
		local fallback = StripNewlines(step.text) or "Follow the RestedXP step"
		block:AddObjective(1, fallback, nil, nil, IF_OBJECTIVE_DASH_STYLE_SHOW, IF_OBJECTIVE_TRACKER_COLOR["Normal"])
	end

	return self:LayoutBlock(block)
end

local function EnsureTicker()
	if ticker then
		return
	end
	ticker = C_Timer.NewTicker(TICK_SECONDS, function()
		if not IQT.RXPAvailable() then
			MaybeReportMissing()
			return
		end

		local levelDirty, profDirty = false, false

		if GuideEnabled() and IQT.RXPHasApi() then
			local steps = CollectLevelingSteps()
			local sig = StepSignature(steps, "L")
			if sig ~= lastLevelSignature then
				lastLevelSignature = sig
				levelDirty = true
				-- Waypoint/focus follow the live arrow / active leveling steps.
				SyncBlizzardWaypoint()
				SyncQuestFocus(steps)
			end
		end

		if ProfessionEnabled() then
			local steps = CollectProfessionSteps()
			local sig = StepSignature(steps, "P")
			if sig ~= lastProfSignature then
				lastProfSignature = sig
				profDirty = true
			end
		end

		if levelDirty and IFRXPGuideObjectiveTracker then
			IFRXPGuideObjectiveTracker:MarkDirty()
		end
		if profDirty and IFRXPProfessionObjectiveTracker then
			IFRXPProfessionObjectiveTracker:MarkDirty()
		end
	end)
end

---------------------------------------------------------------------------
-- Leveling module
---------------------------------------------------------------------------

function IFRXPGuideObjectiveTrackerMixin:InitModule()
	MaybeReportMissing()
	MaybeReportApi()
	IQT.RXPDetectProfessionPacks(true)
	EnsureTicker()
end

function IFRXPGuideObjectiveTrackerMixin:OnEvent(event, ...)
	self:MarkDirty()
end

function IFRXPGuideObjectiveTrackerMixin:OnBlockHeaderClick(block, mouseButton)
	if mouseButton == "RightButton" then
		IFObjectiveTrackerMenu.CreateContextMenu(self:GetContextMenuParent(), function(owner, rootDescription)
			rootDescription:SetTag("MENU_RXP_GUIDE_TRACKER")
			rootDescription:CreateTitle(block.name or "RestedXP")
			rootDescription:CreateButton("Open RestedXP window", function()
				if _G.RXPFrame and _G.RXPFrame.Show then
					_G.RXPFrame:Show()
				else
					ChatError(MODULE, "Could not open RXP window", "Use RXPGuides' own slash command")
				end
			end)
			rootDescription:CreateButton("Hide RestedXP leveling in tracker", function()
				IQT.SetRXPGuide(false)
			end)
		end)
	elseif _G.RXPFrame and _G.RXPFrame.Show then
		_G.RXPFrame:Show()
	end
end

function IFRXPGuideObjectiveTrackerMixin:LayoutContents()
	if not GuideEnabled() then
		return
	end
	if not IQT.RXPAvailable() then
		MaybeReportMissing()
		return
	end
	if not IQT.RXPHasApi() then
		MaybeReportApi()
		return
	end

	local steps = CollectLevelingSteps()
	if not steps or #steps == 0 then
		return
	end

	for i, step in ipairs(steps) do
		if not AddStepToModule(self, step, i, 0) then
			return
		end
	end
end

---------------------------------------------------------------------------
-- Profession module
---------------------------------------------------------------------------

function IFRXPProfessionObjectiveTrackerMixin:InitModule()
	MaybeReportMissing()
	MaybeReportProfApi()
	IQT.RXPDetectProfessionPacks(true)
	EnsureTicker()
end

function IFRXPProfessionObjectiveTrackerMixin:OnEvent(event, ...)
	self:MarkDirty()
end

function IFRXPProfessionObjectiveTrackerMixin:OnBlockHeaderClick(block, mouseButton)
	if mouseButton == "RightButton" then
		IFObjectiveTrackerMenu.CreateContextMenu(self:GetContextMenuParent(), function(owner, rootDescription)
			rootDescription:SetTag("MENU_RXP_PROFESSION_TRACKER")
			rootDescription:CreateTitle(block.name or "RestedXP Profession")
			rootDescription:CreateButton("Open RestedXP window", function()
				if _G.RXPFrame and _G.RXPFrame.Show then
					_G.RXPFrame:Show()
				else
					ChatError(MODULE_PROF, "Could not open RXP window", "Use RXPGuides' own slash command")
				end
			end)
			rootDescription:CreateButton("Hide RestedXP profession in tracker", function()
				IQT.SetRXPProfession(false)
			end)
		end)
	elseif _G.RXPFrame and _G.RXPFrame.Show then
		_G.RXPFrame:Show()
	end
end

function IFRXPProfessionObjectiveTrackerMixin:LayoutContents()
	if not ProfessionEnabled() then
		return
	end
	if not IQT.RXPAvailable() then
		MaybeReportMissing()
		return
	end

	local steps, err = CollectProfessionSteps()
	if err == "api" then
		MaybeReportApi()
		return
	end
	if not steps or #steps == 0 then
		return
	end

	for i, step in ipairs(steps) do
		-- Offset ids so profession blocks never collide with leveling blocks.
		if not AddStepToModule(self, step, i, 700000) then
			return
		end
	end
end

---------------------------------------------------------------------------
-- Settings / slash helpers
---------------------------------------------------------------------------

function IQT.SetRXPGuide(on)
	IQT.Settings().rxpGuide = not not on
	IQT.Refresh()
	if IFRXPGuideObjectiveTracker then
		IFRXPGuideObjectiveTracker:MarkDirty()
	end
	IQT.Print("RestedXP leveling in tracker: " .. (on and "on" or "off"))
end

function IQT.SetRXPProfession(on)
	IQT.Settings().rxpProfession = not not on
	IQT.Refresh()
	if IFRXPProfessionObjectiveTracker then
		IFRXPProfessionObjectiveTracker:MarkDirty()
	end
	IQT.Print("RestedXP profession in tracker: " .. (on and "on" or "off"))
end

function IQT.SetRXPWaypoint(on)
	IQT.Settings().rxpWaypoint = not not on
	lastWaypointKey = nil
	IQT.Print("RestedXP Blizzard waypoint sync: " .. (on and "on" or "off"))
end

function IQT.SetRXPQuestFocus(on)
	IQT.Settings().rxpQuestFocus = not not on
	IQT.Print("RestedXP quest SuperTrack when known: " .. (on and "on" or "off"))
end

function IQT.RXPDebug()
	local det = IQT.RXPDetectProfessionPacks(true)
	IQT.Print("RXP available: " .. tostring(IQT.RXPAvailable())
		.. ", activeSteps API: " .. tostring(IQT.RXPHasApi())
		.. ", leveling: " .. tostring(GuideEnabled())
		.. ", profession: " .. tostring(ProfessionEnabled()))
	IQT.Print("Profession packs loaded: "
		.. (#det.addons > 0 and table.concat(det.addons, ", ") or "(none of the known folder names)")
		.. ("; registered profession guides: " .. tostring(det.registeredProfessionGuides))
		.. ("; RXP addon table: " .. tostring(det.rxpAddonTable))
		.. ("; GetGuideProgress: " .. tostring(det.hasGuideProgressApi)))

	local level = CollectLevelingSteps()
	IQT.Print(("Leveling active steps: %d"):format(level and #level or 0))
	if level then
		for i, step in ipairs(level) do
			IQT.Print(("  L%d. %s"):format(i, StepTitle(step, i)))
		end
	end

	local prof = CollectProfessionSteps()
	IQT.Print(("Profession steps: %d"):format(prof and #prof or 0))
	if prof then
		for i, step in ipairs(prof) do
			local g = step.guide and (step.guide.displayname or step.guide.name) or "?"
			IQT.Print(("  P%d. [%s] %s"):format(i, tostring(g), StepTitle(step, i)))
		end
	end

	local el = _G.RXPG_ARROW and _G.RXPG_ARROW.element
	if el then
		IQT.Print(("Arrow: map %s @ %.1f, %.1f"):format(tostring(el.zone), tonumber(el.x) or 0, tonumber(el.y) or 0))
	else
		IQT.Print("Arrow: none")
	end
end
