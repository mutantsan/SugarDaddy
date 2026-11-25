-- Profile.lua: whom you shop for. Every character that logs in leaves a snapshot here (SugarDaddyDB.chars): class,
-- level, talents, base stats, hit, what it wears and the gear in its bags. Shopping for yourself reads the game
-- live, as before; shopping for another character (say from a bank character, to mail the loot) reads its snapshot.
local _, SD = ...

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local IsCached = C_Item and C_Item.IsItemDataCachedByID
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

local Who = {}
SD.Who = Who

local SNAPSHOT_DELAY = 1       -- seconds; bursts of bag and gear events make one snapshot
local LOADED_DELAY = 0.3       -- seconds; item data arriving for the target is batched into one rescore
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local HIT, SPELL_HIT = "hit", "shit"
local PICK_DEFAULTS = { spec = false, pawnScale = false, levelsBelow = 10, levelsAbove = 0 }

local meKey
local listeners = {}
local announced = false        -- the "saved" chat line shows once per session

local function Secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function Number(value)
    if value == nil or Secret(value) or type(value) ~= "number" then return nil end
    return value
end

local function StatsSecret()
    return C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret()
end

local function Ready() return SD.db ~= nil and meKey ~= nil end

local function Record(key)
    return Ready() and SD.db.chars[key] or nil
end

-- Live reads of the logged-in character ---------------------------------------------------------------------------

local function Rating(cr)
    return (GetCombatRatingBonus and cr and GetCombatRatingBonus(cr)) or 0
end

-- Your hit chance now (gear, talents, buffs): ranged for hunters, melee for everyone else, and spell hit.
local function LiveHit(kind)
    if kind == SPELL_HIT then
        return Rating(CR_HIT_SPELL) + ((GetSpellHitModifier and GetSpellHitModifier()) or 0)
    end
    if select(2, UnitClass("player")) == "HUNTER" then
        return Rating(CR_HIT_RANGED) + ((GetRangedHitModifier and GetRangedHitModifier()) or 0)
    end
    return Rating(CR_HIT_MELEE) + ((GetHitModifier and GetHitModifier()) or 0)
end

local function LiveBags(fn)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for bagSlot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, bagSlot)
            if id then fn(id, C_Container.GetContainerItemLink(bag, bagSlot)) end
        end
    end
end

-- Snapshot -------------------------------------------------------------------------------------------------------

local function Snapshot()
    local rec = Record(meKey)
    if not rec then return end
    local _, class, classID = UnitClass("player")
    rec.class, rec.classID = class, classID
    rec.faction = UnitFactionGroup("player")
    rec.level = UnitLevel("player")
    rec.seen = time()
    local ok, spec = pcall(SD.TalentSpec)
    if ok and spec then rec.talentSpec = spec end
    local dualWield = CanDualWield and CanDualWield()
    if not Secret(dualWield) then rec.dualWield = dualWield and true or false end

    -- While the game isn't giving out the inventory (loading in, logging out) every slot reads empty. Nobody shops
    -- naked, so an empty read never replaces gear already saved.
    local equipped, worn = {}, 0
    for _, slot in ipairs(EQUIP_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and not Secret(link) then
            equipped[slot] = link
            worn = worn + 1
        end
    end
    if worn > 0 or not (rec.equipped and next(rec.equipped)) then
        rec.equipped = equipped
        -- Only gear: what can be worn is all scoring looks at.
        rec.bags = {}
        LiveBags(function(id, link)
            if link and not Secret(link) and SD.Gear.SlotsFor(id) then rec.bags[#rec.bags + 1] = link end
        end)
        if worn > 0 and not announced then
            announced = true
            SD.Print(("Saved %s's gear and bags"):format(rec.name or "your character"))
        end
    end

    -- Stats and hit can be secret (in combat on Forever), or all 0 while unavailable; keep the last good ones then.
    if not StatsSecret() then
        local stats, total = {}, 0
        for i = 1, 5 do
            stats[i] = Number(select(2, UnitStat("player", i)))
            if not stats[i] then stats = nil break end
            total = total + stats[i]
        end
        if stats and total > 0 then rec.stats = stats end
        local melee, spell = Number(LiveHit(HIT)), Number(LiveHit(SPELL_HIT))
        if melee and spell then rec.hit = { [HIT] = melee, [SPELL_HIT] = spell } end
    end
end

local snapshotSoon = false
local function SnapshotSoon()
    if snapshotSoon then return end
    snapshotSoon = true
    C_Timer.After(SNAPSHOT_DELAY, function()
        snapshotSoon = false
        Snapshot()
    end)
end

for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "UNIT_STATS",
    "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    SD.On(event, function(_, unit)
        if event == "UNIT_STATS" and unit ~= "player" then return end
        SnapshotSoon()
    end)
end
-- Not at logout: by then the game reports an empty inventory and zero stats.
SD.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, Snapshot) end)

