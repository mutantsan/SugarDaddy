-- Scanner.lua: browses the auction house for weapons and armor at your level, weighs every item, checks
-- items with suffixes ("of the Monkey") by their real stats, ranks the upgrades and buys the one you pick.
local _, SD = ...

local AH = C_AuctionHouse
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID
local Gear = SD.Gear

local Scanner = {}
SD.Scanner = Scanner

local MIN_GAIN = 0.05          -- percent; anything smaller is noise
local BROWSE_TIMEOUT = 20      -- seconds without an answer while browsing
local DEEP_TIMEOUT = 6         -- seconds per item search
local BUY_TIMEOUT = 10
local THROTTLE_RETRY = 1
local PENDING_DELAY = 0.3
local UNCOMMON = 2
local WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local ARMOR = (Enum.ItemClass and Enum.ItemClass.Armor) or 4
local ITEM_SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }
local BROWSE_SORTS = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false } }
local QUALITIES = { "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality", "LegendaryQuality" }

local ahOpen = false
local gen = 0
local phase = "idle"           -- idle, browse, deep, done
local status = "Open the auction house and press Scan."
local entries = {}             -- one per auction house item: { key, id, perListing, listings = { {link, price, auctionID} } }
local results = {}
local deepQueue = {}
local deepBusy
local pendingRows, readyIDs = {}, {}
local pendingScheduled = false
local browse = {}
local sending = false
local waiting
local buy

local function Update()
    if SD.UI and SD.UI.Refresh then SD.UI.Refresh() end
end

local showSummary = false     -- when done, the status line is the live summary

local function Status(text)
    status, showSummary = text, false
    Update()
end

local function CopyKey(key)
    return { itemID = key.itemID, itemLevel = key.itemLevel or 0, itemSuffix = key.itemSuffix or 0,
        battlePetSpeciesID = key.battlePetSpeciesID or 0 }
end

local function SameKey(a, b)
    return a and b and a.itemID == b.itemID and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

-- The link to weigh an auction house item by. On Forever a suffix ("of the Monkey") is a bonus ID in the link, and
-- its stats scale with the item, so an item key with a suffix is asked for its real link (as Auctionator's
-- tooltips do). Plain items are weighed by their base link.
local function KeyLink(key)
    if (key.itemSuffix or 0) ~= 0 and C_TooltipInfo and C_TooltipInfo.GetItemKey then
        local ok, info = pcall(C_TooltipInfo.GetItemKey, key.itemID, key.itemLevel or 0, key.itemSuffix)
        local link = ok and info and info.hyperlink
        if link and GetItemInfoInstant(link) == key.itemID then return link end
    end
    return "item:" .. key.itemID
end

-- The auction house allows so many messages; run fn once it's ready again.
local function WhenReady(fn)
    if AH.IsThrottledMessageSystemReady() then return fn() end
    waiting = fn
    C_Timer.After(THROTTLE_RETRY, function()
        if waiting == fn then
            waiting = nil
            WhenReady(fn)
        end
    end)
end

SD.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    local fn = waiting
    waiting = nil
    if fn then fn() end
end)

-- Ranking --------------------------------------------------------------------------------------------------------

-- Slots you hid in Settings.
function SD.SlotAllowed(slot)
    return not SD.db.skipSlots[tostring(Gear.GroupOf(slot))]
end

-- The biggest upgrade per slot group among gear already in your bags (that you can wear now).
local function BagBest(weights, power)
    local best = {}
    local level = UnitLevel("player")
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for bagSlot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, bagSlot)
            if id and Gear.SlotsFor(id) then
                local link = C_Container.GetContainerItemLink(bag, bagSlot)
                if Gear.Usable(id, link, SD.db.lowerArmor) and (Gear.RequiredLevel(link) or 0) <= level then
                    local gain, points, slot = SD.BestGain(id, link, weights, power, SD.SlotAllowed)
                    if gain and points > 0 then
                        local group = Gear.GroupOf(slot)
                        if not best[group] or points > best[group] then best[group] = points end
                    end
                end
            end
        end
    end
    return best
