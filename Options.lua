-- Pint's Bags - options window (/pbag options, the gear button on the bag window, or right-click the minimap button).
local PB = PintsBags
local opt

local function db() return PB.db end
local function Changed() PB.RefreshAll() end

local function Check(parent, x, y, label, key, tip)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"); c:SetSize(22, 22); c:SetPoint("TOPLEFT", x, y)
	local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(label)
	c:SetScript("OnShow", function(self) self:SetChecked(db()[key] and true or false) end)
	c:SetScript("OnClick", function(self) db()[key] = self:GetChecked() and true or false; Changed() end)
	if tip then PB.Tip(c, tip) end
	return c
end
local function Stepper(parent, x, y, label, key, lo, hi, step, fmt)
	local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("TOPLEFT", x, y - 4); t:SetText(label)
	local m = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); m:SetSize(20, 18); m:SetPoint("TOPLEFT", x + 120, y); m:SetText("-")
	local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); v:SetPoint("LEFT", m, "RIGHT", 2, 0); v:SetWidth(40)
	local p = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); p:SetSize(20, 18); p:SetPoint("LEFT", v, "RIGHT", 2, 0); p:SetText("+")
	local function show() v:SetText((fmt or tostring)(db()[key])) end
	local function go(d) db()[key] = math.max(lo, math.min(hi, math.floor((db()[key] + d) * 100 + 0.5) / 100)); show(); Changed() end
	m:SetScript("OnClick", function() go(-step) end); p:SetScript("OnClick", function() go(step) end)
	parent:HookScript("OnShow", show)
end
local function PickColor(r, g, b, onChange)
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = function() onChange(ColorPickerFrame:GetColorRGB()) end, cancelFunc = function() onChange(r, g, b) end })
	else
		ColorPickerFrame.hasOpacity = false; ColorPickerFrame.previousValues = { r, g, b }
		ColorPickerFrame.func = function() onChange(ColorPickerFrame:GetColorRGB()) end
		ColorPickerFrame.cancelFunc = function() onChange(r, g, b) end
		ColorPickerFrame:SetColorRGB(r, g, b); ColorPickerFrame:Hide(); ColorPickerFrame:Show()
	end
end
local function Swatch(parent, x, y, bag, label)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate"); b:SetSize(18, 18); b:SetPoint("TOPLEFT", x, y)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); b:SetBackdropBorderColor(0, 0, 0, 1)
	local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", b, "RIGHT", 4, 0); t:SetText(label)
	local function show() b:SetBackdropColor(PB.BagColor(bag)) end
	b:SetScript("OnClick", function()
		local r, g, bl = PB.BagColor(bag)
		PickColor(r, g, bl, function(nr, ng, nb) db().colors[bag] = { nr, ng, nb }; show(); Changed() end)
	end)
	parent:HookScript("OnShow", show)
	return show
end

function PB.ToggleOptions()
	if not opt then
		opt = CreateFrame("Frame", "PintsBagsOptions", UIParent, "BasicFrameTemplateWithInset")
		opt:SetSize(380, 532); opt:SetPoint("CENTER"); opt:SetFrameStrata("DIALOG")
		opt:SetMovable(true); opt:EnableMouse(true); opt:RegisterForDrag("LeftButton")
		opt:SetScript("OnDragStart", opt.StartMoving); opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
		tinsert(UISpecialFrames, "PintsBagsOptions")
		local title = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); title:SetPoint("TOP", 0, -5); title:SetText("|cffd4a017Pint's|r Bags")
		local function head(y, s) local h = opt:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 16, y); h:SetText(s) end

		head(-32, "Layout")
		do
			local t = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("TOPLEFT", 16, -54); t:SetText("Show items")
			local b = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate"); b:SetSize(170, 20); b:SetPoint("TOPLEFT", 136, -50)
			local function show() b:SetText(db().view == "category" and "Grouped by kind" or "One big bag") end
			b:SetScript("OnClick", function() db().view = (db().view == "category") and "bags" or "category"; show(); Changed() end)
			opt:HookScript("OnShow", show)
		end
		Stepper(opt, 16, -74, "Slots across", "columns", 6, 30, 1)
		Check(opt, 236, -96, "Combine stacks", "combine", "In the grouped view, the same item in several stacks shows once with the total. Your bags aren't changed, and free space stays exact.")
		Check(opt, 236, -74, "Auto-sort groups", "groupSorted", "Off: items in a group keep your bag order, so things you move by hand stay put and the sort button decides the order. On: each group is always sorted by kind, quality and level.")
		Stepper(opt, 16, -96, "Group columns", "lanes", 1, 4, 1)
		Stepper(opt, 16, -118, "Slot size", "size", 26, 50, 1)
		Stepper(opt, 16, -140, "Gap between slots", "spacing", 0, 8, 1)
		Stepper(opt, 16, -162, "Window scale", "scale", 0.5, 1.6, 0.05, function(v) return math.floor(v * 100 + 0.5) .. "%" end)

		head(-192, "Look")
		Check(opt, 16, -210, "Quality borders", "quality"); Check(opt, 190, -210, "Quest item marks", "quest")
		Check(opt, 16, -232, "Item level on gear", "ilvl"); Check(opt, 190, -232, "Glow on new items", "newGlow")
		Check(opt, 190, -254, "Fade junk", "dimJunk")

		head(-284, "Colour each bag")
		Check(opt, 16, -302, "Colour slots by the bag they're in", "bagColors")
		Stepper(opt, 190, -302, "Strength", "colorStrength", 0.2, 1, 0.1, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
		local names = { [0] = "Backpack", "Bag 1", "Bag 2", "Bag 3", "Bag 4" }
		for i = 0, 4 do Swatch(opt, 16 + (i % 3) * 110, -328 - math.floor(i / 3) * 22, i, names[i]) end
		local bnames = { [-1] = "Bank", [5] = "Bank bag 1", [6] = "Bank bag 2", [7] = "Bank bag 3", [8] = "Bank bag 4", [9] = "Bank bag 5", [10] = "Bank bag 6" }
		local order = { -1, 5, 6, 7, 8, 9, 10 }
		for i, bag in ipairs(order) do Swatch(opt, 16 + ((i - 1) % 3) * 110, -376 - math.floor((i - 1) / 3) * 22, bag, bnames[bag]) end
		local reset = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate"); reset:SetSize(110, 20); reset:SetPoint("TOPLEFT", 236, -420); reset:SetText("Reset colours")
		reset:SetScript("OnClick", function() wipe(db().colors); opt:Hide(); opt:Show(); Changed() end)

		head(-448, "Behaviour")
		Check(opt, 16, -466, "Use for bags", "replaceBags", "Takes over B and Shift-B.")
		Check(opt, 190, -466, "Use for the bank", "replaceBank", "Needs /reload to switch.")
		Check(opt, 16, -488, "Lock window position", "locked"); Check(opt, 190, -488, "Use the game's sort", "gameSort", "When the game has its own bag sort, use it; otherwise Pint's Bags sorts by kind, quality and level.")
		opt.bagnon = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate"); opt.bagnon:SetSize(160, 20); opt.bagnon:SetPoint("TOPRIGHT", -14, -30)
		opt.bagnon:SetText("Switch Bagnon off"); opt.bagnon:SetScript("OnClick", PB.BagnonOff)
		opt:HookScript("OnShow", function() opt.bagnon:SetShown(PB.BagnonLoaded()) end)
		opt:Hide()
	end
	opt:SetShown(not opt:IsShown())
end
