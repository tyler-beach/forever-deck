-- RestedXP path lines on the world map: thick Immersion-gold polylines for
-- Steam Deck OLED. Soft-dep RXPGuides — no-ops when missing. Reads
-- RXPG_ARROW.element (+ active-step gotos); does not vendor guide text.
-- Default: synthesize player → target (+ same-zone lookahead) only when the
-- step has no RXP .line segments (avoids double-draw). forceIFStyle redraws
-- anyway. Quest Tracker's rxpWaypoint already mirrors the arrow to Blizzard.
local IF = ImprovedForever

local Path = {}
IF.RXPPath = Path

local GOLD = { 1, 0.82, 0.45, 0.95 }
local BORDER = { 0.05, 0.04, 0.02, 0.55 }
local TICK = 0.5
local DEFAULTS = {
	enabled = true,
	synthesize = true,   -- connect discrete gotos when no RXP segments
	playerToTarget = true,
	lookahead = 1,       -- extra same-zone gotos ahead
	thickness = 3.5,     -- Deck OLED default (RXP ~2)
	forceIFStyle = false, -- draw even when RXP already has segments
}

local hintOnce = false
local dirty = true
local lastKey = ""
local pool = {}
local active = {}
local ticker

local function Settings()
	local db = IF.db
	db.rxpPath = db.rxpPath or {}
	local s = db.rxpPath
	for k, v in pairs(DEFAULTS) do
		if s[k] == nil then
			s[k] = v
		end
	end
	return s
end
Path.Settings = Settings

local function RXPLoaded()
	return _G.RXPG_ARROW ~= nil or _G.RXPGuides ~= nil or _G.RXPFrame ~= nil
end

local function ArrowElement()
	local el = _G.RXPG_ARROW and _G.RXPG_ARROW.element
	return type(el) == "table" and el or nil
end

local function StepHasSegments(step)
	if type(step) ~= "table" or type(step.elements) ~= "table" then
		return false
	end
	for _, e in ipairs(step.elements) do
		if type(e.segments) == "table" and #e.segments >= 4 then
			return true
		end
	end
	return false
end

local function ValidPoint(zone, x, y)
	return type(zone) == "number" and type(x) == "number" and type(y) == "number"
		and x >= 0 and y >= 0 and x <= 100 and y <= 100
end

