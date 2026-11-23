-- WockyLinks: other addons (6.0.0). Every part only works when that addon is
-- loaded and does nothing otherwise; all calls are guarded.
--  1. Questie: quest steps without a position take the quest giver or the
--     turn-in NPC position from Questie's database.
--  2. TomTom: the guide target goes to the WockyPro arrow, to TomTom, or both.
--  3. LibDataBroker: a WockyPro button for Titan Panel, ChocolateBar and the
--     like (level, lines done, XP); click toggles the guide.
local W = WockyAPI
if not W then return end

local L, Cfg, SetCfg = W.L, W.Cfg, W.SetCfg
local D = W.DEFAULTS
local ARROW_MODES = { "wocky", "tomtom", "both" }
local ARROW_KEYS = { wocky = "LN_ARROW_WOCKY", tomtom = "LN_ARROW_TOMTOM", both = "LN_ARROW_BOTH" }

for k, v in pairs({ useQuestie = true, arrowMode = "wocky", useLDB = true }) do
    if D[k] == nil then D[k] = v end
end

local function Loaded(name)
    local ok, r = pcall(function()
        if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
        if IsAddOnLoaded then return IsAddOnLoaded(name) end
    end)
    return ok and r and true or false
end

---------------------------------------------------------------------------
-- Questie
---------------------------------------------------------------------------
local mapNames -- uiMapID -> zone name used by the guide
local function MapName(uiMapID)
    if not mapNames then
        mapNames = {}
        for name, id in pairs(W.MAP_IDS or {}) do
            -- prefer the long names ("Hillsbrad Foothills" over "Hillsbrad")
            if not mapNames[id] or #name > #mapNames[id] then mapNames[id] = name end
        end
    end
    return mapNames[uiMapID]
end

local questieDB, zoneDB
local function QuestieModules()
    if questieDB ~= nil then return questieDB, zoneDB end
    questieDB, zoneDB = false, false
    pcall(function()
        local loader = rawget(_G, "QuestieLoader")
        if loader and loader.ImportModule then
            questieDB = loader:ImportModule("QuestieDB") or false
            zoneDB = loader:ImportModule("ZoneDB") or false
        end
    end)
    return questieDB, zoneDB
end

local spotCache = {}
-- kind: accept (the giver) or turnin / complete (the turn-in NPC)
local function QuestieSpot(questID, kind)
    if not Cfg("useQuestie") or type(questID) ~= "number" or not Loaded("Questie") then return nil end
    local key = questID .. ":" .. tostring(kind)
    if spotCache[key] ~= nil then return spotCache[key] or nil end
    spotCache[key] = false
    local qdb, zdb = QuestieModules()
    if not qdb or not qdb.QueryQuestSingle or not qdb.QueryNPCSingle then return nil end
    local spot
    pcall(function()
        local field = (kind == "accept") and "startedBy" or "finishedBy"
        local by = qdb.QueryQuestSingle(questID, field)
        local npcs = type(by) == "table" and by[1]
        local npcID = type(npcs) == "table" and npcs[1]
        if type(npcID) ~= "number" then return end
        local spawns = qdb.QueryNPCSingle(npcID, "spawns")
        local name = qdb.QueryNPCSingle(npcID, "name")
        if type(spawns) ~= "table" then return end
        for areaID, list in pairs(spawns) do
            local first = type(list) == "table" and list[1]
            if type(first) == "table" and type(first[1]) == "number" and type(first[2]) == "number" then
                local uiMap = zdb and zdb.GetUiMapIdByAreaId and zdb:GetUiMapIdByAreaId(areaID)
                local zone = uiMap and MapName(uiMap)
                if zone then
                    spot = { zone = zone, x = math.floor(first[1] * 10 + 0.5) / 10, y = math.floor(first[2] * 10 + 0.5) / 10,
                        npc = type(name) == "string" and name or nil }
                    return
                end
            end
        end
    end)
    spotCache[key] = spot or false
    return spot
end
W.QuestieSpot = QuestieSpot

---------------------------------------------------------------------------
-- TomTom
---------------------------------------------------------------------------
local tomUID
local function TomTomOK()
    local t = rawget(_G, "TomTom")
    return t and t.AddWaypoint and t or nil
end

local function ClearTomTom()
    local t = TomTomOK()
    if t and tomUID and t.RemoveWaypoint then pcall(t.RemoveWaypoint, t, tomUID) end
    tomUID = nil
end

local lastTarget
local function SendTomTom(zone, x, y, name, manual)
    -- map clicks already go to TomTom (setting "Use TomTom"); here: guide targets
    if manual then return end
    local mode = Cfg("arrowMode")
    if mode ~= "tomtom" and mode ~= "both" then return end
    local t = TomTomOK()
    local mapID = W.MAP_IDS and W.MAP_IDS[zone]
    if not t or not mapID or not x or not y then return end
    local key = zone .. x .. y
    if key == lastTarget and tomUID then return end
    lastTarget = key
    ClearTomTom()
    pcall(function()
        tomUID = t:AddWaypoint(mapID, x / 100, y / 100, { title = "WockyPro: " .. tostring(name or zone), persistent = false, minimap = true, world = true })
    end)
