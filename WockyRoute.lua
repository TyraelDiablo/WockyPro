-- WockyRoute: route planning (4.2.0)
-- /wocky plan opens a small window with:
--  1. Hearthstone: where you are bound, where the route wants it for your level and the next change
--  2. Next levels: the coming hubs and zones of your route, and whether you have a flight path there
--  3. Open steps in this zone: guide lines of your route in the zone you stand in that are not ticked
-- Flight paths are learned from the game: every time you open a flight map or find a new flight path,
-- WockyPro notes the zone (map ID) and the flight point names. Nothing is guessed.
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local MAX_LEVEL = W.MAX_LEVEL or 60
local AHEAD = 12      -- levels shown in "Next levels"
local MAX_HUBS = 6
local MAX_OPEN = 10

if W.DEFAULTS.planReminder == nil then W.DEFAULTS.planReminder = true end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function Safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function Low(s) return string.lower(tostring(s or "")) end

---------------------------------------------------------------------------
-- Route data
---------------------------------------------------------------------------
local function Route()
    local key = W.RouteKey and Safe(W.RouteKey)
    return key and WockyGuideDB and WockyGuideDB[key]
end

local function PlayerLevel()
    return (UnitLevel and Safe(UnitLevel, "player")) or 1
end

local function QuestLines(data)
    local out = {}
    for line in string.gmatch((data and data.quest) or "", "[^\n]+") do out[#out + 1] = line end
    return out
end

local function Strip(line)
    return (string.gsub(line or "", "^%[ %] ", ""))
end

-- the named place a guide line or level talks about (a key of WockyPlaces), or nil
local function PlaceIn(text, zone)
    if type(WockyPlaces) ~= "table" then return nil end
    local low, best = Low(text), nil
    for name, p in pairs(WockyPlaces) do
        if (not zone or p[1] == zone) and string.find(low, Low(name), 1, true) then
            if not best or string.len(name) > string.len(best) then best = name end
        end
    end
    return best
end

local function Hub(data)
    if not data then return nil end
    if type(WockyPlaces) == "table" and data.npc and WockyPlaces[data.npc] then return data.npc end
    return PlaceIn(data.quest, data.zone) or data.npc or data.zone
end

local function Translate(text)
    if W.TranslateLine then
        local ok, t = pcall(W.TranslateLine, text)
        if ok and type(t) == "string" then return t end
    end
    return text
end

---------------------------------------------------------------------------
-- Where am I (zone name as the guide data writes it)
---------------------------------------------------------------------------
local function CurrentZone()
    local spot = W.PlayerSpot and Safe(W.PlayerSpot)
    if not spot then
        return (GetRealZoneText and Safe(GetRealZoneText)) or nil, nil
    end
    local zone = spot.zone
    if spot.mapID and W.MAP_IDS then
        local best
        for name, id in pairs(W.MAP_IDS) do
            if id == spot.mapID and (not best or string.len(name) > string.len(best)) then best = name end
        end
        if best then zone = best end
    end
    return zone, spot.mapID
end

local function SameZone(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local ma, mb = W.MAP_IDS and W.MAP_IDS[a], W.MAP_IDS and W.MAP_IDS[b]
    return ma ~= nil and ma == mb
end

---------------------------------------------------------------------------
-- Hearthstone
---------------------------------------------------------------------------
-- every route line that sets the hearthstone: { level, place }
local function HearthSteps(route)
    local out = {}
    if not route then return out end
    for lvl = 1, MAX_LEVEL do
        local data = route["L" .. lvl]
        if data then
            for _, line in ipairs(QuestLines(data)) do
                if string.find(Low(line), "hearthstone", 1, true) and string.find(Low(line), "set", 1, true) then
                    out[#out + 1] = { level = lvl, place = PlaceIn(line, data.zone) or Hub(data), zone = data.zone }
                    break
                end
            end
        end
    end
    return out
end

-- the bind name is in the game language; compare only when the client is English
local function BindMatches(bind, place)
    if not bind or not place then return nil end
    local loc = GetLocale and Safe(GetLocale)
    if loc and loc ~= "enUS" and loc ~= "enGB" then return nil end
    local b, p = Low(bind), Low(place)
    return string.find(b, p, 1, true) ~= nil or string.find(p, b, 1, true) ~= nil
end

local function HearthPlan(level)
    local steps = HearthSteps(Route())
    local cur, nextStep
    for _, s in ipairs(steps) do
        if s.level <= level then cur = s elseif not nextStep then nextStep = s end
    end
    local bind = GetBindLocation and Safe(GetBindLocation)
    if bind == "" then bind = nil end
    return { bind = bind, cur = cur, nextStep = nextStep, match = cur and BindMatches(bind, cur.place) }
end

---------------------------------------------------------------------------
-- Flight paths seen by this character
---------------------------------------------------------------------------
local function FlightDB()
    WockyDB = WockyDB or {}
    WockyDB.flight = WockyDB.flight or {}
    local key = (W.CharKey and Safe(W.CharKey)) or "?"
    local t = WockyDB.flight[key]
    if type(t) ~= "table" then
        t = { maps = {}, nodes = {} }
        WockyDB.flight[key] = t
    end
    t.maps = t.maps or {}
    t.nodes = t.nodes or {}
    return t
end

local function NoteMap()
    local _, mapID = CurrentZone()
    if mapID then FlightDB().maps[mapID] = true end
end

-- flight map open: the flight master you stand at, plus every flight point you can fly to
local function RecordTaxi()
    local t = FlightDB()
    NoteMap()
    pcall(function()
        local n = NumTaxiNodes and NumTaxiNodes() or 0
        for i = 1, n do
            local name = TaxiNodeName and TaxiNodeName(i)
            local kind = TaxiNodeGetType and TaxiNodeGetType(i)
            if name and name ~= "" and (kind == "CURRENT" or kind == "REACHABLE") then t.nodes[name] = true end
        end
    end)
end

local function HasFlight(hub, zone)
    local t = FlightDB()
    local id = zone and W.MAP_IDS and W.MAP_IDS[zone]
    if id and t.maps[id] then return true end
    local h = Low(hub)
    if h ~= "" then
        for name in pairs(t.nodes) do
            if string.find(Low(name), h, 1, true) then return true end
        end
    end
    return false
end

local function FlightCount()
    local n = 0
    for _ in pairs(FlightDB().nodes) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Next levels: hubs and zones in route order
---------------------------------------------------------------------------
local function NextHubs(level)
    local route = Route()
    local out = {}
    if not route then return out end
    local last
    for lvl = level, math.min(MAX_LEVEL, level + AHEAD) do
        local data = route["L" .. lvl]
        if data and data.zone then
            local hub = Hub(data)
            -- a level without a named place stays with the hub before it in the same zone
            local named = type(WockyPlaces) == "table" and hub and WockyPlaces[hub]
            if not named and last and last.zone == data.zone then hub = last.hub end
            local id = data.zone .. "|" .. tostring(hub)
            if last and last.id == id then
                last.to = lvl
            else
                if #out >= MAX_HUBS then break end
                local fp = false
                for _, line in ipairs(QuestLines(data)) do
                    local l = Low(line)
                    if string.find(l, "flight path", 1, true) then fp = true end
                end
                last = { id = id, from = lvl, to = lvl, zone = data.zone, hub = hub, data = data, routeFP = fp }
                out[#out + 1] = last
            end
            if string.find(Low(data.quest), "flight path", 1, true) then last.routeFP = true end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Open steps in a zone
---------------------------------------------------------------------------
-- onlyBelow: levels under maxLevel only; onlyStarted: only levels where you ticked something
local function OpenSteps(zone, maxLevel, onlyBelow, onlyStarted)
    local route = Route()
    local out = {}
    if not route or not zone then return out end
    local doneT = W.DoneTable and Safe(W.DoneTable) or {}
    local top = onlyBelow and (maxLevel - 1) or maxLevel
    for lvl = 1, math.min(MAX_LEVEL, top) do
        local data = route["L" .. lvl]
        if data and SameZone(data.zone, zone) then
            local lines, open, started = QuestLines(data), {}, false
            for i, line in ipairs(lines) do
                local key = "Q" .. lvl .. ":" .. i
                if doneT[key] then started = true else open[#open + 1] = { level = lvl, key = key, text = Strip(line) } end
            end
            if started or not onlyStarted then
                for _, o in ipairs(open) do out[#out + 1] = o end
            end
        end
        -- quest steps of 4.0.0 (only ticked by hand ones are counted here; quest ones tick themselves)
        local steps = W.QuestStepsFor and Safe(W.QuestStepsFor, lvl)
        if type(steps) == "table" then
            for i, step in ipairs(steps) do
                local kind = step[1]
                if (kind == "goto" or kind == "learn" or kind == "fly") and SameZone(step.zone or (data and data.zone), zone) then
                    local key = "S" .. lvl .. ":" .. i
                    if not doneT[key] then
                        out[#out + 1] = { level = lvl, key = key, text = tostring(step.name or kind) }
                    end
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Text for the report and the tests
---------------------------------------------------------------------------
local function PlanText()
    local level = PlayerLevel()
    local r = {}
    local hs = HearthPlan(level)
    r[#r + 1] = "Hearth: " .. tostring(hs.bind or "-") .. " / route: " .. (hs.cur and (tostring(hs.cur.place) .. " (L" .. hs.cur.level .. ")") or "-")
        .. (hs.nextStep and (", next L" .. hs.nextStep.level .. " " .. tostring(hs.nextStep.place)) or "")
    local zone = CurrentZone()
    r[#r + 1] = "Open steps in " .. tostring(zone) .. ": " .. #OpenSteps(zone, level, false)
    r[#r + 1] = "Flight points seen: " .. FlightCount()
    return table.concat(r, "; ")
end
W.RoutePlanInfo = PlanText

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame
local rows = {}
local ROW_W = 396

local function NewRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ROW_W, 14)
    b.text = W.NewFS(b, W.fonts.small)
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.text:SetWidth(ROW_W)
    b.text:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.07)
    b:SetScript("OnClick", function(self)
        if self.onClick then pcall(self.onClick) end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local function CreateFrameUI()
    local f = CreateFrame("Frame", "WockyRoutePlanFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(424, 200)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    pcall(function()
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
    end)
    pcall(function() table.insert(UISpecialFrames, "WockyRoutePlanFrame") end)

    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.title:SetWidth(360)
    f.title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    f.hint = W.NewFS(f, W.fonts.small)
    f.hint:SetWidth(ROW_W)
    f.hint:SetJustifyH("LEFT")

    f:Hide()
    return f
end

local function Row(i)
    if not rows[i] then rows[i] = NewRow(frame) end
    return rows[i]
end

local Refresh

local function Fill()
    local level = PlayerLevel()
    local n, y = 0, -36
    local function add(text, onClick, tip, indent)
        n = n + 1
        local b = Row(n)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (indent or 0), y)
        b.text:SetWidth(ROW_W - (indent or 0))
        b.text:SetText(text)
        local h = 14
        pcall(function() h = math.max(14, math.ceil(b.text:GetStringHeight() or 14)) end)
        b:SetHeight(h)
        b.onClick, b.tip = onClick, tip
        b:Show()
        y = y - h - 3
    end
    local function head(text)
        y = y - 4
        add("|cFFFFD100" .. text .. "|r")
    end

    frame.title:SetText("|cFF8787EDWockyPro|r - " .. L("PLAN_TITLE", level))
    if not Route() then
        add(L("PLAN_NO_ROUTE"))
    else
        -- 1. Hearthstone
        head(L("PLAN_HEARTH"))
        local hs = HearthPlan(level)
        add(L("PLAN_BOUND", hs.bind or "?"), nil, nil, 8)
        if hs.cur then
            local mark = ""
            if hs.match == true then mark = "  |cFF33FF33" .. L("PLAN_HS_OK") .. "|r"
            elseif hs.match == false then mark = "  |cFFFF8833" .. L("PLAN_HS_DIFF") .. "|r" end
            local p = WockyPlaces and WockyPlaces[hs.cur.place]
            add(L("PLAN_HS_ROUTE", tostring(hs.cur.place), hs.cur.level) .. mark,
                p and function() W.SetArrowTarget(p[1], p[2], p[3], hs.cur.place, true) end,
                p and L("PLAN_CLICK_ARROW") or nil, 8)
        else
            add(L("PLAN_HS_NONE"), nil, nil, 8)
        end
        if hs.nextStep then
            add(L("PLAN_HS_NEXT", hs.nextStep.level, tostring(hs.nextStep.place)), nil, nil, 8)
        end

        -- 2. Next levels
        head(L("PLAN_NEXT"))
        for _, h in ipairs(NextHubs(level)) do
            local lv = (h.from == h.to) and L("PLAN_LVL", h.from) or L("PLAN_LVL_RANGE", h.from, h.to)
            local fp
            if HasFlight(h.hub, h.zone) then fp = "|cFF33FF33" .. L("PLAN_FP_KNOWN") .. "|r"
            elseif h.routeFP then fp = "|cFFFFD100" .. L("PLAN_FP_ROUTE") .. "|r"
            else fp = "|cFF999999" .. L("PLAN_FP_UNKNOWN") .. "|r" end
            local place = (h.hub and h.hub ~= h.zone) and (h.zone .. " - " .. h.hub) or h.zone
            local d = h.data
            add(lv .. "  " .. place .. "  " .. fp,
                function() W.SetArrowTarget(d.zone, d.x, d.y, h.hub or d.zone, true) end,
                L("PLAN_CLICK_ARROW"), 8)
        end

        -- 3. Open steps here
        local zone = CurrentZone()
        head(L("PLAN_OPEN", tostring(zone or "?")))
        local all = OpenSteps(zone, level, false)
        -- newest level first
        local open = {}
        for i, o in ipairs(all) do o.n = i; open[i] = o end
        table.sort(open, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            return a.n < b.n
        end)
        if #open == 0 then
            add(L("PLAN_OPEN_NONE"), nil, nil, 8)
        end
        for i, s in ipairs(open) do
            if i > MAX_OPEN then
                add("|cFF999999" .. L("PLAN_MORE", #open - MAX_OPEN) .. "|r", nil, nil, 8)
                break
            end
            add("|cFFFFFFFF[ ]|r " .. L("PLAN_LVL", s.level) .. ": " .. Translate(s.text), function()
                local doneT = W.DoneTable()
                doneT[s.key] = true
                if W.UpdateWockyGuide and W.GetViewLevel then pcall(W.UpdateWockyGuide, W.GetViewLevel()) end
                Refresh()
            end, L("PLAN_CLICK_TICK"), 8)
        end
    end
    for j = n + 1, #rows do rows[j]:Hide() end
    y = y - 6
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
    frame.hint:SetText("|cFF999999" .. L("PLAN_HINT") .. "|r")
    local hh = 14
    pcall(function() hh = math.ceil(frame.hint:GetStringHeight() or 14) end)
    frame:SetHeight(math.max(140, -y + hh + 16))
end

Refresh = function()
    if frame and frame:IsShown() then
        local ok, err = pcall(Fill)
        if not ok and geterrorhandler then pcall(geterrorhandler(), err) end
    end
end

local function ShowPlan()
    if not frame then frame = CreateFrameUI() end
    frame:Show()
    Refresh()
end

local function TogglePlan()
    if frame and frame:IsShown() then frame:Hide() else ShowPlan() end
end

W.ShowRoutePlan = ShowPlan
W.ToggleRoutePlan = TogglePlan

---------------------------------------------------------------------------
-- Reminders in the guide window
---------------------------------------------------------------------------
local baseReminders = W.ExtraReminders
W.ExtraReminders = function(list)
    if baseReminders then pcall(baseReminders, list) end
    if not Cfg("planReminder") or not Route() then return end
    pcall(function()
        local level = PlayerLevel()
        local hs = HearthPlan(level)
        if hs.cur and hs.match == false then list[#list + 1] = L("REMIND_PLAN_HS", tostring(hs.cur.place)) end
        local zone = CurrentZone()
        local open = OpenSteps(zone, level, true, true)
        if #open > 0 then list[#list + 1] = L("REMIND_PLAN_OPEN", #open) end
    end)
end

W.AddToggle(W.pageMap, "planReminder", "PLAN_REMIND")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TAXIMAP_OPENED", "UI_INFO_MESSAGE", "ZONE_CHANGED_NEW_AREA", "HEARTHSTONE_BOUND",
    "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
local queued = false
local function Queue()
    if queued then return end
    queued = true
    local function run()
        queued = false
        Refresh()
        if W.WockyUI and W.WockyUI:IsShown() and W.UpdateWockyGuide and W.GetViewLevel then
            pcall(W.UpdateWockyGuide, W.GetViewLevel())
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.7, run) else run() end
end
ev:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "TAXIMAP_OPENED" then
        pcall(RecordTaxi)
        Queue()
    elseif event == "UI_INFO_MESSAGE" then
        local msg = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil
        if msg and ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH then
            pcall(NoteMap)
            Queue()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if frame and frame:IsShown() then Queue() end
    else
        Queue()
    end
end)

---------------------------------------------------------------------------
-- Slash command and help
---------------------------------------------------------------------------
W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky plan", "HELP_PLAN" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "plan" or m == "route plan" then
        TogglePlan()
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._RouteHearthSteps = function() return HearthSteps(Route()) end
W._RouteNextHubs = NextHubs
W._RouteOpenSteps = OpenSteps
W._RouteHasFlight = HasFlight
W._RouteRecordTaxi = RecordTaxi
