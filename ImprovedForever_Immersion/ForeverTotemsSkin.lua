-- Soft-dep skin for Forever Totems (bverger/ForeverTotems, MIT): restyle its
-- bar to Immersion's gold / diamond language without vendoring their code.
-- Install ForeverTotems separately; this module no-ops when it is missing.
-- Setting foreverTotemsSkin (Immersion → Bottom → Totems).
local IF = ImprovedForever
local IN = IF.Interface
local HS = IN.HeaderSlot

local FT = {}
IN.ForeverTotemsSkin = FT

local GOLD = HS.GOLD
local TRACK = { 0.02, 0.02, 0.03, 0.88 }
local MASK = "progress-bar-diamond-pip-mask"
local SLOT = "gamepad-actionbar-squareslot-bg"
local ROOT2 = math.sqrt(2)

local hooked
local skinned = {}

local function Loaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded("ForeverTotems")
	end
	return _G.IsAddOnLoaded and _G.IsAddOnLoaded("ForeverTotems")
end

local function Enabled()
	return IF.db and IN.Settings().foreverTotemsSkin ~= false and Loaded()
end

local function Mix(r, g, b, toward, k)
	k = k or 0.55
	return r + (toward[1] - r) * k, g + (toward[2] - g) * k, b + (toward[3] - b) * k
end

local function SetFont(fs, size)
	if not fs then
		return
	end
	local file = HS.FONT
	if not fs:SetFont(file, size, "OUTLINE") then
		fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
	end
end

-- One-time diamond chrome on a Forever Totems button (icon + optional slot bg).
local function EnsureChrome(b)
	if not b or skinned[b] then
		return
	end
	skinned[b] = true
	if b.icon then
		local mask = b:CreateMaskTexture()
		mask:SetAtlas(MASK)
		mask:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(mask)
		b.ifMask = mask
		-- Soft Immersion slot plate behind the icon (under their bg).
		if not b.ifSlot then
			local slot = b:CreateTexture(nil, "BACKGROUND", nil, -1)
			slot:SetAtlas(SLOT)
			slot:SetPoint("CENTER")
			local side = (b:GetWidth() or 44) * 1.15
			slot:SetSize(side, side)
			slot:SetRotation(math.pi / 4)
			slot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
			b.ifSlot = slot
		end
	end
	SetFont(b.timer, 13)
	SetFont(b.keybind, 10)
	SetFont(b.emptyLabel, 10)
	SetFont(b.label, 10)
end

local function TintEdges(b, active)
	if not (b and b.edges) then
		return
	end
	for _, edge in ipairs(b.edges) do
		if active then
			edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
		else
			edge:SetColorTexture(GOLD[1] * 0.45, GOLD[2] * 0.45, GOLD[3] * 0.45, 0.75)
		end
	end
end

local function StyleButton(b)
	if not b then
		return
	end
	EnsureChrome(b)
	if b.bg then
		b.bg:SetColorTexture(TRACK[1], TRACK[2], TRACK[3], TRACK[4])
	end
	local active = b.icon and b.icon:GetAlpha() and b.icon:GetAlpha() > 0.8
	-- Totem out = bright icon; assigned dimmed = mid; empty = no icon.
	if b.icon and b.icon:IsShown() ~= false then
		local a = b.icon:GetAlpha() or 0
		TintEdges(b, a > 0.75)
		if b.timer and b.timer:GetText() and b.timer:GetText() ~= "" then
			b.timer:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		end
	else
		TintEdges(b, false)
	end
	if b.keybind then
		b.keybind:SetTextColor(0.92, 0.86, 0.7)
	end
end

local BUTTONS = {
	"ForeverTotemsButton1", "ForeverTotemsButton2", "ForeverTotemsButton3", "ForeverTotemsButton4",
	"ForeverTotemsBarSetButton", "ForeverTotemsCallButton",
	"ForeverTotemsWeaponButton", "ForeverTotemsShieldButton",
}

local function StyleSwing()
	local swing = _G.ForeverTotemsSwingBar
	if not swing then
		return
	end
	if swing.SetStatusBarColor then
		swing:SetStatusBarColor(GOLD[1], GOLD[2] * 0.85, GOLD[3] * 0.5, 1)
	end
	if swing.bg then
		swing.bg:SetColorTexture(TRACK[1], TRACK[2], TRACK[3], 0.85)
	end
	if swing.text then
		SetFont(swing.text, 11)
		swing.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end
end

local function StyleDrag()
	local bar = _G.ForeverTotemsBar
	if not (bar and bar.GetChildren) then
		return
	end
	-- Drag overlay is an unnamed child with a backdrop; tint gold when present.
	local kids = { bar:GetChildren() }
	for _, child in ipairs(kids) do
		if child.SetBackdropBorderColor and child.label then
			pcall(child.SetBackdropColor, child, GOLD[1] * 0.15, GOLD[2] * 0.12, GOLD[3] * 0.05, 0.65)
			pcall(child.SetBackdropBorderColor, child, GOLD[1], GOLD[2], GOLD[3], 0.9)
			SetFont(child.label, 10)
			child.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		end
	end
end

function FT.Apply()
	if not Enabled() then
		return
	end
	if not _G.ForeverTotemsBar then
		return
	end
	for _, name in ipairs(BUTTONS) do
		StyleButton(_G[name])
	end
	StyleSwing()
	StyleDrag()
end

local function HookBar()
	local bar = _G.ForeverTotemsBar
	if not bar or hooked then
		return
	end
	hooked = true
	local prev = bar:GetScript("OnUpdate")
	local acc = 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		if prev then
			prev(self, elapsed)
		end
		if not Enabled() then
			return
		end
		-- After Forever Totems redraws slots; light throttle.
		acc = acc + (elapsed or 0)
		if acc < 0.05 then
			return
		end
		acc = 0
		FT.Apply()
	end)
	FT.Apply()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "ForeverTotems" and name ~= "ImprovedForever_Immersion" then
		return
	end
	if not Enabled() then
		return
	end
	-- Bar may be created a moment after ADDON_LOADED.
	C_Timer.After(0.5, HookBar)
	C_Timer.After(2, HookBar)
end)

-- Poll briefly until the bar exists (options / delayed create).
local since = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	if hooked or not Enabled() then
		return
	end
	since = since + elapsed
	if since < 1 then
		return
	end
	since = 0
	HookBar()
end)