-- Item data for someone else's gear may not be cached on this character: ask for it, rescore when it's in.
local waitingFor = {}
local loadedSoon = false

local function Warm()
    wipe(waitingFor)
    local rec = Record(Who.Key())
    if not (rec and IsCached and RequestLoad) or Who.IsMe() then return end
    local function Want(link)
        local id = link and GetItemInfoInstant(link)
        if id and not IsCached(id) then
            waitingFor[id] = true
            RequestLoad(id)
        end
    end
    for _, link in pairs(rec.equipped or {}) do Want(link) end
    for _, link in ipairs(rec.bags or {}) do Want(link) end
end

SD.On("ITEM_DATA_LOAD_RESULT", function(_, itemID)
    if not waitingFor[itemID] then return end
    waitingFor[itemID] = nil
    if loadedSoon then return end
    loadedSoon = true
    C_Timer.After(LOADED_DELAY, function()
        loadedSoon = false
        SD.Forget()
        SD.WeightsChanged()
    end)
end)

-- Setup ----------------------------------------------------------------------------------------------------------

SD.OnReady(function()
    -- Forever names are two words: UnitName gives (first name, surname), and only the pair is unique. Elsewhere
    -- the second value is nil and the realm tells characters apart.
    local first, surname = UnitName("player")
    local realm = GetRealmName()
    local name = (surname and surname ~= "") and (first .. " " .. surname) or first
    meKey = name .. "-" .. realm
    local chars = SD.db.chars
    local oldKey = first .. "-" .. realm   -- 0.4.0 keyed by the first name alone
    if oldKey ~= meKey and chars[oldKey] and chars[oldKey].pawnName == name then
        chars[meKey] = chars[meKey] or chars[oldKey]
        chars[oldKey] = nil
    end
    for _, rec in pairs(chars) do   -- other characters' old keys: their records move when they log in
        if rec.name and rec.pawnName and rec.name ~= rec.pawnName and not rec.pawnName:find("-", 1, true) then
            rec.name = rec.pawnName
        end
    end
    chars[meKey] = chars[meKey] or {}
    local rec = chars[meKey]
    rec.name, rec.realm = name, realm
    -- Pawn keys its per-character scale settings by the full name on Forever, "Name-Realm" elsewhere.
    rec.pawnName = (name ~= first) and name or (first .. "-" .. realm)
    local _, class, classID = UnitClass("player")
    rec.class, rec.classID, rec.level = class, classID, UnitLevel("player")
    rec.faction = UnitFactionGroup("player")
    -- Spec, Pawn scale and level range used to be saved per character; they now belong to whom you shop for.
    if not rec.pick then
        rec.pick = {}
        for field, default in pairs(PICK_DEFAULTS) do
            local old = SD.char[field]
            if old == nil then old = default end
            rec.pick[field] = old
        end
    end
    for field in pairs(PICK_DEFAULTS) do SD.char[field] = nil end
    Warm()
end)

-- Whom you shop for ----------------------------------------------------------------------------------------------

function Who.MeKey() return meKey end

-- The character you shop for: the one you picked while it is still remembered, else yourself.
function Who.Key()
    local target = SD.char and SD.char.target
    if target and target ~= meKey and Record(target) then return target end
    return meKey
