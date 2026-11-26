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
    minUpgrade = 0,      -- leave out upgrades smaller than this (points)
    perSlot = 3,         -- options shown per slot until its header is clicked
    minQuality = 0,      -- 0 any, 2 green and better, 3 blue and better
    lowerArmor = false,  -- also suggest armor types below your class's best (a hunter's leather)
    sort = "gain",       -- "gain" (biggest upgrade) or "value" (upgrade per gold)
    suffixLinks = {},    -- ["itemID:suffix id:item level"] = the item link its listings carry, learned from searches
    chars = {},          -- ["Name-Realm"] = snapshot of each character and what you picked for it (see Profile.lua)
}
-- Spec, Pawn scale and level range belong to whom you shop for: SugarDaddyDB.chars[key].pick.
local CHAR_DEFAULTS = {
    maxPrice = 0,        -- in copper, 0 = no limit
    target = false,      -- "Name-Realm" of the character you shop for, false = yourself
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
    for _, old in ipairs({ "autoOpen", "pos", "onePerSlot", "startOnTab", "groupBySlot", "suffixBonus" }) do SugarDaddyDB[old] = nil end   -- retired settings
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

-- Slash command: /sugar switches the auction house to the Sugar Daddy tab.
local function Slash()
    SD.UI.Toggle()
end

SLASH_SUGARDADDY1, SLASH_SUGARDADDY2 = "/sugar", "/sugardaddy"
SlashCmdList.SUGARDADDY = Slash
