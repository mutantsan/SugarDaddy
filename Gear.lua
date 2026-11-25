-- Gear.lua: the slots, what fits where, what you wear and what your class can use. "You" is whom you shop for
-- (SD.Who): yourself, or another of your characters.
local _, SD = ...

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local Gear = {}
SD.Gear = Gear

local WEAPON_CLASS = 2
local NO_ARMOR_TYPE = 0
local SHIELD_SUBCLASS = 6
local HEAVY_ARMOR_LEVEL = 40
local TWO_HAND = "INVTYPE_2HWEAPON"
local CLOAK = "INVTYPE_CLOAK"

Gear.MAIN_HAND, Gear.OFF_HAND = 16, 17
Gear.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
Gear.SLOT_NAME = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist",
    [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring", [12] = "Ring",
    [13] = "Trinket", [14] = "Trinket", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}

local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local DUAL_WIELD = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local PAIR = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

local ARMOR = { MAGE = 1, PRIEST = 1, WARLOCK = 1, ROGUE = 2, DRUID = 2, HUNTER = 3, SHAMAN = 3,
    WARRIOR = 4, PALADIN = 4 }
local ARMOR_BEFORE_HEAVY = { HUNTER = 2, SHAMAN = 2, WARRIOR = 3, PALADIN = 3 }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
local WEAPONS = {
    DRUID = { 4, 5, 10, 13, 15 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    MAGE = { 7, 10, 15, 19 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    PRIEST = { 4, 10, 15, 19 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    WARLOCK = { 7, 10, 15, 19 },
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
}
for class, list in pairs(WEAPONS) do
    local set = {}
    for _, sub in ipairs(list) do set[sub] = true end
    WEAPONS[class] = set
end

-- Slots as the list and the settings group them: both rings as one, both trinkets as one.
Gear.GROUPS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { "ring", "Rings" }, { "trinket", "Trinkets" },
    { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}
local GROUP_OF = { [11] = "ring", [12] = "ring", [13] = "trinket", [14] = "trinket" }
local GROUP_NAME = {}
for _, group in ipairs(Gear.GROUPS) do GROUP_NAME[group[1]] = group[2] end

function Gear.GroupOf(slot) return GROUP_OF[slot] or slot end
function Gear.GroupName(key) return GROUP_NAME[key] end

function Gear.SlotsFor(itemID)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return EQUIP_SLOTS[equipLoc]
end

function Gear.IsTwoHand(itemID)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return equipLoc == TWO_HAND
end

function Gear.NeedsDualWield(itemID, slot)
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return slot == Gear.OFF_HAND and DUAL_WIELD[equipLoc] == true
end

function Gear.OtherHand(slot)
    if slot == Gear.MAIN_HAND then return Gear.OFF_HAND end
    if slot == Gear.OFF_HAND then return Gear.MAIN_HAND end
end

function Gear.Wearing(itemID, slots)
    for i = 1, #slots do
        local slot = slots[i]
        if SD.Who.EquippedID(slot) == itemID then return true end
        local pair = PAIR[slot]
        if pair and SD.Who.EquippedID(pair) == itemID then return true end
    end
    return false
end

-- true, false, or nil while the item's data is still loading. With allowLower, armor below your class's best
-- type counts too; the second value then says the item is one of those.
function Gear.Usable(itemID, link, allowLower)
    local _, _, _, equipLoc, _, itemClass, subclass = GetItemInfoInstant(itemID)
    local _, _, _, _, required = GetItemInfo(link or itemID)
    if not (itemClass and required) then return nil end
    local myClass = SD.Who.Class()
    if equipLoc == CLOAK then subclass = NO_ARMOR_TYPE end
    if itemClass == WEAPON_CLASS then return WEAPONS[myClass] ~= nil and WEAPONS[myClass][subclass] == true end
    if subclass == NO_ARMOR_TYPE then return true end
    if subclass == SHIELD_SUBCLASS then return SHIELD[myClass] == true end
    if RELIC[subclass] then return RELIC[subclass] == myClass end
    local best = required < HEAVY_ARMOR_LEVEL and ARMOR_BEFORE_HEAVY[myClass] or ARMOR[myClass]
    if subclass == best then return true end
    if allowLower and best and subclass >= 1 and subclass < best then return true, true end
    return false
end

function Gear.RequiredLevel(item)
    local _, _, _, _, required = GetItemInfo(item)
    return required
end
