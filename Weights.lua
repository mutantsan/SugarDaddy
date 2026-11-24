-- Weights.lua: what each stat is worth to your spec. Defaults per spec (the same numbers NaowhForever's
-- Stat Weights ships, from MythicSim's Forever sims) with your own changes on top.
local _, SD = ...

local NONE = {}
local MELEE = { sta = 0.1, armor = 0.005 }
local CASTER = { spell = 1, sta = 0.05, armor = 0.005 }
local HEALER = { heal = 1, sta = 0.05, armor = 0.005 }
local TANK = { sta = 1, def = 1.5, armor = 0.06, dodge = 10, threat = 6 }

local function Spec(class, key, name, role, own)
    local weights = {}
    for stat, worth in pairs(role) do weights[stat] = worth end
    for stat, worth in pairs(own or NONE) do weights[stat] = worth end
    return { class = class, key = key, name = name, weights = weights }
end

SD.SPECS = {
    Spec("DRUID", "balance-druid", "Balance", CASTER, { int = 0.28, nature = 0.36, arcane = 0.64, mp5 = 0.14,
        shit = 11.2, scrit = 9.4, haste = 8.4 }),
    Spec("DRUID", "feral-dps-druid", "Feral DPS", MELEE, { str = 0.89, agi = 1, ap = 0.36, dps = 8.6, hit = 6.9,
        crit = 10.9, haste = 5.5, exp = 6.7, arp = 0.12 }),
    Spec("DRUID", "feral-tank-druid", "Feral Tank", TANK, { str = 1.08, agi = 0.7, ap = 0.49, dps = 10.2, hit = 18.4,
        crit = 12.5, haste = 4.8, exp = 36.9, arp = 0.2, def = 1.2, dodge = 12, armor = 0.12, threat = 5 }),
    Spec("DRUID", "restoration-druid", "Restoration", HEALER, { int = 0.45, spi = 0.5, mp5 = 1.8, scrit = 3,
        haste = 6 }),
    Spec("HUNTER", "beast-mastery-hunter", "Beast Mastery", MELEE, { str = 0.1, agi = 1, int = 0.59, spi = 0.05,
        ap = 0.09, rap = 0.29, dps = 3.1, mp5 = 0.26, hit = 14.1, crit = 12.7, haste = 4, exp = 7.3, arp = 0.13 }),
    Spec("HUNTER", "marksmanship-hunter", "Marksmanship", MELEE, { str = 0.11, agi = 1, int = 0.58, spi = 0.05,
        ap = 0.1, rap = 0.3, dps = 3.6, mp5 = 0.21, hit = 11.1, crit = 11.8, haste = 3.8, exp = 3.1, arp = 0.13 }),
    Spec("HUNTER", "survival-hunter", "Survival", MELEE, { str = 0.17, agi = 1, int = 0.67, ap = 0.16, rap = 0.2,
        dps = 3.2, mp5 = 0.39, hit = 10.5, crit = 10.8, haste = 4.1, exp = 6.2, arp = 0.13 }),
    Spec("MAGE", "arcane-mage", "Arcane", CASTER, { int = 0.99, spi = 0.27, fire = 0.44, arcane = 0.56, mp5 = 0.43,
        shit = 17.9, scrit = 11.2, haste = 6.6 }),
    Spec("MAGE", "fire-mage", "Fire", CASTER, { int = 0.47, spi = 0.11, fire = 0.88, arcane = 0.12, mp5 = 0.25,
        shit = 15.3, scrit = 10.6 }),
    Spec("MAGE", "frost-mage", "Frost", CASTER, { int = 0.18, spi = 0.01, frost = 0.85, arcane = 0.15, mp5 = 0.02,
        shit = 16.4, scrit = 9.1, haste = 10.9 }),
    Spec("PALADIN", "holy-paladin", "Holy", HEALER, { int = 0.6, spi = 0.1, mp5 = 2, scrit = 6, haste = 5 }),
    Spec("PALADIN", "protection-paladin", "Protection", TANK, { str = 0.45, agi = 0.51, int = 0.03, ap = 0.19,
        dps = 3, spell = 1.13, holy = 0.45, mp5 = 0.6, hit = 3, shit = 5.9, crit = 10.3, scrit = 1.1, haste = 4.6,
        exp = 25.5, arp = 0.04, block = 6 }),
    Spec("PALADIN", "retribution-paladin", "Retribution", MELEE, { str = 1, agi = 1.36, int = 1.6, ap = 0.41, dps = 8,
        spell = 2.11, holy = 0.25, mp5 = 0.3, hit = 12, shit = 2, crit = 24.2, haste = 14.8, exp = 28.6, arp = 0.1 }),
    Spec("PRIEST", "discipline-priest", "Discipline", HEALER, { spell = 0.15, int = 0.55, spi = 0.4, mp5 = 2,
        scrit = 4, haste = 5 }),
    Spec("PRIEST", "holy-priest", "Holy", HEALER, { int = 0.5, spi = 0.55, mp5 = 2, scrit = 4, haste = 5 }),
    Spec("PRIEST", "shadow-priest", "Shadow", CASTER, { int = 0.26, shadow = 1, shit = 11.9, scrit = 12.7,
        haste = 6.5 }),
    Spec("ROGUE", "assassination-rogue", "Assassination", MELEE, { str = 0.54, agi = 1, ap = 0.49, dps = 7.5,
        hit = 9.3, crit = 12.5, haste = 6.6, exp = 14.6, arp = 0.2 }),
    Spec("ROGUE", "combat-rogue", "Combat", MELEE, { str = 0.61, agi = 1, ap = 0.55, dps = 7.2, hit = 12.6,
        crit = 10.4, haste = 8.8, exp = 15.5, arp = 0.19 }),
    Spec("ROGUE", "subtlety-rogue", "Subtlety", MELEE, { str = 0.57, agi = 1, ap = 0.52, dps = 5.3, hit = 11.1,
        crit = 11.2, haste = 8, exp = 13.3, arp = 0.13 }),
    Spec("SHAMAN", "elemental-shaman", "Elemental", CASTER, { int = 0.19, spi = 0.1, fire = 0.25, frost = 0.1,
        nature = 0.88, shit = 13.2, scrit = 9.7, haste = 9.6 }),
    Spec("SHAMAN", "enhancement-shaman", "Enhancement", MELEE, { str = 1, agi = 0.65, int = 0.89, ap = 0.45, dps = 8,
        spell = 0.62, nature = 0.29, mp5 = 0.3, hit = 13, shit = 9.5, crit = 11.7, scrit = 5.2, haste = 9.8,
        exp = 18.5, arp = 0.16 }),
    Spec("SHAMAN", "restoration-shaman", "Restoration", HEALER, { int = 0.55, spi = 0.25, mp5 = 2.2, scrit = 4,
        haste = 5 }),
    Spec("WARLOCK", "affliction-warlock", "Affliction", CASTER, { sta = 0.1, int = 0.17, spi = 0.3, shadow = 1,
        shit = 5.2, scrit = 9.7, haste = 2.2 }),
    Spec("WARLOCK", "demonology-warlock", "Demonology", CASTER, { sta = 0.1, int = 0.45, spi = 0.3, shadow = 0.79,
        fire = 0.18, mp5 = 0.28, shit = 12.9, scrit = 10.8, haste = 8.7 }),
    Spec("WARLOCK", "destruction-warlock", "Destruction", CASTER, { sta = 0.1, int = 0.5, spi = 0.3, shadow = 0.77,
        fire = 0.21, mp5 = 0.3, shit = 11.4, scrit = 11.8, haste = 7.9 }),
    Spec("WARRIOR", "arms-warrior", "Arms", MELEE, { str = 1, agi = 0.84, ap = 0.45, dps = 8, hit = 11.2, crit = 15.1,
        haste = 8.3, exp = 10.4, arp = 0.2 }),
    Spec("WARRIOR", "fury-warrior", "Fury", MELEE, { str = 1, agi = 0.8, ap = 0.45, dps = 7.5, hit = 13.3,
        crit = 14.3, haste = 8.7, exp = 15.3, arp = 0.19 }),
    Spec("WARRIOR", "protection-warrior", "Protection", TANK, { str = 0.65, agi = 0.34, ap = 0.29, dps = 4, hit = 8,
        crit = 7, haste = 4.2, exp = 27.2, arp = 0.12, bv = 0.36, block = 4 }),
}

-- { key, name }. Percent stats are worth per 1%, everything else per point.
SD.STATS = {
    { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" },
    { "spi", "Spirit" }, { "ap", "Attack Power" }, { "rap", "Ranged Attack Power" }, { "dps", "Weapon DPS" },
    { "hit", "Hit %" }, { "crit", "Crit %" }, { "haste", "Haste %" }, { "exp", "Expertise %" },
    { "arp", "Armor Penetration" }, { "spell", "Spell Damage" }, { "heal", "Healing" },
    { "shit", "Spell Hit %" }, { "scrit", "Spell Crit %" }, { "mp5", "Mana per 5 sec" },
    { "fire", "Fire Damage" }, { "frost", "Frost Damage" }, { "shadow", "Shadow Damage" },
    { "nature", "Nature Damage" }, { "arcane", "Arcane Damage" }, { "holy", "Holy Damage" },
    { "def", "Defense" }, { "dodge", "Dodge %" }, { "block", "Block %" }, { "bv", "Block Value" },
    { "armor", "Armor" }, { "threat", "Threat %" },
}

-- GetItemStats keys -> our stats. A table means the stat counts for each of them.
SD.GAME_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spell",
    ITEM_MOD_SPELL_POWER_SHORT = { "spell", "heal" }, ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_HIT_RATING_SHORT = { "hit", "shit" }, ITEM_MOD_CRIT_RATING_SHORT = { "crit", "scrit" },
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "shit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "scrit",
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = "scrit", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_HASTE_RATING_SHORT = "haste", RESISTANCE0_NAME = "armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", ITEM_MOD_EXPERTISE_RATING_SHORT = "exp",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arp", ITEM_MOD_BLOCK_VALUE_SHORT = "bv",
}
-- Rating points per 1%.
SD.PER_PERCENT = {
    ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_HIT_SPELL_RATING_SHORT = 10, ITEM_MOD_CRIT_RATING_SHORT = 14,
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14, ITEM_MOD_SPELL_CRIT_RATING_SHORT = 14, ITEM_MOD_DODGE_RATING_SHORT = 12,
    ITEM_MOD_BLOCK_RATING_SHORT = 5, ITEM_MOD_HASTE_RATING_SHORT = 10, ITEM_MOD_EXPERTISE_RATING_SHORT = 10,
}

local TREES = {
    DRUID = { "balance-druid", "feral-dps-druid", "restoration-druid" },
    HUNTER = { "beast-mastery-hunter", "marksmanship-hunter", "survival-hunter" },
    MAGE = { "arcane-mage", "fire-mage", "frost-mage" },
    PALADIN = { "holy-paladin", "protection-paladin", "retribution-paladin" },
    PRIEST = { "discipline-priest", "holy-priest", "shadow-priest" },
    ROGUE = { "assassination-rogue", "combat-rogue", "subtlety-rogue" },
    SHAMAN = { "elemental-shaman", "enhancement-shaman", "restoration-shaman" },
    WARLOCK = { "affliction-warlock", "demonology-warlock", "destruction-warlock" },
    WARRIOR = { "arms-warrior", "fury-warrior", "protection-warrior" },
}

local STAT_NAME = {}
for _, stat in ipairs(SD.STATS) do STAT_NAME[stat[1]] = stat[2] end

local byKey = {}
for _, spec in ipairs(SD.SPECS) do byKey[spec.key] = spec end

local classSpecs
local talentSpec, talentRead = nil, false
local merged
local listeners = {}

function SD.StatName(stat) return STAT_NAME[stat] or stat end

function SD.ClassSpecs()
    if not classSpecs then
        classSpecs = {}
        local _, class = UnitClass("player")
        for _, spec in ipairs(SD.SPECS) do
            if spec.class == class then classSpecs[#classSpecs + 1] = spec end
        end
    end
    return classSpecs
end

-- Forever's talent frame: one config, its three trees as trait groups.
local function TraitTalents(trees)
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return nil end
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if not groups then return nil end
    local ids, spent = {}, {}
    for i, group in ipairs(groups) do ids[i] = group.groupID end
    for _, info in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local currency = info.currencyInfos and info.currencyInfos[1]
        spent[info.traitNodeGroupID] = currency and currency.spent or 0
    end
    local best, most = nil, 0
    for i, group in ipairs(groups) do
        local points = spent[group.groupID] or 0
        if points > most then best, most = trees[i], points end
    end
    return best
end

-- The classic talent frame: GetTalentTabInfo is (name, icon, spent) or (id, name, desc, icon, spent).
local function ClassicTalents(trees)
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local best, most = nil, 0
    for i = 1, GetNumTalentTabs() do
        local a, _, c, _, e = GetTalentTabInfo(i)
        local points = (type(a) == "number" and e) or c
        if type(points) == "number" and points > most then best, most = trees[i], points end
    end
    return best
end

function SD.TalentSpec()
    if talentRead then return talentSpec end
    local trees = TREES[select(2, UnitClass("player"))]
    if not trees then return nil end
    local ok, spec = pcall(TraitTalents, trees)
    if not (ok and spec) then
        ok, spec = pcall(ClassicTalents, trees)
        if not ok then spec = nil end
    end
    talentSpec, talentRead = spec, true
    return talentSpec
end

local function TalentsChanged()
    talentRead = false
    merged = nil
    for i = 1, #listeners do listeners[i]() end
end
SD.On("TRAIT_CONFIG_UPDATED", TalentsChanged)
SD.On("CHARACTER_POINTS_CHANGED", TalentsChanged)
SD.On("PLAYER_TALENT_UPDATE", TalentsChanged)

function SD.ActiveSpec()
    local picked = SD.char and SD.char.spec
    if picked and byKey[picked] then return picked end
    local talents = SD.TalentSpec()
    if talents then return talents end
    local mine = SD.ClassSpecs()
    return mine[1] and mine[1].key
end

function SD.SpecName(key)
    local spec = byKey[key or SD.ActiveSpec()]
    return spec and spec.name or "?"
end

function SD.SpecDefault(stat, key)
    local spec = byKey[key or SD.ActiveSpec()]
    return spec and spec.weights[stat] or 0
end

-- The spec's weights with your changes.
function SD.BaseWeights()
    local key = SD.ActiveSpec()
    local spec = byKey[key]
    local weights = {}
    if not spec then return weights end
    for stat, worth in pairs(spec.weights) do weights[stat] = worth end
    for stat, worth in pairs(SD.db.weights[key] or {}) do
        if STAT_NAME[stat] and type(worth) == "number" then weights[stat] = worth end
    end
    return weights
end

-- What every score uses (cached until the weights or spec change).
function SD.Weights()
    if not merged then merged = SD.BaseWeights() end
    return merged
end

local function Changed()
    merged = nil
    for i = 1, #listeners do listeners[i]() end
end

function SD.OnWeightsChanged(fn) listeners[#listeners + 1] = fn end

function SD.SetWeight(stat, worth)
    local key = SD.ActiveSpec()
    if not (key and STAT_NAME[stat]) then return end
    local own = SD.db.weights[key] or {}
    if worth == nil or math.abs(worth - SD.SpecDefault(stat, key)) < 1e-9 then worth = nil end
    own[stat] = worth
    SD.db.weights[key] = next(own) and own or nil
    Changed()
end

function SD.WeightChanged(stat)
    local own = SD.db.weights[SD.ActiveSpec()]
    return own ~= nil and own[stat] ~= nil
end

function SD.ResetWeights()
    local key = SD.ActiveSpec()
    SD.db.weights[key] = nil
    SD.db.shownStats[key] = nil
    Changed()
end

-- Stats listed in the Weights panel besides the spec's own: ones you added or edited. They stay until a reset.
function SD.StatShown(stat)
    local shown = SD.db.shownStats[SD.ActiveSpec()]
    return shown ~= nil and shown[stat] == true
end

function SD.ShowStat(stat)
    local key = SD.ActiveSpec()
    if not (key and STAT_NAME[stat]) or SD.StatShown(stat) then return end
    SD.db.shownStats[key] = SD.db.shownStats[key] or {}
    SD.db.shownStats[key][stat] = true
    Changed()
end

function SD.PickSpec(key)
    SD.char.spec = key or false
    Changed()
end

-- Cycles Automatic -> each class spec -> Automatic.
function SD.NextSpec()
    local mine = SD.ClassSpecs()
    local current = SD.char.spec
    if not current then return SD.PickSpec(mine[1] and mine[1].key) end
    for i, spec in ipairs(mine) do
        if spec.key == current then return SD.PickSpec(mine[i + 1] and mine[i + 1].key or false) end
    end
    SD.PickSpec(false)
end

