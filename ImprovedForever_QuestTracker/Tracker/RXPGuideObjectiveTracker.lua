-- RestedXP -> ImprovedForever Quest Tracker bridge.
-- Soft-depends on RXPGuides (+ optional profession/dungeon/legacy packs).
-- Four IF modules: Leveling, Profession, Dungeon, Legacy - native tracker
-- chrome (not stock RXP UI). With rxpOnly (default on), Blizzard quest /
-- campaign watches are suppressed while RXP is driving so the IF tracker
-- shows RestedXP steps only. Stock RXP window stays hidden via rxpHideWindow.
-- Taint-safe (no IFQuestCache writes). Guide text is display-only.

local addonName, IQT = ...
local IF = ImprovedForever

-- Match RXP's sticky + current + tip window; tips/train/"buy spells" are often
-- separate activeSteps entries or * lines inside a step.
-- Deck compact: keep current + tips first; cap stickies so the IF tracker
-- doesn't mirror RXP's full sticky dump (native window is hidden instead).
local MAX_STEPS = 8
local MAX_STICKY = 3
local MAX_OBJECTIVES = 12
local MAX_GLANCE_GUIDES = 2
local TICK_SECONDS = 0.5

local KINDS = { "leveling", "profession", "dungeon", "legacy" }

local KIND_META = {
	leveling = {
		module = "RXPGuide",
		header = "RestedXP Guide",
		setting = "rxpGuide",
		frame = "IFRXPGuideObjectiveTracker",
		mixin = "IFRXPGuideObjectiveTrackerMixin",
		idOffset = 0,
		menuTag = "MENU_RXP_GUIDE_TRACKER",
		packs = { "RXPGuides" },
	},
	profession = {
		module = "RXPProfession",
		header = "RestedXP Profession",
		setting = "rxpProfession",
		frame = "IFRXPProfessionObjectiveTracker",
		mixin = "IFRXPProfessionObjectiveTrackerMixin",
		idOffset = 700000,
		menuTag = "MENU_RXP_PROFESSION_TRACKER",
		packs = {
			"RXPGuides", "RXPGuides_Professions", "RXPGuides_Profession",
			"RXP_Professions", "RXP_Profession", "RestedXP_Professions",
			"RestedXP_Profession", "RXPProfessionGuides", "RXPGuides_ProfessionLeveling",
		},
		events = { "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW" },
	},
	dungeon = {
		module = "RXPDungeon",
		header = "RestedXP Dungeon",
		setting = "rxpDungeon",
		frame = "IFRXPDungeonObjectiveTracker",
		mixin = "IFRXPDungeonObjectiveTrackerMixin",
		idOffset = 800000,
		menuTag = "MENU_RXP_DUNGEON_TRACKER",
		packs = {
			"RXPGuides", "RXPGuides_Dungeon", "RXPGuides_Dungeons",
			"RXP_Dungeon", "RXP_Dungeons", "RestedXP_Dungeon",
			"RestedXP_Dungeons", "RXPDungeonGuides",
		},
	},
	legacy = {
		module = "RXPLegacy",
		header = "RestedXP Legacy",
		setting = "rxpLegacy",
		frame = "IFRXPLegacyObjectiveTracker",
		mixin = "IFRXPLegacyObjectiveTrackerMixin",
		idOffset = 900000,
		menuTag = "MENU_RXP_LEGACY_TRACKER",
		packs = {
			"RXPGuides", "RXPGuides_Legacy", "RXP_Legacy",
			"RestedXP_Legacy", "RXPLegacyGuides",
		},
	},
}

local baseEvents = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

local function MakeSettings(kind)
	local meta = KIND_META[kind]
	local events = {}
	for _, e in ipairs(baseEvents) do
		events[#events + 1] = e
	end
	for _, e in ipairs(meta.events or {}) do
		events[#events + 1] = e
	end
	return {
		headerText = meta.header,
		events = events,
		blockTemplate = "IFObjectiveTrackerAnimBlockTemplate",
		lineTemplate = "IFObjectiveTrackerAnimLineTemplate",
		hasDisplayPriority = true,
	}
end

IFRXPGuideObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, MakeSettings("leveling"))
IFRXPProfessionObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, MakeSettings("profession"))
IFRXPDungeonObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, MakeSettings("dungeon"))
IFRXPLegacyObjectiveTrackerMixin = CreateFromMixins(IFObjectiveTrackerModuleMixin, MakeSettings("legacy"))

