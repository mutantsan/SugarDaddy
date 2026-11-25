-- Scanner.lua: browses the auction house for weapons and armor at your level, weighs every item, checks
-- items with suffixes ("of the Monkey") by their real stats, ranks the upgrades and buys the one you pick.
local _, SD = ...

local AH = C_AuctionHouse
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID
local Gear = SD.Gear
local Who = SD.Who

local Scanner = {}
SD.Scanner = Scanner

local MIN_GAIN = 0.05          -- percent; anything smaller is noise
local BROWSE_TIMEOUT = 20      -- seconds without an answer while browsing
local DEEP_TIMEOUT = 6         -- seconds per item search
local BUY_TIMEOUT = 10
local THROTTLE_RETRY = 1
local PENDING_DELAY = 0.3
local RESCORE_DELAY = 0.5      -- seconds; rescoring is batched while results stream in
-- Safety margin on the best possible suffix, for items itemized above the budget formula.
local SUFFIX_HEADROOM = 1.3
-- Classic Era suffixes have up to two stats and no ratings; later versions up to three, ratings included.
local ERA = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local SUFFIX_STATS = ERA and 2 or 3
-- Stat budget by slot (Classic itemization): the share of an item's value the slot gets.
local SLOT_BUDGET = {
    INVTYPE_HEAD = 1, INVTYPE_CHEST = 1, INVTYPE_ROBE = 1, INVTYPE_LEGS = 1, INVTYPE_2HWEAPON = 1,
    INVTYPE_SHOULDER = 0.77, INVTYPE_HAND = 0.77, INVTYPE_WAIST = 0.77, INVTYPE_FEET = 0.77,
    INVTYPE_TRINKET = 0.7, INVTYPE_NECK = 0.56, INVTYPE_WRIST = 0.56, INVTYPE_FINGER = 0.56, INVTYPE_CLOAK = 0.56,
    INVTYPE_SHIELD = 0.56, INVTYPE_HOLDABLE = 0.56, INVTYPE_WEAPON = 0.42, INVTYPE_WEAPONMAINHAND = 0.42,
    INVTYPE_WEAPONOFFHAND = 0.42, INVTYPE_RANGED = 0.32, INVTYPE_RANGEDRIGHT = 0.32, INVTYPE_THROWN = 0.32,
    INVTYPE_RELIC = 0.32,
}
-- How much of each stat one budget point buys.
local PER_BUDGET = { str = 1, agi = 1, sta = 1, int = 1, spi = 1, def = 1, ap = 2, rap = 2.5, heal = 2.2,
    fire = 1.4, frost = 1.4, shadow = 1.4, nature = 1.4, arcane = 1.4, holy = 1.4, mp5 = 0.4, bv = 2, armor = 10 }