end

function Scanner.Rescore()
    wipe(results)
    if SD.db and #entries > 0 then
        local weights = SD.Weights()
        local power = SD.Power(weights)
        if power and power > 0 then
            local maxPrice = SD.char.maxPrice or 0
            local byValue = SD.db.sort == "value"
            local minUpgrade = SD.db.minUpgrade or 0
            local minQuality = SD.db.minQuality or 0
            local lowerArmor = SD.db.lowerArmor
            local inBags = SD.db.checkBags and BagBest(weights, power) or nil
            for _, entry in ipairs(entries) do
                local best
                if not entry.bought and entry.quality >= minQuality and (lowerArmor or not entry.lowerArmor) then
                    for _, listing in ipairs(entry.listings) do
                        if maxPrice == 0 or listing.price <= maxPrice then
                            local gain, points, slot, partner, replaced, also =
                                SD.BestGain(entry.id, listing.link, weights, power, SD.SlotAllowed)
                            if gain and gain >= MIN_GAIN and points >= minUpgrade
                                and not (inBags and (inBags[Gear.GroupOf(slot)] or 0) >= points) then
                                local value = points * SD.COPPER_PER_GOLD / math.max(listing.price, 1)
                                local score = byValue and value or points
                                if not best or score > best.score then
                                    best = { entry = entry, listing = listing, gain = gain, points = points,
                                        slot = slot, partner = partner, value = value, score = score,
                                        replaced = replaced, also = also }
                                end
                            end
                        end
                    end
                end
                if best then results[#results + 1] = best end
            end
            table.sort(results, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                return a.listing.price < b.listing.price
            end)
        end
    end
    Update()
end

local function Summary()
    local loading = 0
    for _ in pairs(pendingRows) do loading = loading + 1 end
    local text = ("%d upgrade%s among %d items."):format(#results, #results == 1 and "" or "s", #entries)
    if loading > 0 then text = text .. (" %d still loading."):format(loading) end
    return text
end

-- Weighing one browse row ----------------------------------------------------------------------------------------

local function Pend(row)
    local id = row.key.itemID
    local list = pendingRows[id]
    if not list then
        list = {}
        pendingRows[id] = list
        if RequestLoad then RequestLoad(id) end
    end
    list[#list + 1] = row
end

local function Consider(row)
    local key, id = row.key, row.key.itemID
    if not Gear.SlotsFor(id) then return end
    local link = KeyLink(key)
    local usable, lowerArmor = Gear.Usable(id, link, true)   -- kept either way; Settings decides live
    if usable == nil then return Pend(row) end
    if not usable then return end
    local required = Gear.RequiredLevel(link) or 0
    local _, maxLevel = Scanner.LevelRange()
    if required > maxLevel then return end
    local stats = SD.Stats(link)
    if not stats then return Pend(row) end
    local _, _, quality = GetItemInfo(link)
    local entry = { key = key, id = id, minPrice = row.minPrice, quantity = row.quantity, listings = {},
        required = required, quality = quality or 0, lowerArmor = lowerArmor }
    -- A green or better with no stats of its own gets them from a suffix the key doesn't show:
    -- look its listings up one by one and weigh each.
    local hiddenSuffix = (quality or 0) >= UNCOMMON and not SD.HasRealStats(stats)
    if hiddenSuffix and not SD.db.deepScan then return end
    if hiddenSuffix and SD.db.deepScan then
        entry.perListing = true
        local maxPrice = SD.char.maxPrice or 0
        if maxPrice == 0 or row.minPrice <= maxPrice then deepQueue[#deepQueue + 1] = entry end
    else
        entry.listings[1] = { link = link, price = row.minPrice }
    end
    entries[#entries + 1] = entry
end

-- Items whose suffix varies by listing: one item search each, every listing weighed on its own --------------------

local function ReadListings(entry)
    wipe(entry.listings)
    for i = 1, AH.GetNumItemSearchResults(entry.key) or 0 do
        local r = AH.GetItemSearchResultInfo(entry.key, i)
        if r and r.itemLink and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
            entry.listings[#entry.listings + 1] = { link = r.itemLink, price = r.buyoutAmount, auctionID = r.auctionID }
        end
    end
end

local PumpDeep

local function Finish()
    phase = "done"
    showSummary = true
    Scanner.Rescore()
end

PumpDeep = function()
    if phase ~= "deep" or deepBusy or buy then return end
    local entry = table.remove(deepQueue, 1)
    if not entry then return Finish() end
    deepBusy = entry
    Status(("Checking items with suffixes listing by listing... %d left."):format(#deepQueue + 1))
    local myGen = gen
    WhenReady(function()
        if gen ~= myGen or deepBusy ~= entry then return end
        AH.SendSearchQuery(entry.key, ITEM_SORTS, true)
        C_Timer.After(DEEP_TIMEOUT, function()
            if gen == myGen and deepBusy == entry then
                deepBusy = nil
                PumpDeep()
            end
        end)
    end)
end

local function ResumeDeep()
    if #deepQueue > 0 and (phase == "deep" or phase == "done") then
        phase = "deep"
        PumpDeep()
    end
end

-- Items whose data arrived late
local function ProcessPending()
    pendingScheduled = false
    for id in pairs(readyIDs) do
        local rows = pendingRows[id]
        pendingRows[id] = nil
        for _, row in ipairs(rows or {}) do Consider(row) end
    end
    wipe(readyIDs)
    Scanner.Rescore()
    if phase == "done" then
        if #deepQueue > 0 then return ResumeDeep() end
        showSummary = true
        Update()
    end
end

local function OnItemData(_, itemID)
    if not pendingRows[itemID] then return end
    readyIDs[itemID] = true
    if pendingScheduled then return end
    pendingScheduled = true
    C_Timer.After(PENDING_DELAY, ProcessPending)
end
SD.On("ITEM_DATA_LOAD_RESULT", OnItemData)
SD.On("GET_ITEM_INFO_RECEIVED", OnItemData)

-- Browsing -------------------------------------------------------------------------------------------------------

local function Stop(text)
    gen = gen + 1
    deepBusy = nil
    wipe(deepQueue)
    phase = #entries > 0 and "done" or "idle"
    Scanner.Rescore()
    Status(text)
end

local function Watchdog()
    browse.tick = (browse.tick or 0) + 1
    local tick, myGen = browse.tick, gen
    C_Timer.After(BROWSE_TIMEOUT, function()
        if gen == myGen and phase == "browse" and browse.tick == tick then
            Stop("The auction house stopped answering. Press Scan to try again.")
        end
    end)
end

local function FinishBrowse()
    local rows = AH.GetBrowseResults() or {}
    for _, info in ipairs(rows) do
        if info.itemKey then
            Consider({ key = CopyKey(info.itemKey), minPrice = info.minPrice or 0, quantity = info.totalQuantity or 1 })
        end
    end
    phase = "deep"
    Scanner.Rescore()
    PumpDeep()
end

local function SendBrowse()
    if phase ~= "browse" then return end
    sending = true
    AH.SendBrowseQuery(browse.query)
    sending = false
    browse.sent = true
end

local function OnBrowse()
    if phase ~= "browse" or not browse.sent then return end
    Watchdog()
    if AH.HasFullBrowseResults() then return FinishBrowse() end
    local count = #(AH.GetBrowseResults() or {})
    if count == browse.asked then return end
    browse.asked = count
    Status(("Browsing the auction house... %d items so far."):format(count))
    WhenReady(function()
        if phase == "browse" then AH.RequestMoreBrowseResults() end
    end)
end
SD.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
SD.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)
SD.On("AUCTION_HOUSE_BROWSE_FAILURE", function()
    if phase == "browse" then Stop("The auction house refused the search. Try again in a moment.") end
end)

if AH and AH.SendBrowseQuery then
    hooksecurefunc(AH, "SendBrowseQuery", function()
        if not sending and phase == "browse" then Stop("Another search replaced the scan. Press Scan again.") end
    end)
end

local function Filters()
    local list = {}
    local F = Enum.AuctionHouseFilter or {}
    for _, name in ipairs(QUALITIES) do
        if F[name] then list[#list + 1] = F[name] end
    end
    -- "Usable only" may leave out gear above your level; class and armor checks happen here anyway.
    local _, maxLevel = Scanner.LevelRange()
    if F.UsableOnly and maxLevel <= UnitLevel("player") then list[#list + 1] = F.UsableOnly end
    return list
end

-- Required levels to scan: by default 10 below yours up to yours. Both ends follow you as you level.
function Scanner.LevelRange()
    local level = UnitLevel("player")
    local maxLevel = level + math.max(0, SD.char.levelsAbove or 0)
    local minLevel = math.max(1, level - (SD.char.levelsBelow or 10))
    return math.min(minLevel, maxLevel), maxLevel
end

-- Set either end as an absolute level; the other end moves along if they would cross.
function Scanner.SetLevelRange(minLevel, maxLevel)
    local level = UnitLevel("player")
    local curMin, curMax = Scanner.LevelRange()
    minLevel, maxLevel = math.floor(minLevel or curMin), math.floor(maxLevel or curMax)
    maxLevel = math.max(maxLevel, level)
    minLevel = math.max(1, math.min(minLevel, maxLevel))
    SD.char.levelsBelow = math.max(0, level - minLevel)
    SD.char.levelsAbove = maxLevel - level
end

function Scanner.Start()
    if not ahOpen then return SD.Print("Open the auction house first.") end
    if phase == "browse" or phase == "deep" then return end
    gen = gen + 1
    wipe(entries)
    wipe(results)
    wipe(deepQueue)
    wipe(pendingRows)
    wipe(readyIDs)
    deepBusy = nil
    SD.Forget()
    if SD.UI and SD.UI.ResetScroll then SD.UI.ResetScroll() end
    local minLevel, maxLevel = Scanner.LevelRange()
    browse = { asked = 0, query = {
        searchString = "", minLevel = minLevel, maxLevel = maxLevel, sorts = BROWSE_SORTS, filters = Filters(),
        itemClassFilters = { { classID = WEAPON }, { classID = ARMOR } },
    } }
    phase = "browse"
    Status(("Browsing the auction house for gear of level %d-%d..."):format(minLevel, maxLevel))
    Watchdog()
    WhenReady(SendBrowse)
end

-- Buying ---------------------------------------------------------------------------------------------------------

local function EndBuy(text)
    buy = nil
    StaticPopup_Hide("SUGARDADDY_BUY")
    if text then SD.Print(text) end
    Scanner.Rescore()
    if phase == "deep" then PumpDeep() elseif phase == "done" then showSummary = true end
    Update()
end

local function ReadBuy()
    local result = buy.result
    local entry, wanted = result.entry, result.listing
    local pick
    for i = 1, AH.GetNumItemSearchResults(entry.key) or 0 do
        local r = AH.GetItemSearchResultInfo(entry.key, i)
        if r and r.itemLink and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
            if wanted.auctionID then
                if r.auctionID == wanted.auctionID then pick = r end
            elseif not pick or r.buyoutAmount < pick.buyoutAmount then
                pick = r
            end
        end
    end
    if entry.perListing then ReadListings(entry) end
    local maxPrice = SD.char.maxPrice or 0
    if not pick or (maxPrice > 0 and pick.buyoutAmount > maxPrice) then
        if not entry.perListing then
            entry.listings[1] = pick and { link = entry.listings[1].link, price = pick.buyoutAmount } or nil
        end
        return EndBuy("That listing is gone or over your max price. The list is updated.")
    end
    buy.state = "confirm"
    buy.auctionID, buy.price, buy.link = pick.auctionID, pick.buyoutAmount, pick.itemLink
    local what = ("%s\n|cff20ff20+%.1f gear score|r"):format(pick.itemLink, result.points)
    StaticPopup_Show("SUGARDADDY_BUY", what, SD.Money(pick.buyoutAmount))
end

SD.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
    if buy and buy.state == "searching" then
        if SameKey(itemKey, buy.result.entry.key) then ReadBuy() end
        return
    end
    local entry = deepBusy
    if not (entry and SameKey(itemKey, entry.key)) then return end
    ReadListings(entry)
    deepBusy = nil
    Scanner.Rescore()
    PumpDeep()
end)

function Scanner.Buy(result)
    if not ahOpen then return SD.Print("Open the auction house first.") end
    if buy then return SD.Print("Still busy with the last purchase.") end
    if GetMoney() < result.listing.price then return SD.Print("You can't afford that one.") end
    if deepBusy then
        table.insert(deepQueue, 1, deepBusy)
        deepBusy = nil
    end
    local current = { result = result, state = "searching" }
    buy = current
    Status("Looking up " .. result.listing.link .. "...")
    WhenReady(function()
        if buy ~= current then return end
        AH.SendSearchQuery(result.entry.key, ITEM_SORTS, true)
        C_Timer.After(BUY_TIMEOUT, function()
            if buy == current and buy.state == "searching" then EndBuy("The auction house didn't answer. Try again.") end
        end)
    end)
end

local function PlaceBid()
    if not (buy and buy.state == "confirm") then return end
    if GetMoney() < buy.price then return EndBuy("You can't afford that one.") end
    buy.state = "buying"
    local current = buy
    AH.PlaceBid(buy.auctionID, buy.price)
    C_Timer.After(BUY_TIMEOUT, function()
        if buy == current and buy.state == "buying" then EndBuy("No word from the auction house on that purchase. Check your mail.") end
    end)
end

StaticPopupDialogs.SUGARDADDY_BUY = {
    text = "Buy %s\n\nfor %s?",
    button1 = BUY or "Buy",
    button2 = CANCEL or "Cancel",
    OnAccept = PlaceBid,
    OnCancel = function(_, _, reason)
        if buy and buy.state == "confirm" then EndBuy() end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

SD.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, auctionID)
    if not (buy and buy.state == "buying") then return end
    if auctionID and buy.auctionID and auctionID ~= buy.auctionID then return end
    buy.result.entry.bought = true
    EndBuy("Bought " .. buy.link .. " for " .. SD.Money(buy.price) .. ". It's in your mailbox.")
end)

SD.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if buy and buy.state == "buying" then EndBuy("The purchase failed. Someone may have been faster.") end
end)

-- Auction house open / closed, and anything that changes the scores -------------------------------------------------

SD.On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
    if phase == "idle" then status = "Press Scan to look for upgrades." end
    if SD.UI then SD.UI.OnAuctionHouse(true) end
end)

SD.On("AUCTION_HOUSE_CLOSED", function()
    ahOpen = false
    waiting = nil
    if buy then
        buy = nil
        StaticPopup_Hide("SUGARDADDY_BUY")
    end
    if phase == "browse" or phase == "deep" then Stop("The auction house closed; the scan stopped.") end
    if SD.UI then SD.UI.OnAuctionHouse(false) end
end)

local rescoreSoon = false
local function RescoreSoon()
    if rescoreSoon then return end
    rescoreSoon = true
    C_Timer.After(0.2, function()
        rescoreSoon = false
        Scanner.Rescore()
    end)
end
SD.On("PLAYER_EQUIPMENT_CHANGED", RescoreSoon)
SD.On("PLAYER_LEVEL_UP", RescoreSoon)
SD.On("BAG_UPDATE_DELAYED", function()
    if SD.db and SD.db.checkBags then RescoreSoon() end
end)
SD.OnWeightsChanged(RescoreSoon)

function Scanner.Results() return results end
function Scanner.Status()
    if showSummary and phase == "done" then return Summary() end
    return status
end
function Scanner.Busy() return phase == "browse" or phase == "deep" end
function Scanner.AHOpen() return ahOpen end

function Scanner.SetMaxPrice(copper)
    SD.char.maxPrice = math.max(0, copper or 0)
    Scanner.Rescore()
end
SD.SetMaxPrice = Scanner.SetMaxPrice
