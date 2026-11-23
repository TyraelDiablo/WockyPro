-- WockyRouteEdit: your own route (6.0.0)
--  1. Route editor (/wocky edit): add, remove and move the lines of a level,
--     and set the level's arrow target from where you stand. Edits are saved
--     per route and replace the lines of that level; "Reset level" undoes it.
--  2. Import / export: a route's edits as plain text to share (Discord etc.).
--  3. Level together: group members with WockyPro see which level and how
--     many lines of it the others have done; ticks can be shared (option).
-- Only text and addon messages; no casting, no item use.
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local D = W.DEFAULTS
local PREFIX = "WockyPro"
local MAX_LINES = 6
local MAX_TEXT = 160
local SEND_GAP = 8

for k, v in pairs({ togetherShow = true, togetherTicks = false }) do
    if D[k] == nil then D[k] = v end
end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function InCombat()
    local c = false
    pcall(function()
        c = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    end)
    return c and true or false
end

local function Str(v)
    if type(v) ~= "string" or v == "" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function Route() return (W.RouteKey and W.RouteKey()) or "SCOURGE" end
local function ViewLevel() return (W.GetViewLevel and W.GetViewLevel()) or 1 end

local function PlayerLevel()
    local ok, l = pcall(UnitLevel, "player")
    if ok and type(l) == "number" and not (issecretvalue and issecretvalue(l)) then return l end
    return 1
end

---------------------------------------------------------------------------
-- Saved edits: WockyDB.routeEdit[route]["L<level>"] = { lines = {...}, zone, x, y, npc }
---------------------------------------------------------------------------
local function Store()
    WockyDB = WockyDB or {}
    WockyDB.routeEdit = WockyDB.routeEdit or {}
    return WockyDB.routeEdit
end

local function Edit(route, level, create)
    local s = Store()
    if create then s[route] = s[route] or {} end
    local r = s[route]
    if not r then return nil end
    local key = "L" .. level
    if create and not r[key] then r[key] = { lines = {} } end
    return r[key]
end

local function DefaultData(route, level)
    local raceData = WockyGuideDB and WockyGuideDB[route]
    return raceData and raceData["L" .. level]
end

