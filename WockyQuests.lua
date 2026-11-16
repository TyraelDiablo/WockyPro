-- WockyQuests: quest engine, first step (4.0.0)
-- 1. Quest recorder: saves quest ID, name, giver / turn-in NPC and position while you play.
--    /wocky quests shows everything recorded as text (also as draft route steps) to copy.
-- 2. Quest steps: a route level can list steps tied to real quest IDs
--    (WockyQuestSteps in WockyDatabase.lua). Accept / complete / turn in tick themselves
--    from the game's quest log; go / learn / fly steps are ticked by hand.
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local MAX_QUESTS = 400
local MAX_EVENTS = 800
local MAX_ROWS = 6
local GIVER_TTL = 120

for k, v in pairs({ questRecorder = true, showQuestSteps = true }) do
    if W.DEFAULTS[k] == nil then W.DEFAULTS[k] = v end
end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

---------------------------------------------------------------------------
-- Quest log helpers (old and new client functions)
---------------------------------------------------------------------------
local function LogIndex(id)
    local idx
    pcall(function()
        if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
            local i = C_QuestLog.GetLogIndexForQuestID(id)
            if i and i > 0 then idx = i end
        end
    end)
    if idx then return idx end
    pcall(function()
        if not GetNumQuestLogEntries or not GetQuestLogTitle then return end
        local n = GetNumQuestLogEntries()
        for i = 1, n or 0 do
            local _, _, _, isHeader, _, _, _, qid = GetQuestLogTitle(i)
            if not isHeader and qid == id then idx = i return end
        end
    end)
    return idx
end

local function LogTitle(i)
    local title, level, complete, qid
    pcall(function()
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader then title, level, qid = info.title, info.level, info.questID end
        end
    end)
    if not title then
        pcall(function()
            local t, lvl, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
            if not isHeader then title, level, complete, qid = t, lvl, isComplete, id end
        end)
    end
    return title, level, complete, qid
end

local function TurnedIn(id)
    local done = false
    pcall(function()
        if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
            done = C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
        elseif IsQuestFlaggedCompleted then
            done = IsQuestFlaggedCompleted(id) and true or false
        end
    end)
    return done
end

local function ObjectivesDone(id, idx)
    local done
    pcall(function()
        if C_QuestLog and C_QuestLog.IsComplete then done = C_QuestLog.IsComplete(id) and true or false end
    end)
    if done == nil and idx then
        local _, _, complete = LogTitle(idx)
        done = (complete == 1 or complete == true)
    end
    return done or false
end

