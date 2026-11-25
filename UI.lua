-- UI.lua: the Sugar Daddy tab inside the auction house window (made with LibAHTab, like Auctionator's tabs):
-- controls on top, the ranked upgrades with Buy buttons, and a Weights column that slides in on the right.
local _, SD = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local LibAHTab = LibStub("LibAHTab-1-0")
local Gear = SD.Gear
local Who = SD.Who

local UI = {}
SD.UI = UI

local TAB_ID = "SugarDaddy"
local TAB_TEXT = "Sugar Daddy"
local TAB_HEADER = "Sugar Daddy"

local LEFT = 62                -- clears the portrait in the auction house's top-left corner
local LIST_TOP = -84
local ROW_H, MAX_ROWS = 22, 24
local LIST_HEAD = 28
local WHEEL_STEP = 3
local WEIGHTS_W = 310
local SHORT_STAT = { rap = "Ranged AP", arp = "Armor Pen", mp5 = "Mana per 5" }   -- fit the Weights column
local WEIGHT_COLS, WEIGHT_ROWS, WEIGHT_H = 2, 12, 22
local GREEN = "|cff20ff20"
local GREY = "|cff9d9d9d"
local GOLD = "|cffffd100"
local RED = "|cffff4040"
local INDENT = 14

-- Gear score numbers: one decimal, without a trailing ".0".
local function Score(value)
    return (("%.1f"):format(value):gsub("%.0$", ""))
end
-- Options shown per slot until its header is clicked (Settings).
local function PerSlot() return SD.db.perSlot or 3 end

local tab, list, weights, picker, settings
local rows, weightLines = {}, {}
local offset, visibleRows = 0, 0
local expanded = {}            -- slot groups showing all their options

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Tip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function EditBox(parent, width, onCommit)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self)
        self.cancel = true
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        if self.cancel then
            self.cancel = nil
            return UI.Refresh()
        end
        onCommit(self:GetText())
        UI.Refresh()
    end)
    return e
end

local function SetIfIdle(edit, text)
    if not edit:HasFocus() then edit:SetText(text) end
end

