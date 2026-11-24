-- Core.lua: the namespace, saved settings, events, money helpers and slash commands.
local _, SD = ...
_G.SugarDaddy = SD

SD.TAG = "|cffff69b4Sugar Daddy|r"
SD.COPPER_PER_GOLD = 10000

local ACCOUNT_DEFAULTS = {
    weights = {},        -- [specKey] = { stat = worth } overrides on top of the spec defaults
    shownStats = {},     -- [specKey] = { stat = true } stats added to the Weights panel
    deepScan = true,     -- weigh items with suffixes ("of the Monkey") listing by listing when needed
    skipSlots = {},      -- [slot group as text] = true: slots left out of the results
    checkBags = false,   -- leave out items worse than one already in your bags
    minUpgrade = 0,      -- leave out upgrades smaller than this (gear score)
    perSlot = 3,         -- options shown per slot until its header is clicked
    minQuality = 0,      -- 0 any, 2 green and better, 3 blue and better
    lowerArmor = false,  -- also suggest armor types below your class's best (a hunter's leather)
    sort = "gain",       -- "gain" (biggest upgrade) or "value" (upgrade per gold)
}
local CHAR_DEFAULTS = {
    spec = false,        -- picked spec key, false = automatic from talents
    maxPrice = 0,        -- in copper, 0 = no limit
    levelsBelow = 10,    -- scan required levels from (your level - levelsBelow)
    levelsAbove = 0,     -- to (your level + levelsAbove); both follow you as you level
}

local function Fill(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = {}
                Fill(db[key], value)
            else
                db[key] = value
            end
        end
    end
    return db
end

function SD.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(SD.TAG .. ": " .. tostring(msg))
end

-- Events: SD.On(event, fn) adds a listener; several modules can listen to one event.
local events = CreateFrame("Frame")
local handlers = {}

function SD.On(event, fn)
    if not handlers[event] then
        if not pcall(events.RegisterEvent, events, event) then return end
        handlers[event] = {}
    end
    local list = handlers[event]
    list[#list + 1] = fn
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](event, ...) end
end)

-- Ready callbacks run once the saved variables are loaded.
local ready = {}
function SD.OnReady(fn) ready[#ready + 1] = fn end

SD.On("ADDON_LOADED", function(_, name)
    if name ~= "SugarDaddy" then return end
    SugarDaddyDB = Fill(type(SugarDaddyDB) == "table" and SugarDaddyDB or {}, ACCOUNT_DEFAULTS)
    SugarDaddyCharDB = Fill(type(SugarDaddyCharDB) == "table" and SugarDaddyCharDB or {}, CHAR_DEFAULTS)
    for _, old in ipairs({ "autoOpen", "pos", "onePerSlot", "startOnTab", "groupBySlot" }) do SugarDaddyDB[old] = nil end   -- retired settings
    SugarDaddyCharDB.pvp, SugarDaddyCharDB.pvpStam = nil, nil
    SD.db, SD.char = SugarDaddyDB, SugarDaddyCharDB
    for i = 1, #ready do ready[i]() end
end)

-- Money
local CoinString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString

function SD.Money(copper)
    if not copper then return "?" end
    return CoinString(copper)
end

-- "12", "12g", "12.5", "12g 50s", "1g50s20c" -> copper
function SD.ParseMoney(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" or text == "0" then return 0 end
    local plain = tonumber(text)
    if plain then return math.floor(plain * SD.COPPER_PER_GOLD + 0.5) end
    local g = tonumber(text:match("([%d%.]+)g")) or 0
    local s = tonumber(text:match("([%d%.]+)s")) or 0
    local c = tonumber(text:match("([%d%.]+)c")) or 0
    local total = math.floor(g * SD.COPPER_PER_GOLD + s * 100 + c + 0.5)
    if total == 0 and not text:find("[gsc]") then return nil end
    return total
end

-- Slash commands
local HELP = {
    "/sugar - switch the auction house to the Sugar Daddy tab",
    "/sugar scan - scan the auction house (it must be open)",
    "/sugar price <amount> - max price, e.g. 15g, 2g50s or 50s; 0 = no limit",
    "/sugar weight <stat> <weight> - set a stat weight, e.g. /sugar weight agi 1.2",
    "/sugar stats - list the stat keys",
    "/sugar reset - reset this spec's weights to the defaults",
}

local function Slash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then return SD.UI.Toggle() end
    if cmd == "scan" then return SD.Scanner.Start() end
    if cmd == "price" then
        local copper = SD.ParseMoney(rest)
        if not copper then return SD.Print("Couldn't read that price.") end
        SD.SetMaxPrice(copper)
        return SD.Print(copper > 0 and ("Max price: " .. SD.Money(copper)) or "No max price.")
    end
    if cmd == "weight" then
        local stat, value = rest:match("^(%S+)%s+(%S+)$")
        value = tonumber(value)
        if not (stat and value and SD.IsStat(stat:lower())) then
            return SD.Print("Usage: /sugar weight <stat> <weight>. /sugar stats lists the stats.")
        end
        SD.SetWeight(stat:lower(), value)
        return SD.Print(SD.StatName(stat:lower()) .. ": " .. value)
    end
    if cmd == "stats" then
        local list = {}
        for _, stat in ipairs(SD.STATS) do list[#list + 1] = stat[1] .. " (" .. stat[2] .. ")" end
        return SD.Print(table.concat(list, ", "))
    end
    if cmd == "reset" then
        SD.ResetWeights()
        return SD.Print("Weights reset for " .. SD.SpecName() .. ".")
    end
    for _, line in ipairs(HELP) do SD.Print(line) end
end

SLASH_SUGARDADDY1, SLASH_SUGARDADDY2 = "/sugar", "/sugardaddy"
SlashCmdList.SUGARDADDY = Slash