-- list of { text, finished }
local function Objectives(id, idx)
    local out = {}
    pcall(function()
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
                if o.text and o.text ~= "" then out[#out + 1] = { o.text, o.finished and true or false } end
            end
        end
    end)
    if #out == 0 and idx then
        pcall(function()
            if not GetNumQuestLeaderBoards or not GetQuestLogLeaderBoard then return end
            for j = 1, GetNumQuestLeaderBoards(idx) or 0 do
                local text, _, finished = GetQuestLogLeaderBoard(j, idx)
                if text and text ~= "" then out[#out + 1] = { text, finished and true or false } end
            end
        end)
    end
    return out
end

local function Store()
    WockyDB = WockyDB or {}
    WockyDB.questRec = WockyDB.questRec or {}
    local r = WockyDB.questRec
    r.quests = r.quests or {}
    r.events = r.events or {}
    return r
end

local function QuestTitle(id, fallback)
    local t
    pcall(function()
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then t = C_QuestLog.GetTitleForQuestID(id) end
    end)
    if (not t or t == "") then
        local idx = LogIndex(id)
        if idx then t = LogTitle(idx) end
    end
    if (not t or t == "") and WockyDB and WockyDB.questRec and WockyDB.questRec.quests[id] then
        t = WockyDB.questRec.quests[id].name
    end
    if not t or t == "" then t = fallback end
    return t
end

---------------------------------------------------------------------------
-- Quest recorder
---------------------------------------------------------------------------
local pendingGiver, pendingTurnin

local function NpcInfo()
    local name, npcID
    pcall(function()
        name = UnitName("npc")
        local guid = UnitGUID("npc")
        if type(guid) == "string" then
            local kind, _, _, _, _, id = strsplit("-", guid)
            if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then npcID = tonumber(id) end
            if kind == "GameObject" then name = name and (name .. " (object)") end
        end
    end)
    local spot = (W.PlayerSpot and W.PlayerSpot()) or {}
    local zone = spot.zone
    -- route data uses English zone names; find one from the map ID
    if spot.mapID and W.MAP_IDS then
        for zname, mid in pairs(W.MAP_IDS) do
            if mid == spot.mapID and (zone == spot.zone or string.len(zname) > string.len(zone or "")) then zone = zname end
        end
    end
    return { npc = npcID, name = name, zone = zone, x = spot.x, y = spot.y, mapID = spot.mapID, t = GetTime and GetTime() or 0 }
end

local function Fresh(p)
    return p and GetTime and (GetTime() - (p.t or 0)) < GIVER_TTL
end

local function AddEvent(kind, id)
    local r = Store()
    table.insert(r.events, { kind, id, UnitLevel("player") or 0, (W.RouteKey and W.RouteKey()) or "?" })
    while #r.events > MAX_EVENTS do table.remove(r.events, 1) end
end

local function CountQuests(r)
    local n = 0
    for _ in pairs(r.quests) do n = n + 1 end
    return n
end

local function TrimQuests(r)
    if CountQuests(r) <= MAX_QUESTS then return end
    local oldest, oldestT
    for id, q in pairs(r.quests) do
        local t = q.seen or 0
        if not oldestT or t < oldestT then oldest, oldestT = id, t end
    end
    if oldest then r.quests[oldest] = nil end
end

local seq = 0
local function Seen()
    seq = seq + 1
    return ((time and time()) or 0) * 1000 + seq % 1000
end

local function OnAccepted(a1, a2)
    local id = (type(a2) == "number" and a2 > 0) and a2 or a1
    if type(id) ~= "number" or id <= 0 then return end
    local r = Store()
    local q = r.quests[id] or {}
    q.name = QuestTitle(id, q.name)
    local idx = LogIndex(id)
    if idx then
        local _, qlevel = LogTitle(idx)
        q.qlevel = qlevel or q.qlevel
    end
    q.lvl = UnitLevel("player") or q.lvl
    q.route = (W.RouteKey and W.RouteKey()) or q.route
    if Fresh(pendingGiver) then
        local g = pendingGiver
        q.giver = { g.npc, g.name, g.zone, g.x, g.y }
    end
    pendingGiver = nil
    q.seen = Seen()
    r.quests[id] = q
    TrimQuests(r)
    AddEvent("accept", id)
end

local function OnTurnedIn(id, xp, money)
    if type(id) ~= "number" or id <= 0 then return end
    local r = Store()
    local q = r.quests[id] or {}
    q.name = q.name or QuestTitle(id, nil)
    if Fresh(pendingTurnin) then
        local g = pendingTurnin
        q.turnin = { g.npc, g.name, g.zone, g.x, g.y }
    end
    pendingTurnin = nil
    q.xp = tonumber(xp) or q.xp
    q.money = tonumber(money) or q.money
    q.done = true
    q.seen = q.seen or Seen()
    r.quests[id] = q
    TrimQuests(r)
    AddEvent("turnin", id)
end

local function Num(v)
    if not v then return "nil" end
    return string.format("%.1f", v)
end

local function Str(s)
    if s == nil then return "nil" end
    return string.format("%q", tostring(s))
end

local function NpcText(g)
    if not g then return "nil" end
    return "{ " .. tostring(g[1] or "nil") .. ", " .. Str(g[2]) .. ", " .. Str(g[3]) .. ", " .. Num(g[4]) .. ", " .. Num(g[5]) .. " }"
end

local function StepText(kind, id, q)
    local g = q and ((kind == "turnin") and q.turnin or q.giver)
    local s = "{ " .. Str(kind) .. ", " .. id
    if g and g[3] and g[4] and g[5] then
        s = s .. ", npc = " .. Str(g[2]) .. ", zone = " .. Str(g[3]) .. ", x = " .. Num(g[4]) .. ", y = " .. Num(g[5])
    end
    s = s .. " }, -- " .. tostring(q and q.name or "?")
    return s
end

local function RecorderText()
    local r = Store()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local ids = {}
    for id in pairs(r.quests) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (r.quests[a].seen or 0) < (r.quests[b].seen or 0) end)
    local turned = 0
    for _, id in ipairs(ids) do if r.quests[id].done then turned = turned + 1 end end
    add("-- WockyPro " .. tostring(W.VERSION) .. " quest recorder")
    pcall(function()
        local version, build = GetBuildInfo()
        add("-- client " .. tostring(version) .. " (" .. tostring(build) .. "), " .. tostring(GetLocale and GetLocale() or "?"))
    end)
    add("-- " .. L("QREC_COUNT", #ids, turned))
    add("")
    add("-- quests: { id, name, quest level, your level, giver { npcID, name, zone, x, y }, turn-in { ... }, xp }")
    for _, id in ipairs(ids) do
        local q = r.quests[id]
        add("{ id = " .. id .. ", name = " .. Str(q.name) .. ", qlevel = " .. tostring(q.qlevel or "nil")
            .. ", lvl = " .. tostring(q.lvl or "nil") .. ", giver = " .. NpcText(q.giver)
            .. ", turnin = " .. NpcText(q.turnin) .. ", xp = " .. tostring(q.xp or "nil") .. " },")
    end
    -- draft route steps in the order you played them, grouped by your level
    local byRoute = {}
    local routes = {}
    for _, e in ipairs(r.events) do
        local route = e[4] or "?"
        if not byRoute[route] then byRoute[route] = {}; routes[#routes + 1] = route end
        local lv = e[3] or 0
        local list = byRoute[route]
        if not list[lv] then list[lv] = {}; list[#list + 1] = lv end
        table.insert(list[lv], e)
    end
    for _, route in ipairs(routes) do
        add("")
        add("-- draft steps for WockyQuestSteps[" .. Str(route) .. "] (check before use)")
        local list = byRoute[route]
        table.sort(list)
        for _, lv in ipairs(list) do
            add("[\"L" .. lv .. "\"] = {")
            for _, e in ipairs(list[lv]) do add("    " .. StepText(e[1], e[2], r.quests[e[2]])) end
            add("},")
        end
    end
    return table.concat(lines, "\n"), #ids, turned
end

function W.QuestRecInfo()
    local r = Store()
    local n, turned = 0, 0
    for _, q in pairs(r.quests) do
        n = n + 1
        if q.done then turned = turned + 1 end
    end
    return (Cfg("questRecorder") and "on" or "off") .. ", " .. n .. " quests, " .. turned .. " turned in"
end

---------------------------------------------------------------------------
-- Recorder window
---------------------------------------------------------------------------
local recFrame, recBox

local function CreateRecFrame()
    local f = CreateFrame("Frame", "WockyQuestRecFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(560, 400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
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
        f:SetBackdropColor(0, 0, 0, 0.95)
        f:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
    end)
    pcall(function() table.insert(UISpecialFrames, "WockyQuestRecFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.title:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    local scroll
    pcall(function() scroll = CreateFrame("ScrollFrame", "WockyQuestRecScroll", f, "UIPanelScrollFrameTemplate") end)
    if not scroll then scroll = CreateFrame("ScrollFrame", "WockyQuestRecScroll", f) end
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 60)
    recBox = CreateFrame("EditBox", nil, scroll)
    recBox:SetMultiLine(true)
    recBox:SetAutoFocus(false)
    recBox:SetFontObject(ChatFontNormal or W.fonts.normal)
    recBox:SetWidth(510)
    recBox:SetScript("OnEscapePressed", function() f:Hide() end)
    recBox:SetScript("OnTextChanged", function(self, user)
        if user and f.text then self:SetText(f.text); self:HighlightText() end
    end)
    scroll:SetScrollChild(recBox)
    f.status = W.NewFS(f, W.fonts.small)
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 38)
    f.status:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.status:SetJustifyH("LEFT")
    local sel = W.StyleButton(CreateFrame("Button", nil, f, "UIPanelButtonTemplate"))
    sel:SetSize(150, 22)
    sel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    sel:SetScript("OnClick", function() recBox:SetFocus(); recBox:HighlightText() end)
    f.selButton = sel
    local done = W.StyleButton(CreateFrame("Button", nil, f, "UIPanelButtonTemplate"))
    done:SetSize(100, 22)
    done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    done:SetScript("OnClick", function() f:Hide() end)
    f.doneButton = done
    f:Hide()
    return f
end

local function ShowRecorder()
    if not recFrame then recFrame = CreateRecFrame() end
    local text, n, turned = RecorderText()
    recFrame.text = text
    recFrame.title:SetText("|cFF8787EDWockyPro|r - " .. L("QREC_TITLE"))
    recFrame.selButton:SetText(L("REPORT_SELECT"))
    recFrame.doneButton:SetText(L("REPORT_CLOSE"))
    recFrame.status:SetText((n == 0) and L("QREC_EMPTY") or (L("QREC_COUNT", n, turned) .. " " .. L("QREC_HINT")))
    recBox:SetText(text)
    recFrame:Show()
    recBox:SetFocus()
    recBox:HighlightText()
end
W.ShowQuestRecorder = ShowRecorder

---------------------------------------------------------------------------
-- Quest steps
---------------------------------------------------------------------------
local STEP_KEYS = {
    accept = "QSTEP_ACCEPT", complete = "QSTEP_COMPLETE", turnin = "QSTEP_TURNIN",
    ["goto"] = "QSTEP_GOTO", learn = "QSTEP_LEARN", fly = "QSTEP_FLY"
}
local QUEST_KINDS = { accept = true, complete = true, turnin = true }
local ROUTE_ALIAS = { UNDEAD = "SCOURGE", SCOURGE = "UNDEAD", TROLL = "ORC" }

local function StepsFor(level)
    if type(WockyQuestSteps) ~= "table" then return nil end
    local key = W.RouteKey and W.RouteKey()
    local route = key and (WockyQuestSteps[key] or (ROUTE_ALIAS[key] and WockyQuestSteps[ROUTE_ALIAS[key]]))
    local list = route and route["L" .. tostring(level)]
    if type(list) == "table" and #list > 0 then return list end
end

-- returns done (bool), detail text or nil, tooltip lines
local function StepState(step, level, i)
    local kind, id = step[1], step[2]
    if not QUEST_KINDS[kind] then
        local doneT = W.DoneTable()
        return doneT["S" .. level .. ":" .. i] and true or false, nil, {}
    end
    if type(id) ~= "number" then return false, nil, {} end
    if TurnedIn(id) then return true, nil, {} end
    local idx = LogIndex(id)
    if kind == "accept" then return idx ~= nil, nil, {} end
    if not idx then return false, nil, {} end
    if kind == "turnin" then
        local ready = ObjectivesDone(id, idx)
        return false, ready and ("|cFF33FF33" .. L("QSTEP_READY") .. "|r") or nil, {}
    end
    -- complete
    local objs = Objectives(id, idx)
    local tip, detail = {}, nil
    for _, o in ipairs(objs) do
        tip[#tip + 1] = { o[1], o[2] and 0.3 or 1, o[2] and 1 or 1, o[2] and 0.3 or 1 }
        if not o[2] and not detail then detail = o[1] end
    end
    if ObjectivesDone(id, idx) then return true, nil, tip end
    return false, detail, tip
end

local stepHeader = W.NewFS(W.WockyUI, W.fonts.normal)
stepHeader:Hide()
local stepRows = {}
for i = 1, MAX_ROWS do
    local b = CreateFrame("Button", nil, W.WockyUI)
    b:SetSize(328, 14)
    b.text = W.NewFS(b, W.fonts.small)
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.text:SetWidth(328)
    b.text:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.07)
    b:SetScript("OnEnter", function(self)
        if not self.tip or #self.tip == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(self.tip) do GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.onClick then pcall(self.onClick) end
    end)
    b:Hide()
    stepRows[i] = b
end

local shownSteps = 0

local function StepName(step)
    local kind, id = step[1], step[2]
    if QUEST_KINDS[kind] and type(id) == "number" then
        return QuestTitle(id, step.name or L("QSTEP_UNKNOWN", id))
    end
    return tostring(step.name or id or "?")
end

local function UpdateSteps(level)
    shownSteps = 0
    stepHeader:SetText("")
    local list = Cfg("showQuestSteps") and StepsFor(level)
    if not list then return nil end
    local done, rows, target = 0, {}, nil
    for i, step in ipairs(list) do
        local ok, isDone, detail, tip = pcall(StepState, step, level, i)
        if not ok then isDone, detail, tip = false, nil, {} end
        if isDone then
            done = done + 1
        else
            if not target and step.zone and step.x and step.y then target = step end
            if #rows < MAX_ROWS then rows[#rows + 1] = { step = step, i = i, detail = detail, tip = tip } end
        end
    end
    stepHeader:SetText("|cFFFFD100[" .. L("QSTEPS_HEADER") .. " " .. done .. "/" .. #list .. "]|r")
    for r, row in ipairs(rows) do
        local b = stepRows[r]
        local step = row.step
        local label = L(STEP_KEYS[step[1]] or "QSTEP_GOTO", "|cFFFFFFFF" .. StepName(step) .. "|r")
        if row.detail then label = label .. " |cFFAAAAAA- " .. row.detail .. "|r" end
        b.text:SetText("|cFFFFFFFF[ ]|r " .. label)
        local tip = { { StepName(step), 1, 0.82, 0 } }
        if QUEST_KINDS[step[1]] and type(step[2]) == "number" then tip[#tip + 1] = { "Quest ID " .. step[2], 0.6, 0.6, 0.6 } end
        if step.npc then tip[#tip + 1] = { step.npc, 1, 1, 1 } end
        if step.zone and step.x and step.y then tip[#tip + 1] = { step.zone .. " " .. step.x .. ", " .. step.y, 0.7, 0.7, 0.7 } end
        for _, t in ipairs(row.tip or {}) do tip[#tip + 1] = t end
        if not QUEST_KINDS[step[1]] then
            tip[#tip + 1] = { L("QSTEP_CLICK_TICK"), 0.45, 0.8, 1 }
            local key = "S" .. level .. ":" .. row.i
            b.onClick = function()
                local doneT = W.DoneTable()
                doneT[key] = not doneT[key]
                W.UpdateWockyGuide(W.GetViewLevel())
            end
        elseif step.zone and step.x and step.y then
            tip[#tip + 1] = { L("CLICK_MAP"), 0.45, 0.8, 1 }
            b.onClick = function()
                if W.SetArrowTarget then W.SetArrowTarget(step.zone, step.x, step.y, step.npc or StepName(step), true) end
                if W.OpenMapZone then W.OpenMapZone(step.zone) end
            end
        else
            b.onClick = nil
        end
        b.tip = tip
    end
    shownSteps = #rows
    return target
end

-- chain onto the guide hooks of WockyExtras.lua
local baseOnGuide = W.OnGuide
function W.OnGuide(level, data)
    if baseOnGuide then pcall(baseOnGuide, level, data) end
    local ok, target = pcall(UpdateSteps, level)
    if ok and target and W.SetArrowTarget then
        W.SetArrowTarget(target.zone, target.x, target.y, target.npc or StepName(target), false)
    end
end

local baseLayout = W.ExtraLayout
function W.ExtraLayout(y)
    if baseLayout then
        local ok, ny = pcall(baseLayout, y)
        if ok and ny then y = ny end
    end
    if Cfg("collapsed") or (stepHeader:GetText() or "") == "" then
        stepHeader:Hide()
        for _, b in ipairs(stepRows) do b:Hide() end
        return y
    end
    stepHeader:ClearAllPoints()
    stepHeader:SetPoint("TOPLEFT", W.WockyUI, "TOPLEFT", 16, -y)
    stepHeader:Show()
    y = y + 18
    for i, b in ipairs(stepRows) do
        if i <= shownSteps then
            local h = W.TextH(b.text)
            if h < 14 then h = 14 end
            b:SetHeight(h)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", W.WockyUI, "TOPLEFT", 16, -y)
            b:Show()
            y = y + h + 2
        else
            b:Hide()
        end
    end
    return y + 4
end

---------------------------------------------------------------------------
-- Settings, events and slash commands
---------------------------------------------------------------------------
W.AddToggle(W.pageMap, "showQuestSteps", "QSTEPS_TOGGLE")
W.AddToggle(W.pageMap, "questRecorder", "QREC_TOGGLE")

local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.5, function()
        refreshQueued = false
        if W.WockyUI:IsShown() and StepsFor(W.GetViewLevel()) then W.UpdateWockyGuide(W.GetViewLevel()) end
    end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_ACCEPTED", "QUEST_COMPLETE", "QUEST_PROGRESS", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
ev:SetScript("OnEvent", function(self, event, a1, a2, a3)
    if Cfg("questRecorder") then
        if event == "QUEST_DETAIL" then
            pendingGiver = NpcInfo()
        elseif event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then
            pendingTurnin = NpcInfo()
        elseif event == "QUEST_ACCEPTED" then
            pcall(OnAccepted, a1, a2)
        elseif event == "QUEST_TURNED_IN" then
            pcall(OnTurnedIn, a1, a2, a3)
        end
    end
    if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then QueueRefresh() end
end)

W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky quests", "HELP_QUESTS" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "quests" or m == "quest" or m == "qrec" then
        ShowRecorder()
    elseif m == "quests on" or m == "quests off" then
        W.SetCfg("questRecorder", m == "quests on")
        Chat(L(m == "quests on" and "QREC_ON" or "QREC_OFF"))
        if W.RefreshSettings then pcall(W.RefreshSettings) end
    elseif m == "quests clear" then
        if WockyDB then WockyDB.questRec = nil end
        Chat(L("QREC_CLEARED"))
        if recFrame and recFrame:IsShown() then ShowRecorder() end
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._QuestRecorderText = RecorderText
W._QuestStepsFor = StepsFor
