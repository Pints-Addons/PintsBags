-- Pint's Bags: all your bags in one window (and the bank in another), search, sort, colours per bag,
-- and any character's bags and bank from anywhere (read from Pint's Alts).  /pbag
local ADDON = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)
local GetItemQualityColor = GetItemQualityColor or (C_Item and C_Item.GetItemQualityColor)
local IsAddOnLoaded = IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)

local PB = {}
_G.PintsBags = PB

local INV = { 0, 1, 2, 3, 4 }
local BANK = { -1, 5, 6, 7, 8, 9, 10 }
-- the modern client (WoW Forever) adds a reagent bag as bag 5, so the bank's bags move up one
local REAGENT = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
if REAGENT then
	INV[#INV + 1] = REAGENT
	BANK = { -1 }
	for i = REAGENT + 1, REAGENT + 7 do BANK[#BANK + 1] = i end
end
-- WoW Forever's bank is made of tabs you buy at the banker (bags 6-14); there's no old 28-slot bank (bag -1 is the keyring)
local TABS = Enum and Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1
if TABS then
	BANK = {}
	for i = 1, 9 do local id = Enum.BagIndex["CharacterBankTab_" .. i]; if id then BANK[#BANK + 1] = id end end
end
local FIRST_BANK_BAG = TABS and BANK[1] or BANK[2]
local function IsInvBag(id) return id >= 0 and (id <= 4 or id == REAGENT) end
local BANK_ID = TABS and -999 or (BANK_CONTAINER or -1)
-- no bank tab bought yet: the game's own bank window is the one with the "buy a tab" button, so it's left to do the job
local function NoBankTabs()
	if not (TABS and C_Bank and C_Bank.FetchNumPurchasedBankTabs) then return false end
	local ok, n = pcall(C_Bank.FetchNumPurchasedBankTabs, (Enum.BankType and Enum.BankType.Character) or 0)
	return ok and (n or 0) == 0
end
PB.NoBankTabs = NoBankTabs
-- WoW Forever bank bags (the game's own bank, Camelot/BankFrame.lua): tab 1 is the bank itself; tabs 2-9 are bag slots
-- you buy at the banker and put a bag in. The bag sits at (Characterbanktab, tab number).
local TAB_BAG = Enum and Enum.BagIndex and Enum.BagIndex.Characterbanktab
local CHAR_BANK = Enum and Enum.BankType and Enum.BankType.Character or 0
local function TabNumber(bag) return TABS and bag and (bag - TABS + 1) or nil end
local function TabsBought()
	if not (C_Bank and C_Bank.FetchNumPurchasedBankTabs) then return 0 end
	local ok, n = pcall(C_Bank.FetchNumPurchasedBankTabs, CHAR_BANK); return ok and n or 0
end
local function TabsMax()
	if not (C_Bank and C_Bank.FetchMaxNumBankTabs) then return 0 end
	local ok, n = pcall(C_Bank.FetchMaxNumBankTabs, CHAR_BANK); return ok and n or 0
end
local function NextTabCost()
	if not (C_Bank and C_Bank.FetchNextPurchasableBankTabData) then return end
	local ok, d = pcall(C_Bank.FetchNextPurchasableBankTabData, CHAR_BANK)
	return ok and d and d.tabCost
end
-- Buying is something only the game's own bank window may do (from an add-on it's "blocked from an action"), so the
-- Buy button brings the game's bank window into view next to ours: click its purchase button. It goes back out of
-- sight when you leave the banker.
local function BuyBankTab()
	-- (the game's own purchase button sits on top of "Buy bag slot": that's the one to click)
	print("|cffd4a017Pint's Bags:|r click \"Buy bag slot\" at the top of the bank window to buy the next bag slot.")
end
local DEFAULTS = {
	columns = 10, size = 37, view = "category", lanes = 2, recent = true, groupSorted = false, combine = true, spacing = 3, scale = 1, quality = true, quest = true, ilvl = false, newGlow = true, dimJunk = false,
	bagColors = false, colorStrength = 0.9, colors = {}, bagBar = false, replaceBags = true, replaceBank = true, gameSort = false,
	locked = false, pos = {}, minimap = {}, curSlots = {},
}
local PALETTE = {
	[0] = { 0.85, 0.72, 0.40 }, [1] = { 0.30, 0.55, 1.00 }, [2] = { 0.35, 0.85, 0.35 }, [3] = { 0.72, 0.42, 1.00 }, [4] = { 1.00, 0.55, 0.20 },
	[-1] = { 0.85, 0.72, 0.40 }, [5] = { 0.20, 0.80, 0.80 }, [6] = { 1.00, 0.40, 0.70 }, [7] = { 0.95, 0.30, 0.30 }, [8] = { 1.00, 0.90, 0.30 },
	[9] = { 0.60, 1.00, 0.30 }, [10] = { 0.45, 0.75, 1.00 },
}
-- the reagent bag (WoW Forever) only takes crafting reagents: an off-white, so it stands apart from the coloured bags
if REAGENT then PALETTE[REAGENT] = { 0.92, 0.90, 0.82 } end
PB.PALETTE = PALETTE
local db
local SortKeyFor, SortBefore          -- set in the sorting section
local ME, REALM = (GetUnitName and GetUnitName("player", false) or UnitName("player")), GetRealmName()
local function Print(m) print("|cffd4a017Pint's Bags:|r " .. m) end
PB.Print = Print
function PB.Tip(f, t) f:HookScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:AddLine(t, 1, 1, 1, true); GameTooltip:Show() end); f:HookScript("OnLeave", function() GameTooltip:Hide() end) end

---------------------------------------------------------------- helpers
local C = C_Container or {}
local function NumSlots(bag) return (C.GetContainerNumSlots and C.GetContainerNumSlots(bag)) or 0 end
local function SlotInfo(bag, slot) return C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot) end
local function BagFamily(bag)
	if bag == 0 or bag == BANK_ID then return 0 end
	local _, family = C.GetContainerNumFreeSlots(bag)
	return family or 0
end
function PB.BagColor(bag)
	local c = db and db.colors[bag] or PALETTE[bag] or { 1, 1, 1 }
	return c[1], c[2], c[3]
end
local QUALITY_WORDS = { poor = 0, grey = 0, gray = 0, junk = 0, common = 1, white = 1, uncommon = 2, green = 2, rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5 }
local function Money(v)
	v = v or 0
	local g, s, c = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
	local out = ""
	if g > 0 then out = out .. g .. "|cffffd700g|r " end
	if g > 0 or s > 0 then out = out .. s .. "|cffc7c7cfs|r " end
	return out .. c .. "|cffeda55fc|r"
end
PB.Money = Money

-- does this item match the search text?  name, type, slot, quality word ("epic"), or "bound"
local function Matches(link, text, bound)
	if not text or text == "" then return true end
	if not link then return false end
	local name, _, quality, _, _, itype, isub, _, loc = GetItemInfo(link)
	name = (name or link:match("%[(.-)%]") or ""):lower()
	for word in text:lower():gmatch("%S+") do
		local q = QUALITY_WORDS[word]
		local ok = name:find(word, 1, true)
			or (itype and itype:lower():find(word, 1, true)) or (isub and isub:lower():find(word, 1, true))
			or (loc and loc ~= "" and _G[loc] and _G[loc]:lower():find(word, 1, true))
			or (q and quality == q) or (word == "bound" and bound)
		if not ok then return false end
	end
	return true
end
PB.Matches = Matches

---------------------------------------------------------------- characters (Pint's Alts keeps everyone's bags and bank)
local function LedgerChars() return PintsLedgerDB and PintsLedgerDB.chars and PintsLedgerDB.chars[REALM] or {} end
local function LedgerRec(name) return LedgerChars()[name] end

---------------------------------------------------------------- currencies (WoW Forever: Merchant's Favor, Honor Points...)
-- Shown beside your gold: the currencies you ticked "Show on Backpack" for in the game's Currency tab, or Merchant's
-- Favor when you haven't ticked any. Other characters' amounts come from Pint's Alts.
local CUR = C_CurrencyInfo
-- (WoW Forever only: Classic Era has no currencies to show)
local HAS_CUR = CUR and CUR.GetCurrencyInfo and type(issecretvalue) == "function" and true or false
local CUR_DEFAULT = { "Merchant's Favor", "Honor Points" }
local function SlotCurrency(i) local v = db and db.curSlots and db.curSlots[i]; if v == nil then return CUR_DEFAULT[i] end; return v or nil end
local DEFAULT_CUR = { "Merchant's Favor" }
local function CurIcon(icon) return icon and ("|T" .. icon .. ":14:14:0:0|t") or "" end
-- name -> { id, icon }: learned from the currency list (and kept by Pint's Alts in PintsLedgerDB.currencies)
local curKnown = {}
local function LearnCurrencies()
	if not HAS_CUR then return end
	local shared = PintsLedgerDB and PintsLedgerDB.currencies
	if shared then for n, v in pairs(shared) do curKnown[n] = curKnown[n] or v end end
	for i = 1, (CUR.GetCurrencyListSize and CUR.GetCurrencyListSize() or 0) do
		local info = CUR.GetCurrencyListInfo(i)
		if info and not info.isHeader and info.name then
			local link = CUR.GetCurrencyListLink and CUR.GetCurrencyListLink(i)
			local id = link and tonumber(link:match("currency:(%d+)"))
			if id then curKnown[info.name] = { id = id, icon = info.iconFileID } end
		end
	end
end
-- the currencies to show: { name, icon, amount }
local function ShownCurrencies(rec)
	if not HAS_CUR then return {} end
	local out, names = {}, {}
	if not rec and CUR.GetBackpackCurrencyInfo then
		for i = 1, 5 do
			local info = CUR.GetBackpackCurrencyInfo(i)
			if not info then break end
			names[#names + 1] = info.name
			-- (the backpack list carries the amount and icon itself)
			if info.currencyTypesID then curKnown[info.name] = curKnown[info.name] or { id = info.currencyTypesID, icon = info.iconFileID } end
			out[#out + 1] = { info.name, info.iconFileID, info.quantity or 0 }
		end
		if #out > 0 then return out end
	end
	if #names == 0 then names = DEFAULT_CUR end
	for _, n in ipairs(names) do
		if not curKnown[n] then LearnCurrencies() end
		local k, amt = curKnown[n], nil
		if rec then amt = rec.cur and rec.cur[n]
		elseif k then local info = CUR.GetCurrencyInfo(k.id); amt = info and info.quantity end
		if not k and rec then k = (PintsLedgerDB and PintsLedgerDB.currencies or {})[n] end
		if amt then out[#out + 1] = { n, k and k.icon, amt } end
	end
	return out
end
local function LiveAmount(name)
	local k = curKnown[name]
	local info = k and HAS_CUR and CUR.GetCurrencyInfo(k.id)
	return info and info.quantity
end
local function CurrencyText(rec)
	local t = {}
	for _, c in ipairs(ShownCurrencies(rec)) do t[#t + 1] = c[3] .. " " .. CurIcon(c[2]) end
	return table.concat(t, "   ")
end
PB.CurrencyText = CurrencyText

-- the two currency spots on the bottom edge: which currency each shows (click its icon to pick another)
local function CurrencyInfoFor(name, rec)
	if not HAS_CUR or not name then return end
	if not curKnown[name] then LearnCurrencies() end
	local k = curKnown[name] or (PintsLedgerDB and PintsLedgerDB.currencies and PintsLedgerDB.currencies[name])
	local amt
	if rec then amt = rec.cur and rec.cur[name] else amt = LiveAmount(name) end
	return amt, k and k.icon
end
-- every currency we know of, by name (for the picker)
local function AllCurrencies()
	LearnCurrencies()
	local seen, out = {}, {}
	local function add(n, icon) if n and not seen[n] then seen[n] = true; out[#out + 1] = { n, icon } end end
	for n, k in pairs(curKnown) do add(n, k.icon) end
	for n, k in pairs(PintsLedgerDB and PintsLedgerDB.currencies or {}) do add(n, k.icon) end
	table.sort(out, function(a, b) return a[1] < b[1] end)
	return out
end
-- every character on the realm with its amount (or not seen yet), and the total
local function CurrencyTooltip(name, icon)
	GameTooltip:AddLine(CurIcon(icon) .. " " .. name)
	local list, total, missing = {}, 0, 0
	local names = {}
	for n in pairs(LedgerChars()) do names[n] = true end
	names[ME] = true
	for n in pairs(names) do
		local rec = LedgerChars()[n] or { classFile = select(2, UnitClass("player")) }
		local amt = rec.cur and rec.cur[name]
		if n == ME then amt = LiveAmount(name) or amt end
		if amt then total = total + amt else missing = missing + 1 end
		list[#list + 1] = { n, amt, rec.classFile }
	end
	table.sort(list, function(a, b) return (a[2] or -1) > (b[2] or -1) end)
	for _, e in ipairs(list) do
		local col = RAID_CLASS_COLORS[e[3] or ""]
		GameTooltip:AddDoubleLine(e[1], e[2] and tostring(e[2]) or "|cff808080not seen yet|r", col and col.r or 1, col and col.g or 1, col and col.b or 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Account total", total, 1, 0.82, 0, 1, 1, 1)
	if missing > 0 then GameTooltip:AddLine("Log in once on the others (with Pint's Alts) to count theirs.", 0.6, 0.6, 0.6, true) end
end
-- the picker: every known currency, plus "none"
local curMenu
local function PickCurrency(anchor, slot, onPick)
	if not curMenu then
		curMenu = CreateFrame("Frame", "PintsBagsCurrencyMenu", UIParent, "BackdropTemplate")
		curMenu:SetFrameStrata("FULLSCREEN_DIALOG"); curMenu:SetClampedToScreen(true); curMenu:EnableMouse(true)
		curMenu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		curMenu:SetBackdropColor(0, 0, 0, 0.95)
		curMenu.items = {}
		tinsert(UISpecialFrames, "PintsBagsCurrencyMenu")
		-- click anywhere else to close it
		local function Away()
			if not curMenu:IsShown() then return end
			local over = curMenu:IsMouseOver() or (curMenu.anchor and curMenu.anchor:IsMouseOver())
			if not over then curMenu:Hide() end
		end
		local hasEvent = pcall(curMenu.RegisterEvent, curMenu, "GLOBAL_MOUSE_DOWN")
		curMenu:SetScript("OnUpdate", function(self)
			-- the bags closed (or the spot went away): close the list with them
			if not (self.anchor and self.anchor:IsVisible()) then self:Hide(); return end
			-- (no click-anywhere event on this client: watch the mouse buttons instead)
			if not hasEvent and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then Away() end
		end)
		curMenu:SetScript("OnEvent", function() Away() end)
	end
	local list = AllCurrencies()
	table.insert(list, { false, nil })
	for i, e in ipairs(list) do
		local b = curMenu.items[i]
		if not b then
			b = CreateFrame("Button", nil, curMenu); b:SetSize(200, 18); b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 18)
			b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 4, 0)
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.18)
			curMenu.items[i] = b
		end
		local cur = SlotCurrency(slot)
		b.t:SetText((e[1] == (cur or false) and "|cff40ff40>|r " or "   ") .. (e[1] and (CurIcon(e[2]) .. " " .. e[1]) or "|cff9d9d9dNone (leave this spot empty)|r"))
		b:SetScript("OnClick", function() db.curSlots[slot] = e[1] or false; curMenu:Hide(); onPick() end)
		b:Show()
	end
	for i = #list + 1, #curMenu.items do curMenu.items[i]:Hide() end
	curMenu:SetSize(216, #list * 18 + 12)
	curMenu:ClearAllPoints(); curMenu:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
	curMenu.anchor = anchor
	curMenu:Show()
end
-- fill a window's two currency spots (rec = the saved character being viewed, or nil for you)
-- space the two spots evenly between the free-slot count (left) and the gold (right)
local function SpaceCurrencySlots(w)
	local b1, b2 = w.curBtn[1], w.curBtn[2]
	local left, right = w.free and w.free:GetRight(), w.money and w.money.t and w.money.t:GetLeft()
	local wl = w:GetLeft()
	if not (left and right and wl) then return end
	local w1 = b1:IsShown() and b1:GetWidth() or 0
	local w2 = b2:IsShown() and b2:GetWidth() or 0
	local gap = (right - left - w1 - w2) / 3
	if gap < 4 then return end
	b1:ClearAllPoints(); b1:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", left - wl + gap, 8)
	b2:ClearAllPoints(); b2:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", left - wl + gap + w1 + gap, 8)
end
function PB.UpdateCurrencySlots(w, rec)
	if not w.curBtn then return end
	-- (positions need the texts' widths, which settle a moment after they change)
	C_Timer.After(0, function() SpaceCurrencySlots(w) end)
	for i, b in ipairs(w.curBtn) do
		local name = SlotCurrency(i)
		if HAS_CUR and name then
			local amt, icon = CurrencyInfoFor(name, rec)
			b.name, b.icon = name, icon
			b.t:SetText(((amt and tostring(amt)) or "|cff808080-|r") .. " " .. CurIcon(icon or "Interface\\Icons\\INV_Misc_QuestionMark"))
			b:SetWidth(math.max(16, b.t:GetStringWidth()))
			b:Show()
		else
			b.name = nil
			b:SetShown(HAS_CUR and true or false)      -- (an empty spot stays clickable to pick a currency)
			b.t:SetText(HAS_CUR and "|cff606060+|r" or ""); b:SetWidth(16)
		end
	end
end

---------------------------------------------------------------- item buttons
local liveButtons, bagFrames, offButtons = {}, {}, {}
local nameN = 0
local function Decorate(b)
	local size = 37
	b.pbEdge = b:CreateTexture(nil, "BACKGROUND", nil, -7)
	b.pbEdge:SetPoint("TOPLEFT", -2, 2); b.pbEdge:SetPoint("BOTTOMRIGHT", 2, -2); b.pbEdge:SetColorTexture(1, 1, 1, 1); b.pbEdge:Hide()
	b.pbBack = b:CreateTexture(nil, "BACKGROUND", nil, -6)
	b.pbBack:SetAllPoints(); b.pbBack:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
	-- empty reagent-bag slots (WoW Forever) get a light off-white wash, so you can see at a glance where reagents go
	b.pbTint = b:CreateTexture(nil, "BACKGROUND", nil, -5)
	b.pbTint:SetAllPoints(); b.pbTint:SetColorTexture(0.92, 0.90, 0.82, 0.38); b.pbTint:Hide()
	b.pbGlow = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.pbGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.pbGlow:SetBlendMode("ADD")
	b.pbGlow:SetPoint("CENTER"); b.pbGlow:SetSize(size * 1.8, size * 1.8); b.pbGlow:Hide()
	b.pbQuest = b:CreateTexture(nil, "OVERLAY", nil, 2); b.pbQuest:SetAllPoints(); b.pbQuest:Hide()
	b.pbNew = b:CreateTexture(nil, "OVERLAY", nil, 3); b.pbNew:SetAllPoints()
	b.pbNew:SetTexture("Interface\\Buttons\\CheckButtonHilight"); b.pbNew:SetBlendMode("ADD"); b.pbNew:Hide()
	b.pbLevel = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); b.pbLevel:SetPoint("TOPLEFT", 2, -2)
	b.pbFreeText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge"); b.pbFreeText:SetPoint("CENTER")
	-- junk mark: a small coin in the top-right corner (grey items and Pint's Junk quick-list items)
	b.pbJunk = b:CreateTexture(nil, "OVERLAY", nil, 7); b.pbJunk:SetSize(14, 14); b.pbJunk:SetPoint("TOPRIGHT", -1, -1); b.pbJunk:Hide()
	if b.IconBorder then b.IconBorder:SetAlpha(0) end
end
local function Icon(b) return b.icon or b.Icon or _G[(b:GetName() or "") .. "IconTexture"] end
local function CountText(b) return b.Count or _G[(b:GetName() or "") .. "Count"] end

local function BagFrame(bag)
	local f = bagFrames[bag]
	if not f then
		f = CreateFrame("Frame", nil, UIParent); f:SetID(bag); f:SetAllPoints(UIParent)
		bagFrames[bag] = f
	end
	return f
end
-- WoW Forever: right-click to use (potions, food, anything with a use) goes through a secure overlay on each slot,
-- the same kind of button the action bars use - so the game always lets it through, in combat too. Left-click,
-- dragging and tooltips still reach the slot underneath.
local pendingUse, useOff = {}, false
-- The overlays live on a layer of their own, not inside the bag window: a secure button inside the window would make
-- the whole window "protected", and the game then refuses to let it update or close during combat. Out of combat they
-- follow their slots. When a fight starts with your bags open, each one is pinned to the spot its slot is on, and the
-- bag window holds still until the fight ends (no rearranging, moving or closing), so every pinned button stays over
-- its own item and right-click keeps using potions mid-fight. Bags opened during a fight don't get them.
local useLayer = CreateFrame("Frame", "PintsBagsUseLayer", UIParent)
useLayer:SetAllPoints(UIParent)
-- The use buttons sit one layer above the bag windows. On the same layer, clicking a bag window brings it to the
-- front, which lifts its slots over the use buttons; in a fight they can't be lifted back, so right-click stopped working.
local USE_STRATA = "DIALOG"
local function Sync(b)
	local o = b.pbUse
	if not o or InCombatLockdown() then return end
	if b:IsVisible() and not useOff then
		o:ClearAllPoints(); o:SetAllPoints(b)
		o:SetFrameStrata(USE_STRATA); o:SetFrameLevel(5)
		o:Show()
	else
		o:Hide(); o:ClearAllPoints()
	end
end
local function AddUse(b, bag, slot)
	if b.pbUse or type(issecretvalue) ~= "function" then return end
	if InCombatLockdown() then pendingUse[b] = { bag, slot }; return end
	local o = CreateFrame("Button", nil, useLayer, "SecureActionButtonTemplate")
	o:Hide()
	o:RegisterForClicks("RightButtonUp", "RightButtonDown")
	o:SetAttribute("type2", "item")
	o:SetAttribute("item2", bag .. " " .. slot)
	if o.SetPassThroughButtons then pcall(o.SetPassThroughButtons, o, "LeftButton", "MiddleButton", "Button4", "Button5") end
	o:SetScript("OnEnter", function() local f = b:GetScript("OnEnter"); if f then f(b) end end)
	o:SetScript("OnLeave", function() local f = b:GetScript("OnLeave"); if f then f(b) end end)
	b.pbUse = o
	if PB.IsTargeting and PB.IsTargeting() then PB.TargetMode(o, true) end
	-- a right-click that reached the slot itself in a fight did nothing (only a pinned use button can use an item):
	-- say why, at most every few seconds
	b:HookScript("OnMouseUp", function(self, btn)
		if btn ~= "RightButton" or not InCombatLockdown() then return end
		local now = GetTime()
		if PB.combatNoteAt and now - PB.combatNoteAt < 4 then return end
		PB.combatNoteAt = now
		local why
		if not PB.fightLock then why = "your bags weren't open when this fight started"
		elseif useOff then why = "use buttons were off (a vendor, bank, mailbox or trade window was open when the fight started)"
		elseif not (self.pbUse and self.pbUse:IsShown()) then why = "this slot wasn't showing when the fight started"
		else why = "the use button over this slot didn't take the click" end
		Print("couldn't use that in this fight - " .. why .. ". Open your bags before a fight starts (or drag the item to an action bar).")
	end)
	b:HookScript("OnShow", function(self) C_Timer.After(0, function() Sync(self) end) end)
	b:HookScript("OnHide", function(self) Sync(self) end)
	Sync(b)
end
local function SyncAll() for _, b in pairs(liveButtons) do Sync(b) end end
-- Using an item ON another item (a crate that takes Strange Dust, Disenchant, Pick Lock, a weapon stone...): the game
-- waits for you to left-click the second item. Through the game's own slot code that left-click is blocked on WoW Forever
-- ("PintsBags tried to call UseContainerItem"), so while it's waiting the use buttons take the left-click too.
-- (Out of a fight only - the game won't let add-ons change these buttons in one.)
local targeting = false
local function TargetMode(o, on)
	if on then
		o:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")
		o:SetAttribute("type1", "item"); o:SetAttribute("item1", o:GetAttribute("item2"))
		if o.SetPassThroughButtons then pcall(o.SetPassThroughButtons, o, "MiddleButton", "Button4", "Button5") end
	else
		o:RegisterForClicks("RightButtonUp", "RightButtonDown")
		o:SetAttribute("type1", nil); o:SetAttribute("item1", nil)
		if o.SetPassThroughButtons then pcall(o.SetPassThroughButtons, o, "LeftButton", "MiddleButton", "Button4", "Button5") end
	end
end
PB.TargetMode = TargetMode
local function SetTargeting(on)
	if on == targeting or InCombatLockdown() then return end
	targeting = on
	for _, b in pairs(liveButtons) do if b.pbUse then TargetMode(b.pbUse, on) end end
end
PB.IsTargeting = function() return targeting end
if type(issecretvalue) == "function" and SpellIsTargeting then
	local poll, acc = CreateFrame("Frame"), 0
	poll:SetScript("OnUpdate", function(_, el)
		acc = acc + el
		if acc < 0.05 then return end
		acc = 0
		SetTargeting(SpellIsTargeting() and true or false)
	end)
end
PB.AddPendingUse = function()
	for b, bs in pairs(pendingUse) do pendingUse[b] = nil; AddUse(b, bs[1], bs[2]) end
	SyncAll()
end
-- at a vendor, bank, mailbox, auction house or trade the game's own right-click is the one you want (sell, store,
-- attach...), and it works there: the overlays step aside while one of those is open
local function UseOverlays(on)
	if PB.testClick then on = false end         -- (/pbag testclick: the slots get the click themselves)
	useOff = not on                      -- (remembered even in combat, so a window closed mid-fight doesn't leave them off)
	if InCombatLockdown() then return end
	SyncAll()
end
-- the windows where the game's own right-click is wanted; other interactions (talking to a quest giver, say) leave them on
local PIT = Enum and Enum.PlayerInteractionType
local STEP_ASIDE = {}
if PIT then for _, k in ipairs({ "Merchant", "Banker", "MailInfo", "Auctioneer", "GuildBanker", "TradePartner", "AccountBanker" }) do if PIT[k] then STEP_ASIDE[PIT[k]] = true end end end
do
	local uv = CreateFrame("Frame")
	local open = { MERCHANT_SHOW = true, BANKFRAME_OPENED = true, MAIL_SHOW = true, AUCTION_HOUSE_SHOW = true, TRADE_SHOW = true,
		GUILDBANKFRAME_OPENED = true, PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true }
	for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
		"AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
		"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_REGEN_DISABLED" }) do pcall(uv.RegisterEvent, uv, e) end
	uv:SetScript("OnEvent", function(_, e, a1)
		if e == "PLAYER_REGEN_DISABLED" then
			-- the last moment before combat locks things: pin each use button to where its slot is right now (not to the
			-- slot itself, so the window stays free), and keep the window still until the fight is over
			PB.fightLock = false
			-- WoW Forever with the game's own item buttons over the slots: they do the clicking in a fight, so the old use
			-- buttons are put away (now, while that's still allowed) and the bags can be moved and closed as usual
			-- (only once the mouse has been seen landing on the game's buttons: until then the old way, which is known to work)
			if PB.DockItems and type(issecretvalue) == "function" and db.gameButtonsTest and (PB.dockedCount or 0) > 0 and PB.dockVerified then
				-- (Pint's Bags' own slots ignore right-click until it ends: the game's buttons on top take it)
				for _, b in pairs(liveButtons) do if b.pbUse then b.pbUse:Hide(); b.pbUse:ClearAllPoints(); b:RegisterForClicks("LeftButtonUp") end end
				return
			end
			-- bags closed? lay them out anyway (out of sight), so the use buttons can wait in place for when they're opened
			local inv = PB.windows and PB.windows.inv     -- (PB.windows: the windows table is made further down the file)
			if inv and not inv:IsShown() and not inv.offline and PB.toggleBtn then pcall(PB.Refresh, inv, true) end
			local ls = useLayer:GetEffectiveScale()
			for _, b in pairs(liveButtons) do
				-- every slot ignores right-click in a fight (only the pinned use buttons may use items)
				if type(issecretvalue) == "function" then b:RegisterForClicks("LeftButtonUp"); b.pbNoRight = true end
				if b.pbUse then
					local o = b.pbUse
					-- the slot itself ignores right-clicks until combat ends (the game's own right-click from an add-on's bag is blocked)
					b:RegisterForClicks("LeftButtonUp")
					local l, bt = b:GetLeft(), b:GetBottom()
					local here = b:IsVisible() or (PB.toggleBtn and inv and b.pbWindow == inv and not inv.offline and b:IsShown())
					if here and not useOff and not PB.testClick and l and bt then
						local sc = b:GetEffectiveScale() / ls
						o:ClearAllPoints(); o:SetPoint("BOTTOMLEFT", useLayer, "BOTTOMLEFT", l * sc, bt * sc)
						o:SetSize(b:GetWidth() * sc, b:GetHeight() * sc)
						o:SetFrameStrata(USE_STRATA); o:SetFrameLevel(5); o:Show()
						PB.fightLock = true
					else
						o:Hide(); o:ClearAllPoints()
					end
				end
			end
			if PB.PinSecureClose then PB.PinSecureClose(ls) end
			return
		end
		if (e == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or e == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE") and PIT and not STEP_ASIDE[a1] then return end
		UseOverlays(not open[e])
	end)
end
local function LiveButton(bag, slot)
	local key = bag * 100 + slot
	local b = liveButtons[key]
	if b then return b end
	nameN = nameN + 1
	local name = "PintsBagsItem" .. nameN
	local parent = BagFrame(bag)
	local ok, nb = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
	if not ok or not nb then nb = CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate") end
	b = nb
	b:SetID(slot)
	b.pbBag, b.pbSlot = bag, slot
	-- the button finds its bag from its parent frame's id. Never replace the game's own GetBagID: the click that
	-- uses an item runs through it, and an add-on's version there gets "blocked from an action" on the modern client
	if not b.GetBagID then b.GetBagID = function() return bag end end
	if not b.GetSlotAndBagID then b.GetSlotAndBagID = function() return slot, bag end end
	Decorate(b)
	if bag == BANK_ID then
		-- the main bank slots aren't a normal bag for tooltips
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local inv = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(slot)
			if inv then GameTooltip:SetInventoryItem("player", inv) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide(); ResetCursor() end)
	end
	b:HookScript("OnEnter", function(self)
		if C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) then C_NewItems.RemoveNewItem(bag, slot); self.pbNew:Hide() end
		if PB.hoverFlash then PB.hoverFlash(self) end
		if self.pbMerged and GameTooltip:IsOwned(self) then
			GameTooltip:AddLine(("%d in %d stacks"):format(self.pbMerged[2], self.pbMerged[1]), 0.6, 0.8, 1)
			GameTooltip:Show()
		end
		if self.pbFreeFamily and self:IsShown() and self.pbWindow then PB.FreeTip(self, self.pbFreeFamily, self.pbWindow) end
	end)
	AddUse(b, bag, slot)
	if InCombatLockdown() and type(issecretvalue) == "function" then b:RegisterForClicks("LeftButtonUp"); b.pbNoRight = true end
	liveButtons[key] = b
	return b
end
local offN = 0
local function OffButton(i)
	local b = offButtons[i]
	if b then return b end
	offN = offN + 1
	b = CreateFrame("Button", "PintsBagsOffline" .. offN, UIParent, "ItemButtonTemplate")
	Decorate(b)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", function(self)
		if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self) if self.link then HandleModifiedItemClick(self.link) end end)
	offButtons[i] = b
	return b
end

-- is this junk? grey quality, or on Pint's Junk's quick list ("sell" = coin, "destroy" = red cross)
local function JunkMark(link, quality)
	if quality == 0 then return "sell" end
	local quick = PintsJunkDB and PintsJunkDB.quick
	if not quick then return nil end
	local id = link and tonumber(link:match("item:(%d+)"))
	return id and quick[id] or nil
end
PB.JunkMark = JunkMark
-- paint one slot. data = { link, count, quality, texture, locked, bound, quest = {isQuestItem, questID, isActive}, new }
local BLUE_FRAME = 651080
local function Paint(b, bag, d, search)
	local icon, count = Icon(b), CountText(b)
	if d and d.link then
		local name, _, quality, level, _, _, _, _, loc, tex = GetItemInfo(d.link)
		quality = d.quality or quality
		if icon then icon:SetTexture(d.texture or tex or GetItemIcon and GetItemIcon(d.link)); icon:Show() end
		if SetItemButtonCount then SetItemButtonCount(b, d.count or 1) elseif count then count:SetText((d.count or 1) > 1 and d.count or "") end
		b.pbBack:Hide(); if b.pbTint then b.pbTint:Hide() end
		-- quality border
		if db.quality and quality and quality >= 2 then
			local r, g, bl = GetItemQualityColor(quality)
			b.pbGlow:SetVertexColor(r, g, bl, 1); b.pbGlow:SetAlpha(0.75); b.pbGlow:Show()
		else b.pbGlow:Hide() end
		-- quest items
		local q = d.quest
		if db.quest and q and (q.questID and not q.isActive) then b.pbQuest:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBang"); b.pbQuest:Show()
		elseif db.quest and q and (q.isQuestItem or q.questID) then b.pbQuest:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBorder"); b.pbQuest:Show()
		else b.pbQuest:Hide() end
		b.pbNew:SetShown(db.newGlow and d.new or false)
		local junk = db.junkMark ~= false and JunkMark(d.link, quality)
		if junk then
			-- the game's own junk coin where it has one (WoW Forever), else the gold coin; a red cross for "destroy"
			if junk == "destroy" then b.pbJunk:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
			elseif not (b.pbJunk.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-junkcoin") and b.pbJunk:SetAtlas("bags-junkcoin") ~= false) then
				b.pbJunk:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
			end
			b.pbJunk:Show()
		else b.pbJunk:Hide() end
		local gear = loc and loc ~= "" and loc ~= "INVTYPE_BAG" and loc ~= "INVTYPE_AMMO"
		b.pbLevel:SetText((db.ilvl and gear and level and level > 1) and level or "")
		local dim = not Matches(d.link, search, d.bound) or (db.dimJunk and quality == 0)
		if SetItemButtonDesaturated then SetItemButtonDesaturated(b, d.locked or dim) end
		b:SetAlpha(dim and 0.3 or 1)
	else
		if icon then icon:SetTexture(nil); icon:Hide() end
		if SetItemButtonCount then SetItemButtonCount(b, 0) elseif count then count:SetText("") end
		b.pbBack:Show(); b.pbGlow:Hide(); b.pbQuest:Hide(); b.pbNew:Hide(); b.pbJunk:Hide(); b.pbLevel:SetText("")
		if b.pbTint then b.pbTint:SetShown(REAGENT ~= nil and bag == REAGENT) end
		b:SetAlpha((search and search ~= "") and 0.3 or 1)
	end
	-- the slot frame: the game's own (blue) border in the grouped view; in the one big bag it goes,
	-- and a light edge in each bag's colour shows where one bag ends and the next begins
	local nt = b.GetNormalTexture and b:GetNormalTexture()
	-- every other piece of the game's slot art (whatever this client draws round the icon) follows the same rule
	local mine = { [b.pbEdge] = true, [b.pbBack] = true, [b.pbTint or 0] = true, [b.pbGlow] = true, [b.pbQuest] = true, [b.pbNew] = true, [icon or 0] = true, [b.IconBorder or 0] = true }
	local plain = db.view ~= "category"
	for _, r in ipairs({ b:GetRegions() }) do
		if r.GetTexture and not mine[r] and r ~= (b.GetHighlightTexture and b:GetHighlightTexture()) and r ~= (b.GetPushedTexture and b:GetPushedTexture()) then
			if not r.pbSeen then
				r.pbSeen = true
				db.slotArt = db.slotArt or {}
				local t = r:GetTexture(); local a = r.GetAtlas and r:GetAtlas()
				local key = tostring(r.GetDebugName and r:GetDebugName() or "?"):gsub("^PintsBags%a*%d*%.?", "") .. " = " .. tostring(a or t) .. " (" .. tostring(r:GetDrawLayer()) .. ")"
				db.slotArt[key] = true
			end
			-- hide it in the big bag; in the grouped view put back exactly what it was (some of these are meant to stay invisible)
			if r ~= icon then
				if plain then
					if r.pbAlpha == nil then r.pbAlpha = r:GetAlpha() end
					r:SetAlpha(0)
				elseif r.pbAlpha ~= nil then
					r:SetAlpha(r.pbAlpha); r.pbAlpha = nil
				end
				-- the blue slot frame (texture 651080): softened in the grouped view
				if not plain and r:GetTexture() == BLUE_FRAME then
					if r.pbBase == nil then r.pbBase = r:GetAlpha() end
					r:SetAlpha(r.pbBase * (db.frameSoft or 0.55))
				end
			end
		end
	end
	if plain then
		if nt then if nt.pbAlpha == nil then nt.pbAlpha = nt:GetAlpha() end; nt:SetAlpha(0) end
		local r, g, bl = PB.BagColor(bag)
		b.pbEdge:SetVertexColor(r, g, bl, 0.35); b.pbEdge:Show()
		b.pbBack:SetVertexColor(1, 1, 1)
		return
	end
	if nt and nt.pbAlpha ~= nil then nt:SetAlpha(nt.pbAlpha); nt.pbAlpha = nil end
	-- the colour of the bag it lives in
	if db.bagColors then
		local r, g, bl = PB.BagColor(bag)
		b.pbEdge:SetVertexColor(r, g, bl, db.colorStrength); b.pbEdge:Show()
		b.pbBack:SetVertexColor(0.55 + r * 0.45, 0.55 + g * 0.45, 0.55 + bl * 0.45)
	else
		b.pbEdge:Hide(); b.pbBack:SetVertexColor(1, 1, 1)
	end
end

local function LiveData(bag, slot)
	local info = SlotInfo(bag, slot)
	if not info or not info.hyperlink then return nil end
	local q = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
	return { link = info.hyperlink, count = info.stackCount, quality = info.quality, texture = info.iconFileID, locked = info.isLocked, bound = info.isBound,
		quest = q, new = C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) }
end
local function Cooldown(b, bag, slot)
	local cd = b.Cooldown or _G[(b:GetName() or "") .. "Cooldown"]
	if not cd or not C.GetContainerItemCooldown then return end
	local start, dur, enable = C.GetContainerItemCooldown(bag, slot)
	if CooldownFrame_Set then CooldownFrame_Set(cd, start or 0, dur or 0, enable) end
end

---------------------------------------------------------------- windows
local windows = {}
PB.windows = windows
local function Btn(parent, icon, tip, onClick, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 22, size or 22)
	local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetTexture(icon); t:SetTexCoord(0.08, 0.92, 0.08, 0.92); b.tex = t
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(type(tip) == "function" and tip() or tip, 1, 1, 1, true); GameTooltip:Show() end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local menu
local function Menu(anchor, items)
	if not menu then
		menu = CreateFrame("Frame", "PintsBagsMenu", UIParent, "BackdropTemplate")
		menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetClampedToScreen(true); menu:EnableMouse(true)
		menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		menu:SetBackdropColor(0, 0, 0, 0.95); menu.b = {}
		tinsert(UISpecialFrames, "PintsBagsMenu")
	end
	for i, it in ipairs(items) do
		local b = menu.b[i]
		if not b then
			b = CreateFrame("Button", nil, menu); b:SetSize(200, 16); b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 16)
			b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 4, 0)
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.18)
			menu.b[i] = b
		end
		b.t:SetText(it.text); b:EnableMouse(it.fn ~= nil)
		b:SetScript("OnClick", function() menu:Hide(); if it.fn then it.fn() end end)
		b:Show()
	end
	for i = #items + 1, #menu.b do menu.b[i]:Hide() end
	menu:SetSize(216, #items * 16 + 12)
	menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2); menu:Show()
end

-- the bag slots along the top (equip, swap, buy bank slots); hovering one shows only its slots
local function BagSlotButton(w, bag)
	local b = CreateFrame("Button", nil, w.bagBar)
	b:SetSize(26, 26)
	b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
	b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -2, 2); b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForDrag("LeftButton")
	local inv = (bag ~= 0 and bag ~= BANK_ID) and C.ContainerIDToInventoryID and select(2, pcall(C.ContainerIDToInventoryID, bag))
	if type(inv) ~= "number" then inv = nil end
	b.inv, b.bag = inv, bag
	if TABS and TAB_BAG and w.kind == "bank" and TabNumber(bag) then
		-- WoW Forever bank bag slot: pick up / put down the bag at (Characterbanktab, n); tab 1 is the bank itself
		local n = TabNumber(bag)
		b.tabN = n
		local function pick() if not w.offline and n > 1 and not b.locked and not InCombatLockdown() then C.PickupContainerItem(TAB_BAG, n) end end
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, btn)
			if w.offline or n == 1 then return end
			if b.locked then if PB.atBank and n == TabsBought() + 1 then BuyBankTab() end; return end
			pick()
		end)
		b:SetScript("OnDragStart", pick)
		b:SetScript("OnReceiveDrag", pick)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if n == 1 then GameTooltip:AddLine(_G.BANK or "Bank")
			elseif self.locked then
				GameTooltip:AddLine("Bank bag slot - not bought yet", 0.7, 0.7, 0.7)
				local cost = NextTabCost()
				if PB.atBank and n == TabsBought() + 1 then
					GameTooltip:AddLine("Click to buy" .. (cost and (": " .. Money(cost)) or ""), 0.4, 1, 0.4)
				elseif not PB.atBank then GameTooltip:AddLine("Buy it at a banker", 0.6, 0.6, 0.6) end
			elseif self.link then GameTooltip:SetHyperlink(self.link)
			elseif not (not w.offline and GameTooltip:SetBagItem(TAB_BAG, n)) then
				GameTooltip:AddLine("Empty bank bag slot", 0.7, 0.7, 0.7)
				GameTooltip:AddLine("Drop a bag here", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
			if not self.locked then w.onlyBag = bag; PB.Refresh(w) end      -- (a slot not bought yet has nothing to light up)
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide(); if w.onlyBag then w.onlyBag = nil; PB.Refresh(w) end end)
		return b
	end
	local function put() if inv and CursorHasItem() then PutItemInBag(inv) end end
	b:SetScript("OnClick", function() if not w.offline and inv then if CursorHasItem() then PutItemInBag(inv) else PickupBagFromSlot(inv) end end end)
	b:SetScript("OnDragStart", function() if not w.offline and inv then PickupBagFromSlot(inv) end end)
	b:SetScript("OnReceiveDrag", put)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if bag == 0 then GameTooltip:AddLine(BACKPACK_TOOLTIP or "Backpack")
		elseif bag == BANK_ID then GameTooltip:AddLine(_G.BANK or "Bank")
		elseif self.link then GameTooltip:SetHyperlink(self.link)
		elseif not w.offline and inv and GetInventoryItemLink("player", inv) then GameTooltip:SetInventoryItem("player", inv)
		else GameTooltip:AddLine(self.locked and "Bank slot not bought" or "Empty bag slot", 0.7, 0.7, 0.7) end
		GameTooltip:Show()
		w.onlyBag = bag; PB.Refresh(w)
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide(); w.onlyBag = nil; PB.Refresh(w) end)
	return b
end

local function SavePos(w)
	local p, _, rp, x, y = w:GetPoint()
	db.pos[w.kind] = { p, rp, x, y }
end
local function MakeWindow(kind)
	local w = CreateFrame("Frame", kind == "inv" and "PintsBagsInventory" or "PintsBagsBank", UIParent, "BackdropTemplate")
	w.kind, w.bags = kind, kind == "inv" and INV or BANK
	w:SetFrameStrata("HIGH"); w:SetToplevel(true); w:SetClampedToScreen(true)
	w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
	w:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	w:SetBackdropColor(0.05, 0.05, 0.05, 0.92); w:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
	w:SetScript("OnDragStart", function(self) if not db.locked and not (PB.fightLock and InCombatLockdown()) then self:StartMoving() end end)
	w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos(self) end)
	w:Hide()
	tinsert(UISpecialFrames, w:GetName())

	-- top row: character, bag slots, sort, search | title | options, close
	local x = 8
	w.charBtn = Btn(w, "Interface\\Icons\\INV_Misc_GroupNeedMore", "Show another character's bags", function(self) PB.CharMenu(w, self) end)
	w.charBtn:SetPoint("TOPLEFT", x, -8)
	w.bagBtn = Btn(w, "Interface\\Icons\\INV_Misc_Bag_08", "Show the bag slots", function() db.bagBar = not db.bagBar; PB.Refresh(w) end)
	w.bagBtn:SetPoint("LEFT", w.charBtn, "RIGHT", 4, 0)
	w.sortBtn = Btn(w, "Interface\\Icons\\INV_Misc_Broom_01" , "Sort", function() PB.Sort(w) end)
	w.sortBtn.tex:SetTexture("Interface\\Icons\\Ability_Repair")
	w.sortBtn:SetPoint("LEFT", w.bagBtn, "RIGHT", 4, 0)
	w.findBtn = Btn(w, "Interface\\Icons\\INV_Misc_Spyglass_02", "Search (or just start typing in the box)", function() w.search:Show(); w.search:SetFocus() end)
	w.findBtn:SetPoint("LEFT", w.sortBtn, "RIGHT", 4, 0)
	w.viewBtn = Btn(w, "Interface\\Icons\\INV_Misc_Note_02", function() return db.view == "category" and "Showing groups - click for one big bag (every slot, in bag order)" or "Showing one big bag - click to group by kind" end,
		function() db.view = (db.view == "category") and "bags" or "category"; PB.RefreshAll() end)
	w.viewBtn:SetPoint("LEFT", w.findBtn, "RIGHT", 4, 0)
	w.headers = {}
	w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal"); w.title:SetPoint("LEFT", w.viewBtn, "RIGHT", 8, 0); w.title:SetJustifyH("LEFT")
	w.close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); w.close:SetPoint("TOPRIGHT", 0, 0)
	w.close:SetScript("OnClick", function() w:Hide() end)
	w.optBtn = Btn(w, "Interface\\Icons\\INV_Misc_Gear_01", "Options", function() PB.ToggleOptions() end)
	w.optBtn:SetPoint("RIGHT", w.close, "LEFT", -2, 0)

	-- search box over the title
	w.search = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
	w.search:SetHeight(20); w.search:SetPoint("LEFT", w.viewBtn, "RIGHT", 10, 0); w.search:SetPoint("RIGHT", w.optBtn, "LEFT", -8, 0)
	w.search:SetAutoFocus(false); w.search:Hide()
	w.search:SetScript("OnTextChanged", function(self) PB.searchText = self:GetText(); for _, ow in pairs(windows) do if ow ~= w and ow.search:GetText() ~= PB.searchText then ow.search:SetText(PB.searchText); ow.search:SetShown(PB.searchText ~= "") end; PB.Refresh(ow) end end)
	w.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); self:Hide() end)
	w.search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if self:GetText() == "" then self:Hide() end end)
	w.search:SetScript("OnShow", function() w.title:Hide() end)
	w.search:SetScript("OnHide", function() w.title:Show() end)

	-- bag slot bar
	w.bagBar = CreateFrame("Frame", nil, w); w.bagBar:SetHeight(30); w.bagBar:SetPoint("TOPLEFT", 10, -36); w.bagBar:SetPoint("TOPRIGHT", -10, -36)
	w.bagSlots = {}
	for i, bag in ipairs(w.bags) do
		local b = BagSlotButton(w, bag)
		b:SetPoint("LEFT", (i - 1) * 30, 0)
		w.bagSlots[i] = b
	end
	if kind == "bank" then
		w.buy = CreateFrame("Button", nil, w.bagBar, "UIPanelButtonTemplate"); w.buy:SetSize(110, 22); w.buy:SetPoint("LEFT", #w.bags * 30 + 6, 0)
		w.buy:SetText("Buy bag slot")
		-- leaving the bank window: the game's purchase button goes back where it belongs
		w:HookScript("OnHide", function() if PB.RestashBlizzardBank then C_Timer.After(0, PB.RestashBlizzardBank) end end)
		-- the price, read from the game (WoW Forever: the next bank bag slot's cost)
		-- (just after the bag slots, inside the window)
		w.buyCost = w.bagBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); w.buyCost:SetPoint("LEFT", w.bagSlots[#w.bagSlots], "RIGHT", 8, 0)
		w.buy:SetScript("OnClick", function()
			-- (WoW Forever: the game's own purchase button normally sits over this one and takes the click)
			if TABS then if PB.ShowBlizzardBank then PB.ShowBlizzardBank() end; return end
			local cost = GetBankSlotCost and GetBankSlotCost(GetNumBankSlots())
			if not cost then return end
			if BankFrame then BankFrame.nextSlotCost = cost end
			StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
		end)
		w.buy:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP"); local cost = TABS and NextTabCost() or (GetBankSlotCost and GetBankSlotCost(GetNumBankSlots()))
			GameTooltip:AddLine("Buy another bank bag slot"); if cost then GameTooltip:AddLine(Money(cost), 1, 1, 1) end; GameTooltip:Show()
		end)
		w.buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	-- the item grid
	w.grid = CreateFrame("Frame", nil, w); w.grid:SetPoint("TOPLEFT", 10, -36); w.grid:SetSize(280, 40)

	-- bottom: free slots, gold
	w.free = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); w.free:SetPoint("BOTTOMLEFT", 12, 10)
	w.money = CreateFrame("Button", nil, w); w.money:SetSize(160, 16); w.money:SetPoint("BOTTOMRIGHT", -12, 8)
	w.money.t = w.money:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); w.money.t:SetPoint("RIGHT")
	w.money:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:AddLine("Gold on " .. REALM)
		local total, list = 0, {}
		for n, rec in pairs(LedgerChars()) do local m = (n == ME) and GetMoney() or rec.money or 0; total = total + m; list[#list + 1] = { n, m, rec.classFile } end
		if #list == 0 then list[1] = { ME, GetMoney(), select(2, UnitClass("player")) }; total = GetMoney() end
		table.sort(list, function(a, b) return a[2] > b[2] end)
		for _, c in ipairs(list) do
			local col = RAID_CLASS_COLORS[c[3] or ""]; GameTooltip:AddDoubleLine(c[1], Money(c[2]), col and col.r or 1, col and col.g or 1, col and col.b or 1, 1, 1, 1)
		end
		GameTooltip:AddLine(" "); GameTooltip:AddDoubleLine("Total", Money(total), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:Show()
	end)
	w.money:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- currencies, just left of the gold
	-- two currency spots in the middle of the bottom edge (Merchant's Favor and Honor Points to start), away from the
	-- gold so they aren't misread at a glance. Hover: every character's amount and the account total. Click: pick another.
	w.curBtn = {}
	for i = 1, 2 do
		local b = CreateFrame("Button", nil, w); b:SetSize(16, 16); b:EnableMouse(true)
		if i == 1 then b:SetPoint("BOTTOMRIGHT", w, "BOTTOM", -12, 8) else b:SetPoint("BOTTOMLEFT", w, "BOTTOM", 8, 8) end   -- (until spaced)
		b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.t:SetPoint("RIGHT")
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if self.name then CurrencyTooltip(self.name, self.icon) else GameTooltip:AddLine("Empty currency spot") end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Click: show a different currency here", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(self)
			GameTooltip:Hide()
			-- (clicking the spot again closes the list)
			local m = _G.PintsBagsCurrencyMenu
			if m and m:IsShown() and m.anchor == self then m:Hide(); return end
			PickCurrency(self, i, function() PB.RefreshAll() end)
		end)
		w.curBtn[i] = b
	end

	w:SetScript("OnShow", function(self)
		PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN or 862); PB.Refresh(self)
		if self.kind == "inv" and PB.SyncUseLayer then PB.SyncUseLayer() end
	end)
	w:SetScript("OnHide", function(self)
		if self.kind == "inv" and PB.fightLock and InCombatLockdown() and not PB.secureToggle and not (PB.toggleBtn and not useLayer:IsShown()) then
			-- in a fight only the bag key, the minimap button or the X may close the bags (they put the use buttons away
			-- with them); anything else (Escape) would leave them behind, so the bags stay open
			C_Timer.After(0, function() if PB.fightLock and InCombatLockdown() and useLayer:IsShown() then self:Show() end end)
			if not PB.lockNote then PB.lockNote = true; Print("in a fight, close the bags with your bag key, the minimap button or the X.") end
			return
		end
		if self.kind == "inv" and PB.SyncUseLayer then C_Timer.After(0, PB.SyncUseLayer) end
		PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE or 863)
		self.viewing = nil
		if self.kind == "bank" and PB.atBank then
			PB.atBank = false
			local close = CloseBankFrame or (C_Bank and C_Bank.CloseBankFrame)
			if close then pcall(close) elseif C_PlayerInteractionManager and C_PlayerInteractionManager.ClearInteraction then pcall(C_PlayerInteractionManager.ClearInteraction) end
		end
		if self.kind == "inv" and C_NewItems and C_NewItems.ClearAll and db.newGlow then C_NewItems.ClearAll() end
		if menu then menu:Hide() end
	end)
	-- position
	local p = db.pos[kind]
	if p then w:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	elseif kind == "inv" then w:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110)
	else w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -110) end
	windows[kind] = w
	return w