-- Ratings, converted to percent (the weights' unit). Not on Classic Era suffixes.
local RATING_PER_BUDGET = { haste = 0.1, exp = 0.1, dodge = 1 / 12, block = 0.2, arp = 1.5 }
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
local stopped = false          -- the last scan was cut short: results are partial
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

local PumpDeep

local rescoreSoon = false
local function RescoreSoon()
    if rescoreSoon then return end
    rescoreSoon = true
    C_Timer.After(RESCORE_DELAY, function()
        rescoreSoon = false
        Scanner.Rescore()
    end)
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

-- The link to weigh an auction house item by: its base link. A suffix ("of the Monkey") isn't in the key's link
-- (the game's tooltip link for a key leaves it out), so suffix items are weighed by a learned link (see Resolve)
-- or listing by listing.
local function KeyLink(key)
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
    local level = Who.Level()
    Who.ForEachBagItem(function(id, link)
        if Gear.SlotsFor(id) and Gear.Usable(id, link, SD.db.lowerArmor) and (Gear.RequiredLevel(link) or 0) <= level then
            local gain, points, slot = SD.BestGain(id, link, weights, power, SD.SlotAllowed)
            if gain and points > 0 then
                local group = Gear.GroupOf(slot)
                if not best[group] or points > best[group] then best[group] = points end
            end
        end
    end)
    return best
end

-- Suffixes without searching ------------------------------------------------------------------------------------
-- The auction house names a suffix by its own id; item links carry it as bonus IDs. Each search shows both, so the
-- pair is remembered, and later items with that suffix get their link built and weighed right away. A built link
-- is only trusted when its name matches the auction house's name for the item ("Elder's Cloak of the Champion").

local function LinkFields(link)
    local itemString = link and link:match("item:([%-%d:]+)")
    if not itemString then return nil end
    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    return fields
end

-- "1:12756": the bonus count and IDs of a link (fields 13 on), or nil when it has none.
local function BonusOf(link)
    local fields = LinkFields(link)
    local count = fields and tonumber(fields[13])
    if not count or count < 1 then return nil end
    local parts = { count }
    for i = 1, count do
        if not tonumber(fields[13 + i]) then return nil end
        parts[#parts + 1] = fields[13 + i]
    end
    return table.concat(parts, ":")
end

local function Learn(entry)
    local suffix = entry.key.itemSuffix or 0
    if suffix == 0 or not entry.listings[1] then return end
    local bonus = BonusOf(entry.listings[1].link)
    if not bonus then return end
    for _, listing in ipairs(entry.listings) do
        if BonusOf(listing.link) ~= bonus then return end
    end
    SD.db.suffixBonus[tostring(suffix)] = bonus
end

-- Weigh suffix items whose suffix is already known by a built link instead of a search.
local function Resolve()
    local known = SD.db.suffixBonus
    for _, entry in ipairs(entries) do
        local bonus = entry.unchecked and entry ~= deepBusy and known[tostring(entry.key.itemSuffix or 0)]
        if bonus and entry.triedBonus ~= bonus then
            local info = AH.GetItemKeyInfo and AH.GetItemKeyInfo(entry.key)
            local link = ("item:%d::::::::%d::::%s"):format(entry.id, Who.Level(), bonus)
            local name = GetItemInfo(link)
            local stats = name and info and info.itemName and SD.Stats(link)
            if stats then
                entry.triedBonus = bonus   -- checked once; a mismatch leaves it to a search
                if name == info.itemName and SD.HasRealStats(stats) then
                    entry.unchecked, entry.perListing = nil, nil
                    entry.listings[1] = { link = link, price = entry.minPrice }
                end
            end
        end
    end
end

-- Most one budget point of suffix can be worth with these weights. Stats share the budget as
-- sum(stat ^ 1.5) = budget ^ 1.5, so the best mix of the top stats worths k is worth (sum k^3)^(1/3) per point.
local function SuffixWorth(weights)
    local w = function(stat) return math.max(weights[stat] or 0, 0) end
    local worths = { 1.2 * (w("spell") + w("heal")) }
    for stat, per in pairs(PER_BUDGET) do worths[#worths + 1] = w(stat) * per end
    if not ERA then
        for stat, per in pairs(RATING_PER_BUDGET) do worths[#worths + 1] = w(stat) * per end
        worths[#worths + 1] = (w("hit") + w("shit")) / 10
        worths[#worths + 1] = (w("crit") + w("scrit")) / 14
    end
    table.sort(worths, function(a, b) return a > b end)
    local cubes = 0
    for i = 1, SUFFIX_STATS do cubes = cubes + (worths[i] or 0) ^ 3 end
    return cubes ^ (1 / 3)
end

-- Most a hidden suffix could add to this item, in score points.
local function SuffixMax(entry, perBudget)
    local _, _, _, equipLoc = GetItemInfoInstant(entry.id)
    local _, _, _, itemLevel = GetItemInfo(entry.link)
    itemLevel = itemLevel or entry.key.itemLevel or 0
    local value
    if entry.quality >= 4 then
        value = (itemLevel - 1.3) / 1.3
    elseif entry.quality == 3 then
        value = (itemLevel - 1.84) / 1.6
    else
        value = (itemLevel - 4) / 2
    end
    return SUFFIX_HEADROOM * math.max(value, 1) * (SLOT_BUDGET[equipLoc] or 1) * perBudget
end

-- Queue the suffix items still worth a search, most promising first. Items that can't pass the filters or beat
-- your gear even with the best suffix wait; they get queued if settings, weights or gear change.
local function Plan(weights, power, inBags)
    wipe(deepQueue)
    if stopped or not SD.db.deepScan then return end
    local perBudget = SuffixWorth(weights)
    local maxPrice = SD.char.maxPrice or 0
    local byValue = SD.db.sort == "value"
    local minUpgrade = SD.db.minUpgrade or 0
    local minQuality = SD.db.minQuality or 0
    local lowerArmor = SD.db.lowerArmor
    for _, entry in ipairs(entries) do
        if entry.unchecked and entry ~= deepBusy and entry.quality >= minQuality
            and (lowerArmor or not entry.lowerArmor) and (maxPrice == 0 or entry.minPrice <= maxPrice) then
            local _, points, slot = SD.BestGain(entry.id, entry.link, weights, power, SD.SlotAllowed)
            if points then
                local bound = points + SuffixMax(entry, perBudget)
                if bound > 0 and 100 * bound / power >= MIN_GAIN and bound >= minUpgrade
                    and not (inBags and (inBags[Gear.GroupOf(slot)] or 0) >= bound) then
                    entry.priority = byValue and bound / math.max(entry.minPrice, 1) or bound
                    deepQueue[#deepQueue + 1] = entry
                end
            end
        end
    end
    table.sort(deepQueue, function(a, b) return a.priority > b.priority end)
end

function Scanner.Rescore()
    wipe(results)
    local planned = false
    if SD.db and #entries > 0 then Resolve() end
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
            Plan(weights, power, inBags)
            planned = true
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
    if not planned then wipe(deepQueue) end
    Update()
    -- Settings or gear changed after the scan: check the suffix items that may now be upgrades.
    if phase == "done" and ahOpen and #deepQueue > 0 then
        phase = "deep"
        PumpDeep()
    end
end

local function NoGearText()
    return ("No gear saved for %s yet. Log in on %s once, then come back."):format(Who.Name(), Who.Name())
end

local function Summary()
    if not Who.HasGear() then return NoGearText() end
    local loading = 0
    for _ in pairs(pendingRows) do loading = loading + 1 end
    local text = ("%d upgrade%s among %d items."):format(#results, #results == 1 and "" or "s", #entries)
    if loading > 0 then text = text .. (" %d still loading."):format(loading) end
    if stopped then text = text .. " Scan stopped early." end
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
    if hiddenSuffix then
        entry.perListing, entry.unchecked, entry.link = true, true, link
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

local function Finish()
    phase = "done"
    showSummary = true
    Scanner.Rescore()
end

PumpDeep = function()
    if phase ~= "deep" or deepBusy or buy then return end
    local entry = table.remove(deepQueue, 1)
    if not entry then return Finish() end
    entry.unchecked = nil
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

-- Items whose data arrived late
local function ProcessPending()
    pendingScheduled = false
    for id in pairs(readyIDs) do
        local rows = pendingRows[id]
        pendingRows[id] = nil
        for _, row in ipairs(rows or {}) do Consider(row) end
    end
    wipe(readyIDs)
    if phase == "done" then showSummary = true end
    Scanner.Rescore()
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
    stopped = true
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
    -- "Usable only" may leave out gear above your level; class and armor checks happen here anyway. It goes by
    -- the logged-in character, so it's left out while shopping for someone else.
    local _, maxLevel = Scanner.LevelRange()
    if F.UsableOnly and Who.IsMe() and maxLevel <= UnitLevel("player") then list[#list + 1] = F.UsableOnly end
    return list
end

-- Required levels to scan: by default 10 below yours up to yours. Both ends follow you as you level.
function Scanner.LevelRange()
    local level = Who.Level()
    local pick = Who.Pick() or {}
    local maxLevel = level + math.max(0, pick.levelsAbove or 0)
    local minLevel = math.max(1, level - (pick.levelsBelow or 10))
    return math.min(minLevel, maxLevel), maxLevel
end

-- Set either end as an absolute level; the other end moves along if they would cross.
function Scanner.SetLevelRange(minLevel, maxLevel)
    local pick = Who.Pick()
    if not pick then return end
    local level = Who.Level()
    local curMin, curMax = Scanner.LevelRange()
    minLevel, maxLevel = math.floor(minLevel or curMin), math.floor(maxLevel or curMax)
    maxLevel = math.max(maxLevel, level)
    minLevel = math.max(1, math.min(minLevel, maxLevel))
    pick.levelsBelow = math.max(0, level - minLevel)
    pick.levelsAbove = maxLevel - level
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
    stopped = false
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

function Scanner.Stop()
    if not Scanner.Busy() then return end
    Stop("Scan stopped.")
    if phase == "done" then
        showSummary = true
        Update()
    end
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
    Learn(entry)
    deepBusy = nil
    RescoreSoon()
    PumpDeep()
end)

function Scanner.Buy(result)
    if not ahOpen then return SD.Print("Open the auction house first.") end
    if buy then return SD.Print("Still busy with the last purchase.") end
    if GetMoney() < result.listing.price then return SD.Print("You can't afford that one.") end
    if deepBusy then
        deepBusy.unchecked = true
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

-- Your own gear and level only matter while you shop for yourself.
SD.On("PLAYER_EQUIPMENT_CHANGED", function() if Who.IsMe() then RescoreSoon() end end)
SD.On("PLAYER_LEVEL_UP", function() if Who.IsMe() then RescoreSoon() end end)
SD.On("BAG_UPDATE_DELAYED", function()
    if SD.db and SD.db.checkBags and Who.IsMe() then RescoreSoon() end
end)

-- Another character to shop for: a new class and level range, so the old scan no longer applies.
Who.OnChanged(function()
    gen = gen + 1
    wipe(entries)
    wipe(results)
    wipe(deepQueue)
    wipe(pendingRows)
    wipe(readyIDs)
    deepBusy = nil
    stopped = false
    phase = "idle"
    if SD.UI and SD.UI.ResetScroll then SD.UI.ResetScroll() end
    local whom = Who.IsMe() and "yourself" or Who.Name()
    if not Who.HasGear() then return Status(NoGearText()) end
    Status(("Shopping for %s. Press Scan%s."):format(whom, ahOpen and "" or " at the auction house"))
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
