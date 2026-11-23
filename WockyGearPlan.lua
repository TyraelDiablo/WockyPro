-- WockyGearPlan: gear by level range (5.3.0)
--  1. /wocky items: good items a Warlock can wear for 10-19, 20-29 ... 50-60.
--     Two parts: the checked list (WockyGearData.lua, filled after testing)
--     and the items WockyPro saw in game: loot, quest rewards, crafting and
--     vendors. Nothing is guessed.
--  2. The dungeon line tooltip lists good Warlock loot of each dungeon:
--     checked items and items that dropped while you were inside.
--  3. /wocky items export: everything as text in the WockyGearData format.
-- Only reads item data; no item use, no casting. Nothing runs in combat.
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local D = W.DEFAULTS
local RANGES = { { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 60 } }
local MAX_PER_RANGE = 40
local MAX_PER_DUNGEON = 30
local MAX_LINES = 14
local MAX_PENDING = 20
local SRC_RANK = { quest = 4, dungeon = 3, craft = 3, vendor = 3, drop = 1 }
-- English dungeon names of the guide that the game writes another way.
-- Classic names; check in game.
local DUNGEON_ALIAS = { ["Sunken Temple"] = "The Temple of Atal'Hakkar" }

for k, v in pairs({ gearRecord = true, gearDungeonTip = true }) do
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

