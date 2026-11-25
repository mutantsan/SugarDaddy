-- Worth.lua: an item's score by your weights, your character's total score, and how much stronger an item makes
-- you over what you wear (SD.BestGain), with the hit cap and two-hand / dual-wield swaps counted.
local _, SD = ...

local GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local IsCached = C_Item and C_Item.IsItemDataCachedByID
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

local Gear = SD.Gear
local GAME_KEYS, PER_PERCENT = SD.GAME_KEYS, SD.PER_PERCENT
local MAIN_HAND, OFF_HAND = Gear.MAIN_HAND, Gear.OFF_HAND

local PERCENT = 100
local DPS = "dps"
local HUNTER = "HUNTER"
local DPS_SHARE = { [16] = 1, [17] = 0.5 }
local HUNTER_DPS_SHARE = { [18] = 1 }
local PRIMARY = { "str", "agi", "sta", "int", "spi" }
local PRIMARY_KEY = { str = true, agi = true, sta = true, int = true, spi = true }
local HIT, SPELL_HIT = "hit", "shit"
local HIT_KINDS = { HIT, SPELL_HIT }
local HIT_CAP = { [HIT] = 8, [SPELL_HIT] = 17 }
local DUAL_WIELD_HIT_CAP = 27
local HIT_RATING, SPELL_HIT_RATING = "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT"

local statsOf = {}
local hitGear, hitNow = { [HIT] = 0, [SPELL_HIT] = 0 }, { [HIT] = 0, [SPELL_HIT] = 0 }
local lastPower
local partners
local Who = SD.Who

local function Class() return Who.Class() end

-- Your own stats can be secret (in combat on Forever); another character's are a snapshot and never are.
local function Secret()
    return Who.IsMe() and C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret()
end

-- Forget cached stats and the bag partners: on equipment changes and at each scan.
function SD.Forget()
    wipe(statsOf)
    partners = nil
end
SD.On("PLAYER_EQUIPMENT_CHANGED", SD.Forget)
SD.On("BAG_UPDATE_DELAYED", function() partners = nil end)
Who.OnChanged(function() lastPower = nil end)

-- The item's stats, or nil while its data loads (it is asked for).
function SD.Stats(item)
    local stats = statsOf[item]
    if stats then return stats end
    local id = type(item) == "number" and item or GetItemInfoInstant(item)
    if not id then return nil end
    if IsCached and not IsCached(id) then
        if RequestLoad then RequestLoad(id) end
        return nil
    end
    stats = GetItemStats(type(item) == "number" and ("item:" .. item) or item) or {}
    statsOf[item] = stats
    return stats
end

-- True when the item has stats other than armor and weapon dps.
function SD.HasRealStats(stats)
    for key in pairs(stats) do
        local mine = GAME_KEYS[key]
        if mine and mine ~= "armor" and mine ~= DPS then return true end
    end
    return false
end

function SD.DpsShare(slot)
    local shares = Class() == HUNTER and HUNTER_DPS_SHARE or DPS_SHARE
    return shares[slot] or 0
end

function SD.Worth(stats, weights, dpsShare, skipPrimary)
    local worth = 0
    for key, value in pairs(stats) do
        local mine = GAME_KEYS[key]
        local per = PER_PERCENT[key]
        if per then value = value / per end
        if type(mine) == "table" then
            for i = 1, #mine do worth = worth + (weights[mine[i]] or 0) * value end
        elseif mine == DPS then
            worth = worth + (weights.dps or 0) * value * (dpsShare or 0)
        elseif mine and not (skipPrimary and PRIMARY_KEY[mine]) then
            worth = worth + (weights[mine] or 0) * value
        end
    end
    return worth
end

local function WornWorth(slot, weights)
    local link = Who.Equipped(slot)
    if not link then return 0 end
    local worn = SD.Stats(link)
    return worn and SD.Worth(worn, weights, SD.DpsShare(slot))
end

-- Hit cap: hit past the cap is worth nothing.
local function HitOf(stats, kind)
    local hit = (stats[HIT_RATING] or 0) / PER_PERCENT[HIT_RATING]
    if kind == SPELL_HIT then hit = hit + (stats[SPELL_HIT_RATING] or 0) / PER_PERCENT[SPELL_HIT_RATING] end
    return hit
end

local function WornHit(slot, kind)
    local link = slot and Who.Equipped(slot)
    local worn = link and SD.Stats(link)
    return worn and HitOf(worn, kind) or 0
end

local function HitCap(kind, off)
    if kind == HIT and Class() ~= HUNTER and off and Gear.NeedsDualWield(off, OFF_HAND) then
        return DUAL_WIELD_HIT_CAP
    end
    return HIT_CAP[kind]
end

local function CountedHit(from, delta, cap, capAfter)
    return math.min(from + delta, capAfter or cap) - math.min(from, cap)
end

local function ReadHit()
    hitGear[HIT], hitGear[SPELL_HIT] = 0, 0
    for _, slot in ipairs(Gear.SLOTS) do
        local link = Who.Equipped(slot)
        local stats = link and SD.Stats(link)
        if stats then
            for _, kind in ipairs(HIT_KINDS) do hitGear[kind] = hitGear[kind] + HitOf(stats, kind) end
        end
    end
    hitNow[HIT], hitNow[SPELL_HIT] = Who.HitNow(HIT), Who.HitNow(SPELL_HIT)