end

function Who.IsMe() return Who.Key() == meKey end
function Who.Record() return Record(Who.Key()) end

function Who.Name()
    local rec = Who.Record()
    if rec and rec.name then return rec.name end
    local first, surname = UnitName("player")
    return (surname and surname ~= "") and (first .. " " .. surname) or first
end

-- Spec, Pawn scale and level range picked for this character.
function Who.Pick()
    local rec = Who.Record()
    if not rec then return nil end
    rec.pick = rec.pick or {}
    for field, default in pairs(PICK_DEFAULTS) do
        if rec.pick[field] == nil then rec.pick[field] = default end
    end
    return rec.pick
end

function Who.Class()
    if Who.IsMe() then return select(2, UnitClass("player")) end
    return Who.Record().class
end

function Who.ClassID()
    if Who.IsMe() then return select(3, UnitClass("player")) end
    return Who.Record().classID
end

function Who.Level()
    if Who.IsMe() then return UnitLevel("player") end
    return Who.Record().level or 1
end

function Who.Equipped(slot)
    if Who.IsMe() then return GetInventoryItemLink("player", slot) end
    local equipped = Who.Record().equipped
    return equipped and equipped[slot]
end

function Who.EquippedID(slot)
    if Who.IsMe() then return GetInventoryItemID("player", slot) end
    local link = Who.Equipped(slot)
    return link and GetItemInfoInstant(link)
end

-- fn(itemID, link) for each item in the bags (for someone else: the gear among them).
function Who.ForEachBagItem(fn)
    if Who.IsMe() then return LiveBags(fn) end
    for _, link in ipairs(Who.Record().bags or {}) do
        local id = GetItemInfoInstant(link)
        if id then fn(id, link) end
    end
end

-- Base stat i (1 strength .. 5 spirit), with buffs, as UnitStat gives it.
function Who.BaseStat(i)
    if Who.IsMe() then return select(2, UnitStat("player", i)) end
    local stats = Who.Record().stats
    return stats and stats[i] or 0
end

function Who.HitNow(kind)
    if Who.IsMe() then return LiveHit(kind) end
    local hit = Who.Record().hit
    return hit and hit[kind] or 0
end

function Who.CanDualWield()
    if Who.IsMe() then return CanDualWield and CanDualWield() end
    return Who.Record().dualWield == true
end

-- The spec the character's talents point to.
function Who.TalentSpec()
    if Who.IsMe() then return SD.TalentSpec() end
    return Who.Record().talentSpec
end

-- Who you can shop for: characters on this realm and faction (mail reaches them), yourself first, then by level.
function Who.List()
    local out = {}
    if not Ready() then return out end
    local me = Record(meKey)
    for key, rec in pairs(SD.db.chars) do
        if rec.name and rec.class and rec.realm == me.realm and rec.faction == me.faction then
            out[#out + 1] = { key = key, name = rec.name, class = rec.class, level = rec.level or 1, seen = rec.seen,
                me = key == meKey }
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return out
end

-- False while the character you shop for has no gear saved yet (it hasn't logged in with Sugar Daddy since 0.4.0).
function Who.HasGear()
    if Who.IsMe() then return true end
    local rec = Who.Record()
    return rec ~= nil and rec.equipped ~= nil and next(rec.equipped) ~= nil
end

function Who.OnChanged(fn) listeners[#listeners + 1] = fn end

local function Changed()
    SD.Forget()
    Warm()
    for i = 1, #listeners do listeners[i]() end
    SD.WeightsChanged()
end

function Who.Set(key)
    if not Ready() or key == Who.Key() then return end
    SD.char.target = (key ~= meKey and Record(key)) and key or false
    Changed()
end

-- Drop a character's snapshot (not your own).
function Who.Forget(key)
    if not Ready() or key == meKey then return end
    local wasTarget = key == Who.Key()
    SD.db.chars[key] = nil
    if wasTarget then
        SD.char.target = false
        Changed()
    end
end