end

-- wraps the arrow: guide and map targets also go to TomTom in that mode
local baseSetArrow = W.SetArrowTarget
if baseSetArrow then
    W.SetArrowTarget = function(zone, x, y, name, manual)
        baseSetArrow(zone, x, y, name, manual)
        pcall(SendTomTom, zone, x, y, name, manual)
    end
end

local function ApplyArrowMode()
    local mode = Cfg("arrowMode")
    -- only TomTom: the WockyPro arrow stays hidden (when TomTom is there)
    if mode == "tomtom" and TomTomOK() then
        if Cfg("showArrow") then SetCfg("showArrow", false); W.arrowOffByMode = true end
    elseif W.arrowOffByMode then
        W.arrowOffByMode = nil
        SetCfg("showArrow", true)
    end
    if mode == "wocky" then ClearTomTom() end
end

---------------------------------------------------------------------------
-- LibDataBroker
---------------------------------------------------------------------------
local ldbObj
local function BrokerText()
    local lv = 1
    pcall(function() lv = UnitLevel("player") or 1 end)
    if type(lv) ~= "number" then lv = 1 end
    local lines = (W.GuideLines and W.GuideLines(lv)) or {}
    local t = W.DoneTable and W.DoneTable() or {}
    local done = 0
    for i = 1, #lines do if t["Q" .. lv .. ":" .. i] then done = done + 1 end end
    return "Wocky " .. lv .. " (" .. done .. "/" .. #lines .. ")"
end

local function SetupLDB()
    if ldbObj or not Cfg("useLDB") then return end
    pcall(function()
        local stub = rawget(_G, "LibStub")
        local ldb = stub and stub("LibDataBroker-1.1", true)
        if not ldb then return end
        ldbObj = ldb:NewDataObject("WockyPro", {
            type = "launcher",
            text = BrokerText(),
            icon = "Interface\\AddOns\\WockyPro\\WockyIcon",
            OnClick = function(self, button)
                if button == "RightButton" then
                    if W.ToggleSettings then W.ToggleSettings() end
                elseif SlashCmdList["WOCKY"] then
                    SlashCmdList["WOCKY"]("toggle")
                end
            end,
            OnTooltipShow = function(tip)
                if not tip or not tip.AddLine then return end
                tip:AddLine("WockyPro " .. tostring(W.VERSION))
                tip:AddLine(BrokerText(), 1, 1, 1)
                if W.SessionText then
                    local ok, s = pcall(W.SessionText)
                    if ok and s then tip:AddLine(s, 0.8, 0.8, 0.8, true) end
                end
                tip:AddLine(L("LN_LDB_TIP"), 0.45, 0.8, 1)
            end
        })
    end)
end

local function UpdateLDB()
    if ldbObj then pcall(function() ldbObj.text = BrokerText() end) end
end

W.LinksInfo = function()
    return "Questie " .. (Loaded("Questie") and "yes" or "no") .. ", TomTom " .. (TomTomOK() and "yes" or "no")
        .. " (mode " .. tostring(Cfg("arrowMode")) .. "), LDB " .. (ldbObj and "yes" or "no")
end

---------------------------------------------------------------------------
-- Settings and events
---------------------------------------------------------------------------
local page = W.pageUI
if page then
    if W.AddCycle then
        W.AddCycle(page, "LN_ARROW", ARROW_MODES,
            function() return Cfg("arrowMode") or "wocky" end,
            function(v) SetCfg("arrowMode", v); pcall(ApplyArrowMode) end,
            function(v) return L(ARROW_KEYS[v] or "LN_ARROW_WOCKY") end)
    end
    W.AddToggle(page, "useQuestie", "LN_OPT_QUESTIE")
    W.AddToggle(page, "useLDB", "LN_OPT_LDB")
end

local baseApply = W.OnApply
W.OnApply = function(...)
    if baseApply then pcall(baseApply, ...) end
    pcall(SetupLDB)
    pcall(UpdateLDB)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "ADDON_LOADED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
ev:SetScript("OnEvent", function(self, event, a1)
    if event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function() pcall(SetupLDB); pcall(ApplyArrowMode); pcall(UpdateLDB) end)
        end
    elseif event == "ADDON_LOADED" then
        if a1 == "Questie" then questieDB = nil; spotCache = {} end
    else
        pcall(UpdateLDB)
    end
end)

local acc = 0
ev:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 5 then return end
    acc = 0
    pcall(UpdateLDB)
end)