local reportedMissing
local reportedApi = {}
local lastSignature = {}
local lastWaypointKey
local ticker
local detectedCache
local detectedAt

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

local function KindEnabled(kind)
	local key = KIND_META[kind].setting
	return IQT.Settings()[key] ~= false
end

local function AnyKindEnabled()
	for _, kind in ipairs(KINDS) do
		if KindEnabled(kind) then
			return true
		end
	end
	return false
end

-- RXP is "driving" when a guide is current or activeSteps has content and
-- at least one IF RXP section is enabled.
function IQT.RXPDriving()
	if not IQT.RXPAvailable() or not AnyKindEnabled() then
		return false
	end
	local frame = _G.RXPFrame
	if type(frame) == "table" and type(frame.activeSteps) == "table" and #frame.activeSteps > 0 then
		return true
	end
	local rxp = GetRXPAddon()
	return rxp ~= nil and rxp.currentGuide ~= nil
end

-- Default on: while RXP drives, hide Blizzard quest + campaign modules in
-- the IF tracker (RXP steps keep IF chrome). Off = previous side-by-side.
function IQT.ShouldHideBlizzardQuests()
	if IQT.Settings().rxpOnly == false then
		return false
	end
	return IQT.RXPDriving()
end

local function DirtyBlizzardQuestModules()
	if IFQuestObjectiveTracker and IFQuestObjectiveTracker.MarkDirty then
		IFQuestObjectiveTracker:MarkDirty()
	end
	if IFCampaignQuestObjectiveTracker and IFCampaignQuestObjectiveTracker.MarkDirty then
		IFCampaignQuestObjectiveTracker:MarkDirty()
	end
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

-- RXP's guide window shows element.text even when hideTooltip is set (* tip
-- lines use hideTooltip so they stay off the map tooltip — still on-screen).
local function ElementLineText(element)
	if not element or element.skip then
		return nil
	end
	local text = element.text
	if text == " " then
		-- RXP placeholder while waiting on server IDs; skip until filled.
		return nil
	end
	return StripNewlines(text or element.rawtext or element.tooltipText)
end

local function StepTitle(step, index)
	if type(step.title) == "string" and step.title ~= "" then
		return step.title
	end
	if step.tip then
		return "Tip"
	end
	return ("Step %d"):format(tonumber(step.index) or index or 1)
end

local function StepIsShown(step)
	return type(step) == "table" and not step.hidewindow and not step.hidetip and not step.inactive
end

-- Classify a guide into leveling | profession | dungeon | legacy.
-- Step tags `.profession` / `.dungeon` are RXP *filters* (show when that
-- profession/dungeon is enabled), NOT guide-kind — keep them on their guide.
local function ClassifyGuide(guide)
	if type(guide) ~= "table" then
		return "leveling"
	end
	local kindTag = tostring(guide.guideKind or guide.kind or ""):lower()
	if kindTag == "profession" or kindTag == "dungeon" or kindTag == "legacy" then
		return kindTag
	end
	local blob = table.concat({
		tostring(guide.group or ""),
		tostring(guide.groupdisplayname or ""),
		tostring(guide.subgroup or ""),
		tostring(guide.name or ""),
		tostring(guide.displayname or ""),
	}, " "):lower()
	-- Order matters: dungeon/legacy/profession before generic leveling.
	if blob:find("profession", 1, true) then
		return "profession"
	end
	if blob:find("dungeon", 1, true) then
		return "dungeon"
	end
	if blob:find("legacy", 1, true) then
		return "legacy"
	end
	return "leveling"
end

-- RXP activeSteps often omit step.guide; fall back to currentGuide.
local function StepGuide(step)
	if type(step) == "table" and type(step.guide) == "table" then
		return step.guide
	end
	local rxp = GetRXPAddon()
	return rxp and rxp.currentGuide or nil
end

local function ClassifyStep(step)
	if type(step) ~= "table" then
		return "leveling"
	end
	return ClassifyGuide(StepGuide(step))
end

