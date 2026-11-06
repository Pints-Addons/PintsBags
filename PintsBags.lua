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
local DEFAULTS = {
	columns = 10, size = 37, view = "category", lanes = 2, recent = true, groupSorted = false, combine = true, spacing = 3, scale = 1, quality = true, quest = true, ilvl = false, newGlow = true, dimJunk = false,
	bagColors = false, colorStrength = 0.9, colors = {}, bagBar = false, replaceBags = true, replaceBank = true, gameSort = true,
	locked = false, pos = {}, minimap = {},
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
-- the whole window "protected", and the game then refuses to let it update or close during combat. They're lined up
-- over the slots out of combat; when combat starts they step aside (right-click in combat uses the game's own
-- click again - use the action bar for potions mid-fight), and come back when it ends.
local useLayer = CreateFrame("Frame", "PintsBagsUseLayer", UIParent)
useLayer:SetAllPoints(UIParent)
local function Sync(b)
	local o = b.pbUse
	if not o or InCombatLockdown() then return end
	if b:IsVisible() and not useOff then
		o:ClearAllPoints(); o:SetAllPoints(b)
		o:SetFrameStrata(b:GetFrameStrata()); o:SetFrameLevel(b:GetFrameLevel() + 5)
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
	b:HookScript("OnMouseUp", function(_, btn)
		if btn == "RightButton" and InCombatLockdown() and not PB.combatNote then
			PB.combatNote = true
			Print("in combat, right-click in the bags is off - use a potion from your action bar. It works again when the fight ends.")
		end
	end)
	b:HookScript("OnShow", function(self) C_Timer.After(0, function() Sync(self) end) end)
	b:HookScript("OnHide", function(self) Sync(self) end)
	Sync(b)
end
local function SyncAll() for _, b in pairs(liveButtons) do Sync(b) end end
PB.AddPendingUse = function()
	for b, bs in pairs(pendingUse) do pendingUse[b] = nil; AddUse(b, bs[1], bs[2]) end
	SyncAll()
end
-- at a vendor, bank, mailbox, auction house or trade the game's own right-click is the one you want (sell, store,
-- attach...), and it works there: the overlays step aside while one of those is open
local function UseOverlays(on)
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
			-- the last moment before combat locks things: let go of the slots, so the window stays free to update
			for _, b in pairs(liveButtons) do
				if b.pbUse then
					b.pbUse:Hide(); b.pbUse:ClearAllPoints()
					-- and the slot itself ignores right-clicks until combat ends: the game's own right-click from an
					-- add-on's bag gets "blocked" mid-fight (use the action bar for potions in combat)
					b:RegisterForClicks("LeftButtonUp")
				end
			end
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
		local gear = loc and loc ~= "" and loc ~= "INVTYPE_BAG" and loc ~= "INVTYPE_AMMO"
		b.pbLevel:SetText((db.ilvl and gear and level and level > 1) and level or "")
		local dim = not Matches(d.link, search, d.bound) or (db.dimJunk and quality == 0)
		if SetItemButtonDesaturated then SetItemButtonDesaturated(b, d.locked or dim) end
		b:SetAlpha(dim and 0.3 or 1)
	else
		if icon then icon:SetTexture(nil); icon:Hide() end
		if SetItemButtonCount then SetItemButtonCount(b, 0) elseif count then count:SetText("") end
		b.pbBack:Show(); b.pbGlow:Hide(); b.pbQuest:Hide(); b.pbNew:Hide(); b.pbLevel:SetText("")
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
	w:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
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
		w.buy:SetScript("OnClick", function()
			local cost = GetBankSlotCost and GetBankSlotCost(GetNumBankSlots())
			if not cost then return end
			if BankFrame then BankFrame.nextSlotCost = cost end
			StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
		end)
		w.buy:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP"); local cost = GetBankSlotCost and GetBankSlotCost(GetNumBankSlots())
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

	w:SetScript("OnShow", function(self) PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN or 862); PB.Refresh(self) end)
	w:SetScript("OnHide", function(self)
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

function PB.Refresh(w)
	if not w or not w:IsShown() or not db then return end
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
		elseif sb.inv then tex = GetInventoryItemTexture("player", sb.inv) end
		sb.link = offline and link or nil
		sb.locked = (w.kind == "bank" and bag ~= BANK_ID and not offline and GetNumBankSlots and (bag - FIRST_BANK_BAG + 1) > GetNumBankSlots())
		sb.tex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
		sb.tex:SetDesaturated(sb.locked or false); sb.tex:SetVertexColor(sb.locked and 1 or 1, sb.locked and 0.3 or 1, sb.locked and 0.3 or 1)
		local r, g, b = PB.BagColor(bag)
		sb.edge:SetColorTexture(r, g, b, db.bagColors and 1 or 0)
	end
	if w.buy then
		local n, full = GetNumBankSlots and GetNumBankSlots()
		w.buy:SetShown(not offline and PB.atBank and n and not full and n < 6)
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
	w.sortBtn:SetEnabled(not offline and (w.kind == "inv" or PB.atBank))
	w.sortBtn.tex:SetDesaturated(offline or (w.kind == "bank" and not PB.atBank))
end
function PB.RefreshAll() for _, w in pairs(windows) do PB.Refresh(w) end end

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
local function InstallHooks()
	StashBlizzardBags()
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
-- order: Hearthstone, then by kind (consumables, gear, trade goods, ...), quality (best first), item level, name; junk last
local CLASS_ORDER = { [0] = 1, [2] = 2, [4] = 3, [7] = 4, [5] = 5, [9] = 6, [1] = 7, [11] = 8, [6] = 9, [3] = 10, [15] = 11, [12] = 12, [13] = 13 }
local function SortKey(link, count)
	local id = tonumber(link:match("item:(%d+)")) or 0
	local name, _, quality, level, _, _, _, _, loc = GetItemInfo(link)
	local _, _, _, _, _, classID, subID = GetItemInfoInstant(link)
	return { first = (id == 6948) and 0 or 1, junk = (quality == 0) and 1 or 0, class = CLASS_ORDER[classID or 15] or 14, sub = subID or 0, loc = loc or "",
		q = -(quality or 1), lvl = -(level or 0), name = name or link, id = id, link = link, count = -(count or 1) }
end
local function Before(a, b)
	for _, f in ipairs({ "first", "junk", "class", "sub", "loc", "q", "lvl", "name", "id", "link", "count" }) do
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
	"UNIT_QUEST_LOG_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_NEW_ITEMS_UPDATED", "PLAYER_REGEN_ENABLED" }) do pcall(ev.RegisterEvent, ev, e) end   -- (pcall: events this game version lacks are skipped)
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
		PB.db = db
	elseif e == "PLAYER_LOGIN" then
		InstallHooks()
		if PB.BuildMinimap then PB.BuildMinimap() end
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
	elseif e == "PLAYER_REGEN_ENABLED" then
		for _, b in pairs(liveButtons) do if b.pbUse then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end end
		if PB.AddPendingUse then PB.AddPendingUse() end
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
	function PB.ToggleMinimap()
		local store = db.minimap; store.hide = not store.hide
		if btn and btn.lib then if store.hide then btn.lib:Hide(NAME) else btn.lib:Show(NAME) end elseif btn then btn:SetShown(not store.hide) end
	end
end
