-- RestedXP → ImprovedForever Quest Tracker bridge.
-- Soft-depends on RXPGuides: when loaded, active guide steps appear as a
-- native-looking IF objective-tracker module above Blizzard quest watches.
-- Does not write into IFQuestCache / Blizzard quest objects (taint-safe).
-- Guide step text is display-only at runtime; never persisted to SavedVariables.

local addonName, IQT = ...
local IF = ImprovedForever

local MODULE = "RXPGuide"
local MAX_STEPS = 3
local MAX_OBJECTIVES = 8
local TICK_SECONDS = 0.5

local settings = {
	headerText = "RestedXP Guide",
	events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
	blockTemplate = "IFObjectiveTrackerAnimBlockTemplate",
	lineTemplate = "IFObjectiveTrackerAnimLineTemplate",
	hasDisplayPriority = true,
}

IFRXPGuideObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, settings)

local reportedMissing
local reportedApi
local lastSignature
local lastWaypointKey
local ticker

local function ChatError(cause, hint)
	local msg = ("|cffff6666Improved Forever Quest Tracker [%s]:|r %s"):format(MODULE, cause)
	if hint then
		msg = msg .. " — " .. hint
	end
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

function IQT.RXPAvailable()
	return _G.RXPFrame ~= nil or _G.RXPGuides ~= nil or _G.RXPG_ARROW ~= nil
end

function IQT.RXPHasApi()
	local frame = _G.RXPFrame
	return type(frame) == "table" and type(frame.activeSteps) == "table"
end

local function Enabled()
	return IQT.Settings().rxpGuide ~= false
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
	if step.hidewindow or step.hidetip then
		return false
	end
	-- Prefer activeSteps entries (already filtered); still skip completed stickies when flagged.
	if step.inactive then
		return false
	end
	return true
end

local function CollectActiveSteps()
	local frame = _G.RXPFrame
	if type(frame) ~= "table" or type(frame.activeSteps) ~= "table" then
		return nil, "api"
	end
	local out = {}
	for i, step in ipairs(frame.activeSteps) do
		if StepIsShown(step) then
			out[#out + 1] = step
			if #out >= MAX_STEPS then
				break
			end
		end
	end
	return out
end

local function StepSignature(steps)
	if not steps then
		return "none"
	end
	local parts = {}
	for i, step in ipairs(steps) do
		local idx = tostring(step.index or step.stepId or i)
		local title = tostring(step.title or "")
		local n = 0
		for _, el in ipairs(step.elements or {}) do
			if ElementLineText(el) then
				n = n + 1
			end
		end
		parts[#parts + 1] = idx .. ":" .. title .. ":" .. n
	end
	local arrow = _G.RXPG_ARROW and _G.RXPG_ARROW.element
	if arrow then
		parts[#parts + 1] = ("a:%s:%s:%s"):format(
			tostring(arrow.wpHash or ""),
			tostring(arrow.zone or ""),
			tostring(arrow.x or "")
		)
	end
	return table.concat(parts, "|")
end

local function MaybeReportMissing()
	if reportedMissing or not Enabled() then
		return
	end
	if IQT.RXPAvailable() then
		return
	end
	reportedMissing = true
	ChatError(
		"RXPGuides is not loaded",
		"Enable RXPGuides in the AddOns list, or disable with /if quests rxp off"
	)
end

local function MaybeReportApi()
	if reportedApi or not Enabled() or not IQT.RXPAvailable() then
		return
	end
	if IQT.RXPHasApi() then
		return
	end
	reportedApi = true
	ChatError(
		"RXPGuides is loaded but RXPFrame.activeSteps is missing",
		"Update RestedXP Guides, or disable with /if quests rxp off"
	)
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
	-- RXP coords are percent 0–100; Blizzard CreateFromCoordinates expects 0–1.
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
	if not ok and not reportedApi then
		ChatError("Failed to set Blizzard user waypoint", tostring(err))
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

function IFRXPGuideObjectiveTrackerMixin:InitModule()
	MaybeReportMissing()
	MaybeReportApi()
	if ticker then
		return
	end
	ticker = C_Timer.NewTicker(TICK_SECONDS, function()
		if not Enabled() then
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
		local steps = CollectActiveSteps()
		local sig = StepSignature(steps)
		if sig ~= lastSignature then
			lastSignature = sig
			SyncBlizzardWaypoint()
			SyncQuestFocus(steps)
			self:MarkDirty()
		end
	end)
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
				elseif _G.RXPGuides and _G.RXPGuides.Show then
					_G.RXPGuides:Show()
				else
					ChatError("Could not open RXP window", "Use RXPGuides' own slash command")
				end
			end)
			rootDescription:CreateButton("Hide RestedXP in tracker", function()
				IQT.SetRXPGuide(false)
			end)
		end)
	elseif _G.RXPFrame and _G.RXPFrame.Show then
		_G.RXPFrame:Show()
	end
end

function IFRXPGuideObjectiveTrackerMixin:LayoutContents()
	if not Enabled() then
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

	local steps = CollectActiveSteps()
	if not steps or #steps == 0 then
		return
	end

	for i, step in ipairs(steps) do
		if not self:AddStep(step, i) then
			return
		end
	end
end

function IFRXPGuideObjectiveTrackerMixin:AddStep(step, index)
	local blockID = step.stepId or step.index or index
	-- Avoid colliding numeric ids across sticky/main steps.
	if type(blockID) ~= "number" then
		blockID = 100000 + index
	else
		blockID = blockID + (step.sticky and 500000 or 0)
	end

	local block = self:GetBlock(blockID)
	local title = StepTitle(step, index)
	block.name = title
	block:SetHeader(title)

	local added = 0
	local guideName
	if type(step.guide) == "table" and type(step.guide.name) == "string" then
		guideName = step.guide.name
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

function IQT.SetRXPGuide(on)
	IQT.Settings().rxpGuide = not not on
	IQT.Refresh()
	if IFRXPGuideObjectiveTracker then
		IFRXPGuideObjectiveTracker:MarkDirty()
	end
	IQT.Print("RestedXP guide in tracker: " .. (on and "on" or "off"))
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
	IQT.Print("RXP available: " .. tostring(IQT.RXPAvailable())
		.. ", activeSteps API: " .. tostring(IQT.RXPHasApi())
		.. ", enabled: " .. tostring(Enabled()))
	local steps = CollectActiveSteps()
	if not steps then
		IQT.Print("No active steps (RXP missing or API missing).")
		return
	end
	IQT.Print(("Active steps: %d"):format(#steps))
	for i, step in ipairs(steps) do
		IQT.Print(("  %d. %s"):format(i, StepTitle(step, i)))
	end
	local el = _G.RXPG_ARROW and _G.RXPG_ARROW.element
	if el then
		IQT.Print(("Arrow: map %s @ %.1f, %.1f"):format(tostring(el.zone), tonumber(el.x) or 0, tonumber(el.y) or 0))
	else
		IQT.Print("Arrow: none")
	end
end