-- Hide RXP's own guide window when IF is showing the steps (Deck OLED).
-- Uses RXP's hideGuideWindow profile flag — same as their Settings → Hide Window.
local function ApplyHideRXPWindow()
	local wantHide = IQT.Settings().rxpHideWindow ~= false and KindEnabled("leveling")
	local rxp = GetRXPAddon()
	local profile = rxp and rxp.settings and rxp.settings.profile
	if type(profile) == "table" then
		if wantHide and not profile.hideGuideWindow then
			profile.hideGuideWindow = true
			if _G.RXPFrame and _G.RXPFrame.SetShown then
				_G.RXPFrame:SetShown(false)
			end
			if rxp.v2 and rxp.v2.events and rxp.v2.events.Trigger then
				pcall(function()
					rxp.v2.events:Trigger("GuideWindowRefresh", "visibility", false)
				end)
			end
		elseif not wantHide and profile.hideGuideWindow and IQT.Settings().rxpHideWindow == false then
			-- Only re-show if the user turned our toggle off (don't fight a prior RXP hide).
			profile.hideGuideWindow = false
			if _G.RXPFrame and _G.RXPFrame.SetShown then
				_G.RXPFrame:SetShown(true)
			end
			if rxp.v2 and rxp.v2.events and rxp.v2.events.Trigger then
				pcall(function()
					rxp.v2.events:Trigger("GuideWindowRefresh", "visibility", true)
				end)
			end
		end
	elseif wantHide and _G.RXPFrame and _G.RXPFrame.Hide then
		-- No AceDB profile reachable — soft-hide the classic frame only.
		_G.RXPFrame:Hide()
	end
end

function IQT.ApplyHideRXPWindow()
	ApplyHideRXPWindow()
end

function IQT.RXPDetectPacks(force)
	local now = GetTime and GetTime() or 0
	if not force and detectedCache and detectedAt and (now - detectedAt) < 5 then
		return detectedCache
	end
	local byKind = {}
	local allAddons = {}
	local seenAddon = {}
	for _, kind in ipairs(KINDS) do
		local loaded = {}
		for _, name in ipairs(KIND_META[kind].packs) do
			if IsAddOnLoaded(name) then
				loaded[#loaded + 1] = name
				if not seenAddon[name] then
					seenAddon[name] = true
					allAddons[#allAddons + 1] = name
				end
			end
		end
		byKind[kind] = { addons = loaded, registered = 0 }
	end
	local rxp = GetRXPAddon()
	if rxp and type(rxp.guides) == "table" then
		for _, guide in pairs(rxp.guides) do
			local k = ClassifyGuide(guide)
			if byKind[k] then
				byKind[k].registered = byKind[k].registered + 1
			end
		end
	end
	detectedCache = {
		byKind = byKind,
		addons = allAddons,
		rxpAddonTable = rxp ~= nil,
		hasGuideProgressApi = rxp ~= nil and type(rxp.GetGuideProgress) == "function",
	}
	detectedAt = now
	return detectedCache
end

-- Back-compat alias used by earlier profession work / slash help.
function IQT.RXPDetectProfessionPacks(force)
	local d = IQT.RXPDetectPacks(force)
	return {
		addons = d.byKind.profession.addons,
		registeredProfessionGuides = d.byKind.profession.registered,
		rxpAddonTable = d.rxpAddonTable,
		hasGuideProgressApi = d.hasGuideProgressApi,
	}
end

local function MaybeReportMissing()
	if reportedMissing or not AnyKindEnabled() then
		return
	end
	if IQT.RXPAvailable() then
		return
	end
	reportedMissing = true
	ChatError("RXPGuide", "RXPGuides is not loaded", "Enable RXPGuides, or /if quests rxp off")
end

local function MaybeReportApi(kind)
	if reportedApi[kind] or not KindEnabled(kind) or not IQT.RXPAvailable() then
		return
	end
	if IQT.RXPHasApi() then
		return
	end
	reportedApi[kind] = true
	ChatError(KIND_META[kind].module, "RXPFrame.activeSteps is missing", "Update RestedXP Guides, or disable this RXP tracker section")
end

local function CollectActiveStepsOfKind(wantKind)
	local frame = _G.RXPFrame
	if type(frame) ~= "table" or type(frame.activeSteps) ~= "table" then
		return nil, "api"
	end
	-- Prefer current + tip steps, then incomplete stickies (Deck-readable).
	local current, tips, stickies = {}, {}, {}
	for _, step in ipairs(frame.activeSteps) do
		if StepIsShown(step) and ClassifyStep(step) == wantKind then
			if step.tip then
				tips[#tips + 1] = step
			elseif step.sticky then
				stickies[#stickies + 1] = step
			else
				current[#current + 1] = step
			end
		end
	end
	local out = {}
	for _, step in ipairs(current) do
		if #out >= MAX_STEPS then break end
		out[#out + 1] = step
	end
	for _, step in ipairs(tips) do
		if #out >= MAX_STEPS then break end
		out[#out + 1] = step
	end
	local stickyCap = math.min(MAX_STICKY, MAX_STEPS - #out)
	for i, step in ipairs(stickies) do
		if i > stickyCap or #out >= MAX_STEPS then break end
		out[#out + 1] = step
	end
	return out
end

local function CollectGlanceSteps(wantKind, excludeKeys)
	excludeKeys = excludeKeys or {}
	local rxp = GetRXPAddon()
	if not rxp or type(rxp.guides) ~= "table" or type(rxp.GetGuideProgress) ~= "function" then
		return {}
	end
	local progressDB = type(RXPCData) == "table" and type(RXPCData.guideProgress) == "table" and RXPCData.guideProgress
	local out = {}
	local seen = 0
	for _, guide in pairs(rxp.guides) do
		if seen >= MAX_GLANCE_GUIDES then
			break
		end
		if ClassifyGuide(guide) == wantKind and guide.key and not excludeKeys[guide.key]
			and not guide.empty and not guide.disabled then
			local hasProgress = progressDB and progressDB[guide.key]
			local isCurrent = rxp.currentGuide == guide
			if hasProgress or isCurrent then
				local stepIndex = tonumber(rxp.GetGuideProgress(guide)) or 1
				local step = guide.steps and guide.steps[stepIndex]
				if type(step) == "table" and StepIsShown(step) then
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

local function CollectStepsForKind(kind)
	local fromActive, err = CollectActiveStepsOfKind(kind)
	if err == "api" then
		return nil, "api"
	end
	fromActive = fromActive or {}

	-- Leveling: active steps only (no glance of other leveling guides).
	if kind == "leveling" then
		return fromActive
	end

	local rxp = GetRXPAddon()
	if rxp and ClassifyGuide(rxp.currentGuide) == kind then
		return fromActive
	end

	local exclude = {}
	for _, step in ipairs(fromActive) do
		if step.guide and step.guide.key then
			exclude[step.guide.key] = true
		end
	end
	for _, step in ipairs(CollectGlanceSteps(kind, exclude)) do
		if #fromActive >= MAX_STEPS then
			break
		end
		fromActive[#fromActive + 1] = step
	end
	return fromActive
end

local function StepSignature(steps, prefix)
	if not steps then
		return (prefix or "") .. "none"
	end
	local parts = { prefix or "" }
	for i, step in ipairs(steps) do
		local n = 0
		for _, el in ipairs(step.elements or {}) do
			if ElementLineText(el) then
				n = n + 1
			end
		end
		parts[#parts + 1] = table.concat({
			tostring(step.index or step.stepId or i),
			tostring(step.title or ""),
			step.guide and tostring(step.guide.key or step.guide.name or "") or "",
			tostring(n),
		}, ":")
	end
	return table.concat(parts, "|")
end

local function SyncBlizzardWaypoint()
	if not IQT.Settings().rxpWaypoint then
		return
	end
	local el = _G.RXPG_ARROW and _G.RXPG_ARROW.element
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
	pcall(function()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(zone, nx, ny))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
end

local function SyncQuestFocus(steps)
	if not IQT.Settings().rxpQuestFocus then
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

local function FrameForKind(kind)
	return _G[KIND_META[kind].frame]
end

local function AddStepToModule(self, step, index, idOffset)
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
	local guide = StepGuide(step)
	if type(guide) == "table" then
		guideName = guide.displayname or guide.name
	elseif type(RXPCData) == "table" then
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
			-- textOnly (* tips / train / buy spells) are instructions, not completed.
			local complete = element.completed and not element.textOnly
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
		block:AddObjective(1, StripNewlines(step.text) or "Follow the RestedXP step", nil, nil, IF_OBJECTIVE_DASH_STYLE_SHOW, IF_OBJECTIVE_TRACKER_COLOR["Normal"])
	end
	return self:LayoutBlock(block)
end

local lastHideBlizzard

local function EnsureTicker()
	if ticker then
		return
	end
	ticker = C_Timer.NewTicker(TICK_SECONDS, function()
		if not IQT.RXPAvailable() then
			MaybeReportMissing()
			if lastHideBlizzard then
				lastHideBlizzard = false
				DirtyBlizzardQuestModules()
			end
			return
		end
		ApplyHideRXPWindow()
		local hide = IQT.ShouldHideBlizzardQuests()
		if hide ~= lastHideBlizzard then
			lastHideBlizzard = hide
			DirtyBlizzardQuestModules()
		end
		for _, kind in ipairs(KINDS) do
			if KindEnabled(kind) then
				local steps = CollectStepsForKind(kind)
				local sig = StepSignature(steps, kind)
				if sig ~= lastSignature[kind] then
					lastSignature[kind] = sig
					if kind == "leveling" then
						SyncBlizzardWaypoint()
						SyncQuestFocus(steps)
					end
					local frame = FrameForKind(kind)
					if frame then
						frame:MarkDirty()
					end
				end
			end
		end
	end)
end

local function BindKindMixin(mixin, kind)
	local meta = KIND_META[kind]
	function mixin:InitModule()
		MaybeReportMissing()
		MaybeReportApi(kind)
		IQT.RXPDetectPacks(true)
		EnsureTicker()
		if kind == "leveling" then
			ApplyHideRXPWindow()
		end
	end
	function mixin:OnEvent()
		self:MarkDirty()
	end
	function mixin:OnBlockHeaderClick(block, mouseButton)
		if mouseButton == "RightButton" then
			IFObjectiveTrackerMenu.CreateContextMenu(self:GetContextMenuParent(), function(owner, rootDescription)
				rootDescription:SetTag(meta.menuTag)
				rootDescription:CreateTitle(block.name or meta.header)
				rootDescription:CreateButton("Open RestedXP window", function()
					IQT.Settings().rxpHideWindow = false
					ApplyHideRXPWindow()
					if _G.RXPFrame and _G.RXPFrame.Show then
						_G.RXPFrame:Show()
					else
						ChatError(meta.module, "Could not open RXP window", "Use RXPGuides' slash command")
					end
				end)
				rootDescription:CreateButton("Hide " .. meta.header .. " in tracker", function()
					IQT.SetRXPKind(kind, false)
				end)
			end)
		else
			-- Left click: briefly show native RXP window without changing the hide setting permanently.
			if _G.RXPFrame and _G.RXPFrame.Show then
				_G.RXPFrame:Show()
			end
		end
	end
	function mixin:LayoutContents()
		if not KindEnabled(kind) then
			return
		end
		if not IQT.RXPAvailable() then
			MaybeReportMissing()
			return
		end
		if kind == "leveling" then
			ApplyHideRXPWindow()
		end
		local steps, err = CollectStepsForKind(kind)
		if err == "api" then
			MaybeReportApi(kind)
			return
		end
		if not steps or #steps == 0 then
			return
		end
		for i, step in ipairs(steps) do
			if not AddStepToModule(self, step, i, meta.idOffset) then
				return
			end
		end
	end
end

BindKindMixin(IFRXPGuideObjectiveTrackerMixin, "leveling")
BindKindMixin(IFRXPProfessionObjectiveTrackerMixin, "profession")
BindKindMixin(IFRXPDungeonObjectiveTrackerMixin, "dungeon")
BindKindMixin(IFRXPLegacyObjectiveTrackerMixin, "legacy")

function IQT.SetRXPKind(kind, on)
	local meta = KIND_META[kind]
	if not meta then
		return
	end
	IQT.Settings()[meta.setting] = not not on
	IQT.Refresh()
	local frame = FrameForKind(kind)
	if frame then
		frame:MarkDirty()
	end
	IQT.Print(meta.header .. " in tracker: " .. (on and "on" or "off"))
end

function IQT.SetRXPGuide(on)
	IQT.SetRXPKind("leveling", on)
end
function IQT.SetRXPProfession(on)
	IQT.SetRXPKind("profession", on)
end
function IQT.SetRXPDungeon(on)
	IQT.SetRXPKind("dungeon", on)
end
function IQT.SetRXPLegacy(on)
	IQT.SetRXPKind("legacy", on)
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

function IQT.SetRXPHideWindow(on)
	IQT.Settings().rxpHideWindow = not not on
	ApplyHideRXPWindow()
	IQT.Print("Hide RestedXP guide window: " .. (on and "on" or "off"))
end

function IQT.SetRXPOnly(on)
	IQT.Settings().rxpOnly = not not on
	lastHideBlizzard = nil
	DirtyBlizzardQuestModules()
	IQT.Refresh()
	IQT.Print("RestedXP only (hide Blizzard quest watches): " .. (on and "on" or "off"))
end

-- Suppress Blizzard quest + campaign LayoutContents while RXP owns the IF tracker.
-- Campaign copied LayoutContents at mixin create time, so wrap both tables.
do
	local function WrapLayout(mixin)
		if type(mixin) ~= "table" or type(mixin.LayoutContents) ~= "function" then
			return
		end
		if mixin._ifRxpOnlyWrapped then
			return
		end
		local orig = mixin.LayoutContents
		mixin.LayoutContents = function(self)
			if IQT.ShouldHideBlizzardQuests() then
				return
			end
			return orig(self)
		end
		mixin._ifRxpOnlyWrapped = true
	end
	WrapLayout(IFQuestObjectiveTrackerMixin)
	WrapLayout(IFCampaignQuestObjectiveTrackerMixin)
end

function IQT.RXPDebug()
	local det = IQT.RXPDetectPacks(true)
	local frame = _G.RXPFrame
	local rawN = (type(frame) == "table" and type(frame.activeSteps) == "table") and #frame.activeSteps or -1
	IQT.Print("RXP available: " .. tostring(IQT.RXPAvailable())
		.. ", activeSteps API: " .. tostring(IQT.RXPHasApi())
		.. ", raw activeSteps: " .. tostring(rawN)
		.. ", RXP table: " .. tostring(det.rxpAddonTable)
		.. ", GetGuideProgress: " .. tostring(det.hasGuideProgressApi))
	IQT.Print("Hide RXP window: " .. tostring(IQT.Settings().rxpHideWindow ~= false)
		.. ", RXPFrame shown: " .. tostring(frame and frame.IsShown and frame:IsShown()))
	IQT.Print("RXP only / hide Blizzard watches: " .. tostring(IQT.Settings().rxpOnly ~= false)
		.. ", driving=" .. tostring(IQT.RXPDriving())
		.. ", hidingBlizzard=" .. tostring(IQT.ShouldHideBlizzardQuests()))
	IQT.Print("Packs loaded: " .. (#det.addons > 0 and table.concat(det.addons, ", ") or "(none of the known folder names)"))
	for _, kind in ipairs(KINDS) do
		local meta = KIND_META[kind]
		local info = det.byKind[kind]
		local steps = CollectStepsForKind(kind)
		IQT.Print(("%s [%s]: enabled=%s registered=%d steps=%d packs=%s"):format(
			meta.header,
			kind,
			tostring(KindEnabled(kind)),
			info.registered,
			steps and #steps or 0,
			#info.addons > 0 and table.concat(info.addons, ",") or "-"
		))
		if steps then
			for i, step in ipairs(steps) do
				local g = StepGuide(step)
				local gname = g and (g.displayname or g.name) or "?"
				local lines, tips = 0, 0
				for _, el in ipairs(step.elements or {}) do
					if ElementLineText(el) then
						lines = lines + 1
						if el.textOnly or el.hideTooltip then tips = tips + 1 end
					end
				end
				IQT.Print(("  %d. [%s] %s%s — %d lines (%d tip/textOnly)%s"):format(
					i, tostring(gname), StepTitle(step, i),
					step.sticky and " sticky" or (step.tip and " tip" or ""),
					lines, tips,
					step.hidewindow and " [hidden]" or ""
				))
			end
		end
	end
	local el = _G.RXPG_ARROW and _G.RXPG_ARROW.element
	if el then
		IQT.Print(("Arrow: map %s @ %.1f, %.1f"):format(tostring(el.zone), tonumber(el.x) or 0, tonumber(el.y) or 0))
	else
		IQT.Print("Arrow: none")
	end
end