local function Push(points, zone, x, y, kind)
	if not ValidPoint(zone, x, y) then
		return
	end
	local last = points[#points]
	if last and last.zone == zone and math.abs(last.x - x) < 0.05 and math.abs(last.y - y) < 0.05 then
		return
	end
	points[#points + 1] = { zone = zone, x = x, y = y, kind = kind }
end

local function PlayerOnMap(zone)
	if not (C_Map and C_Map.GetPlayerMapPosition) then
		return
	end
	local pos = C_Map.GetPlayerMapPosition(zone, "player")
	if not pos then
		return
	end
	local x, y = pos:GetXY()
	if not x or not y then
		return
	end
	-- Secret values: never compare; just skip the player hop.
	if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then
		return
	end
	return x * 100, y * 100
end

local function CollectFromStep(points, step, zoneFilter)
	if type(step) ~= "table" or type(step.elements) ~= "table" then
		return
	end
	for _, e in ipairs(step.elements) do
		if e.zone and e.x and e.y and (not zoneFilter or e.zone == zoneFilter)
			and not e.hidePin and not e.skip
			and not (e.parent and (e.parent.completed or e.parent.skip))
		then
			Push(points, e.zone, e.x, e.y, "goto")
		end
	end
end

-- Ordered path points in percent coords (0–100), same-zone only for synthesis.
local function CollectPath()
	local s = Settings()
	local points = {}
	local el = ArrowElement()
	if not el or not ValidPoint(el.zone, el.x, el.y) then
		return points, false
	end
	local zone = el.zone
	local hasSeg = StepHasSegments(el.step)
	if hasSeg and not s.forceIFStyle then
		-- RXP already draws .line / .loop; optional single accent only.
		if s.playerToTarget then
			local px, py = PlayerOnMap(zone)
			if px then
				Push(points, zone, px, py, "player")
			end
			Push(points, zone, el.x, el.y, "arrow")
		end
		return points, true
	end
	if not s.synthesize and not s.playerToTarget then
		return points, hasSeg
	end
	if s.playerToTarget then
		local px, py = PlayerOnMap(zone)
		if px then
			Push(points, zone, px, py, "player")
		end
	end
	Push(points, zone, el.x, el.y, "arrow")
	if s.synthesize then
		CollectFromStep(points, el.step, zone)
		local look = tonumber(s.lookahead) or 0
		if look > 0 and _G.RXPFrame and type(_G.RXPFrame.activeSteps) == "table" then
			local seen = 0
			for _, step in ipairs(_G.RXPFrame.activeSteps) do
				if step ~= el.step then
					CollectFromStep(points, step, zone)
					seen = seen + 1
					if seen >= look then
						break
					end
				end
			end
		end
	end
	return points, hasSeg
end

local function ReleaseLines()
	for i = #active, 1, -1 do
		local f = active[i]
		active[i] = nil
		f:Hide()
		f:ClearAllPoints()
		pool[#pool + 1] = f
	end
end

local function AcquireLine(canvas)
	local f = table.remove(pool)
	if not f then
		f = CreateFrame("Frame", nil, canvas)
		f:EnableMouse(false)
		f.line = f:CreateLine()
		f.border = f:CreateLine()
		f.border:SetDrawLayer("OVERLAY", -6)
		f.line:SetDrawLayer("OVERLAY", -5)
	end
	f:SetParent(canvas)
	f:SetFrameStrata(canvas:GetFrameStrata() or "MEDIUM")
	f:SetFrameLevel((canvas:GetFrameLevel() or 0) + 20)
	return f
end

local function DrawSegment(canvas, sX, sY, fX, fY, thickness)
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	if not width or width <= 0 or not height or height <= 0 then
		return
	end
	-- Same canvas math as RXP MapLinePool (percent → TOPLEFT px).
	local aX, bX = sX * width / 100, fX * width / 100
	local aY, bY = sY * height / -100, fY * height / -100
	local lineWidth = math.abs(aX - bX) + thickness * 4
	local lineHeight = math.abs(aY - bY) + thickness * 4
	local xAnchor = math.max(aX, bX) - thickness * 2 - lineWidth / 2
	local yAnchor = math.min(aY, bY) + thickness * 2 + lineHeight / 2

	local f = AcquireLine(canvas)
	f:SetSize(lineWidth, lineHeight)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", canvas, "TOPLEFT", xAnchor, yAnchor)
	f.border:SetStartPoint("TOPLEFT", aX - xAnchor, aY - yAnchor)
	f.border:SetEndPoint("TOPLEFT", bX - xAnchor, bY - yAnchor)
	f.border:SetThickness(thickness + 2)
	f.border:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
	f.line:SetStartPoint("TOPLEFT", aX - xAnchor, aY - yAnchor)
	f.line:SetEndPoint("TOPLEFT", bX - xAnchor, bY - yAnchor)
	f.line:SetThickness(thickness)
	f.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
	f:Show()
	active[#active + 1] = f
end

local function MapShown()
	local w = _G.WorldMapFrame
	return w and w.IsShown and w:IsShown()
end

local function Canvas()
	local w = _G.WorldMapFrame
	return w and w.GetCanvas and w:GetCanvas() or nil
end

local function ShownMapID()
	local w = _G.WorldMapFrame
	if w and w.GetMapID then
		return w:GetMapID()
	end
end

local function PathKey(points)
	local parts = {}
	for i, p in ipairs(points) do
		parts[i] = ("%d:%.2f:%.2f"):format(p.zone, p.x, p.y)
	end
	return table.concat(parts, "|")
end

function Path.Clear()
	ReleaseLines()
	lastKey = ""
	dirty = true
end

function Path.Redraw()
	ReleaseLines()
	local s = Settings()
	if not s.enabled or not MapShown() then
		return
	end
	if not RXPLoaded() then
		if not hintOnce then
			hintOnce = true
			-- Quiet: only mention when they toggle/debug, not every login.
		end
		return
	end
	local canvas = Canvas()
	if not canvas then
		return
	end
	local points = CollectPath()
	if #points < 2 then
		lastKey = PathKey(points)
		return
	end
	local mapID = ShownMapID()
	local thickness = tonumber(s.thickness) or DEFAULTS.thickness
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if a.zone == b.zone and (not mapID or a.zone == mapID) then
			DrawSegment(canvas, a.x, a.y, b.x, b.y, thickness)
		end
	end
	lastKey = PathKey(points)
end

local function Tick()
	if not Settings().enabled then
		if #active > 0 then
			Path.Clear()
		end
		return
	end
	if not MapShown() then
		if #active > 0 then
			Path.Clear()
		end
		return
	end
	local points = CollectPath()
	local key = PathKey(points) .. ":" .. tostring(ShownMapID() or 0)
	if key ~= lastKey or dirty then
		dirty = false
		Path.Redraw()
	end
end

local function EnsureTicker()
	if ticker then
		return
	end
	if C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(TICK, Tick)
	end
end

function Path.Apply()
	dirty = true
	if Settings().enabled then
		EnsureTicker()
		if MapShown() then
			Path.Redraw()
		end
	else
		Path.Clear()
	end
end

function Path.Debug()
	local el = ArrowElement()
	local points, hasSeg = CollectPath()
	local s = Settings()
	IF.Print(("RXP path: enabled=%s RXP=%s force=%s synthesize=%s segments=%s points=%d map=%s"):format(
		tostring(s.enabled),
		tostring(RXPLoaded()),
		tostring(s.forceIFStyle),
		tostring(s.synthesize),
		tostring(hasSeg),
		#points,
		tostring(ShownMapID() or "?")
	))
	if el then
		IF.Print(("  arrow zone=%s x=%.2f y=%.2f"):format(tostring(el.zone), el.x or -1, el.y or -1))
	else
		IF.Print("  no RXPG_ARROW.element")
	end
	for i, p in ipairs(points) do
		IF.Print(("  [%d] %s %d %.2f,%.2f"):format(i, p.kind or "?", p.zone, p.x, p.y))
	end
	IF.Print(("  lines drawn=%d"):format(#active))
end

function Path.Command(sub, arg)
	sub = sub and sub:lower() or ""
	local s = Settings()
	if sub == "on" or sub == "1" or sub == "true" then
		s.enabled = true
		Path.Apply()
		IF.Print("RXP path: on")
	elseif sub == "off" or sub == "0" or sub == "false" then
		s.enabled = false
		Path.Apply()
		IF.Print("RXP path: off")
	elseif sub == "debug" then
		Path.Debug()
	elseif sub == "force" then
		local on = arg
		if on == nil or on == "" then
			s.forceIFStyle = not s.forceIFStyle
		else
			s.forceIFStyle = on == "on" or on == "1" or on == "true"
		end
		Path.Apply()
		IF.Print("RXP path force IF style: " .. (s.forceIFStyle and "on" or "off"))
	elseif sub == "" or sub == "status" then
		IF.Print(("RXP path: %s (force=%s thickness=%.1f)"):format(
			s.enabled and "on" or "off",
			tostring(s.forceIFStyle),
			tonumber(s.thickness) or DEFAULTS.thickness
		))
	else
		IF.Print("/if path [on|off|debug|force|status]")
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "ImprovedForever_Map" and name ~= "RXPGuides" then
		return
	end
	if event == "PLAYER_LOGIN" or name == "ImprovedForever_Map" or name == "RXPGuides" then
		Path.Apply()
	end
end)

local function HookMap()
	local w = _G.WorldMapFrame
	if not w or w.IFRXPPathHooked then
		return
	end
	w.IFRXPPathHooked = true
	w:HookScript("OnShow", function()
		dirty = true
		EnsureTicker()
		Path.Redraw()
	end)
	w:HookScript("OnHide", function()
		Path.Clear()
	end)
	if w.OnMapChanged then
		hooksecurefunc(w, "OnMapChanged", function()
			dirty = true
			if MapShown() then
				Path.Redraw()
			end
		end)
	end
end

-- WorldMapFrame may load late.
local mapWait = CreateFrame("Frame")
mapWait:SetScript("OnUpdate", function(self)
	if _G.WorldMapFrame then
		HookMap()
		self:SetScript("OnUpdate", nil)
	end
end)