local function Check(parent, text, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = Label(c, text, "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 0, 1)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

local function Inset(parent)
    local ok, frame = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok then return frame end
    return CreateFrame("Frame", nil, parent)
end

-- The item's real link (name in its quality color) for a plain "item:123" link, once its data is in.
local function DisplayLink(link)
    local _, full = GetItemInfo(link)
    return full or link
end

-- The Buy button's icon: the game's shopping cart (from the Trading Post art).
local BUY_W = 32
local CART_ATLAS = "Perks-ShoppingCart"

-- Columns: name on the left, the rest anchored from the right so the list can be any width.
local function Columns(row, template)
    row.slot = Label(row, "", template)
    row.gain = Label(row, "", template)
    row.price = Label(row, "", template)
    row.name = Label(row, "", template)
    row.price:SetSize(110, ROW_H)
    row.price:SetJustifyH("RIGHT")
    row.price:SetPoint("RIGHT", -(BUY_W + 10), 0)
    row.gain:SetSize(72, ROW_H)
    row.gain:SetJustifyH("RIGHT")
    row.gain:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
    row.slot:SetSize(64, ROW_H)
    row.slot:SetJustifyH("LEFT")
    row.slot:SetPoint("RIGHT", row.gain, "LEFT", -6, 0)
    row.name:SetHeight(ROW_H)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", 26, 0)
    row.name:SetPoint("RIGHT", row.slot, "LEFT", -8, 0)
end

-- Results rows ---------------------------------------------------------------------------------------------------

local function RowTip(row)
    local group = row.group
    if group then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(group.name, 1, 1, 1)
        GameTooltip:AddLine(("%d option%s"):format(#group.items, #group.items == 1 and "" or "s"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("The header shows the slot's biggest upgrade.", 0.6, 0.6, 0.6)
        if #group.items > PerSlot() then
            GameTooltip:AddLine(expanded[group.key] and "Click to show fewer." or "Click to show all.", 0.6, 0.6, 0.6)
        end
        return GameTooltip:Show()
    end
    local result = row.result
    if not result then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(result.listing.link)
    GameTooltip:AddLine(" ")
    local old = result.replaced or 0
    GameTooltip:AddLine(("Sugar Daddy: gear score %s -> %s (+%s)"):format(Score(old), Score(old + result.points),
        Score(result.points)), 0.13, 1, 0.13)
    local worn = Who.Equipped(result.slot)
    local alsoWorn = result.also and Who.Equipped(result.also)
    local replacedText = worn and (alsoWorn and (worn .. " and " .. alsoWorn) or worn) or alsoWorn
    local whose = Who.IsMe() and "your" or (Who.Name() .. "'s")
    GameTooltip:AddLine("Replaces " .. (replacedText or (whose .. " empty " .. (Gear.SLOT_NAME[result.slot] or "slot"))), 1, 1, 1)
    if result.partner then GameTooltip:AddLine("Counted with " .. result.partner .. " in the other hand", 1, 1, 1) end
    if (result.entry.required or 0) > Who.Level() then
        local who = Who.IsMe() and "You" or Who.Name()
        GameTooltip:AddLine(("%s can wear it at level %d."):format(who, result.entry.required), 1, 0.25, 0.25)
    end
    GameTooltip:AddLine(result.entry.perListing and "Price of this exact listing (its suffix varies by listing)." or "Cheapest listing.",
        0.6, 0.6, 0.6)
    GameTooltip:AddLine("Gear score: the item's stats added up with your spec's weights (see Weights).", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 6, -LIST_HEAD - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -6, -LIST_HEAD - (i - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints()
    row.band:SetColorTexture(1, 0.82, 0, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    Columns(row, "GameFontHighlightSmall")
    row.buy = Button(row, "", BUY_W, function(self)
        local result = self:GetParent().result
        if result then SD.Scanner.Buy(result) end
    end)
    row.buy:SetHeight(18)
    row.buy:SetPoint("RIGHT", -2, 0)
    row.buy.cart = row.buy:CreateTexture(nil, "OVERLAY")
    row.buy.cart:SetSize(14, 14)
    row.buy.cart:SetPoint("CENTER")
    row.buy.cart:SetAtlas(CART_ATLAS)
    row.buy:SetScript("OnEnter", function(self)
        local result = self:GetParent().result
        if not result then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Buy for " .. SD.Money(result.listing.price), 1, 1, 1)
        if GetMoney() < result.listing.price then GameTooltip:AddLine("You can't afford it.", 1, 0.25, 0.25) end
        GameTooltip:Show()
    end)
    row.buy:SetScript("OnLeave", GameTooltip_Hide)
    row.buy:SetMotionScriptsWhileDisabled(true)
    row:SetScript("OnEnter", RowTip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if self.group then
            expanded[self.group.key] = not expanded[self.group.key] or nil
            return UI.Refresh()
        end
        local link = self.result and DisplayLink(self.result.listing.link)
        if not link then return end
        if IsModifiedClick("DRESSUP") then return DressUpItemLink(link) end
        if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link) end
    end)
    row:Hide()
    rows[i] = row
    return row
end

local function PaintHeader(row, group)
    row.result, row.group = nil, group
    row.band:Show()
    row.icon:Hide()
    row.buy:Hide()
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetText(GOLD .. group.name .. "|r")
    row.slot:SetText(GREY .. ("%d option%s"):format(#group.items, #group.items == 1 and "" or "s") .. "|r")
    local best = 0
    for _, item in ipairs(group.items) do best = math.max(best, item.points) end
    row.gain:SetText(GREEN .. "+" .. Score(best) .. "|r")
    local more = #group.items - PerSlot()
    if more > 0 then
        row.price:SetText(GREY .. (expanded[group.key] and "show fewer" or ("+%d more, click"):format(more)) .. "|r")
    else
        row.price:SetText("")
    end
    row:Show()
end

local function PaintRow(row, item, indent)
    if item and item.header then return PaintHeader(row, item) end
    local result = item
    row.result, row.group = result, nil
    if not result then return row:Hide() end
    row.band:Hide()
    row.icon:Show()
    row.buy:Show()
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 2 + indent, 0)
    row.name:SetPoint("LEFT", 26 + indent, 0)
    local listing = result.listing
    row.icon:SetTexture(select(5, GetItemInfoInstant(result.entry.id)))
    row.name:SetText(DisplayLink(listing.link))
    local slotText = (Gear.SLOT_NAME[result.slot] or "?") .. (result.entry.perListing and GREY .. " *|r" or "")
    if (result.entry.required or 0) > Who.Level() then
        slotText = RED .. "Lv " .. result.entry.required .. "|r" .. (result.entry.perListing and GREY .. " *|r" or "")
    end
    row.slot:SetText(slotText)
    row.gain:SetText(GREEN .. "+" .. Score(result.points) .. "|r")
    row.price:SetText(SD.Money(listing.price))
    local canBuy = SD.Scanner.AHOpen() and GetMoney() >= listing.price
    row.buy:SetEnabled(canBuy)
    row.buy.cart:SetDesaturated(not canBuy)
    row.buy.cart:SetAlpha(canBuy and 1 or 0.5)
    row:Show()
end

-- Grouping: one header per slot (rings and trinkets together), its options under it, slots ordered by their best.
local function DisplayList(results)
    local groups, order = {}, {}
    for _, result in ipairs(results) do
        local key = Gear.GroupOf(result.slot)
        local group = groups[key]
        if not group then
            group = { header = true, key = key, items = {},
                name = Gear.GroupName(key) or "?" }
            groups[key] = group
            order[#order + 1] = group
        end
        group.items[#group.items + 1] = result
    end
    local out = {}
    for _, group in ipairs(order) do
        out[#out + 1] = group
        local shown = expanded[group.key] and #group.items or math.min(PerSlot(), #group.items)
        for i = 1, shown do out[#out + 1] = group.items[i] end
    end
    return out
end
UI.DisplayList = DisplayList

-- Weights column -------------------------------------------------------------------------------------------------

local function UsedStats()
    local base = SD.BaseWeights()
    local used = {}
    for _, stat in ipairs(SD.STATS) do
        local key = stat[1]
        if (base[key] or 0) ~= 0 or key == "sta" or SD.StatShown(key) then used[#used + 1] = key end
    end
    return used, base
end

local HINT_OWN = "Worth of 1 point (or 1%). 0 ignores a stat."
local HINT_PAWN = "Edit the scale in Pawn (/pawn)."

local function RefreshWeights()
    if not (weights and weights:IsShown()) then return end
    local pawn = SD.WeightsFromPawn()
    weights.title:SetText(pawn and SD.ChoiceText() or ("Weights: " .. SD.SpecName()))
    weights.hint:SetText(pawn and HINT_PAWN or HINT_OWN)
    weights.reset:SetEnabled(not pawn)
    local used, base = UsedStats()
    for i, line in ipairs(weightLines) do
        local stat = used[i]
        line.stat = stat
        if stat then
            local changed = SD.WeightChanged(stat)
            line.label:SetText((changed and "|cffffd100" or "|cffffffff") .. (SHORT_STAT[stat] or SD.StatName(stat)) .. "|r")
            SetIfIdle(line.edit, tostring(base[stat] or 0))
            line.edit:SetEnabled(not pawn)
            line.edit:SetTextColor(pawn and 0.6 or 1, pawn and 0.6 or 1, pawn and 0.6 or 1)
            line:Show()
        else
            line:Hide()
        end
    end
    local open = picker and picker:IsShown()
    if open and pawn then picker:Hide() open = false end   -- a Pawn scale can't take new stats
    weights.add:SetEnabled(open or (not pawn and #used < #SD.STATS and #used < #weightLines))
    if open then picker:Fill(used) end
end

-- "Add stat": a list of the stats not in the panel; a click adds one at 0 and puts the cursor in its box.
local PICK_ROWS, PICK_H = 16, 18

local function AddStat(stat)
    picker:Hide()
    SD.ShowStat(stat)
    UI.Refresh()
    for _, line in ipairs(weightLines) do
        if line.stat == stat then
            line.edit:SetFocus()
            line.edit:HighlightText()
        end
    end
end

local function BuildPicker()
    picker = CreateFrame("Frame", nil, weights)
    picker:SetPoint("TOPLEFT", 4, -4)
    picker:SetPoint("BOTTOMRIGHT", -4, 40)
    picker:SetFrameLevel(weights:GetFrameLevel() + 20)
    picker:EnableMouse(true)
    local bg = picker:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.04, 0.97)
    local title = Label(picker, "Add a stat", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -6)
    local hint = Label(picker, "It starts at 0; type its weight.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, -24)
    picker.buttons = {}
    local colW = (WEIGHTS_W - 28) / 2
    for i = 1, PICK_ROWS * 2 do
        local col, r = math.floor((i - 1) / PICK_ROWS), (i - 1) % PICK_ROWS
        local b = CreateFrame("Button", nil, picker)
        b:SetSize(colW - 4, PICK_H)
        b:SetPoint("TOPLEFT", 8 + col * colW, -42 - r * PICK_H)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.label = Label(b, "", "GameFontHighlightSmall")
        b.label:SetPoint("LEFT", 4, 0)
        b:SetScript("OnClick", function(self) AddStat(self.stat) end)
        picker.buttons[i] = b
    end
    function picker:Fill(used)
        local inPanel = {}
        for _, stat in ipairs(used) do inPanel[stat] = true end
        local n = 0
        for _, stat in ipairs(SD.STATS) do
            if not inPanel[stat[1]] and n < #self.buttons then
                n = n + 1
                local b = self.buttons[n]
                b.stat = stat[1]
                b.label:SetText(stat[2])
                b:Show()
            end
        end
        for i = n + 1, #self.buttons do self.buttons[i]:Hide() end
    end
    -- While the list is open its button closes it again.
    picker:SetScript("OnShow", function() weights.add:SetText("Back") end)
    picker:SetScript("OnHide", function() weights.add:SetText("Add stat") end)
    picker:Hide()
end

local function TogglePicker()
    if not picker then BuildPicker() end
    picker:SetShown(not picker:IsShown())
    if picker:IsShown() then picker:Fill((UsedStats())) end
end

local function BuildWeights()
    weights = Inset(tab)
    weights:SetPoint("TOPRIGHT", -4, LIST_TOP)
    weights:SetPoint("BOTTOMRIGHT", -4, 4)
    weights:SetWidth(WEIGHTS_W)
    weights.title = Label(weights, "Weights", "GameFontNormal")
    weights.title:SetPoint("TOPLEFT", 10, -8)
    weights.title:SetPoint("RIGHT", -10, 0)
    weights.title:SetJustifyH("LEFT")
    weights.title:SetWordWrap(false)
    weights.hint = Label(weights, HINT_OWN, "GameFontDisableSmall")
    weights.hint:SetPoint("TOPLEFT", 10, -26)
    local colW = (WEIGHTS_W - 20) / WEIGHT_COLS
    for i = 1, WEIGHT_COLS * WEIGHT_ROWS do
        local col, r = math.floor((i - 1) / WEIGHT_ROWS), (i - 1) % WEIGHT_ROWS
        local line = CreateFrame("Frame", nil, weights)
        line:SetSize(colW - 6, WEIGHT_H)
        line:SetPoint("TOPLEFT", 10 + col * colW, -44 - r * WEIGHT_H)
        line.label = Label(line, "", "GameFontHighlightSmall")
        line.label:SetPoint("LEFT")
        line.label:SetPoint("RIGHT", -42, 0)
        line.label:SetJustifyH("LEFT")
        line.label:SetWordWrap(false)
        line.edit = EditBox(line, 36, function(text)
            local value = tonumber(text)
            if value and line.stat then
                SD.ShowStat(line.stat)   -- a stat you edit stays listed, even at 0
                SD.SetWeight(line.stat, value)
            end
        end)
        line.edit:SetPoint("RIGHT", 0, 0)
        weightLines[i] = line
    end
    weights.reset = Button(weights, "Reset to defaults", 130, function()
        if picker then picker:Hide() end
        SD.ResetWeights()
    end)
    weights.reset:SetPoint("BOTTOMLEFT", 8, 10)
    weights.add = Button(weights, "Add stat", 100, TogglePicker)
    weights.add:SetPoint("BOTTOMRIGHT", -8, 10)
    weights:SetScript("OnHide", function() if picker then picker:Hide() end end)
    weights:Hide()
end

-- Settings column: what the list leaves out and how it shows it.
local SETTING_H = 22
local SLOT_COLS = 3
local QUALITIES = { { 0, "Any" }, { 2, "|cff1eff00Green+|r" }, { 3, "|cff0070ddBlue+|r" } }
local SLIDER_X, SLIDER_W = 118, 140

-- The game's settings slider (with steppers and its value on the right); the classic slider where the client
-- lacks it. read() gives the saved value, write(value) saves a new one (snapped to step), show(value) its text.
local function Slider(parent, minValue, maxValue, step, read, write, show)
    local function Take(value)
        value = math.floor(value / step + 0.5) * step
        if math.abs(value - read()) >= step / 2 then write(value) end
        return value
    end
    local ok, frame = pcall(CreateFrame, "Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
    if ok and frame and frame.Init and frame.RegisterCallback and MinimalSliderWithSteppersMixin then
        frame:SetWidth(SLIDER_W)
        local formatters = {}
        local labels = MinimalSliderWithSteppersMixin.Label
        if labels then formatters[labels.Right] = show end
        frame:Init(read(), minValue, maxValue, math.floor((maxValue - minValue) / step + 0.5), formatters)
        frame:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value) Take(value) end, frame)
        function frame:SyncValue()
            local current = self.Slider and self.Slider:GetValue()
            if not current or math.abs(current - read()) > 1e-6 then self:SetValue(read()) end
        end
        return frame
    end
    frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(SLIDER_W + 40, 20)
    local slider = CreateFrame("Slider", nil, frame, "UISliderTemplate")
    slider:SetSize(SLIDER_W - 10, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("LEFT")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local text = Label(frame, show(read()), "GameFontHighlightSmall")
    text:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    slider:SetValue(read())
    slider:SetScript("OnValueChanged", function(_, value) text:SetText(show(Take(value))) end)
    function frame:SyncValue()
        slider:SetValue(read())
        text:SetText(show(read()))
    end
    return frame
end

local function RefreshSettings()
    if not (settings and settings:IsShown()) then return end
    for _, check in ipairs(settings.slots) do check:SetChecked(not SD.db.skipSlots[check.key]) end
    settings.perSlot:SyncValue()
    settings.minUpgrade:SyncValue()
    settings.bags:SetChecked(SD.db.checkBags)
    settings.lower:SetChecked(SD.db.lowerArmor)
    for _, q in ipairs(QUALITIES) do
        if q[1] == (SD.db.minQuality or 0) then settings.quality:SetText(q[2]) end
    end
    settings.deep:SetChecked(SD.db.deepScan)
end

local function BuildSettings()
    settings = Inset(tab)
    settings:SetPoint("TOPRIGHT", -4, LIST_TOP)
    settings:SetPoint("BOTTOMRIGHT", -4, 4)
    settings:SetWidth(WEIGHTS_W)
    local title = Label(settings, "Settings", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    local slotsLabel = Label(settings, "Slots to show", "GameFontNormalSmall")
    slotsLabel:SetPoint("TOPLEFT", 10, -28)

    settings.slots = {}
    local rowsPerCol = math.ceil(#Gear.GROUPS / SLOT_COLS)
    local colW = (WEIGHTS_W - 20) / SLOT_COLS
    for i, group in ipairs(Gear.GROUPS) do
        local col, r = math.floor((i - 1) / rowsPerCol), (i - 1) % rowsPerCol
        local key = tostring(group[1])
        local check = Check(settings, group[2], function(on)
            SD.db.skipSlots[key] = (not on) or nil
            SD.Scanner.Rescore()
        end)
        check.key = key
        check:SetPoint("TOPLEFT", 8 + col * colW, -42 - r * SETTING_H)
        settings.slots[i] = check
    end
    local y = -42 - rowsPerCol * SETTING_H - 10

    local perSlotLabel = Label(settings, "Options per slot", "GameFontNormalSmall")
    perSlotLabel:SetPoint("TOPLEFT", 12, y - 6)
    settings.perSlot = Slider(settings, 1, 10, 1, PerSlot, function(value)
        SD.db.perSlot = value
        UI.Refresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end)
    settings.perSlot:SetPoint("LEFT", perSlotLabel, "LEFT", SLIDER_X, 0)
    Tip(perSlotLabel, "Options per slot", "How many items each slot shows before you click its header.")
    y = y - 28

    local minLabel = Label(settings, "Hide upgrades under", "GameFontNormalSmall")
    minLabel:SetPoint("TOPLEFT", 12, y - 6)
    settings.minUpgrade = Slider(settings, 0, 20, 0.5, function() return SD.db.minUpgrade or 0 end, function(value)
        SD.db.minUpgrade = value
        SD.Scanner.Rescore()
    end, function(value) return value < 0.25 and "Off" or ("+" .. Score(value)) end)
    settings.minUpgrade:SetPoint("LEFT", minLabel, "LEFT", SLIDER_X, 0)
    y = y - 30

    local qualityLabel = Label(settings, "Quality", "GameFontNormalSmall")
    qualityLabel:SetPoint("TOPLEFT", 12, y - 6)
    settings.quality = Button(settings, "", 90, function()
        local current, nextQ = SD.db.minQuality or 0, QUALITIES[1][1]
        for i, q in ipairs(QUALITIES) do
            if q[1] == current then nextQ = (QUALITIES[i + 1] or QUALITIES[1])[1] end
        end
        SD.db.minQuality = nextQ
        SD.Scanner.Rescore()
    end)
    settings.quality:SetPoint("LEFT", qualityLabel, "LEFT", SLIDER_X, 0)
    Tip(settings.quality, "Quality", "Click to switch: any quality, greens and better, or blues and better.")
    y = y - 28

    settings.bags = Check(settings, "Skip if my bags have better", function(on)
        SD.db.checkBags = on
        SD.Scanner.Rescore()
    end)
    settings.bags:SetPoint("TOPLEFT", 8, y)
    Tip(settings.bags, "Skip if my bags have better",
        "Leave out an item when gear already in your bags would be as big an upgrade for that slot.")
    y = y - SETTING_H - 2

    settings.lower = Check(settings, "Include lower armor types", function(on)
        SD.db.lowerArmor = on
        SD.Scanner.Rescore()
    end)
    settings.lower:SetPoint("TOPLEFT", 8, y)
    Tip(settings.lower, "Include lower armor types",
        "Also suggest armor below your class's best type, like leather for a hunter at 40 or cloth for a rogue. They only show when their stats beat what you wear.")
    y = y - SETTING_H - 2

    settings.deep = Check(settings, "With suffixes", function(on) SD.db.deepScan = on end)
    settings.deep:SetPoint("TOPLEFT", 8, y)
    Tip(settings.deep, "With suffixes",
        "Items like \"... of the Monkey\" get their stats from a suffix. Each suffix is weighed by its real stats. When the auction house lumps an item's suffixes together, its listings are looked up one by one (slower; marked * in the list). Off: those items are skipped. Applies from the next scan.")

    local reset = Button(settings, "Reset settings", 130, function()
        wipe(SD.db.skipSlots)
        SD.db.checkBags, SD.db.minUpgrade, SD.db.perSlot, SD.db.deepScan = false, 0, 3, true
        SD.db.minQuality, SD.db.lowerArmor = 0, false
        SD.Scanner.Rescore()
    end)
    reset:SetPoint("BOTTOMLEFT", 8, 10)
    settings:Hide()
end

-- The right-hand column shows Weights or Settings, or nothing; the list takes the rest.
local function SetSide(panel)
    if weights then weights:SetShown(panel == weights) end
    if settings then settings:SetShown(panel == settings) end
    list:SetPoint("BOTTOMRIGHT", panel and -(WEIGHTS_W + 8) or -4, 4)
    UI.Refresh()
end

local function ToggleWeights()
    if not weights then BuildWeights() end
    SetSide(not weights:IsShown() and weights or nil)
end

local function ToggleSettings()
    if not settings then BuildSettings() end
    SetSide(not settings:IsShown() and settings or nil)
end

-- The settings button's gear: the game's own gear art if this client has it, else the Engineering cog icon.
local GEAR_ATLASES = { "QuestLog-icon-setting", "Options_Gear", "GM-icon-settings" }
local function SetGearIcon(texture)
    if C_Texture and C_Texture.GetAtlasInfo then
        for _, atlas in ipairs(GEAR_ATLASES) do
            if C_Texture.GetAtlasInfo(atlas) then return texture:SetAtlas(atlas) end
        end
    end
    texture:SetTexture("Interface\\Icons\\Trade_Engineering")
end

-- Max price: Blizzard's gold / silver / copper boxes, as on the Sell tab. Empty means no limit.
local PRICE_DELAY = 0.4

-- The compact gold / silver / copper boxes from Send Mail and Trade; Blizzard's large ones if this client lacks them.
local function MoneyBoxes(parent)
    local name = "SugarDaddyMaxPrice"
    local ok, money = pcall(CreateFrame, "Frame", name, parent, "MoneyInputFrameTemplate")
    if ok and MoneyInputFrame_GetCopper and MoneyInputFrame_SetCopper then
        local boxes = { money.gold or _G[name .. "Gold"], money.silver or _G[name .. "Silver"],
            money.copper or _G[name .. "Copper"] }
        local function Get() return MoneyInputFrame_GetCopper(money) or 0 end
        local function Set(copper)
            if copper == 0 and MoneyInputFrame_ResetMoney then return MoneyInputFrame_ResetMoney(money) end
            MoneyInputFrame_SetCopper(money, copper)
        end
        return money, boxes, Get, Set
    end
    money = CreateFrame("Frame", nil, parent, "LargeMoneyInputFrameTemplate")
    money:SetSize(190, 20)
    local function Get() return money:GetAmount() or 0 end
    local function Set(copper)
        if copper > 0 then money:SetAmount(copper) else money:Clear() end
    end
    return money, { money.GoldBox, money.SilverBox, money.CopperBox }, Get, Set
end

local function PriceInput(parent)
    local money, boxes, Get, Set = MoneyBoxes(parent)
    local pending = false
    local function Commit()
        pending = false
        local copper = Get()
        if copper ~= (SD.char.maxPrice or 0) then SD.SetMaxPrice(copper) end
    end
    for _, box in ipairs(boxes) do
        box:HookScript("OnTextChanged", function(_, userInput)
            if not userInput or pending then return end
            pending = true
            C_Timer.After(PRICE_DELAY, Commit)
        end)
        box:HookScript("OnEditFocusLost", Commit)
        box:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Max price", 1, 1, 1)
            GameTooltip:AddLine("Only items at or under this price. Empty means no limit.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        box:HookScript("OnLeave", GameTooltip_Hide)
    end
    -- Shows the saved price unless you're typing in it.
    function money:ShowPrice(copper)
        for _, box in ipairs(boxes) do
            if box:HasFocus() then return end
        end
        copper = copper or 0
        if copper ~= Get() then Set(copper) end
    end
    return money
end

-- Spec menu: your class's specs (Sugar Daddy's weights), then the scales Pawn shows for you, if it's installed.
-- Starts on the spec your talents point to. Clients without the modern dropdown get a button that cycles them.
local SPEC_TIP = "The stat weights used to score items. Starts on your talent spec."

local function HasTemplate(name)
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local function SpecMenu(parent)
    if HasTemplate("WowStyle1DropdownTemplate") then
        local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and dd and dd.SetupMenu then
            dd:SetWidth(170)
            dd:SetupMenu(function(_, root)
                for _, spec in ipairs(SD.ClassSpecs()) do
                    root:CreateRadio(spec.name, function() return SD.SpecSelected(spec.key) end,
                        function() SD.PickSpec(spec.key) end)
                end
                local scales = SD.PawnScale and SD.PawnScale.List() or {}
                if #scales > 0 then
                    root:CreateDivider()
                    root:CreateTitle("Pawn")
                    local picked = SD.PawnScale.Picked()
                    for _, info in ipairs(scales) do
                        root:CreateRadio(info.label, function() return info.name == picked end,
                            function() SD.PawnScale.Pick(info.name) end)
                    end
                end
            end)
            function dd:ShowChoice()
                if self.OverrideText then self:OverrideText(SD.ChoiceText())
                elseif self.GenerateMenu then self:GenerateMenu() end
            end
            dd:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Weights", 1, 1, 1)
                GameTooltip:AddLine(SPEC_TIP, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            dd:HookScript("OnLeave", GameTooltip_Hide)
            return dd
        end
    end
    local b = Button(parent, "", 170, function() SD.NextSpec() end)
    function b:ShowChoice() self:SetText(SD.ChoiceText()) end
    Tip(b, "Weights", SPEC_TIP .. " Click for the next one.")
    return b
end

-- Character menu: whom you shop for. Your characters on this realm and faction show once they have logged in
-- with Sugar Daddy; their gear and bags are as they last saw them.
local CHAR_TIP = "The character you're finding upgrades for. Your other characters show up here "
    .. "after they log in once."

local function ClassColored(class, text)
    local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
    return color and color:WrapTextInColorCode(text) or text
end

local function CharLabel(info)
    return ClassColored(info.class, info.name) .. GREY .. " " .. info.level .. "|r"
end

local function Ago(seen)
    if not seen then return "unknown" end
    local secs = math.max(0, time() - seen)
    if secs < 3600 then return "just now" end
    if secs < 86400 then return ("%d hours ago"):format(math.floor(secs / 3600)) end
    local days = math.floor(secs / 86400)
    return days == 1 and "a day ago" or ("%d days ago"):format(days)
end

local function CharText()
    local rec = Who.Record()
    if not rec then return "Me" end
    return (Who.IsMe() and "Me: " or "For: ") .. ClassColored(rec.class, rec.name or "?")
end

local function CharTip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText("Shopping for", 1, 1, 1)
    GameTooltip:AddLine(CHAR_TIP, nil, nil, nil, true)
    if not Who.IsMe() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%s's gear and bags as last seen: %s."):format(Who.Name(), Ago(Who.Record().seen)),
            1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function CharMenu(parent)
    if HasTemplate("WowStyle1DropdownTemplate") then
        local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and dd and dd.SetupMenu then
            dd:SetWidth(170)
            dd:SetupMenu(function(_, root)
                local others = {}
                for _, info in ipairs(Who.List()) do
                    root:CreateRadio(CharLabel(info), function() return info.key == Who.Key() end,
                        function() Who.Set(info.key) end)
                    if not info.me then others[#others + 1] = info end
                end
                if #others > 0 then
                    root:CreateDivider()
                    local forget = root:CreateButton("Forget a character")
                    for _, info in ipairs(others) do
                        forget:CreateButton(CharLabel(info), function()
                            Who.Forget(info.key)
                            UI.Refresh()
                        end)
                    end
                end
            end)
            function dd:ShowChoice()
                if self.OverrideText then self:OverrideText(CharText())
                elseif self.GenerateMenu then self:GenerateMenu() end
            end
            dd:HookScript("OnEnter", CharTip)
            dd:HookScript("OnLeave", GameTooltip_Hide)
            return dd
        end
    end
    -- Without the dropdown: click for the next character.
    local b = Button(parent, "", 170, function()
        local list = Who.List()
        for i, info in ipairs(list) do
            if info.key == Who.Key() then return Who.Set((list[i + 1] or list[1]).key) end
        end
    end)
    function b:ShowChoice() self:SetText(CharText()) end
    b:SetScript("OnEnter", CharTip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- The tab --------------------------------------------------------------------------------------------------------

local function Build()
    tab = CreateFrame("Frame", "SugarDaddyFrame", AuctionHouseFrame)
    tab:SetPoint("TOPLEFT", 4, -28)
    tab:SetPoint("BOTTOMRIGHT", -4, 27)

    -- Row 1: character, spec, sort, weights
    tab.who = CharMenu(tab)
    tab.who:SetPoint("TOPLEFT", LEFT, -6)
    tab.spec = SpecMenu(tab)
    tab.spec:SetPoint("LEFT", tab.who, "RIGHT", 6, 0)

    tab.gear = Button(tab, "", 28, ToggleSettings)
    tab.gear:SetPoint("TOPRIGHT", -8, -6)
    local gearIcon = tab.gear:CreateTexture(nil, "OVERLAY")
    gearIcon:SetSize(16, 16)
    gearIcon:SetPoint("CENTER")
    SetGearIcon(gearIcon)
    Tip(tab.gear, "Settings", "Slots to show, options per slot, small upgrades, your bags and suffixes.")

    tab.weights = Button(tab, "Weights", 90, ToggleWeights)
    tab.weights:SetPoint("RIGHT", tab.gear, "LEFT", -6, 0)
    tab.sort = Button(tab, "", 160, function()
        SD.db.sort = SD.db.sort == "value" and "gain" or "value"
        SD.Scanner.Rescore()
    end)
    tab.sort:SetPoint("RIGHT", tab.weights, "LEFT", -8, 0)
    Tip(tab.sort, "Sort", "Biggest upgrade first, or the most upgrade per gold first.")

    -- Row 2: levels, max price, scan
    local levelLabel = Label(tab, "Req. level", "GameFontNormalSmall")
    levelLabel:SetPoint("TOPLEFT", LEFT + 2, -40)
    tab.minLevel = EditBox(tab, 30, function(text)
        local value = tonumber(text)
        if value then SD.Scanner.SetLevelRange(value, nil) end
    end)
    tab.minLevel:SetNumeric(true)
    tab.minLevel:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
    local toLabel = Label(tab, "to", "GameFontHighlightSmall")
    toLabel:SetPoint("LEFT", tab.minLevel, "RIGHT", 4, 0)
    tab.maxLevel = EditBox(tab, 30, function(text)
        local value = tonumber(text)
        if value then SD.Scanner.SetLevelRange(nil, value) end
    end)
    tab.maxLevel:SetNumeric(true)
    tab.maxLevel:SetPoint("LEFT", toLabel, "RIGHT", 10, 0)
    Tip(tab.minLevel, "Lowest required level", "Default: 10 below yours. It follows you as you level. Each character keeps its own range.")
    Tip(tab.maxLevel, "Highest required level",
        "Default: your level. Set it higher to shop ahead; gear you can't wear yet shows its level in red.")

    local priceLabel = Label(tab, "Max price", "GameFontNormalSmall")
    priceLabel:SetPoint("LEFT", levelLabel, "RIGHT", 124, 0)
    tab.price = PriceInput(tab)
    tab.price:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)

    tab.scan = Button(tab, "Scan", 110, function()
        if SD.Scanner.Busy() then SD.Scanner.Stop() else SD.Scanner.Start() end
    end)
    tab.scan:SetPoint("TOPRIGHT", -8, -38)

    -- Status line and page counter
    tab.status = Label(tab, "", "GameFontHighlightSmall")
    tab.status:SetPoint("TOPLEFT", 10, -68)
    tab.status:SetJustifyH("LEFT")
    tab.page = Label(tab, "", "GameFontDisableSmall")
    tab.page:SetPoint("TOPRIGHT", -10, -68)
    tab.page:SetJustifyH("RIGHT")
    tab.status:SetPoint("RIGHT", tab.page, "LEFT", -10, 0)

    -- The list
    list = Inset(tab)
    list:SetPoint("TOPLEFT", 4, LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", -4, 4)
    local header = CreateFrame("Frame", nil, list)
    header:SetHeight(ROW_H)
    header:SetPoint("TOPLEFT", 6, -4)
    header:SetPoint("TOPRIGHT", -6, -4)
    Columns(header, "GameFontNormalSmall")
    header.name:SetText("Item")
    header.slot:SetText("Slot")
    header.gain:SetText("Gear score")
    header.price:SetText("Price")
    for i = 1, MAX_ROWS do NewRow(i) end
    list.empty = Label(list, "", "GameFontDisable")
    list.empty:SetPoint("CENTER")

    tab:EnableMouseWheel(true)
    tab:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * WHEEL_STEP
        UI.Refresh()
    end)
    tab:SetScript("OnShow", function() UI.Refresh() end)
    list:SetScript("OnSizeChanged", function() UI.Refresh() end)

    LibAHTab:CreateTab(TAB_ID, tab, TAB_TEXT, TAB_HEADER)
end

function UI.Refresh()
    if not (tab and tab:IsVisible()) then return end
    local Scanner = SD.Scanner
    local results = Scanner.Results()

    tab.who:ShowChoice()
    tab.spec:ShowChoice()
    tab.sort:SetText(SD.db.sort == "value" and "Sort: upgrade per gold" or "Sort: biggest upgrade")

    local minLevel, maxLevel = Scanner.LevelRange()
    SetIfIdle(tab.minLevel, tostring(minLevel))
    SetIfIdle(tab.maxLevel, tostring(maxLevel))
    tab.price:ShowPrice(SD.char.maxPrice)

    tab.scan:SetEnabled(Scanner.AHOpen())
    tab.scan:SetText(Scanner.Busy() and "Stop" or "Scan")
    tab.status:SetText(Scanner.Status())

    local shown = DisplayList(results)
    local indent = INDENT
    visibleRows = math.max(1, math.min(MAX_ROWS, math.floor((list:GetHeight() - LIST_HEAD - 4) / ROW_H)))
    offset = math.max(0, math.min(offset, #shown - visibleRows))
    for i = 1, MAX_ROWS do PaintRow(rows[i], i <= visibleRows and shown[offset + i] or nil, indent) end
    if #shown > visibleRows then
        tab.page:SetText(("Rows %d-%d of %d"):format(offset + 1,
            math.min(offset + visibleRows, #shown), #shown))
    else
        tab.page:SetText("")
    end
    list.empty:SetText(#results == 0 and not Scanner.Busy() and "Press Scan to find upgrades you can buy." or "")
    RefreshWeights()
    RefreshSettings()
end

function UI.ResetScroll()
    offset = 0
    wipe(expanded)
end

-- /sugar: switch the auction house to this tab.
function UI.Toggle()
    if not (SD.Scanner.AHOpen() and AuctionHouseFrame) then
        return SD.Print("Open the auction house; Sugar Daddy is a tab there.")
    end
    if not tab then Build() end
    LibAHTab:SetSelected(TAB_ID)
end

function UI.OnAuctionHouse(open)
    if not open then return end
    if not tab and AuctionHouseFrame then Build() end
    UI.Refresh()
end

SD.OnWeightsChanged(function() UI.Refresh() end)

-- Item names fill in as their data arrives.
local refreshSoon = false
SD.On("GET_ITEM_INFO_RECEIVED", function()
    if refreshSoon or not (tab and tab:IsVisible()) then return end
    refreshSoon = true
    C_Timer.After(0.2, function()
        refreshSoon = false
        UI.Refresh()
    end)
end)