end
function PB.Window(kind) return windows[kind] or MakeWindow(kind) end

-- choose whose bags to show
function PB.CharMenu(w, anchor)
	local items = { { text = "|cffffd100Show bags of|r" } }
	items[#items + 1] = { text = "   " .. ME .. " |cff888888(you)|r", fn = function() w.viewing = nil; PB.Refresh(w) end }
	local names = {}
	for n in pairs(LedgerChars()) do if n ~= ME then names[#names + 1] = n end end
	table.sort(names)
	for _, n in ipairs(names) do
		local rec = LedgerRec(n)
		local col = rec and RAID_CLASS_COLORS[rec.classFile or ""]
		local hex = col and col.colorStr and ("|c" .. col.colorStr) or "|cffffffff"
		items[#items + 1] = { text = "   " .. hex .. n .. "|r", fn = function() w.viewing = n; PB.Refresh(w) end }
	end
	if #names == 0 then items[#items + 1] = { text = "   |cff888888(Pint's Alts remembers your others)|r" } end
	if w.kind == "inv" then
		items[#items + 1] = { text = "|cffffd100Bank|r of " .. (w.viewing or ME) .. "...", fn = function() local b = PB.Window("bank"); b.viewing = w.viewing or (not PB.atBank and ME) or nil; b:Show(); PB.Refresh(b) end }
	end
	Menu(anchor, items)
end

---------------------------------------------------------------- filling a window
local function Layout(w, n)
	local size, gap, cols = db.size, db.spacing, db.columns
	local rows = math.max(1, math.ceil(n / cols))
	local top = db.bagBar and 66 or 36
	w.grid:ClearAllPoints(); w.grid:SetPoint("TOPLEFT", 10, -top)
	local width = math.max(cols * (size + gap) - gap + 20, 300)
	w:SetSize(width, top + rows * (size + gap) - gap + 34)
	w.grid:SetSize(width - 20, math.max(1, rows * (size + gap) - gap))
	return size, gap, cols
end
local function Place(b, i, size, gap, cols, parentGrid)
	b:ClearAllPoints()
	b:SetSize(size, size)
	local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
	b:SetPoint("TOPLEFT", parentGrid, "TOPLEFT", col * (size + gap), -row * (size + gap))
	if b.pbGlow then b.pbGlow:SetSize(size * 1.8, size * 1.8) end
end

---------------------------------------------------------------- what a free slot is for
local FAMILY = { [1] = "Quiver (arrows)", [2] = "Ammo Pouch (bullets)", [4] = "Soul Bag (soul shards)", [8] = "Leatherworking Bag",
	[32] = "Herb Bag (herbs)", [64] = "Enchanting Bag", [128] = "Engineering Bag", [256] = "Keys", [1024] = "Mining Bag" }
local function FamilyName(f)
	if f == 0 then return "Any item (ordinary bags)" end
	if FAMILY[f] then return FAMILY[f] end
	local out = {}
	for bit, n in pairs(FAMILY) do if f % (bit * 2) >= bit then out[#out + 1] = n end end
	return #out > 0 and table.concat(out, ", ") or ("special bag (" .. f .. ")")
end
function PB.FreeTip(owner, family, w)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Free space")
	GameTooltip:AddLine("For: " .. FamilyName(family), 1, 1, 1)
	local BagName = C.GetBagName or GetBagName
	for _, bag in ipairs(w.bags) do
		if BagFamily(bag) == family and NumSlots(bag) > 0 then
			local free = C.GetContainerNumFreeSlots(bag) or 0
			local name = (bag == 0 and (BACKPACK_TOOLTIP or "Backpack")) or (bag == BANK_ID and (_G.BANK or "Bank")) or (BagName and BagName(bag)) or ("Bag " .. bag)
			local r, g, b = PB.BagColor(bag)
			GameTooltip:AddDoubleLine(name, free .. " of " .. NumSlots(bag) .. " free", r, g, b, 1, 1, 1)
		end
	end
	GameTooltip:AddLine("Drop an item here to put it in that kind of bag.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

---------------------------------------------------------------- grouped view: items sorted into kinds, in columns
local CATS = { { "hearth", "Hearthstone" }, { "equip", "Equipment" }, { "cons", "Consumables" }, { "tools", "Profession Tools" }, { "cook", "Cooking" },
	{ "trade", "Tradeskill" }, { "reagent", "Reagents" },
	{ "recipe", "Recipes" }, { "quest", "Quest Items" }, { "ammo", "Ammo" }, { "bags", "Bags" }, { "keys", "Keys" }, { "misc", "Miscellaneous" },
	{ "junk", "Junk" }, { "free", "Free space" } }
local CLASSCAT = { [0] = "cons", [1] = "bags", [2] = "equip", [4] = "equip", [5] = "reagent", [6] = "ammo", [11] = "ammo", [7] = "trade",
	[9] = "recipe", [12] = "quest", [13] = "keys", [15] = "misc" }
-- cooking ingredients: mostly used by Cooking recipes (Pint's Tips knows every recipe's reagents), or the game calls it meat
local function IsCooking(id, classID, subID)
	local uses = PintsTipsUse and PintsTipsUse.prof and PintsTipsUse.prof[id]
	if uses then
		local cook, other = 0, 0
		for skill in uses:gmatch("(%d+),[^;]*") do if skill == "185" then cook = cook + 1 else other = other + 1 end end
		if cook > 0 and cook >= other then return true end
		if other > 0 then return false end
	end
	return classID == 7 and subID == 8
end
-- items professions need on hand (the game checks your bags for them), plus fishing poles
local PROF_TOOLS = {
	[2901] = true,   -- Mining Pick
	[7005] = true,   -- Skinning Knife
	[5956] = true,   -- Blacksmith Hammer
	[6219] = true,   -- Arclight Spanner
	[10498] = true,  -- Gyromatic Micro-Adjustor
	[6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true,   -- Runed Copper/Silver/Golden/Truesilver/Arcanite Rods
	[9149] = true,   -- Philosopher's Stone
	[15846] = true,  -- Salt Shaker
	[4471] = true,   -- Flint and Tinder
	[5060] = true,   -- Thieves' Tools
}
PB.PROF_TOOLS = PROF_TOOLS
local function Category(d)
	local id = tonumber(d.link:match("item:(%d+)"))
	if id == 6948 then return "hearth" end
	if PROF_TOOLS[id] then return "tools" end
	local _, _, _, _, _, cls, sub = GetItemInfoInstant(d.link)
	if cls == 2 and sub == 20 then return "tools" end   -- fishing poles
	local _, _, quality = GetItemInfo(d.link)
	quality = d.quality or quality
	if d.quest and (d.quest.isQuestItem or d.quest.questID) then return "quest" end
	if quality == 0 then return "junk" end
	local _, _, _, _, _, classID, subID = GetItemInfoInstant(d.link)
	if classID ~= 0 and IsCooking(id, classID, subID) then return "cook" end
	return CLASSCAT[classID or 15] or "misc"
end
PB.Category = Category
local function Header(w, i)
	local h = w.headers[i]
	if not h then h = w.grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h:SetJustifyH("LEFT"); w.headers[i] = h end
	h:Show()
	return h
end
function PB.CategoryLayout(w, list, offline)
	local size, gap = db.size, db.spacing
	local lanes = math.max(1, db.lanes)
	local laneCols = math.max(3, math.floor(db.columns / lanes))
	local laneW, laneGap, headH = laneCols * (size + gap) - gap, 14, 16
	local buckets, free = {}, {}
	-- the same item in several stacks shows once, with the total (the bags themselves aren't changed)
	local firstOf = {}
	if db.combine then
		for _, e in ipairs(list) do
			if e.d and e.d.link then
				local f = firstOf[e.d.link]
				if f then f.mTotal = f.mTotal + (e.d.count or 1); f.mStacks = f.mStacks + 1; e.mergedAway = true
				else firstOf[e.d.link] = e; e.mTotal = e.d.count or 1; e.mStacks = 1 end
			end
		end
	end
	for _, e in ipairs(list) do
		if e.d and e.mergedAway then
			-- shown as part of another stack
		elseif e.d then
			local c = Category(e.d)
			buckets[c] = buckets[c] or {}
			local k = SortKeyFor and SortKeyFor(e.d.link, e.d.count) or nil
			e.key = k
			table.insert(buckets[c], e)
		else
			local f = free[e.family]
			if not f then f = { first = e, n = 0 }; free[e.family] = f end
			f.n = f.n + 1
		end
	end
	-- free space: one empty slot per kind of bag, with how many are left on it (drop things on it)
	buckets.free = {}
	for fam, f in pairs(free) do f.first.freeN = f.n; table.insert(buckets.free, f.first) end
	table.sort(buckets.free, function(a, b) return a.family < b.family end)
	local laneH = {}
	for i = 1, lanes do laneH[i] = 0 end
	local hi = 0
	for _, cat in ipairs(CATS) do
		local items = buckets[cat[1]]
		if items and #items > 0 and cat[1] ~= "free" then
			-- in bag order (so moving things by hand sticks, and the broom decides the order), or always auto-sorted
			if db.groupSorted then table.sort(items, function(a, b) return SortBefore(a.key, b.key) end)
			else table.sort(items, function(a, b) return a.idx < b.idx end) end
			local lane = 1
			for i = 2, lanes do if laneH[i] < laneH[lane] then lane = i end end
			local x0, y0 = (lane - 1) * (laneW + laneGap), -laneH[lane]
			hi = hi + 1
			local h = Header(w, hi)
			h:ClearAllPoints(); h:SetPoint("TOPLEFT", w.grid, "TOPLEFT", x0, y0)
			local count = 0
			for _, e in ipairs(items) do count = count + ((cat[1] == "free") and (e.freeN or 1) or 1) end
			h:SetText(cat[2] .. (cat[1] == "free" and "" or (" |cff888888" .. #items .. "|r")))
			for i, e in ipairs(items) do
				local b = e.b
				local col, row = (i - 1) % laneCols, math.floor((i - 1) / laneCols)
				b:ClearAllPoints(); b:SetSize(size, size)
				b:SetPoint("TOPLEFT", w.grid, "TOPLEFT", x0 + col * (size + gap), y0 - headH - row * (size + gap))
				if b.pbGlow then b.pbGlow:SetSize(size * 1.8, size * 1.8) end
				b:SetFrameLevel(w:GetFrameLevel() + 5)
				if cat[1] == "free" then b.pbFreeText:SetText(e.freeN or "") end
				b:Show()
			end
			local rows = math.ceil(#items / laneCols)
			laneH[lane] = laneH[lane] + headH + rows * (size + gap) - gap + 10
		end
	end
	-- free space always goes last, across the bottom
	local tall = 0
	for i = 1, lanes do tall = math.max(tall, laneH[i]) end
	local fullW = lanes * laneW + (lanes - 1) * laneGap
	if #buckets.free > 0 then
		hi = hi + 1
		local h = Header(w, hi)
		h:ClearAllPoints(); h:SetPoint("TOPLEFT", w.grid, "TOPLEFT", 0, -tall)
		h:SetText("Free space")
		local fullCols = math.max(1, math.floor((fullW + gap) / (size + gap)))
		for i, e in ipairs(buckets.free) do
			local b = e.b
			local col, row = (i - 1) % fullCols, math.floor((i - 1) / fullCols)
			b:ClearAllPoints(); b:SetSize(size, size)
			b:SetPoint("TOPLEFT", w.grid, "TOPLEFT", col * (size + gap), -tall - headH - row * (size + gap))
			if b.pbGlow then b.pbGlow:SetSize(size * 1.8, size * 1.8) end
			b:SetFrameLevel(w:GetFrameLevel() + 5)
			b.pbFreeText:SetText(e.freeN or "")
			b:Show()
		end
		tall = tall + headH + math.ceil(#buckets.free / fullCols) * (size + gap) - gap
	end
	-- the empty slots that aren't the "free space" one stay hidden
	for _, e in ipairs(list) do
		local b = e.b
		b.pbMerged, b.pbFreeFamily = nil, nil
		if e.mergedAway or (not e.d and not e.freeN) then b:Hide() end
		if e.freeN then b.pbFreeFamily = e.family end
		if e.mStacks and e.mStacks > 1 then
			b.pbMerged = { e.mStacks, e.mTotal }
			local ct = CountText(b)
			if ct then ct:SetText(e.mTotal > 9999 and (math.floor(e.mTotal / 1000) .. "k") or e.mTotal); ct:Show() end
		end
		e.mergedAway, e.mTotal, e.mStacks = nil, nil, nil
	end
	for _, e in ipairs(list) do e.freeN = nil end
	local top = db.bagBar and 66 or 36
	w.grid:ClearAllPoints(); w.grid:SetPoint("TOPLEFT", 10, -top)
	w:SetSize(math.max(lanes * laneW + (lanes - 1) * laneGap + 20, 300), top + math.max(tall, size) + 30)
	w.grid:SetSize(math.max(lanes * laneW + (lanes - 1) * laneGap, 280), math.max(tall, size))
end

function PB.Refresh(w, force)
	if not w or (not w:IsShown() and not force) or not db then return end
	-- (in a fight the window can be locked by the game - its secure parts - even without pinned use buttons: then only repaint)
	if InCombatLockdown() and (PB.fightLock or w:IsProtected()) then
		-- mid-fight with pinned use buttons: nothing moves - just repaint what's in each slot; the full update waits for the end
		for _, b in pairs(liveButtons) do
			if b.pbWindow == w and b:IsVisible() and not w.offline then Paint(b, b.pbBag, LiveData(b.pbBag, b.pbSlot), PB.searchText); Cooldown(b, b.pbBag, b.pbSlot) end
		end
		w.money.t:SetText(Money(GetMoney()))
		PB.UpdateCurrencySlots(w, nil)
		return
	end
	w:SetScale(db.scale)
	local search = PB.searchText
	local offline = w.viewing and (w.viewing ~= ME or (w.kind == "bank" and not PB.atBank)) and true or false
	w.offline = offline
	local who = w.viewing or ME
	w.title:SetText(who .. "'s " .. (w.kind == "inv" and "Bags" or "Bank") .. (offline and " |cff888888(saved)|r" or ""))
	for _, b in pairs(liveButtons) do if b.pbWindow == w then b:Hide() end end
	for _, b in ipairs(offButtons) do if b.pbWindow == w then b:Hide(); b.pbWindow = nil end end

	-- the bag bar
	w.bagBar:SetShown(db.bagBar)
	-- the view toggle shows what a click switches TO: the backpack (one big bag) or the list (groups)
	w.viewBtn.tex:SetTexture(db.view == "category" and "Interface\\Buttons\\Button-Backpack-Up" or "Interface\\Icons\\INV_Misc_Note_02")
	w.bagBtn.tex:SetDesaturated(not db.bagBar)
	local rec = offline and LedgerRec(who)
	for i, sb in ipairs(w.bagSlots) do
		local bag = sb.bag
		local link, tex
		if bag == 0 then tex = "Interface\\Buttons\\Button-Backpack-Up"
		elseif bag == BANK_ID then tex = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
		elseif offline then
			local s = w.kind == "inv" and rec and rec.bagSlots and rec.bagSlots[bag] or (rec and rec.bankSlots and rec.bankSlots[i])
			link = s and s.bag
			tex = link and GetItemIcon and GetItemIcon(link)
		elseif sb.tabN then
			if sb.tabN == 1 then tex = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
			else
				local info = C.GetContainerItemInfo and C.GetContainerItemInfo(TAB_BAG, sb.tabN)
				tex = info and info.iconFileID
			end
		elseif sb.inv then tex = GetInventoryItemTexture("player", sb.inv) end
		sb.link = offline and link or nil
		if sb.tabN then
			sb.locked = not offline and sb.tabN > math.max(1, TabsBought())
		else
			sb.locked = (w.kind == "bank" and bag ~= BANK_ID and not offline and GetNumBankSlots and (bag - FIRST_BANK_BAG + 1) > GetNumBankSlots())
		end
		sb.tex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
		sb.tex:SetDesaturated(sb.locked or false); sb.tex:SetVertexColor(sb.locked and 1 or 1, sb.locked and 0.3 or 1, sb.locked and 0.3 or 1)
		local r, g, b = PB.BagColor(bag)
		sb.edge:SetColorTexture(r, g, b, db.bagColors and 1 or 0)
	end
	if w.buy then
		if TABS then
			local want = not offline and PB.atBank and TabsBought() < TabsMax()
			-- with the bag slots showing you buy by clicking the next slot, so "Buy bag slot" stays hidden (it used to
			-- show for a moment on every redraw - the flicker while moving over the slots)
			w.buy:SetShown(want and not db.bagBar)
			if not want and PB.HideBuyer then PB.HideBuyer() end
			local cost = want and NextTabCost()
			w.buyCost:SetText(cost and ("|cffaaaaaaNext slot|r " .. Money(cost)) or "")
			if want and not w.dockPending then
				w.dockPending = true
				C_Timer.After(0.1, function()
					w.dockPending = nil
					if not (PB.DockPurchase and PB.DockPurchase(w)) then
						-- no game purchase button to lay over ours: fall back to bringing its bank window into view
						w.buy:SetScript("OnClick", function() if PB.ShowBlizzardBank then PB.ShowBlizzardBank() end end)
					end
				end)
			end
		else
			local n, full = GetNumBankSlots and GetNumBankSlots()
			w.buy:SetShown(not offline and PB.atBank and n and not full and n < 6)
		end
	end

	-- slots
	local list = {}
	if offline then
		local slotsTbl = rec and (w.kind == "inv" and rec.bagSlots or rec.bankSlots)
		for i, bag in ipairs(w.bags) do
			local s = slotsTbl and (w.kind == "inv" and slotsTbl[bag] or slotsTbl[i])
			if s then for slot = 1, (s.size or 0) do local d = s.slots and s.slots[slot]; list[#list + 1] = { bag = bag, slot = slot, d = d and { link = d[1], count = d[2], bound = d[3] } } end end
		end
	else
		for _, bag in ipairs(w.bags) do for slot = 1, NumSlots(bag) do list[#list + 1] = { bag = bag, slot = slot } end end
	end
	local used, total = 0, 0
	for i, e in ipairs(list) do
		local b
		if offline then b = OffButton(i); b:SetParent(w.grid); b:SetFrameStrata(w:GetFrameStrata())
		else
			b = LiveButton(e.bag, e.slot)
			local bf = BagFrame(e.bag)
			if bf:GetParent() ~= w.grid then bf:SetParent(w.grid); bf:ClearAllPoints(); bf:SetAllPoints(w.grid) end
			bf:SetFrameStrata(w:GetFrameStrata()); bf:SetFrameLevel(w:GetFrameLevel() + 2); bf:Show()
			b:SetFrameStrata(w:GetFrameStrata()); e.d = LiveData(e.bag, e.slot); Cooldown(b, e.bag, e.slot) end
		e.b = b
		e.idx = i
		b.pbWindow = w
		b.link = e.d and e.d.link
		Paint(b, e.bag, e.d, search)
		b.pbFreeText:SetText("")
		if w.onlyBag ~= nil and e.bag ~= w.onlyBag then b:SetAlpha(0.15) end
		e.family = offline and 0 or BagFamily(e.bag)
		if e.family == 0 then total = total + 1; if e.d then used = used + 1 end end
	end
	for _, h in ipairs(w.headers) do h:Hide() end
	if db.view == "category" then PB.CategoryLayout(w, list, offline)
	else
		local size, gap, cols = Layout(w, #list)
		for i, e in ipairs(list) do Place(e.b, i, size, gap, cols, w.grid); e.b:SetFrameLevel(w:GetFrameLevel() + 5); e.b:Show() end
	end
	w.free:SetText(("|cffffffff%d|r/%d free"):format(total - used, total))
	w.money.t:SetText(offline and (rec and rec.money and Money(rec.money) or "") or Money(GetMoney()))
	PB.UpdateCurrencySlots(w, offline and rec or nil)
	w.sortBtn:SetEnabled(not offline and (w.kind == "inv" or PB.atBank))
	w.sortBtn.tex:SetDesaturated(offline or (w.kind == "bank" and not PB.atBank))
end
function PB.RefreshAll()
	for _, w in pairs(windows) do PB.Refresh(w) end
	if PB.DockItems then pcall(PB.DockItems) end
end

-- just the slots of one bag (cheap update on lock/cooldown changes)
local function RepaintBag(bag)
	for key, b in pairs(liveButtons) do
		if b.pbBag == bag and b:IsVisible() and b.pbWindow and not b.pbWindow.offline then
			Paint(b, bag, LiveData(bag, b.pbSlot), PB.searchText)
			Cooldown(b, bag, b.pbSlot)
			if b.pbMerged then local ct = CountText(b); if ct then ct:SetText(b.pbMerged[2]); ct:Show() end end
			if b.pbFreeFamily then b.pbFreeText:SetText(b.pbFreeText:GetText()) end
			if b.pbWindow.onlyBag ~= nil and bag ~= b.pbWindow.onlyBag then b:SetAlpha(0.15) end
		end
	end
end

---------------------------------------------------------------- open / close (stand in for the game's bag windows)
function PB.Toggle(kind)
	local w = PB.Window(kind or "inv")
	if w:IsShown() then w:Hide() else w.viewing = nil; w:Show() end
end
function PB.Open() local w = PB.Window("inv"); if not w:IsShown() then w.viewing = nil; w:Show() end end
function PB.Close() if windows.inv then windows.inv:Hide() end end
-- WoW Forever: hiding Blizzard's bag windows from an add-on runs their close-up code as the add-on, and what that
-- code writes then blocks right-clicking items to use them ("PintsBags tried to call UseContainerItem").
-- So there, while they're closed at login, they're moved into a hidden holder instead: the game can still open and
-- close them as it likes, nothing of theirs ever shows, and Pint's Bags never has to hide them.
local stash = CreateFrame("Frame"); stash:Hide()
local stashed = false
local function StashBlizzardBags()
	if stashed or type(issecretvalue) ~= "function" or InCombatLockdown() then return end
	local all = db.replaceBags and db.replaceBank
	local list = {}
	if db.replaceBags and ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
	if all then for i = 1, (NUM_CONTAINER_FRAMES or 13) do local f = _G["ContainerFrame" .. i]; if f then list[#list + 1] = f end end end
	-- Blizzard's bank window too (WoW Forever opens it its own way, so turning off its event doesn't stop it)
	if db.replaceBank and BankFrame and not NoBankTabs() then list[#list + 1] = BankFrame end
	for _, f in ipairs(list) do if f:IsShown() then return end end      -- only while they're all closed
	for _, f in ipairs(list) do f:SetParent(stash) end
	stashed = all and "all" or (#list > 0 and "combined") or false
end
PB.StashBlizzardBags = StashBlizzardBags
-- WoW Forever: only the game's own purchase button may buy a bank bag slot. While you're at the banker, its bank window
-- is brought out of the hidden holder shrunk to a dot and see-through, and just its purchase button - full size and
-- visible - is laid over Pint's Bags' "Buy bag slot". Clicking it is clicking the game's button, so nothing is blocked.
local dockSaved
local function GamePurchaseButton()
	return TABS and BankFrame and ((BankFrame.BankPanel and BankFrame.BankPanel.PurchaseButton) or _G.BankFramePurchaseButton)
end
-- a moved game button is still cut off at the edges of whatever holds it ("clips children"): let it show and be clicked
-- wherever it's laid. What was changed is put back when it goes home.
local unclipped = {}
local function Unclip(f)
	local p = f and f:GetParent()
	while p and p ~= UIParent do
		if p.DoesClipChildren and p:DoesClipChildren() then p:SetClipsChildren(false); unclipped[p] = true end
		p = p:GetParent()
	end
end
local function Reclip() for p in pairs(unclipped) do pcall(p.SetClipsChildren, p, true); unclipped[p] = nil end end
function PB.UnclipCount() local n = 0; for _ in pairs(unclipped) do n = n + 1 end; return n end
-- what the game's purchase button covers: the next bank bag slot to buy (where everyone clicks), or "Buy bag slot"
local function PurchaseTarget(w)
	if db.bagBar and w.bagSlots then
		local sb = w.bagSlots[TabsBought() + 1]
		if sb and sb.tabN and sb:IsVisible() then return sb, true end
	end
	return w.buy, false
end
-- The buy button: a secure button laid over the next locked bank bag slot (or "Buy bag slot") whose click clicks the
-- game's own purchase button - the way a /click macro does - so the game's "buy this slot" popup comes up as if you'd
-- clicked its own window. (Moving the game's button over ours didn't take the clicks.)
local buyer
local function SecureBuyer(w)
	local pb = GamePurchaseButton()
	if not pb or InCombatLockdown() then return false end
	if not buyer then
		buyer = CreateFrame("Button", "PintsBagsBuyBankSlot", UIParent, "SecureActionButtonTemplate")
		buyer:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
		buyer:SetAttribute("useOnKeyDown", false)
		buyer:SetAttribute("type1", "click")
		buyer:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		buyer:SetScript("OnEnter", function(self) local t = self.target; local f = t and t:GetScript("OnEnter"); if f then f(t) end end)
		buyer:SetScript("OnLeave", function(self) local t = self.target; local f = t and t:GetScript("OnLeave"); if f then f(t) end end)
	end
	buyer:SetAttribute("clickbutton1", pb)
	local target, onSlot = PurchaseTarget(w)
	buyer.target = target
	buyer:ClearAllPoints(); buyer:SetAllPoints(target)
	buyer:SetFrameStrata("DIALOG"); buyer:SetFrameLevel(w:GetFrameLevel() + 20)
	buyer:Show()
	w.buy:SetShown(not onSlot)
	return true
end
function PB.HideBuyer() if buyer and not InCombatLockdown() then buyer:Hide(); buyer.target = nil end end
function PB.DockPurchase(w)
	if SecureBuyer(w) then return true end
	local pb = GamePurchaseButton()
	if PB.bankFull or not pb or not w or not w.buy or InCombatLockdown() or not pb.SetIgnoreParentScale or not BankFrame:IsShown() then return false end
	if BankFrame:GetParent() == stash then
		BankFrame:SetAlpha(0); BankFrame:SetScale(0.01); BankFrame:SetParent(UIParent)
		PB.bankUnstashed = true
	end
	if not dockSaved then
		dockSaved = { strata = pb:GetFrameStrata() }
		for i = 1, pb:GetNumPoints() do dockSaved[i] = { pb:GetPoint(i) } end
	end
	local target, onSlot = PurchaseTarget(w)
	Unclip(pb)
	-- over the slot it's see-through (the slot shows through and the click buys it); over "Buy bag slot" it shows
	pb:SetIgnoreParentScale(true); pb:SetIgnoreParentAlpha(true); pb:SetAlpha(onSlot and 0 or 1)
	pb:ClearAllPoints(); pb:SetAllPoints(target)
	pb:SetFrameStrata("DIALOG"); pb:SetFrameLevel(w:GetFrameLevel() + 20)
	PB.docked, PB.dockTarget = pb, target
	w.buy:SetShown(not onSlot)
	if not pb.pbHooked then
		-- the slot's own tooltip while the game's button sits over it
		pb.pbHooked = true
		pb:HookScript("OnEnter", function()
			local t = PB.dockTarget
			if t and t ~= (windows.bank and windows.bank.buy) then local f = t:GetScript("OnEnter"); if f then f(t) end end
		end)
		pb:HookScript("OnLeave", function()
			local t = PB.dockTarget
			if t and t ~= (windows.bank and windows.bank.buy) then local f = t:GetScript("OnLeave"); if f then f(t) end end
		end)
	end
	-- the game hides its button while its bank window shows another tab; there's a slot to buy, so show it
	if not pb:IsShown() then pb:Show() end
	return pb:IsVisible()
end
local function Undock()
	local pb = PB.docked
	if not pb or InCombatLockdown() then return end
	pb:SetIgnoreParentScale(false); pb:SetIgnoreParentAlpha(false); pb:SetAlpha(1)
	Reclip(); PB.dockTarget = nil
	if dockSaved then
		pb:ClearAllPoints()
		for _, pt in ipairs(dockSaved) do pb:SetPoint(unpack(pt)) end
		pb:SetFrameStrata(dockSaved.strata or "MEDIUM")
	end
	PB.docked = nil
end
---------------------------------------------------------------- the game's own item buttons (WoW Forever)
-- A right-click on Pint's Bags' own slot buttons counts as the add-on using the item, which WoW Forever blocks; the
-- hidden "use" buttons that work around it can't move in a fight. So instead, when the game's own bag window is open
-- (it opens with your bag key, out of sight), it's shrunk to a see-through dot and each of its item buttons - still
-- see-through - is laid over the matching slot in Pint's Bags. Every click lands on the game's own button: right-click
-- uses the item, in a fight or not, and nothing is blocked. Moving the game's buttons is allowed in combat, so bags
-- opened mid-fight and items that move work too. Without the game's window open, the hidden use buttons still do the job.
-- Tested on WoW Forever: the buttons sit in place but the mouse never reaches them, so this is OFF - kept only as an
-- experiment (/pbag gamebuttons). The hidden use buttons do the job.
local dockedItems, dockFrames = {}, {}
local function GameBagFrames()
	local out = {}
	if ContainerFrameCombinedBags then out[#out + 1] = ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do local f = _G["ContainerFrame" .. i]; if f then out[#out + 1] = f end end
	return out
end
local function Locked(f) return InCombatLockdown() and f.IsProtected and f:IsProtected() end
local function ShrinkGameFrame(f)
	-- out of the hidden holder, shrunk to a dot, see-through, and no longer catching the mouse itself
	if Locked(f) then return end
	if f:GetParent() == stash then f:SetParent(UIParent) end
	if f:GetScale() > 0.02 then f:SetScale(0.01) end
	if f:GetAlpha() > 0 then f:SetAlpha(0) end
	if f:IsMouseEnabled() then f:EnableMouse(false) end
	dockFrames[f] = true
end
function PB.UndockItems()
	for ib in pairs(dockedItems) do pcall(ib.ClearAllPoints, ib); dockedItems[ib] = nil end
	for f in pairs(dockFrames) do
		if stashed then pcall(f.SetParent, f, stash) end
		pcall(f.SetScale, f, 1); pcall(f.SetAlpha, f, 1); pcall(f.EnableMouse, f, true)
		dockFrames[f] = nil
	end
	PB.dockedCount = 0
end
function PB.DockItems()
	if type(issecretvalue) ~= "function" or not db or not db.gameButtonsTest then return 0 end
	local w = windows.inv
	if not (w and w:IsShown()) or w.offline then PB.UndockItems(); return 0 end
	if not w.pbDockHook then w.pbDockHook = true; w:HookScript("OnHide", function() if PB.UndockItems then PB.UndockItems() end end) end
	local seen, n = {}, 0
	for _, f in ipairs(GameBagFrames()) do
		if f:IsShown() and f.EnumerateValidItems then
			ShrinkGameFrame(f)
			for _, ib in f:EnumerateValidItems() do
				local okB, bag = pcall(ib.GetBagID, ib)
				local slot = ib:GetID()
				local ours = okB and bag and liveButtons[bag * 100 + slot]
				seen[ib] = true
				if Locked(ib) then
					if dockedItems[ib] then n = n + 1 end      -- (protected in a fight: left where it is)
				elseif ours and ours.pbWindow == w and ours:IsVisible() then
					-- only re-anchor when it isn't already sitting on our slot
					local _, rel = ib:GetPoint(1)
					if rel ~= ours or not dockedItems[ib] then
						if not ib.pbUnclipped then ib.pbUnclipped = true; Unclip(ib) end
						ib:SetIgnoreParentScale(true)
						ib:ClearAllPoints(); ib:SetAllPoints(ours)
						ib:SetFrameStrata("FULLSCREEN")
					end
					dockedItems[ib] = ours
					n = n + 1
				elseif dockedItems[ib] or ib:GetNumPoints() > 0 then
					-- a slot Pint's Bags isn't showing (merged stack, hidden empty slot): nothing clickable there
					ib:ClearAllPoints(); dockedItems[ib] = nil
				end
			end
		end
	end
	for ib in pairs(dockedItems) do if not seen[ib] then pcall(ib.ClearAllPoints, ib); dockedItems[ib] = nil end end
	PB.dockedCount = n
	return n
end
do
	-- keep the game's buttons on their slots while the bags are open (they move when the game redraws its window)
	local t = 0
	local poll = CreateFrame("Frame")
	poll:SetScript("OnUpdate", function(_, el)
		t = t + el
		if t < 0.25 then return end
		t = 0
		if not db or not db.gameButtonsTest then return end      -- (off: WoW Forever doesn't let the mouse reach them)
		if windows.inv and windows.inv:IsShown() then
			pcall(PB.DockItems)
			-- does the mouse actually reach the game's buttons? (what's under the pointer while it's over the bags)
			if not PB.dockVerified and windows.inv:IsMouseOver() then
				local f = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
				if f and dockedItems[f] then PB.dockVerified = true end
				PB.lastFocus = f
			end
		elseif next(dockedItems) or next(dockFrames) then pcall(PB.UndockItems) end
	end)
end

-- bring the game's bank window into view (fallback when the purchase button can't be laid over ours)
function PB.ShowBlizzardBank()
	if not BankFrame or InCombatLockdown() then return end
	if BankFrame:GetParent() == stash then BankFrame:SetParent(UIParent); PB.bankUnstashed = true end
	-- (full size and visible again, in case it was shrunk for the purchase button)
	if PB.docked then Undock() end
	BankFrame:SetScale(1); BankFrame:SetAlpha(1); PB.bankFull = true
	BankFrame:SetFrameStrata("HIGH"); if BankFrame.Raise then BankFrame:Raise() end
	if not BankFrame:IsShown() then Print("talk to the banker again, then use the game's bank window to buy the slot.") return end
	Print("buy the slot with the purchase button in the game's bank window.")
end
function PB.RestashBlizzardBank()
	if InCombatLockdown() then return end
	if PB.HideBuyer then PB.HideBuyer() end
	Undock(); PB.bankFull = nil
	if PB.bankUnstashed and BankFrame then
		BankFrame:SetParent(stash); BankFrame:SetScale(1); BankFrame:SetAlpha(1); PB.bankUnstashed = nil
	end
end
local function HideBlizzardBags()
	if stashed == "all" then return end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f and f:IsShown() then
			local id = f:GetID()
			if (db.replaceBags and IsInvBag(id)) or (db.replaceBank and (id == BANK_ID or id >= FIRST_BANK_BAG)) then f:Hide() end
		end
	end
	-- the modern client (WoW Forever) shows all your bags in one "Combined Backpack" window
	local c = ContainerFrameCombinedBags
	if c and c:IsShown() and db.replaceBags and not stashed then c:Hide() end
end
---------------------------------------------------------------- the secure bag toggle (WoW Forever)
-- Only a "secure" button may show the use buttons in a fight. So the bag key and the minimap button press a secure toggle
-- that shows or hides the layer holding the use buttons (allowed in a fight), and the bag window follows it. When a
-- fight starts the use buttons are pinned to every slot, bags open or not - so bags opened mid-fight work too.
local closeBtn
function PB.SyncUseLayer()
	if InCombatLockdown() then return end
	local w = windows.inv
	useLayer:SetShown(w and w:IsShown() and true or false)
end
function PB.PinSecureClose(ls)
	local w = windows.inv
	if not (closeBtn and w and w.close) then return end
	local l, bt = w.close:GetLeft(), w.close:GetBottom()
	if not (l and bt) then return end
	local sc = w.close:GetEffectiveScale() / ls
	closeBtn:ClearAllPoints(); closeBtn:SetPoint("BOTTOMLEFT", useLayer, "BOTTOMLEFT", l * sc, bt * sc)
	closeBtn:SetSize(w.close:GetWidth() * sc, w.close:GetHeight() * sc); closeBtn:Show()
end
function PB.BindBagKeys()
	local t = PB.toggleBtn
	if not t or InCombatLockdown() then return end
	ClearOverrideBindings(t)
	if not db.replaceBags then return end
	for _, action in ipairs({ "OPENALLBAGS", "TOGGLEBACKPACK" }) do
		for _, key in ipairs({ GetBindingKey(action) }) do if key then SetOverrideBindingClick(t, false, key, "PintsBagsToggle", "LeftButton") end end
	end
end
function PB.SecureToggleSetup()
	if type(issecretvalue) ~= "function" or PB.toggleBtn or InCombatLockdown() or not SecureHandlerSetFrameRef then return end
	local t = CreateFrame("Button", "PintsBagsToggle", UIParent, "SecureHandlerClickTemplate")
	t:RegisterForClicks("AnyDown")
	SecureHandlerSetFrameRef(t, "layer", useLayer)
	t:SetAttribute("_onclick", [=[
		local layer = self:GetFrameRef("layer")
		if layer:IsShown() then layer:Hide() else layer:Show() end
	]=])
	-- then the bag window follows the layer (insecure code may show and hide Pint's Bags' own window in a fight)
	t:SetScript("PostClick", function()
		local w = PB.Window("inv")
		PB.secureToggle = true
		if useLayer:IsShown() then w.viewing = nil; w:Show() else w:Hide() end
		PB.secureToggle = nil
	end)
	PB.toggleBtn = t
	-- the X: in a fight a secure button over it does the closing (pinned when the fight starts)
	closeBtn = CreateFrame("Button", "PintsBagsSecureClose", useLayer, "SecureActionButtonTemplate")
	closeBtn:RegisterForClicks("LeftButtonUp", "LeftButtonDown"); closeBtn:SetAttribute("useOnKeyDown", false)
	closeBtn:SetAttribute("type1", "click"); closeBtn:SetAttribute("clickbutton1", t)
	closeBtn:SetFrameStrata(USE_STRATA); closeBtn:SetFrameLevel(6); closeBtn:Hide()
	PB.SyncUseLayer()
	PB.BindBagKeys()
	local ub = CreateFrame("Frame")
	ub:RegisterEvent("UPDATE_BINDINGS"); ub:RegisterEvent("PLAYER_REGEN_ENABLED")
	ub:SetScript("OnEvent", function(_, e)
		if e == "PLAYER_REGEN_ENABLED" then closeBtn:Hide(); PB.SyncUseLayer() end
		PB.BindBagKeys()
	end)
end

local function InstallHooks()
	StashBlizzardBags()
	pcall(PB.SecureToggleSetup)
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f then f:HookScript("OnShow", function() C_Timer.After(0, HideBlizzardBags) end) end
	end
	if ContainerFrameCombinedBags then ContainerFrameCombinedBags:HookScript("OnShow", function() C_Timer.After(0, HideBlizzardBags) end) end
	local function T() if db.replaceBags then PB.Toggle("inv") end end
	if ToggleBackpack then hooksecurefunc("ToggleBackpack", T) end
	if ToggleAllBags then hooksecurefunc("ToggleAllBags", T) end
	if ToggleBag then hooksecurefunc("ToggleBag", function(id) if db.replaceBags and id and IsInvBag(id) then PB.Toggle("inv") end end) end
	if CloseAllBags then hooksecurefunc("CloseAllBags", function() if db.replaceBags then PB.Close() end end) end
	if OpenAllBags then hooksecurefunc("OpenAllBags", function() if db.replaceBags then PB.Open() end end) end
	-- the bank
	if db.replaceBank and BankFrame and not NoBankTabs() then BankFrame:UnregisterEvent("BANKFRAME_OPENED") end
end

---------------------------------------------------------------- sorting
-- order: Hearthstone and tools, then by purpose - what the item is FOR - so things used together sit together:
-- potions, bandages, scrolls, cooking (food and its ingredients), cloth, leather, ore/bars/stone, herbs, gems,
-- elemental, enchanting, engineering parts, other trade goods, reagents, quest items, recipes, gear, bags, ammo,
-- keys, everything else; within a group by kind, quality (best first), item level, name; junk last
local function Has(name, list) for _, w in ipairs(list) do if name:find(w) then return true end end end
local CLOTH = { "Cloth$", "^Bolt of", "Runecloth", "Mageweave", "Felcloth", "Mooncloth" }
local LEATHER = { "Leather$", "Hide$", "Scraps$", "Scale$", "Scales$", "^Thick ", "^Rugged " }
local ORE = { " Ore$" }
local BAR = { " Bar$", "Nugget$" }
local STONE = { "^Rough Stone$", "^Coarse Stone$", "^Heavy Stone$", "^Solid Stone$", "^Dense Stone$" }
local HERB = { "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed", "Steelbloom",
	"Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom", "Purple Lotus",
	"Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil", "Silversage",
	"Plaguebloom", "Icecap", "Black Lotus", "Swiftthistle", "Wildvine", "Bloodthistle" }
local GEM = { "Malachite", "Tigerseye", "Shadowgem", "Moss Agate", "Moonstone", "^Jade$", "Citrine", "Aquamarine", "Star Ruby",
	"Sapphire", "Large Opal", "Huge Emerald", "Azerothian Diamond", "Black Diamond", "Arcane Crystal", "Pearl$", "Amethyst" }
local ELEMENTAL = { "^Elemental ", "^Essence of ", "^Heart of Fire", "^Breath of Wind", "^Core of Earth", "^Globe of Water",
	"^Ichor of Undeath", "^Living Essence", "^Elemental Earth", "^Elemental Fire", "^Elemental Water", "^Elemental Air" }
local ENCHANT = { " Dust$", " Essence$", " Shard$", "^Nexus Crystal" }
local CONS_RANK = { [1] = 1, [2] = 2, [3] = 2, [7] = 4, [4] = 5, [6] = 6, [0] = 7, [8] = 7 }   -- potions, elixirs/flasks, bandages, scrolls, enhancements
local GEAR_RANK = { INVTYPE_WEAPON = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 2, INVTYPE_SHIELD = 2,
	INVTYPE_HOLDABLE = 2, INVTYPE_RANGED = 3, INVTYPE_RANGEDRIGHT = 3, INVTYPE_THROWN = 3, INVTYPE_RELIC = 3, INVTYPE_HEAD = 4,
	INVTYPE_NECK = 5, INVTYPE_SHOULDER = 6, INVTYPE_CLOAK = 7, INVTYPE_CHEST = 8, INVTYPE_ROBE = 8, INVTYPE_BODY = 9, INVTYPE_TABARD = 9,
	INVTYPE_WRIST = 10, INVTYPE_HAND = 11, INVTYPE_WAIST = 12, INVTYPE_LEGS = 13, INVTYPE_FEET = 14, INVTYPE_FINGER = 15, INVTYPE_TRINKET = 16 }
-- returns the purpose group and a rank inside it
local function Purpose(id, name, cls, sub, loc)
	if id == 6948 then return 1, 0 end
	if PROF_TOOLS[id] or (cls == 2 and sub == 20) then return 2, 0 end
	if cls == 0 then
		if sub == 5 then return 6, 1 end                        -- food and drink: with the cooking
		local r = CONS_RANK[sub] or 7
		return (r <= 2 and 3) or (r == 4 and 4) or 5, r
	end
	if cls == 3 then return 11, 0 end
	if cls == 12 then return 17, 0 end
	if cls == 9 then return 18, sub or 0 end
	if cls == 2 or cls == 4 then return 19, GEAR_RANK[loc or ""] or 17 end
	if cls == 1 then return 20, 0 end
	if cls == 6 or cls == 11 then return 21, 0 end
	if cls == 13 then return 22, 0 end
	-- trade goods (and misc. items that are really trade goods): by the game's sub-kind, then by name
	if IsCooking(id, cls, sub) then return 6, 2 end
	if cls == 7 then
		if sub == 5 then return 7, 0 elseif sub == 6 then return 8, 0 elseif sub == 9 then return 10, 0 elseif sub == 4 then return 11, 0
		elseif sub == 10 then return 12, 0 elseif sub == 12 then return 13, 0 elseif sub == 1 or sub == 2 or sub == 3 then return 14, sub end
	end
	if name ~= "" and (cls == 7 or cls == 15 or cls == 5 or cls == nil) then
		if Has(name, CLOTH) then return 7, 0 end
		if Has(name, LEATHER) then return 8, 0 end
		if Has(name, ORE) then return 9, 1 end
		if Has(name, BAR) then return 9, 2 end
		if Has(name, STONE) then return 9, 3 end
		if Has(name, HERB) then return 10, 0 end
		if Has(name, GEM) then return 11, 0 end
		if Has(name, ELEMENTAL) then return 12, 0 end
		if Has(name, ENCHANT) then return 13, 0 end
	end
	if cls == 7 and sub == 7 then return 9, 3 end              -- metal and stone the names didn't place
	if cls == 7 then return 15, sub or 0 end
	if cls == 5 then return 16, 0 end
	return 23, cls or 99
end
PB.Purpose = Purpose
local function SortKey(link, count)
	local id = tonumber(link:match("item:(%d+)")) or 0
	local name, _, quality, level, _, _, _, _, loc = GetItemInfo(link)
	local _, _, _, _, _, classID, subID = GetItemInfoInstant(link)
	local p, pr = Purpose(id, name or "", classID, subID, loc)
	return { first = (id == 6948) and 0 or 1, junk = (quality == 0) and 1 or 0, p = p, pr = pr, sub = subID or 0, loc = loc or "",
		q = -(quality or 1), lvl = -(level or 0), name = name or link, id = id, link = link, count = -(count or 1) }
end
local function Before(a, b)
	for _, f in ipairs({ "first", "junk", "p", "pr", "sub", "loc", "q", "lvl", "name", "id", "link", "count" }) do
		if a[f] ~= b[f] then return a[f] < b[f] end
	end
	return false
end
SortKeyFor, SortBefore = SortKey, Before
local sorter = CreateFrame("Frame"); sorter:Hide()
local job
local function AnyLocked(bags)
	for _, bag in ipairs(bags) do for s = 1, NumSlots(bag) do local i = SlotInfo(bag, s); if i and i.isLocked then return true end end end
	return false
end
local function Positions(bags, family)
	local pos = {}
	for _, bag in ipairs(bags) do if BagFamily(bag) == family then for s = 1, NumSlots(bag) do pos[#pos + 1] = { bag, s } end end end
	return pos
end
local function Step()
	if InCombatLockdown() then Print("sorting stopped - combat."); job = nil; sorter:Hide(); return end
	if CursorHasItem() or AnyLocked(job.bags) then return end
	job.moves = job.moves + 1
	if job.moves > 400 or GetTime() - job.started > 60 then Print("sorting gave up part way - try again."); job = nil; sorter:Hide(); return end
	for _, family in ipairs(job.families) do
		local pos = Positions(job.bags, family)
		-- first put partial stacks of the same item together
		local partial = {}
		for _, p in ipairs(pos) do
			local i = SlotInfo(p[1], p[2])
			if i and i.hyperlink then
				local max = select(8, GetItemInfo(i.hyperlink)) or 1
				if max > 1 and i.stackCount < max then
					local k = i.hyperlink
					if partial[k] then
						C.PickupContainerItem(p[1], p[2]); C.PickupContainerItem(partial[k][1], partial[k][2])
						if CursorHasItem() then C.PickupContainerItem(p[1], p[2]) end
						return
					end
					partial[k] = p
				end
			end
		end
		-- then the order
		local items = {}
		for _, p in ipairs(pos) do
			local i = SlotInfo(p[1], p[2])
			if i and i.hyperlink then local k = SortKey(i.hyperlink, i.stackCount); k.at = p; items[#items + 1] = k end
		end
		table.sort(items, Before)
		for n, want in ipairs(items) do
			local p = pos[n]
			local cur = SlotInfo(p[1], p[2])
			if not (cur and cur.hyperlink == want.link and cur.stackCount == -want.count) then
				-- find the wanted item somewhere after this spot
				for m = n + 1, #pos do
					local q = pos[m]
					local i = SlotInfo(q[1], q[2])
					if i and i.hyperlink == want.link and i.stackCount == -want.count then
						C.PickupContainerItem(q[1], q[2]); C.PickupContainerItem(p[1], p[2])
						if CursorHasItem() then C.PickupContainerItem(q[1], q[2]) end
						return
					end
				end
			end
		end
	end
	job = nil; sorter:Hide()
	PB.RefreshAll()
end
local acc = 0
sorter:SetScript("OnUpdate", function(_, e) acc = acc + e; if acc < 0.08 then return end; acc = 0; if job then Step() end end)
function PB.Sort(w)
	if InCombatLockdown() then Print("can't sort in combat."); return end
	if w.offline then return end
	if w.kind == "bank" and not PB.atBank then return end
	if db.gameSort then
		if w.kind == "inv" and C.SortBags then C.SortBags(); return end
		if w.kind == "bank" and C.SortBankBags then C.SortBankBags(); return end
	end
	local families, seen = {}, {}
	for _, bag in ipairs(w.bags) do local f = BagFamily(bag); if not seen[f] then seen[f] = true; families[#families + 1] = f end end
	job = { bags = w.bags, families = families, moves = 0, started = GetTime() }
	PlaySound(SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 or 862)
	sorter:Show()
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY",
	"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"BANK_TABS_CHANGED", "BAG_CONTAINER_UPDATE",
	"UNIT_QUEST_LOG_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_NEW_ITEMS_UPDATED", "PLAYER_REGEN_ENABLED", "CURRENCY_DISPLAY_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end   -- (pcall: events this game version lacks are skipped)
local pending = false
local function Soon()
	if pending then return end
	pending = true
	C_Timer.After(0.05, function() pending = false; PB.RefreshAll() end)
end
-- WoW Forever opens and closes the bank through the "interaction manager" (whichever of the two arrives works)
local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
if BANKER then pcall(ev.RegisterEvent, ev, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"); pcall(ev.RegisterEvent, ev, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE") end
ev:SetScript("OnEvent", function(_, e, a1)
	if e == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then if a1 ~= BANKER or PB.atBank then return end; e = "BANKFRAME_OPENED"
	elseif e == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then if a1 ~= BANKER then return end; e = "BANKFRAME_CLOSED" end
	if e == "ADDON_LOADED" and a1 == ADDON then
		PintsBagsDB = PintsBagsDB or {}
		db = PintsBagsDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = (type(v) == "table") and {} or v end end
		-- 1.1.11: the sort by purpose is new and better than the game's, so it takes over once (the option can switch back)
		if not db.purposeSort then db.purposeSort = true; db.gameSort = false end
		PB.db = db
	elseif e == "PLAYER_LOGIN" then
		InstallHooks()
		if PB.BuildMinimap then PB.BuildMinimap() end
		if PB.SecureOpener then C_Timer.After(2, function() pcall(PB.SecureOpener) end) end
		if PB.BagnonLoaded() then Print("Bagnon is on too - /pbag off-bagnon to switch it off, then /reload.") end
	elseif e == "ITEM_LOCK_CHANGED" then
		if a1 then RepaintBag(a1) end
	elseif e == "BAG_UPDATE_COOLDOWN" then
		for _, bag in ipairs(INV) do RepaintBag(bag) end
	elseif e == "BANKFRAME_OPENED" then
		if not db.replaceBank then return end
		if NoBankTabs() then
			if not PB.tabNote then PB.tabNote = true; Print("you haven't bought a bank tab yet - buy one in the bank window, then /reload and Pint's Bags will show your bank.") end
			return
		end
		PB.atBank = true
		local b = PB.Window("bank"); b.viewing = nil; b:Show(); PB.Refresh(b)
		PB.Open()
	elseif e == "BANKFRAME_CLOSED" then
		if PB.atBank then PB.atBank = false; if windows.bank then windows.bank:Hide() end end
		if PB.RestashBlizzardBank then C_Timer.After(0.2, PB.RestashBlizzardBank) end
	elseif e == "PLAYER_REGEN_ENABLED" then
		PB.fightLock = false
		if PB.AddPendingUse then PB.AddPendingUse() end
		for _, b in pairs(liveButtons) do if b.pbUse or b.pbNoRight then b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b.pbNoRight = nil end end
		Soon()
	else
		Soon()
	end
end)

---------------------------------------------------------------- Bagnon off, slash, minimap
local function Loaded(a) if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(a) end return IsAddOnLoaded and IsAddOnLoaded(a) end
function PB.BagnonLoaded() return Loaded("Bagnon") or Loaded("BagBrother") end
function PB.BagnonOff()
	local off = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
	for _, a in ipairs({ "Bagnon", "Bagnon_Bank", "Bagnon_Config", "Bagnon_GuildBank", "BagBrother" }) do pcall(off, a) end
	Print("Bagnon switched off - /reload to finish.")
end
SLASH_PINTSBAGS1 = "/pbag"
SLASH_PINTSBAGS2 = "/pintsbags"
SlashCmdList.PINTSBAGS = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "off-bagnon" then PB.BagnonOff()
	elseif msg == "bank" then local b = PB.Window("bank"); b.viewing = b.viewing or ME; b:Show()
	elseif msg == "sort" then PB.Sort(PB.Window("inv"))
	elseif msg == "minimap" then PB.ToggleMinimap()
	elseif msg == "bankdebug" then
		-- what the bank-slot purchase button is doing (for bug reports)
		local pb = BankFrame and ((BankFrame.BankPanel and BankFrame.BankPanel.PurchaseButton) or _G.BankFramePurchaseButton)
		local function yn(v) return v and "yes" or "no" end
		Print(("BankFrame: %s, shown %s, parent %s, scale %.2f | purchase button: %s, shown %s, visible %s | docked %s"):format(
			yn(BankFrame), yn(BankFrame and BankFrame:IsShown()), BankFrame and (BankFrame:GetParent() == UIParent and "UIParent" or "hidden holder") or "-",
			BankFrame and BankFrame:GetScale() or 0, yn(pb), yn(pb and pb:IsShown()), yn(pb and pb:IsVisible()), yn(PB.docked)))
		local ok1, bought = pcall(C_Bank.FetchNumPurchasedBankTabs, Enum.BankType and Enum.BankType.Character or 0)
		local ok2, max = pcall(C_Bank.FetchMaxNumBankTabs, Enum.BankType and Enum.BankType.Character or 0)
		local at = BankFrame and BankFrame.GetActiveBankType and select(2, pcall(BankFrame.GetActiveBankType, BankFrame))
		Print(("tabs bought %s of %s, game bank window on bank type %s, at banker %s"):format(tostring(ok1 and bought), tostring(ok2 and max), tostring(at), yn(PB.atBank)))
		if pb then
			local w = windows.bank
			local function R(f) local l, b, wd, h = f:GetRect(); return l and ("%d,%d %dx%d"):format(l * f:GetEffectiveScale(), b * f:GetEffectiveScale(), wd * f:GetEffectiveScale(), h * f:GetEffectiveScale()) or "none" end
			Print(("purchase button: text \"%s\", alpha %.2f, strata %s, at %s | over %s at %s, enabled %s, mouse %s, unclipped %d"):format(tostring(pb.GetText and pb:GetText()),
				pb.GetEffectiveAlpha and pb:GetEffectiveAlpha() or -1, pb:GetFrameStrata(), R(pb), (PB.dockTarget and PB.dockTarget.tabN) and ("slot " .. PB.dockTarget.tabN) or "Buy bag slot",
				PB.dockTarget and R(PB.dockTarget) or "-", yn(pb:IsEnabled()), yn(pb:IsMouseEnabled()), PB.UnclipCount and PB.UnclipCount() or 0))
		end
	elseif msg == "gamebuttons" then
		db.gameButtonsTest = not db.gameButtonsTest
		if not db.gameButtonsTest then PB.UndockItems() end
		Print("using the game's own item buttons for clicks: " .. (db.gameButtonsTest and "on" or "off (the hidden use buttons only)") .. ".")
	elseif msg == "clickdebug" then
		Print(("game item buttons over your slots: %d (switch %s) | mouse reaches them: %s"):format(PB.dockedCount or 0, db.gameButtonsTest and "on" or "off",
			PB.dockVerified and "yes" or "not seen yet"))
		local f = PB.lastFocus
		if f then
			local p = f.GetParent and f:GetParent()
			local what = (p == useLayer and "Pint's Bags use button") or (f.pbBag and "Pint's Bags slot") or (f.GetBagID and "game item button") or "other"
			Print(("last thing under the pointer over the bags: %s (%s, in %s)"):format(tostring(f.GetName and f:GetName() or "unnamed"), what,
				tostring(p and p.GetName and p:GetName() or "?")))
		end
	elseif msg == "testclick" then
		-- temporary test: turn the right-click "use" buttons off so a right-click reaches the slot itself, to find out
		-- (with /console taintLog 2) what makes the game block it. /pbag testclick again to turn them back on.
		if InCombatLockdown() then Print("after combat."); return end
		PB.testClick = not PB.testClick
		useOff = PB.testClick and true or false
		for _, b in pairs(liveButtons) do b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); if b.pbUse then b.pbUse:Hide() end end
		SyncAll()
		Print(PB.testClick and "test on: right-click now goes to the slot itself. Right-click an item until it's blocked, then tell Claude (no /reload)." or "test off: right-click to use is back to normal.")
	elseif msg == "diag" then
		local w = windows.inv
		if not w then Print("open your bags first."); return end
		Print(("window %s strata %s level %d shown %s size %dx%d"):format(w:GetName(), w:GetFrameStrata(), w:GetFrameLevel(), tostring(w:IsShown()), w:GetWidth(), w:GetHeight()))
		Print(("grid size %dx%d"):format(w.grid:GetWidth(), w.grid:GetHeight()))
		local n = 0
		for _, b in pairs(liveButtons) do
			if b.pbWindow == w and n < 2 then
				n = n + 1
				local ic = Icon(b)
				Print(("slot %d/%d shown %s visible %s strata %s level %d alpha %.2f size %dx%d left %s icon %s parent %s"):format(b.pbBag, b.pbSlot, tostring(b:IsShown()), tostring(b:IsVisible()),
					b:GetFrameStrata(), b:GetFrameLevel(), b:GetAlpha(), b:GetWidth(), b:GetHeight(), tostring(b:GetLeft()), tostring(ic and ic:GetTexture()), tostring(b:GetParent() and b:GetParent():IsVisible())))
			end
		end
	elseif msg == "options" or msg == "config" then PB.ToggleOptions()
	elseif msg == "" then PB.Toggle("inv")
	else Print("/pbag - bags   /pbag bank - your saved bank   /pbag sort   /pbag options   /pbag minimap") end
end
do
	local NAME, ICON, ANGLE = "PintsBags", ((C_Item and C_Item.GetItemIconByID or GetItemIcon) or function() end)(4496) or "Interface\\Icons\\INV_Misc_Bag_10", 200   -- Small Brown Pouch
	local btn
	local function Tip(tt) tt:AddLine("Pint's Bags"); tt:AddLine("Click: bags   Right-click: options", 1, 1, 1); tt:AddLine("/pbag minimap to hide", 0.5, 0.5, 0.5) end
	local function Click(_, b) if b == "RightButton" then PB.ToggleOptions() else PB.Toggle("inv") end end
	function PB.BuildMinimap()
		local store = db.minimap
		local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
		local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
		if LDB and Icon then
			local obj = LDB:NewDataObject(NAME, { type = "launcher", text = "Pint's Bags", icon = ICON, OnClick = Click, OnTooltipShow = Tip })
			Icon:Register(NAME, obj, store); btn = { lib = Icon }; return
		end
		local b = CreateFrame("Button", NAME .. "MinimapButton", Minimap)
		b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
		b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(ICON); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
		local function Place() local a = math.rad(store.angle or ANGLE); b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a)) end
		Place()
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
			store.angle = math.deg(math.atan2(py / s - my, px / s - mx)); Place() end) end)
		b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		b:SetScript("OnClick", Click)
		b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); Tip(GameTooltip); GameTooltip:Show() end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetShown(not store.hide); btn = b
	end
	-- WoW Forever: opening the bags from an add-on's button means the game's own bag window isn't open, so its item
	-- buttons can't take the clicks (and opening it from add-on code would block right-click). So the minimap / Button
	-- Bin button gets a see-through secure button on top whose left-click presses the game's backpack button - the same
	-- as your bag key. Right-click passes through to the button underneath (options). Set up out of combat.
	local opener
	local function GameBackpackButton() return _G.MainMenuBarBackpackButton or (_G.BagsBar and _G.BagsBar.BackpackButton) end
	function PB.SecureOpener()
		if type(issecretvalue) ~= "function" or opener or InCombatLockdown() then return end
		local target = (btn and btn.lib and btn.lib.GetMinimapButton and btn.lib:GetMinimapButton(NAME)) or (btn and not btn.lib and btn) or _G["LibDBIcon10_" .. NAME]
		local pack = GameBackpackButton()
		if not target or not pack then return end
		opener = CreateFrame("Button", "PintsBagsSecureOpener", target, "SecureActionButtonTemplate")   -- (on the button: hidden with it, e.g. when the Button Bin closes in a fight)
		opener:SetAllPoints(target)
		opener:SetFrameStrata(target:GetFrameStrata()); opener:SetFrameLevel(target:GetFrameLevel() + 5)
		opener:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
		opener:SetAttribute("useOnKeyDown", false)
		opener:SetAttribute("type1", "click")
		opener:SetAttribute("clickbutton1", PB.toggleBtn or pack)
		if opener.SetPassThroughButtons then pcall(opener.SetPassThroughButtons, opener, "RightButton", "MiddleButton") end
		opener:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); Tip(GameTooltip); GameTooltip:Show() end)
		opener:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- follow the button underneath: hidden when it is (the Button Bin closed, minimap button turned off)
		local t = 0
		local watch = CreateFrame("Frame")
		watch:SetScript("OnUpdate", function(_, el)
			t = t + el; if t < 0.3 then return end; t = 0
			if InCombatLockdown() then return end
			local want = target:IsVisible()
			if want ~= opener:IsShown() then opener:SetShown(want) end
		end)
	end
	function PB.ToggleMinimap()
		local store = db.minimap; store.hide = not store.hide
		if btn and btn.lib then if store.hide then btn.lib:Hide(NAME) else btn.lib:Show(NAME) end elseif btn then btn:SetShown(not store.hide) end
	end
end