-- a plain string / number addon code may use (never a secret value)
local function Str(v)
    if type(v) ~= "string" or v == "" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function Num(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return pcall(function() return v + 0 end) and v or nil
end

local function PlayerLevel()
    local ok, l = pcall(UnitLevel, "player")
    return (ok and Num(l)) or 1
end

local function RangeIndex(level)
    for i, r in ipairs(RANGES) do
        if level >= r[1] and level <= r[2] then return i end
    end
    if level > 60 then return #RANGES end
    return nil
end

local function RangeKey(i)
    local r = RANGES[i]
    return r and (r[1] .. "-" .. r[2]) or "?"
end

local function Store()
    WockyDB = WockyDB or {}
    WockyDB.gearplan = WockyDB.gearplan or {}
    local g = WockyDB.gearplan
    g.items = g.items or {}
    g.dungeons = g.dungeons or {}
    return g
end

local function ItemID(link)
    local id = Str(link) and tonumber(string.match(link, "item:(%d+)"))
    return id
end

local function ItemInfo(item)
    local name, link, quality, ilvl, minLevel
    pcall(function()
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        name, link, quality, ilvl, minLevel = get(item)
    end)
    return Str(name), Str(link), Num(quality), Num(ilvl), Num(minLevel)
end

local function RequestItem(id)
    pcall(function()
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    end)
end

local function Diff(link)
    if not link or not W.UpgradeDiff then return nil end
    local ok, diff, empty, minLevel, new = pcall(W.UpgradeDiff, link)
    if ok then return diff, empty, minLevel, new end
end

-- the stored dungeon-name form: lower case, letters and digits only, no "the"
local function NormDungeon(name)
    name = string.lower(tostring(name or ""))
    name = string.gsub(name, "^the ", "")
    name = string.gsub(name, "^lower ", "")
    name = string.gsub(name, "^upper ", "")
    return (string.gsub(name, "[^%w]", ""))
end

local function InstanceName()
    local inside, kind, name = false, nil, nil
    pcall(function()
        inside, kind = IsInInstance()
        if GetInstanceInfo then name = GetInstanceInfo() end
    end)
    if inside and kind == "party" then return Str(name) end
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local function CountRange(g, key)
    local n, worstID, worst = 0, nil, nil
    for id, e in pairs(g.items) do
        if e.range == key then
            n = n + 1
            if worst == nil or (e.score or 0) < worst then worstID, worst = id, (e.score or 0) end
        end
    end
    return n, worstID, worst
end

-- src: quest / dungeon / craft / vendor / drop; where: quest or dungeon name
local function Record(link, src, where)
    if not Cfg("gearRecord") or InCombat() then return false end
    local id = ItemID(link)
    if not id then return false end
    local name, fullLink, quality, ilvl, minLevel = ItemInfo(link)
    if not name then RequestItem(id); return false end
    if not quality or quality < 1 or (quality < 2 and src ~= "quest") then return false end
    local diff, _, _, new = Diff(fullLink or link)
    if not diff or not new or new <= 0 then return false end
    local lvl = (minLevel and minLevel > 0) and minLevel or PlayerLevel()
    local ri = RangeIndex(lvl)
    local g = Store()
    if ri then
        local key = RangeKey(ri)
        local e = g.items[id]
        if e then
            e.seen = (e.seen or 1) + 1
            e.score = math.floor(new * 10 + 0.5) / 10
            if (SRC_RANK[src] or 0) > (SRC_RANK[e.src] or 0) then e.src, e.where = src, where end
        else
            local n, worstID, worst = CountRange(g, key)
            if n >= MAX_PER_RANGE then
                if worst and new <= worst then ri = nil else g.items[worstID] = nil end
            end
            if ri then
                g.items[id] = { link = fullLink or link, lvl = lvl, range = key, score = math.floor(new * 10 + 0.5) / 10,
                    src = src, where = where, seen = 1 }
            end
        end
    end
    if src == "dungeon" and where then
        local dk = NormDungeon(where)
        g.dungeons[dk] = g.dungeons[dk] or { name = where, items = {} }
        local d = g.dungeons[dk]
        if not d.items[id] then
            local n, worstID, worst = 0, nil, nil
            for did, de in pairs(d.items) do
                n = n + 1
                if worst == nil or (de.score or 0) < worst then worstID, worst = did, (de.score or 0) end
            end
            if n >= MAX_PER_DUNGEON and worstID then d.items[worstID] = nil end
        end
        d.items[id] = { link = fullLink or link, lvl = lvl, score = math.floor(new * 10 + 0.5) / 10 }
    end
    return true
end

-- chat lines and rewards seen in combat wait here
local pending = {}

local function Queue(link, src, where)
    if #pending < MAX_PENDING then pending[#pending + 1] = { link, src, where } end
end

local refreshWindow -- defined below

local function Flush()
    if InCombat() then return end
    local list = pending
    pending = {}
    local again = {}
    for _, p in ipairs(list) do
        local ok, done = pcall(Record, p[1], p[2], p[3])
        -- item data may still be loading: try once more later
        if ok and not done and not p[4] and ItemID(p[1]) and not select(1, ItemInfo(p[1])) then
            again[#again + 1] = { p[1], p[2], p[3], true }
        end
    end
    for _, p in ipairs(again) do pending[#pending + 1] = p end
    if refreshWindow then pcall(refreshWindow) end
end

local flushQueued = false
local function QueueFlush(delay)
    if flushQueued then return end
    flushQueued = true
    local function run() flushQueued = false; Flush() end
    if C_Timer and C_Timer.After then C_Timer.After(delay or 0.8, run) else run() end
end

local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = string.gsub(fmt, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = string.gsub(p, "%%%%s", "(.+)")
    p = string.gsub(p, "%%%%d", "%%d+")
    return "^" .. p .. "$"
end

local patterns
local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, e in ipairs({ { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "craft" }, { "LOOT_ITEM_CREATED_SELF", "craft" },
        { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "push" }, { "LOOT_ITEM_PUSHED_SELF", "push" },
        { "LOOT_ITEM_SELF_MULTIPLE", "loot" }, { "LOOT_ITEM_SELF", "loot" } }) do
        local p = ToPattern(rawget(_G, e[1]))
        if p then patterns[#patterns + 1] = { p, e[2] } end
    end
    return patterns
end

local function MerchantOpen()
    local open = false
    pcall(function() open = MerchantFrame and MerchantFrame:IsShown() and true or false end)
    return open
end

local function OnLootMsg(msg)
    if not Cfg("gearRecord") then return end
    msg = Str(msg)
    if not msg then return end
    local link = string.match(msg, "(|c%x+|Hitem:.-|h%[.-%]|h|r)") or string.match(msg, "(|Hitem:.-|h%[.-%]|h)")
    if not link then return end
    local kind
    for _, p in ipairs(Patterns()) do
        if string.find(msg, p[1]) then kind = p[2]; break end
    end
    local dungeon = InstanceName()
    if kind == "craft" then
        Queue(link, "craft")
    elseif dungeon then
        -- in a dungeon every item in the loot chat dropped there (also other players' loot and rolls)
        Queue(link, "dungeon", dungeon)
    elseif kind == "push" then
        -- quest rewards are saved from the quest window; a vendor buy shows as "receive"
        if MerchantOpen() then Queue(link, "vendor") end
    elseif kind == "loot" then
        Queue(link, "drop")
    else
        return
    end
    QueueFlush()
end

local function OnLootOpened()
    if not Cfg("gearRecord") then return end
    local dungeon = InstanceName()
    if not dungeon then return end
    local n = 0
    pcall(function() n = GetNumLootItems() or 0 end)
    n = Num(n) or 0
    for i = 1, math.min(n, 10) do
        local link
        pcall(function() link = GetLootSlotLink(i) end)
        link = Str(link)
        if link then Queue(link, "dungeon", dungeon) end
    end
    QueueFlush()
end

local function OnQuestWindow()
    if not Cfg("gearRecord") then return end
    local title
    pcall(function() title = GetTitleText() end)
    title = Str(title)
    for _, kind in ipairs({ "choice", "reward" }) do
        local n = 0
        pcall(function()
            n = (kind == "choice" and GetNumQuestChoices and GetNumQuestChoices()) or (GetNumQuestRewards and GetNumQuestRewards()) or 0
        end)
        n = Num(n) or 0
        for i = 1, math.min(n, 10) do
            local link
            pcall(function() link = GetQuestItemLink(kind, i) end)
            link = Str(link)
            if link then Queue(link, "quest", title) end
        end
    end
    QueueFlush(0.5)
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
local function SourceText(src, where)
    if src == "quest" then return L("GP_SRC_QUEST", where or "?")
    elseif src == "dungeon" then return L("GP_SRC_DUNGEON", where or "?")
    elseif src == "craft" then return L("GP_SRC_CRAFT")
    elseif src == "vendor" then return L("GP_SRC_VENDOR")
    end
    return L("GP_SRC_DROP")
end

local function CheckedList(ri)
    local data = W.GEAR_DATA and W.GEAR_DATA.ranges and W.GEAR_DATA.ranges[RangeKey(ri)]
    local out = {}
    for _, e in ipairs(data or {}) do
        if type(e) == "table" and type(e.id) == "number" then
            local _, link = ItemInfo(e.id)
            if not link then RequestItem(e.id) end
            out[#out + 1] = { link = link or ("item:" .. e.id), lvl = e.lvl, src = e.src, where = e.where, checked = true }
        end
    end
    return out
end

local function SavedList(ri)
    local key = RangeKey(ri)
    local out = {}
    local live = not InCombat()
    for id, e in pairs(Store().items) do
        if e.range == key and e.link then
            local entry = { id = id, link = e.link, lvl = e.lvl, src = e.src, where = e.where, score = e.score or 0 }
            if live then
                local diff, empty, _, new = Diff(e.link)
                if new then entry.score = new end
                entry.diff, entry.empty = diff, empty
            end
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.lvl or 0) < (b.lvl or 0)
    end)
    return out
end

-- loot lines of one dungeon (English guide name): checked IDs first, then saved items
local function DungeonLoot(name)
    local out, seen = {}, {}
    local checked = W.GEAR_DATA and W.GEAR_DATA.dungeons and W.GEAR_DATA.dungeons[name]
    for _, id in ipairs(checked or {}) do
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            local _, link = ItemInfo(id)
            if link then out[#out + 1] = link else RequestItem(id) end
        end
    end
    local saved = {}
    local keys = { [NormDungeon(name)] = true }
    if DUNGEON_ALIAS[name] then keys[NormDungeon(DUNGEON_ALIAS[name])] = true end
    for dk, d in pairs(Store().dungeons) do
        if keys[dk] and type(d.items) == "table" then
            for id, e in pairs(d.items) do
                if not seen[id] and e.link then
                    seen[id] = true
                    saved[#saved + 1] = e
                end
            end
        end
    end
    table.sort(saved, function(a, b) return (a.score or 0) > (b.score or 0) end)
    for _, e in ipairs(saved) do out[#out + 1] = e.link end
    return out
end

---------------------------------------------------------------------------
-- Dungeon line tooltip
---------------------------------------------------------------------------
local guideLevel

local baseOnGuide = W.OnGuide
W.OnGuide = function(level, data)
    guideLevel = level
    if baseOnGuide then return baseOnGuide(level, data) end
end

local function DungeonsFor(level)
    local faction
    pcall(function() faction = UnitFactionGroup("player") end)
    local list = {}
    for _, d in ipairs(WockyDungeons or {}) do
        if level >= d[2] and level <= d[3] and (not d[5] or not faction or d[5] == faction) then list[#list + 1] = d end
    end
    return list
end

local function AddDungeonLoot(tip)
    if not Cfg("gearDungeonTip") or not tip then return end
    local level = guideLevel or PlayerLevel()
    local any = false
    local rows = {}
    for _, d in ipairs(DungeonsFor(level)) do
        local loot = DungeonLoot(d[1])
        if #loot > 0 then
            any = true
            local shown = {}
            for i = 1, math.min(3, #loot) do shown[#shown + 1] = loot[i] end
            local text = d[1] .. ": " .. table.concat(shown, " ")
            if #loot > 3 then text = text .. " |cFF888888+" .. (#loot - 3) .. "|r" end
            rows[#rows + 1] = text
        end
    end
    tip:AddLine(L("GP_DTIP_HEAD"), 0.6, 0.53, 0.93)
    if not any then
        tip:AddLine(L("GP_DTIP_NONE"), 0.6, 0.6, 0.6, true)
    else
        for _, r in ipairs(rows) do tip:AddLine(r, 1, 1, 1) end
    end
    tip:Show()
end

local dbtn = W.dungeonBtn
if dbtn then
    pcall(function()
        dbtn:HookScript("OnEnter", function() pcall(AddDungeonLoot, GameTooltip) end)
    end)
end

---------------------------------------------------------------------------
-- Gear by level window (/wocky items)
---------------------------------------------------------------------------
local frame
local rows = {}
local ROW_W = 440
local shownRange

local function NewButton(parent, w, h)
    local b = W.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w, h)
    return b
end

local function CreateFrameUI()
    local f = CreateFrame("Frame", "WockyGearPlanFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(ROW_W + 28, 240)
    f:SetPoint("CENTER", UIParent, "CENTER", 80, 20)
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
    pcall(function() table.insert(UISpecialFrames, "WockyGearPlanFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.title:SetWidth(ROW_W - 90)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    f.nextB = NewButton(f, 24, 20)
    f.nextB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -8)
    f.nextB:SetText(">")
    f.prevB = NewButton(f, 24, 20)
    f.prevB:SetPoint("RIGHT", f.nextB, "LEFT", -4, 0)
    f.prevB:SetText("<")
    f.nextB:SetScript("OnClick", function()
        shownRange = math.min(#RANGES, (shownRange or 1) + 1)
        refreshWindow()
    end)
    f.prevB:SetScript("OnClick", function()
        shownRange = math.max(1, (shownRange or 1) - 1)
        refreshWindow()
    end)
    f.exportB = NewButton(f, 160, 22)
    f.exportB:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.exportB:SetScript("OnClick", function() if W.ShowGearExport then W.ShowGearExport() end end)
    f:Hide()
    return f
end

local function Row(i)
    if not rows[i] then
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(ROW_W, 14)
        b.text = W.NewFS(b, W.fonts.small)
        b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.text:SetWidth(ROW_W)
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnEnter", function(self)
            if not self.link or not GameTooltip then return end
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end)
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        rows[i] = b
    end
    return rows[i]
end

local function ScoreText(e)
    if e.diff and (e.diff >= 0.5 or (e.empty and e.diff > 0)) then
        return "|cFF00FF00+" .. string.format("%.1f", e.diff) .. "|r"
    end
    return "|cFF999999" .. string.format("%.1f", e.score or 0) .. "|r"
end

local function EntryText(e)
    local name = e.link
    local s = "  " .. tostring(name)
    if e.lvl then s = s .. " |cFFFFD100" .. L("GP_LVL", e.lvl) .. "|r" end
    if e.score then s = s .. " " .. ScoreText(e) end
    if e.src then s = s .. " |cFF999999" .. SourceText(e.src, e.where) .. "|r" end
    return s
end

refreshWindow = function()
    if not frame or not frame:IsShown() then return end
    shownRange = shownRange or RangeIndex(PlayerLevel()) or 1
    frame.title:SetText("|cFF8787EDWockyPro|r - " .. L("GP_TITLE", RangeKey(shownRange)))
    frame.exportB:SetText(L("GP_EXPORT"))
    frame.prevB:SetEnabled(shownRange > 1)
    frame.nextB:SetEnabled(shownRange < #RANGES)
    local t = {}
    local checked = CheckedList(shownRange)
    t[#t + 1] = { "|cFFFFD100" .. L("GP_CHECKED") .. "|r" }
    if #checked == 0 then t[#t + 1] = { "  |cFF999999" .. L("GP_CHECKED_NONE") .. "|r" } end
    for i = 1, math.min(6, #checked) do t[#t + 1] = { EntryText(checked[i]), checked[i].link } end
    local saved = SavedList(shownRange)
    t[#t + 1] = { "|cFFFFD100" .. L("GP_SAVED", #saved) .. "|r" }
    if #saved == 0 then t[#t + 1] = { "  |cFF999999" .. L("GP_SAVED_NONE") .. "|r" } end
    for i = 1, math.min(MAX_LINES, #saved) do t[#t + 1] = { EntryText(saved[i]), saved[i].link } end
    if #saved > MAX_LINES then t[#t + 1] = { "  |cFF888888+" .. (#saved - MAX_LINES) .. "|r" } end
    t[#t + 1] = { "" }
    t[#t + 1] = { "|cFF999999" .. L("GP_HINT") .. "|r" }

    local y = 38
    for i, line in ipairs(t) do
        local b = Row(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -y)
        b.text:SetText(line[1])
        b.link = line[2]
        local h = math.max(14, (b.text:GetStringHeight() or 14))
        b:SetHeight(h)
        b:Show()
        y = y + h + 2
    end
    for i = #t + 1, #rows do rows[i]:Hide() end
    frame:SetHeight(y + 44)
end

local function ShowPlan(range)
    if not frame then frame = CreateFrameUI() end
    shownRange = range or RangeIndex(PlayerLevel()) or 1
    frame:Show()
    refreshWindow()
end

local function TogglePlan()
    if frame and frame:IsShown() then frame:Hide() else ShowPlan() end
end
W.ShowGearPlan = ShowPlan

---------------------------------------------------------------------------
-- Export (text in the WockyGearData format)
---------------------------------------------------------------------------
local function Quote(s)
    s = string.gsub(tostring(s or ""), "\\", "\\\\")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "|", "||")
    return "\"" .. s .. "\""
end

local function PlainName(link)
    return (Str(link) and string.match(link, "%[(.-)%]")) or tostring(link)
end

local function ExportText()
    local g = Store()
    local out = { "-- WockyPro " .. tostring(W.VERSION) .. " gear by level (check in game before adding to WockyGearData.lua)", "ranges = {" }
    for ri = 1, #RANGES do
        local key = RangeKey(ri)
        local list = {}
        for id, e in pairs(g.items) do
            if e.range == key then list[#list + 1] = { id = id, e = e } end
        end
        table.sort(list, function(a, b) return (a.e.score or 0) > (b.e.score or 0) end)
        out[#out + 1] = "    [\"" .. key .. "\"] = {"
        for _, it in ipairs(list) do
            local e = it.e
            local line = "        { id = " .. it.id .. ", lvl = " .. tostring(e.lvl or 0) .. ", src = \"" .. tostring(e.src or "drop") .. "\""
            if e.where then line = line .. ", where = " .. Quote(e.where) end
            out[#out + 1] = line .. " }, -- " .. PlainName(e.link)
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    out[#out + 1] = "dungeons = {"
    local names = {}
    for dk, d in pairs(g.dungeons) do names[#names + 1] = { dk = dk, d = d } end
    table.sort(names, function(a, b) return tostring(a.d.name) < tostring(b.d.name) end)
    for _, n in ipairs(names) do
        local ids, labels = {}, {}
        for id, e in pairs(n.d.items or {}) do ids[#ids + 1] = { id = id, name = PlainName(e.link) } end
        table.sort(ids, function(a, b) return a.id < b.id end)
        for i, v in ipairs(ids) do ids[i], labels[i] = tostring(v.id), v.name end
        out[#out + 1] = "    [" .. Quote(n.d.name) .. "] = { " .. table.concat(ids, ", ") .. " }, -- " .. table.concat(labels, ", ")
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

local copyFrame, copyBox
local function CreateCopy()
    local f = CreateFrame("Frame", "WockyGearExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, 360)
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
    pcall(function() table.insert(UISpecialFrames, "WockyGearExportFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.title:SetWidth(440)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    local scroll
    pcall(function() scroll = CreateFrame("ScrollFrame", "WockyGearExportScroll", f, "UIPanelScrollFrameTemplate") end)
    if not scroll then scroll = CreateFrame("ScrollFrame", "WockyGearExportScroll", f) end
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 40)
    copyBox = CreateFrame("EditBox", nil, scroll)
    copyBox:SetMultiLine(true)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject(ChatFontNormal or W.fonts.normal)
    copyBox:SetWidth(470)
    copyBox:SetScript("OnEscapePressed", function() f:Hide() end)
    copyBox:SetScript("OnTextChanged", function(self, user)
        if user and f.text then self:SetText(f.text); self:HighlightText() end
    end)
    scroll:SetScrollChild(copyBox)
    f.sel = NewButton(f, 150, 22)
    f.sel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.sel:SetScript("OnClick", function() copyBox:SetFocus(); copyBox:HighlightText() end)
    f.done = NewButton(f, 100, 22)
    f.done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    f.done:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

local function ShowExport()
    if not copyFrame then copyFrame = CreateCopy() end
    local text = ExportText()
    copyFrame.text = text
    copyFrame.title:SetText("|cFF8787EDWockyPro|r - " .. L("GP_EXPORT_TITLE"))
    copyFrame.sel:SetText(L("REPORT_SELECT"))
    copyFrame.done:SetText(L("REPORT_CLOSE"))
    copyBox:SetText(text)
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
end
W.ShowGearExport = ShowExport

---------------------------------------------------------------------------
-- Settings (Gear tab), report line
---------------------------------------------------------------------------
local page = W.pageGear
if page then
    W.AddToggle(page, "gearRecord", "GP_OPT_RECORD")
    W.AddToggle(page, "gearDungeonTip", "GP_OPT_DTIP")
    if W.AddButton then W.AddButton(page, "GP_OPEN", function() ShowPlan() end) end
end

local baseApply = W.OnApply
W.OnApply = function(...)
    if baseApply then pcall(baseApply, ...) end
    pcall(refreshWindow)
end

local baseGearInfo = W.GearInfo
W.GearInfo = function()
    local s = ""
    if baseGearInfo then
        local ok, v = pcall(baseGearInfo)
        if ok and v then s = tostring(v) end
    end
    local n, dn = 0, 0
    for _ in pairs(Store().items) do n = n + 1 end
    for _ in pairs(Store().dungeons) do dn = dn + 1 end
    return s .. ", saved items " .. n .. " (" .. dn .. " dungeons)" .. (Cfg("gearRecord") and "" or " recorder off")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_LOOT", "LOOT_OPENED", "QUEST_DETAIL", "QUEST_COMPLETE", "PLAYER_REGEN_ENABLED",
    "GET_ITEM_INFO_RECEIVED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end

ev:SetScript("OnEvent", function(self, event, a1)
    if event == "CHAT_MSG_LOOT" then
        pcall(OnLootMsg, a1)
    elseif event == "LOOT_OPENED" then
        pcall(OnLootOpened)
    elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        pcall(OnQuestWindow)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if #pending > 0 then QueueFlush(0.5) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if #pending > 0 then QueueFlush(0.5) end
        if frame and frame:IsShown() and not InCombat() then pcall(refreshWindow) end
    end
end)

---------------------------------------------------------------------------
-- Slash command and help
---------------------------------------------------------------------------
W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky items", "HELP_ITEMS" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "items" or m == "gearplan" then
        TogglePlan()
    elseif m == "items export" then
        ShowExport()
    elseif m == "items clear" then
        local g = Store()
        g.items, g.dungeons = {}, {}
        Chat(L("GP_CLEARED"))
        pcall(refreshWindow)
    elseif string.find(m, "^items %d") then
        local lv = tonumber(string.match(m, "^items (%d+)"))
        ShowPlan(lv and RangeIndex(lv) or nil)
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._GPRecord = Record
W._GPFlush = Flush
W._GPLootMsg = OnLootMsg
W._GPQuest = OnQuestWindow
W._GPLootOpened = OnLootOpened
W._GPDungeonLoot = DungeonLoot
W._GPSaved = SavedList
W._GPExport = ExportText
W._GPTip = AddDungeonLoot
