-- PawnScale.lua: use one of Pawn's scales as Sugar Daddy's weights. Pawn is optional: without it nothing here
-- does anything. Only Pawn's numbers are borrowed; scoring (hit cap, weapon dps share, bag partners) stays ours.
--
-- Units match without conversion: Pawn reads Forever's "+1% hit" as HitRating = 1, so its hit, crit, haste,
-- expertise, dodge and block weights are per 1%, like ours; everything else is per point on both sides.
local _, SD = ...

local PawnScale = {}
SD.PawnScale = PawnScale

-- Pawn stat -> ours. Weapon dps and spell power are handled below; Pawn stats we don't weigh (parry,
-- resistances, health, spell penetration) are left out.
local STAT_OF = {
    Strength = "str", Agility = "agi", Stamina = "sta", Intellect = "int", Spirit = "spi",
    Ap = "ap", Rap = "rap", HitRating = "hit", CritRating = "crit", HasteRating = "haste",
    ExpertiseRating = "exp", ArmorPenetration = "arp", SpellDamage = "spell", Healing = "heal",
    SpellHitRating = "shit", SpellCritRating = "scrit", Mp5 = "mp5",
    FireSpellDamage = "fire", FrostSpellDamage = "frost", ShadowSpellDamage = "shadow",
    NatureSpellDamage = "nature", ArcaneSpellDamage = "arcane", HolySpellDamage = "holy",
    DefenseRating = "def", DodgeRating = "dodge", BlockRating = "block", BlockValue = "bv", Armor = "armor",
}
local IGNORED = -1000   -- Pawn marks "can't use" stats with a huge negative value

local function Ready()
    return type(PawnIsReady) == "function" and PawnIsReady() and type(PawnCommon) == "table"
        and type(PawnCommon.Scales) == "table" and type(PawnGetAllScalesEx) == "function"
end

function PawnScale.Available() return Ready() and true or false end

local function Scale(name)
    return name and Ready() and PawnCommon.Scales[name] or nil
end

-- The picked scale's internal name, while Pawn still has it.
function PawnScale.Picked()
    local name = SD.char and SD.char.pawnScale
    return Scale(name) and name or nil
end

function PawnScale.Active() return PawnScale.Picked() ~= nil end

function PawnScale.Name(name)
    local scale = Scale(name or PawnScale.Picked())
    if not scale then return nil end
    return (PawnGetScaleLocalizedName and PawnGetScaleLocalizedName(name or PawnScale.Picked())) or scale.LocalizedName
        or name
end

-- Pawn's own scales are named "Hunter: Beast Mastery"; under a Pawn heading the spec alone reads better.
-- Scales you made keep their names.
function PawnScale.ShortName(name)
    name = name or PawnScale.Picked()
    local scale = Scale(name)
    local label = PawnScale.Name(name)
    if scale and scale.Provider and label then label = label:gsub("^[^:]+:%s*", "") end
    return label
end

-- The scales Pawn shows for this character (its "active scales"), in Pawn's own order.
function PawnScale.List()
    local out = {}
    if not Ready() then return out end
    local ok, all = pcall(PawnGetAllScalesEx)
    if not ok or type(all) ~= "table" then return out end
    for _, info in ipairs(all) do
        if info.IsVisible then out[#out + 1] = { name = info.Name, label = PawnScale.ShortName(info.Name) } end
    end
    return out
end

local function Number(values, key)
    local v = values[key]
    if type(v) ~= "number" or v <= IGNORED then return 0 end
    return v
end

-- Pawn's scale as our weights table, or nil when no scale is picked.
function PawnScale.Weights()
    local scale = Scale(PawnScale.Picked())
    local values = scale and scale.Values
    if type(values) ~= "table" then return nil end
    local weights = {}
    for pawnStat, mine in pairs(STAT_OF) do
        local v = Number(values, pawnStat)
        if v ~= 0 then weights[mine] = v end
    end
    -- Pawn splits weapon dps into any weapon (Dps) plus melee or ranged; ours is one number per spec.
    local hunter = select(2, UnitClass("player")) == "HUNTER"
    local dps = Number(values, "Dps") + Number(values, hunter and "RangedDps" or "MeleeDps")
    if dps ~= 0 then weights.dps = dps end
    -- Retail-style combined spell power, when a custom scale uses it instead of spell damage and healing.
    local power = Number(values, "SpellPower")
    if power ~= 0 then
        weights.spell = weights.spell or power
        weights.heal = weights.heal or power
    end
    return weights
end

function PawnScale.Pick(name)
    SD.char.pawnScale = name or false
    SD.WeightsChanged()
end

-- Editing, renaming, importing or deleting a scale in Pawn changes our weights too.
for _, fn in ipairs({ "PawnSetStatValue", "PawnSetScaleVisible", "PawnDeleteScale", "PawnRenameScale",
    "PawnImportScale", "PawnResetScales" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, function() SD.WeightsChanged() end) end
end

-- Pawn finishes setting up its scales after login; read them again then.
SD.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(1, function() if SD.char and SD.char.pawnScale then SD.WeightsChanged() end end)
end)