local function SplitLines(text)
    local out = {}
    for line in string.gmatch(text or "", "[^\n]+") do
        out[#out + 1] = (string.gsub(line, "^%[ %] ", ""))
    end
    return out
end

-- the lines of a level as the guide shows them (your edit or the route)
local function LevelLines(route, level)
    local e = Edit(route, level)
    if e and e.lines then
        local out = {}
        for i, l in ipairs(e.lines) do out[i] = l end
        return out, true
    end
    local d = DefaultData(route, level)
    return SplitLines(d and d.quest), false
end
W.GuideLines = function(level) return (LevelLines(Route(), level or ViewLevel())) end

-- core hook: replaces the level data when you edited it
W.GuideOverride = function(route, level, data)
    local e = Edit(route, level)
    if not e or not e.lines then return nil end
    local parts = {}
    for i, l in ipairs(e.lines) do
        if i > MAX_LINES then break end
        parts[#parts + 1] = "[ ] " .. l
    end
    if #parts == 0 then parts[1] = "[ ] " .. L("RE_EMPTY_LEVEL") end
    local out = {}
    if type(data) == "table" then for k, v in pairs(data) do out[k] = v end end
    out.quest = table.concat(parts, "\n")
    if e.zone and e.x and e.y then
        out.zone, out.x, out.y, out.npc = e.zone, e.x, e.y, e.npc or e.zone
    end
    return out
end

-- ticks belong to line numbers: a changed level starts with no ticks
local function ClearTicks(level)
    if not W.DoneTable then return end
    local t = W.DoneTable()
    for i = 1, MAX_LINES do t["Q" .. level .. ":" .. i] = nil end
end

local function Refresh()
    if W.UpdateWockyGuide then pcall(W.UpdateWockyGuide, ViewLevel()) end
end

local function StartEdit(route, level)
    local e = Edit(route, level, true)
    if not e.started then
        local d = DefaultData(route, level)
        e.lines = SplitLines(d and d.quest)
        e.started = true
    end
    return e
end

local function Clean(text)
    text = strtrim(tostring(text or ""))
    text = string.gsub(text, "[\r\n]", " ")
    text = string.gsub(text, "||", "/")
    text = string.gsub(text, "|", "/")
    if #text > MAX_TEXT then text = string.sub(text, 1, MAX_TEXT) end
    return text
end

local function AddLine(level, text)
    text = Clean(text)
    if text == "" then return false end
    local e = StartEdit(Route(), level)
    if #e.lines >= MAX_LINES then Chat(L("RE_FULL", MAX_LINES)); return false end
    e.lines[#e.lines + 1] = text
    ClearTicks(level)
    return true
end

local function RemoveLine(level, i)
    local e = StartEdit(Route(), level)
    if e.lines[i] then table.remove(e.lines, i) end
    ClearTicks(level)
end

local function MoveLine(level, i, delta)
    local e = StartEdit(Route(), level)
    local j = i + delta
    if not e.lines[i] or not e.lines[j] then return end
    e.lines[i], e.lines[j] = e.lines[j], e.lines[i]
    ClearTicks(level)
end

local function MapName(mapID)
    for name, id in pairs(W.MAP_IDS or {}) do
        if id == mapID and not string.find(name, "^Hillsbrad$") and name ~= "Arathi" then return name end
    end
end

local function TargetHere(level)
    local spot = W.PlayerSpot and W.PlayerSpot()
    if not spot or not spot.x or not spot.y then Chat(L("HERE_NO_COORDS")); return false end
    local zone = (spot.mapID and MapName(spot.mapID)) or spot.zone
    local e = StartEdit(Route(), level)
    e.zone, e.x, e.y = zone, spot.x, spot.y
    e.npc = (spot.sub and spot.sub ~= "" and spot.sub) or zone
    Chat(L("RE_TARGET_SET", level, zone, spot.x, spot.y))
    return true
end

local function ResetLevel(level)
    local r = Store()[Route()]
    if r then r["L" .. level] = nil end
    ClearTicks(level)
end

---------------------------------------------------------------------------
-- Import / export text
--   WockyRoute 1 <ROUTE>
--   #12                  a level
--   @Zone;60.5;52.3;Name   its arrow target (optional)
--   - a line
---------------------------------------------------------------------------
local function ExportText(route)
    local r = Store()[route] or {}
    local levels = {}
    for key in pairs(r) do
        local n = tonumber(string.match(key, "^L(%d+)$"))
        if n then levels[#levels + 1] = n end
    end
    table.sort(levels)
    local out = { "WockyRoute 1 " .. route }
    for _, lv in ipairs(levels) do
        local e = r["L" .. lv]
        if e and e.lines then
            out[#out + 1] = "#" .. lv
            if e.zone and e.x and e.y then
                out[#out + 1] = "@" .. e.zone .. ";" .. e.x .. ";" .. e.y .. ";" .. tostring(e.npc or e.zone)
            end
            for _, l in ipairs(e.lines) do out[#out + 1] = "- " .. l end
        end
    end
    return table.concat(out, "\n"), #levels
end

-- returns route, number of levels, or nil and an error key
local function ParseImport(text)
    text = string.gsub(tostring(text or ""), "||", "|")
    local route = string.match(text, "WockyRoute%s+1%s+(%u+)")
    if not route or not (WockyGuideDB and WockyGuideDB[route]) then return nil, "RE_IMPORT_BAD" end
    local levels, cur, count = {}, nil, 0
    for raw in string.gmatch(text, "[^\r\n]+") do
        local line = strtrim(raw)
        local lv = tonumber(string.match(line, "^#(%d+)$"))
        if lv then
            if lv < 1 or lv > (W.MAX_LEVEL or 60) then return nil, "RE_IMPORT_BAD" end
            cur = { lines = {}, started = true }
            levels[lv] = cur
            count = count + 1
        elseif cur and string.sub(line, 1, 1) == "@" then
            local zone, x, y, npc = string.match(line, "^@([^;]+);([%d%.]+);([%d%.]+);?(.*)$")
            x, y = tonumber(x), tonumber(y)
            if zone and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                cur.zone, cur.x, cur.y = Clean(zone), x, y
                cur.npc = (npc and npc ~= "") and Clean(npc) or cur.zone
            end
        elseif cur and string.sub(line, 1, 2) == "- " then
            local t = Clean(string.sub(line, 3))
            if t ~= "" and #cur.lines < MAX_LINES then cur.lines[#cur.lines + 1] = t end
        end
    end
    if count == 0 then return nil, "RE_IMPORT_BAD" end
    return route, count, levels
end

local function DoImport(text)
    local route, count, levels = ParseImport(text)
    if not route then Chat(L(count)); return false end
    local s = Store()
    s[route] = s[route] or {}
    for lv, e in pairs(levels) do
        s[route]["L" .. lv] = e
        if route == Route() then ClearTicks(lv) end
    end
    Chat(L("RE_IMPORTED", count, (W.ROUTE_NAMES and W.ROUTE_NAMES[route]) or route))
    Refresh()
    return true
end

---------------------------------------------------------------------------
-- A text box to copy or paste (shared by export and import)
---------------------------------------------------------------------------
local box
local function TextBox()
    if box then return box end
    local f = CreateFrame("Frame", "WockyTextBoxFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, 340)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
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
    pcall(function() table.insert(UISpecialFrames, "WockyTextBoxFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.title:SetWidth(460)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    local scroll
    pcall(function() scroll = CreateFrame("ScrollFrame", "WockyTextBoxScroll", f, "UIPanelScrollFrameTemplate") end)
    if not scroll then scroll = CreateFrame("ScrollFrame", "WockyTextBoxScroll", f) end
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 40)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or W.fonts.normal)
    eb:SetWidth(470)
    eb:SetMaxLetters(20000)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(self, user)
        if user and f.readOnly and f.text then self:SetText(f.text); self:HighlightText() end
    end)
    scroll:SetScrollChild(eb)
    f.eb = eb
    f.left = W.StyleButton(CreateFrame("Button", nil, f, "UIPanelButtonTemplate"))
    f.left:SetSize(150, 22)
    f.left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.right = W.StyleButton(CreateFrame("Button", nil, f, "UIPanelButtonTemplate"))
    f.right:SetSize(100, 22)
    f.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    f.right:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    box = f
    return f
end

-- readOnly: text to copy; otherwise an empty box and onAccept(text)
local function ShowTextBox(titleText, text, onAccept)
    local f = TextBox()
    f.title:SetText("|cFF8787EDWockyPro|r - " .. titleText)
    f.readOnly = not onAccept
    f.text = text
    f.eb:SetText(text or "")
    f.right:SetText(L("REPORT_CLOSE"))
    if onAccept then
        f.left:SetText(L("RE_IMPORT_DO"))
        f.left:SetScript("OnClick", function()
            local ok = onAccept(f.eb:GetText() or "")
            if ok then f:Hide() end
        end)
    else
        f.left:SetText(L("REPORT_SELECT"))
        f.left:SetScript("OnClick", function() f.eb:SetFocus(); f.eb:HighlightText() end)
    end
    f:Show()
    f.eb:SetFocus()
    if not onAccept then f.eb:HighlightText() end
end
W.ShowTextBox = ShowTextBox

local function ShowExport()
    local text, n = ExportText(Route())
    if n == 0 then Chat(L("RE_EXPORT_NONE")) end
    ShowTextBox(L("RE_EXPORT_TITLE"), text)
end

local function ShowImport()
    ShowTextBox(L("RE_IMPORT_TITLE"), "", DoImport)
end

---------------------------------------------------------------------------
-- Editor window
---------------------------------------------------------------------------
local ed
local edLevel
local rowsUI = {}
local ROW_W = 440

local function Btn(parent, w, text)
    local b = W.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w, 20)
    if text then b:SetText(text) end
    return b
end

local RefreshEditor

local function CreateEditor()
    local f = CreateFrame("Frame", "WockyRouteEditFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(ROW_W + 28, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
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
        f:SetBackdropColor(0, 0, 0, 0.94)
        f:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
    end)
    pcall(function() table.insert(UISpecialFrames, "WockyRouteEditFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.title:SetWidth(ROW_W - 80)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    f.nextB = Btn(f, 24, ">")
    f.nextB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -8)
    f.prevB = Btn(f, 24, "<")
    f.prevB:SetPoint("RIGHT", f.nextB, "LEFT", -4, 0)
    f.nextB:SetScript("OnClick", function() edLevel = math.min(W.MAX_LEVEL or 60, edLevel + 1); RefreshEditor() end)
    f.prevB:SetScript("OnClick", function() edLevel = math.max(1, edLevel - 1); RefreshEditor() end)

    f.info = W.NewFS(f, W.fonts.small)
    f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    f.info:SetWidth(ROW_W)
    f.info:SetJustifyH("LEFT")

    for i = 1, MAX_LINES do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(ROW_W, 20)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -52 - (i - 1) * 22)
        r.text = W.NewFS(r, W.fonts.small)
        r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.text:SetWidth(ROW_W - 92)
        r.text:SetJustifyH("LEFT")
        pcall(function() r.text:SetWordWrap(false) end)
        r.up = Btn(r, 26, "^")
        r.up:SetPoint("RIGHT", r, "RIGHT", -60, 0)
        r.down = Btn(r, 26, "v")
        r.down:SetPoint("LEFT", r.up, "RIGHT", 2, 0)
        r.del = Btn(r, 28, "x")
        r.del:SetPoint("LEFT", r.down, "RIGHT", 2, 0)
        r.up:SetScript("OnClick", function() MoveLine(edLevel, i, -1); Refresh(); RefreshEditor() end)
        r.down:SetScript("OnClick", function() MoveLine(edLevel, i, 1); Refresh(); RefreshEditor() end)
        r.del:SetScript("OnClick", function() RemoveLine(edLevel, i); Refresh(); RefreshEditor() end)
        rowsUI[i] = r
    end

    local y = -52 - MAX_LINES * 22 - 6
    local input = CreateFrame("EditBox", "WockyRouteEditInput", f, "InputBoxTemplate")
    input:SetSize(ROW_W - 90, 20)
    input:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
    input:SetAutoFocus(false)
    input:SetMaxLetters(MAX_TEXT)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.input = input
    f.add = Btn(f, 80)
    f.add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    local function add()
        if AddLine(edLevel, input:GetText()) then input:SetText(""); Refresh() end
        RefreshEditor()
    end
    f.add:SetScript("OnClick", add)
    input:SetScript("OnEnterPressed", add)

    y = y - 28
    f.here = Btn(f, 210)
    f.here:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
    f.here:SetScript("OnClick", function() if TargetHere(edLevel) then Refresh() end RefreshEditor() end)
    f.reset = Btn(f, 210)
    f.reset:SetPoint("LEFT", f.here, "RIGHT", 8, 0)
    f.reset:SetScript("OnClick", function() ResetLevel(edLevel); Refresh(); RefreshEditor() end)
    y = y - 24
    f.export = Btn(f, 210)
    f.export:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
    f.export:SetScript("OnClick", ShowExport)
    f.import = Btn(f, 210)
    f.import:SetPoint("LEFT", f.export, "RIGHT", 8, 0)
    f.import:SetScript("OnClick", ShowImport)
    y = y - 26
    f.hint = W.NewFS(f, W.fonts.small)
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
    f.hint:SetWidth(ROW_W)
    f.hint:SetJustifyH("LEFT")
    f:SetHeight(-y + 40)
    f:Hide()
    return f
end

RefreshEditor = function()
    if not ed or not ed:IsShown() then return end
    local route = Route()
    local lines, edited = LevelLines(route, edLevel)
    local routeName = (W.ROUTE_NAMES and W.ROUTE_NAMES[route]) or route
    ed.title:SetText("|cFF8787EDWockyPro|r - " .. L("RE_TITLE", edLevel, routeName))
    local e = Edit(route, edLevel)
    local info = edited and ("|cFF00FF00" .. L("RE_EDITED") .. "|r") or ("|cFF999999" .. L("RE_DEFAULT") .. "|r")
    if e and e.zone then info = info .. "  |cFFFFD100" .. L("RE_TARGET", e.zone, e.x or 0, e.y or 0) .. "|r" end
    ed.info:SetText(info)
    for i, r in ipairs(rowsUI) do
        local l = lines[i]
        if l then
            local shown = l
            if W.TranslateLine then
                local ok, t = pcall(W.TranslateLine, l)
                if ok and type(t) == "string" then shown = t end
            end
            r.text:SetText(i .. ". " .. shown)
            r.up:SetEnabled(i > 1)
            r.down:SetEnabled(lines[i + 1] ~= nil)
            r:Show()
        else
            r:Hide()
        end
    end
    ed.add:SetText(L("RE_ADD"))
    ed.here:SetText(L("RE_HERE"))
    ed.reset:SetText(L("RE_RESET"))
    ed.export:SetText(L("RE_EXPORT"))
    ed.import:SetText(L("RE_IMPORT"))
    ed.hint:SetText("|cFF999999" .. L("RE_HINT") .. "|r")
    ed.prevB:SetEnabled(edLevel > 1)
    ed.nextB:SetEnabled(edLevel < (W.MAX_LEVEL or 60))
end

local function ShowEditor(level)
    if not ed then ed = CreateEditor() end
    edLevel = level or ViewLevel()
    ed:Show()
    RefreshEditor()
end
W.ShowRouteEditor = ShowEditor

---------------------------------------------------------------------------
-- Level together
---------------------------------------------------------------------------
local mates = {}   -- name -> { route, level, done, total, at }
local lastSent, lastMsg = -100, nil

local function Now() return (GetTime and GetTime()) or 0 end

local function InGroup()
    local g = false
    pcall(function() g = (IsInGroup and IsInGroup()) or false end)
    return g and true or false
end

local function Send(msg)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not InGroup() then return end
    pcall(function()
        local chan = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
        C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
    end)
end

local function Progress(level)
    local lines = LevelLines(Route(), level)
    local t = W.DoneTable and W.DoneTable() or {}
    local done = 0
    for i = 1, #lines do if t["Q" .. level .. ":" .. i] then done = done + 1 end end
    return done, #lines
end

local function SendProgress(force)
    if not Cfg("togetherShow") or not InGroup() or InCombat() then return end
    local level = PlayerLevel()
    local done, total = Progress(level)
    local msg = "P:" .. Route() .. ":" .. level .. ":" .. done .. ":" .. total
    if not force and msg == lastMsg then return end
    if Now() - lastSent < SEND_GAP and not force then return end
    lastSent, lastMsg = Now(), msg
    Send(msg)
end

-- ticks: compare the player level's ticks with the last look
local lastTicks = {}
local function TickSnapshot(level)
    local t = W.DoneTable and W.DoneTable() or {}
    local snap = {}
    for i = 1, MAX_LINES do snap[i] = t["Q" .. level .. ":" .. i] and true or false end
    return snap
end

local function CheckTicks()
    if InCombat() then return end
    local level = PlayerLevel()
    local snap = TickSnapshot(level)
    local prev = lastTicks[level]
    if prev and Cfg("togetherTicks") then
        for i = 1, MAX_LINES do
            if snap[i] ~= prev[i] then Send("T:" .. Route() .. ":" .. level .. ":" .. i .. ":" .. (snap[i] and 1 or 0)) end
        end
    end
    lastTicks = { [level] = snap }
    SendProgress(false)
end

local function ShortName(n)
    n = Str(n)
    if not n then return nil end
    return (string.match(n, "^([^%-]+)") or n)
end

local function OnMessage(msg, sender)
    msg = Str(msg)
    local who = ShortName(sender)
    if not msg or not who then return end
    local me = ShortName(UnitName and UnitName("player"))
    if who == me then return end
    local route, lv, done, total = string.match(msg, "^P:(%u+):(%d+):(%d+):(%d+)$")
    if route then
        mates[who] = { route = route, level = tonumber(lv), done = tonumber(done), total = tonumber(total), at = Now() }
        if W.UpdateWockyGuide and W.WockyUI and W.WockyUI:IsShown() and not InCombat() then pcall(W.UpdateWockyGuide, ViewLevel()) end
        return
    end
    local tr, tl, ti, tv = string.match(msg, "^T:(%u+):(%d+):(%d+):([01])$")
    if tr and Cfg("togetherTicks") and tr == Route() and W.DoneTable and not InCombat() then
        tl, ti = tonumber(tl), tonumber(ti)
        if ti >= 1 and ti <= MAX_LINES then
            local key = "Q" .. tl .. ":" .. ti
            local t = W.DoneTable()
            t[key] = (tv == "1") or nil
            lastTicks[tl] = lastTicks[tl] or TickSnapshot(tl)
            lastTicks[tl][ti] = (tv == "1")
            if tl == ViewLevel() then Refresh() end
        end
    end
end

-- members we still see in the group, freshest first
local function MateList()
    local list = {}
    for name, m in pairs(mates) do
        local inGroup = false
        pcall(function() inGroup = (UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name)) or false end)
        if inGroup or Now() - (m.at or 0) < 120 then list[#list + 1] = { name = name, m = m } end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
W.TogetherMates = MateList

-- a line under the dungeon line: "Group: Ann 23 (2/3), Bob 22 (3/3)"
local togetherText = W.NewFS(W.WockyUI, W.fonts.small)
togetherText:SetWidth(328)
togetherText:SetJustifyH("LEFT")
togetherText:Hide()
W.togetherText = togetherText

local baseLayout = W.ExtraLayout
W.ExtraLayout = function(y)
    if baseLayout then y = baseLayout(y) or y end
    local list = (Cfg("togetherShow") and InGroup() and not Cfg("collapsed")) and MateList() or {}
    if #list == 0 then togetherText:Hide(); return y end
    local parts = {}
    for i = 1, math.min(4, #list) do
        local e = list[i]
        local p = e.name .. " " .. e.m.level .. " (" .. e.m.done .. "/" .. e.m.total .. ")"
        if e.m.route ~= Route() then p = p .. "*" end
        parts[#parts + 1] = p
    end
    togetherText:SetText("|cFF9999FF" .. L("TG_LINE") .. ":|r " .. table.concat(parts, ", "))
    togetherText:ClearAllPoints()
    togetherText:SetPoint("TOPLEFT", W.WockyUI, "TOPLEFT", 16, -y)
    togetherText:Show()
    return y + (W.TextH and W.TextH(togetherText) or 12) + 4
end

W.TogetherInfo = function()
    local n = 0
    for _ in pairs(mates) do n = n + 1 end
    local edits = 0
    for _, e in pairs(Store()[Route()] or {}) do if type(e) == "table" and e.lines then edits = edits + 1 end end
    return "edited levels " .. edits .. ", together " .. (Cfg("togetherShow") and "on" or "off") .. " (" .. n .. " seen), shared ticks " .. (Cfg("togetherTicks") and "on" or "off")
end

---------------------------------------------------------------------------
-- Settings, events, slash commands
---------------------------------------------------------------------------
if W.pageMap and W.AddButton then
    W.AddButton(W.pageMap, "RE_OPEN", function() ShowEditor() end)
end
local gpage = W.pageGroup
if gpage then
    W.AddToggle(gpage, "togetherShow", "TG_OPT_SHOW")
    W.AddToggle(gpage, "togetherTicks", "TG_OPT_TICKS")
end

local baseApply = W.OnApply
W.OnApply = function(...)
    if baseApply then pcall(baseApply, ...) end
    pcall(RefreshEditor)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
ev:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then pcall(OnMessage, a2, a4) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        pcall(SendProgress, true)
    else
        pcall(CheckTicks)
    end
end)

local tick = 0
ev:SetScript("OnUpdate", function(self, elapsed)
    tick = tick + (elapsed or 0)
    if tick < 2 then return end
    tick = 0
    if InGroup() then pcall(CheckTicks) end
end)

W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky edit", "HELP_EDIT" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "edit" or m == "editor" then
        if ed and ed:IsShown() then ed:Hide() else ShowEditor() end
    elseif string.find(m, "^edit %d+$") then
        ShowEditor(tonumber(string.match(m, "(%d+)")))
    elseif m == "export" or m == "route export" then
        ShowExport()
    elseif m == "import" or m == "route import" then
        ShowImport()
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._REAdd = AddLine
W._REMove = MoveLine
W._RERemove = RemoveLine
W._REReset = ResetLevel
W._REHere = TargetHere
W._REExport = ExportText
W._REImport = DoImport
W._REParse = ParseImport
W._TGMessage = OnMessage
W._TGCheck = CheckTicks