end

local function HitBeyondCap(weights, stats, item, slot, also)
    local off = Who.EquippedID(OFF_HAND)
    local offAfter = off
    if slot == OFF_HAND then
        offAfter = GetItemInfoInstant(item)
    elseif also == OFF_HAND then
        offAfter = nil
    end
    local fix = 0
    for _, kind in ipairs(HIT_KINDS) do
        local weight = weights[kind] or 0
        if weight ~= 0 then
            local delta = HitOf(stats, kind) - WornHit(slot, kind) - WornHit(also, kind)
            local counted = CountedHit(hitNow[kind], delta, HitCap(kind, off), HitCap(kind, offAfter))
            fix = fix + weight * (counted - delta)
        end
    end
    return fix
end

-- Your whole character by these weights: base stats plus everything your gear gives. Gains are a percent of it.
function SD.Power(weights)
    if Secret() then return lastPower end
    local power = 0
    for i, key in ipairs(PRIMARY) do power = power + (weights[key] or 0) * Who.BaseStat(i) end
    for _, slot in ipairs(Gear.SLOTS) do
        local link = Who.Equipped(slot)
        local stats = link and SD.Stats(link)
        if stats then power = power + SD.Worth(stats, weights, SD.DpsShare(slot), true) end
    end
    ReadHit()
    local off = Who.EquippedID(OFF_HAND)
    for _, kind in ipairs(HIT_KINDS) do
        local gear = hitGear[kind]
        power = power + (weights[kind] or 0) * (CountedHit(hitNow[kind] - gear, gear, HitCap(kind, off)) - gear)
    end
    lastPower = power
    return power
end

-- Wearing a two-hander, a one-hander only counts with something for the other hand: the best one in your bags.
local function BagPartners(weights)
    if partners and partners.weights == weights then return partners end
    partners = { weights = weights, [MAIN_HAND] = {}, [OFF_HAND] = {} }
    local dualWield = Who.CanDualWield()
    Who.ForEachBagItem(function(id, link)
        local slots = Gear.SlotsFor(id)
        if slots and Gear.OtherHand(slots[1]) and not Gear.IsTwoHand(id) then
            local stats = Gear.Usable(id, link, SD.db.lowerArmor) and SD.Stats(link)
            if stats then
                for _, slot in ipairs(slots) do
                    if dualWield or not Gear.NeedsDualWield(id, slot) then
                        local worth = SD.Worth(stats, weights, SD.DpsShare(slot))
                        local hand = partners[slot]
                        if not hand.worth or worth > hand.worth then
                            hand.id, hand.link, hand.worth = id, link, worth
                        end
                    end
                end
            end
        end
    end)
    return partners
end

-- Gain over what you wear in one slot (and `also`, the other hand a two-hander replaces):
-- percent of your power, score points and what the replaced gear was worth; nil while data loads.
local function Gain(item, slot, weights, power, also)
    local stats = SD.Stats(item)
    local worn = WornWorth(slot, weights)
    local other = also and WornWorth(also, weights) or 0
    if not (stats and worn and other) then return nil end
    local delta = SD.Worth(stats, weights, SD.DpsShare(slot)) + HitBeyondCap(weights, stats, item, slot, also)
        - worn - other
    return PERCENT * delta / power, delta, worn + other
end

-- The best gain this item gives in any slot it fits (and that `allowed(slot)` lets through, if given).
-- Returns gainPercent, points, slot, partnerLink, replacedWorth, alsoSlot; nil when it is no use or still loading.
function SD.BestGain(id, link, weights, power, allowed)
    if not (weights and power and power > 0) then return nil end
    local slots = Gear.SlotsFor(id)
    if not slots or Gear.Wearing(id, slots) then return nil end
    local twoHand = Gear.IsTwoHand(id)
    local main = Who.EquippedID(MAIN_HAND)
    local wornTwoHand = main ~= nil and Gear.IsTwoHand(main)
    local dualWield = Who.CanDualWield()
    local best, points, bestSlot, partner, replaced, bestAlso
    for _, slot in ipairs(slots) do
        if (not allowed or allowed(slot)) and (dualWield or not Gear.NeedsDualWield(id, slot)) then
            local also
            if slot == MAIN_HAND and twoHand then
                also = OFF_HAND
            elseif slot == OFF_HAND and wornTwoHand then
                also = MAIN_HAND
            end
            local gain, delta, wornWorth = Gain(link or id, slot, weights, power, also)
            local with
            if gain and wornTwoHand and not twoHand and Gear.OtherHand(slot) then
                local hand = BagPartners(weights)[Gear.OtherHand(slot)]
                if hand.worth and hand.worth > 0 and hand.id ~= id then
                    gain, delta, with = gain + PERCENT * hand.worth / power, delta + hand.worth, hand.link
                end
            end
            if gain and (not best or gain > best) then
                best, points, bestSlot, partner, replaced, bestAlso = gain, delta, slot, with, wornWorth, also
            end
        end
    end
    return best, points, bestSlot, partner, replaced, bestAlso
end
