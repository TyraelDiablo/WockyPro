-- WockyGroup: group and dungeon mode (5.1.0)
-- /wocky group (or right-click the dungeon line) opens a small window with:
--  1. Group: members with level, zone, healer, Soulstone and WockyPro users
--  2. Stones: who has your Soulstone, Healthstones in your bags for the group
--  3. Summon helper: members far away; a click tells the group whom you summon
--  4. Dungeon quests: quests of your dungeons, read from your quest log and
--     the quest recorder (nothing is guessed), click to share or point the arrow
--  5. Dungeon runs: time, XP, kills, money, shards and deaths per run
-- Plus: ready check list, Soulstone announce (off by default), guide reminders.
-- No casting, no item use: advice and chat messages only.
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local D = W.DEFAULTS
local SHARD_ID = 6265
local RITUAL_ID = 698
local SS_TIME = 1800
local RESUME_TIME = 600
local MAX_RUNS = 10
local MAX_DQ_LINES = 14

for k, v in pairs({ groupMode = true, groupSSRemind = true, groupHSRemind = true, groupSummon = true,
    readyCheck = true, ssAnnounce = false, runSummary = true }) do
    if D[k] == nil then D[k] = v end
end

-- Classic item / spell IDs, the same lists the stone icons use
local HS_IDS = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }
local SS_IDS = { 5232, 16892, 16893, 16895, 16896 }
local SS_BUFFS = { [20707] = true, [20762] = true, [20763] = true, [20764] = true, [20765] = true }
local HEAL_CLASS = { PRIEST = 4, DRUID = 3, SHAMAN = 2, PALADIN = 1 }

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function Safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- a plain number addon code may use (never a secret value)
local function Num(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return pcall(function() return v + 0 end) and v or nil
end

-- a plain string (never a secret value)
local function Str(v)
    if type(v) ~= "string" or v == "" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function InCombat()
    local c = false
    pcall(function()
        c = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    end)
    return c and true or false
end

local function Now() return (time and time()) or 0 end

local function IsWarlock()
    local cls
    pcall(function() cls = select(2, UnitClass("player")) end)
    return cls == "WARLOCK"
end

local function InGroup()
    local g = false
    pcall(function()
        if IsInGroup then g = IsInGroup() and true or false
        elseif GetNumGroupMembers then g = (GetNumGroupMembers() or 0) > 0 end
    end)
    return g
end

local function InRaid()
    local r = false
    pcall(function() r = IsInRaid and IsInRaid() and true or false end)
    return r
end

local function ShortName(n)
    n = Str(n)
    if not n then return nil end
    return (string.match(n, "^([^%-]+)")) or n
end

local function Count(counts, ids)
    local n = 0
    for _, id in ipairs(ids) do n = n + (counts[id] or 0) end
    return n
end

local function Bags()
    local counts = (W.BagCounts and Safe(W.BagCounts)) or {}
    return Count(counts, HS_IDS), Count(counts, SS_IDS), counts[SHARD_ID] or 0
end

local function SpellName(id)
    local n
    pcall(function()
        if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
        if not n and GetSpellInfo then n = GetSpellInfo(id) end
    end)
    return Str(n)
end

local function KnowsRitual()
    local known = false
    pcall(function()
        if (IsPlayerSpell and IsPlayerSpell(RITUAL_ID)) or (IsSpellKnown and IsSpellKnown(RITUAL_ID)) then known = true end
    end)
    if not known then
        local n = SpellName(RITUAL_ID)
        if n then pcall(function() known = type(GetSpellInfo and select(7, GetSpellInfo(n))) == "number" end) end
    end
    return known
end

local function Store()
    WockyDB = WockyDB or {}
    local g = WockyDB.group
    if type(g) ~= "table" then
        g = {}
        WockyDB.group = g
    end
    g.runs = g.runs or {}
    g.dq = g.dq or {}
    g.ss = g.ss or {}
    return g
end

local function CharKey() return (W.CharKey and Safe(W.CharKey)) or "?" end

---------------------------------------------------------------------------
-- 1. Group members (read out of combat only; the last list stays in combat)
---------------------------------------------------------------------------
local wockyUsers = {} -- name -> version, from the addon's own version messages
local members = {}

local function MyMap()
    return Num(C_Map and C_Map.GetBestMapForUnit and Safe(C_Map.GetBestMapForUnit, "player"))
end

local function MapName(id)
    local n
    pcall(function()
        local info = C_Map.GetMapInfo(id)
        n = info and info.name
    end)
    return Str(n)
end

local function HasSoulstone(unit)
    local has = false
    pcall(function()
        for i = 1, 40 do
            local name, sid
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
                if not a then break end
                name, sid = a.name, a.spellId
            elseif UnitBuff then
                local r = { UnitBuff(unit, i) }
                if not r[1] then break end
                name, sid = r[1], r[10]
            else
                break
            end
            sid = Num(sid)
            if sid and SS_BUFFS[sid] then has = true break end
            name = Str(name)
            if name and (name == "Soulstone Resurrection" or name == SpellName(20707)) then has = true break end
        end
    end)
    return has
end

local function GroupUnits()
    local units = {}
    pcall(function()
        local n = Num(GetNumGroupMembers and GetNumGroupMembers()) or 0
        if InRaid() then
            for i = 1, math.min(n, 40) do
                local u = "raid" .. i
                if not (UnitIsUnit and UnitIsUnit(u, "player")) then units[#units + 1] = u end
            end
        else
            for i = 1, 4 do
                if UnitExists and UnitExists("party" .. i) then units[#units + 1] = "party" .. i end
            end
        end
    end)
    return units
end

local function ScanMembers()
    if InCombat() then return members end
    local list = {}
    local myMap = MyMap()
    for _, u in ipairs(GroupUnits()) do
        pcall(function()
            local m = { unit = u }
            m.name = ShortName(UnitName(u)) or "?"
            m.cls = Str(select(2, UnitClass(u)))
            m.level = Num(UnitLevel(u))
            m.online = not (UnitIsConnected and not UnitIsConnected(u))
            m.dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost(u)) and true or false
            m.visible = (UnitIsVisible and UnitIsVisible(u)) and true or false
            m.map = Num(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit(u))
            m.zone = m.map and MapName(m.map)
            m.otherZone = (m.map and myMap and m.map ~= myMap) and true or false
            m.far = m.online and not m.visible
            m.role = Str(UnitGroupRolesAssigned and UnitGroupRolesAssigned(u))
            m.ss = HasSoulstone(u)
            m.wocky = wockyUsers[m.name]
            list[#list + 1] = m
        end)
    end
    members = list
    return list
end

-- healer: picked by a click, else the group role, else the best healing class
local function Healer()
    local pick = Store().healer
    local best, bestScore
    for _, m in ipairs(members) do
        if pick and m.name == pick then return m end
        local score = (m.role == "HEALER" and 10) or HEAL_CLASS[m.cls or ""]
        if score and (not bestScore or score > bestScore) then best, bestScore = m, score end
    end
    return best
end

local function SetHealer(name)
    local g = Store()
    if g.healer == name then g.healer = nil else g.healer = name end
end

---------------------------------------------------------------------------
-- 2. Soulstone: who has it (aura scan) and the last one you cast
---------------------------------------------------------------------------
local function SSHolder()
    if HasSoulstone("player") then return (ShortName(UnitName("player")) or "?"), true end
    for _, m in ipairs(members) do
        if m.ss then return m.name, true end
    end
    local t = Store().ss[CharKey()]
    if type(t) == "table" and t.t and Now() - t.t < SS_TIME then return t.n, false, SS_TIME - (Now() - t.t) end
end

local pendingTarget
local function OnSpellSent(unit, a2, a3, a4)
    if unit ~= "player" then return end
    -- new clients: unit, target, castGUID, spellID; old: unit, spell, rank, target
    local target = (type(a4) == "number") and Str(a2) or Str(a4) or Str(a2)
    pendingTarget = ShortName(target)
end

local function OnSpellDone(unit, a2, a3)
    if unit ~= "player" then return end
    local sid = Num(a3) or Num(a2)
    if not sid or not SS_BUFFS[sid] then return end
    local name = pendingTarget or (ShortName(UnitName("target")))
    pendingTarget = nil
    if not name then return end
    Store().ss[CharKey()] = { n = name, t = Now() }
    if Cfg("ssAnnounce") and InGroup() then
        pcall(SendChatMessage, L("SS_ANNOUNCE", name), InRaid() and "RAID" or "PARTY")
    end
end

---------------------------------------------------------------------------
-- 3. Summon helper
---------------------------------------------------------------------------
local function FarMembers()
    local far = {}
    for _, m in ipairs(members) do
        if m.far and not m.dead then far[#far + 1] = m end
    end
    return far
end

local lastSummonMsg = 0
local function AnnounceSummon(name)
    if not InGroup() then return end
    local t = (GetTime and Safe(GetTime)) or 0
    if t - lastSummonMsg < 3 then return end
    lastSummonMsg = t
    pcall(SendChatMessage, L("SUMMON_MSG", name), InRaid() and "RAID" or "PARTY")
end

---------------------------------------------------------------------------
-- 4. Dungeon quests (quest log + quest recorder; no made-up data)
---------------------------------------------------------------------------
-- Checked Forever data can be added here later: ["The Deadmines"] = { questID, ... }
-- TODO: fill from quest recorder exports once checked in game.
W.DUNGEON_QUESTS = W.DUNGEON_QUESTS or {}

local function Norm(s)
    s = string.lower(tostring(s or ""))
    s = string.gsub(s, "^the ", "")
    return (string.gsub(s, "[^%w]", ""))
end

local dungeonByNorm
local function DungeonOf(name)
    if not dungeonByNorm then
        dungeonByNorm = {}
        for _, d in ipairs(WockyDungeons or {}) do dungeonByNorm[Norm(d[1])] = d end
    end
    return name and dungeonByNorm[Norm(name)]
end

local function IsDungeonTag(id)
    local yes = false
    pcall(function()
        local tagID, tagName
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local info = C_QuestLog.GetQuestTagInfo(id)
            if info then tagID, tagName = info.tagID, info.tagName end
        elseif GetQuestTagInfo then
            tagID, tagName = GetQuestTagInfo(id)
        end
        yes = (tagID == 81) or (Str(tagName) == "Dungeon")
    end)
    return yes
end

local function TurnedIn(id)
    local done = false
    pcall(function()
        if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then done = C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
        elseif IsQuestFlaggedCompleted then done = IsQuestFlaggedCompleted(id) and true or false end
    end)
    return done
end

-- quest log entries: { idx, id, title, level, header, complete }
local function LogEntries()
    local out = {}
    pcall(function()
        local n = Num(GetNumQuestLogEntries and (GetNumQuestLogEntries())) or 0
        if n == 0 and C_QuestLog and C_QuestLog.GetNumQuestLogEntries then n = Num(C_QuestLog.GetNumQuestLogEntries()) or 0 end
        local header
        for i = 1, n do
            local title, level, isHeader, complete, id
            if GetQuestLogTitle then
                local t, lv, _, h, _, c, _, qid = GetQuestLogTitle(i)
                title, level, isHeader, complete, id = t, lv, h, c, qid
            elseif C_QuestLog and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(i)
                if info then title, level, isHeader, id = info.title, info.level, info.isHeader, info.questID end
                if id and C_QuestLog.IsComplete then complete = C_QuestLog.IsComplete(id) end
            end
            if isHeader then
                header = Str(title)
            elseif Str(title) and Num(id) then
                out[#out + 1] = { idx = i, id = id, title = title, level = Num(level), header = header,
                    complete = (complete == 1 or complete == true) }
            end
        end
    end)
    return out
end

local inLog = {}
local function ScanQuests()
    if InCombat() then return end
    local dq = Store().dq
    local now = {}
    for _, e in ipairs(LogEntries()) do
        local d = DungeonOf(e.header)
        if d or IsDungeonTag(e.id) then
            local q = dq[e.id] or {}
            q.n, q.lv = e.title, e.level or q.lv
            q.d = (d and d[1]) or q.d or e.header
            dq[e.id] = q
            now[e.id] = e
        end
    end
    inLog = now
end

local function Faction()
    return Str(UnitFactionGroup and Safe(UnitFactionGroup, "player"))
end

local function PlayerLevel()
    return Num(UnitLevel and Safe(UnitLevel, "player")) or 1
end

-- dungeons to list: those of your level, plus any with a quest in your log
local function DungeonQuestList()
    local level, faction = PlayerLevel(), Faction()
    local dq, rec = Store().dq, WockyDB and WockyDB.questRec and WockyDB.questRec.quests
    local byD, order = {}, {}
    local function want(name)
        if not byD[name] then
            byD[name] = {}
            order[#order + 1] = name
        end
        return byD[name]
    end
    for _, d in ipairs(WockyDungeons or {}) do
        if level >= d[2] - 2 and level <= d[3] and (not d[5] or not faction or d[5] == faction) then want(d[1]) end
    end
    for id, q in pairs(dq) do
        if type(q) == "table" and q.d and (inLog[id] or byD[q.d]) and not TurnedIn(id) then
            local list = want(q.d)
            local e = inLog[id]
            local g = rec and rec[id] and rec[id].giver
            list[#list + 1] = { id = id, n = q.n, lv = q.lv, log = e, giver = g }
        end
    end
    for _, name in ipairs(order) do
        for _, id in ipairs(W.DUNGEON_QUESTS[name] or {}) do
            local found = false
            for _, x in ipairs(byD[name]) do if x.id == id then found = true end end
            if not found and not TurnedIn(id) then
                local q = rec and rec[id]
                table.insert(byD[name], { id = id, n = q and q.name or ("#" .. id), giver = q and q.giver })
            end
        end
        table.sort(byD[name], function(a, b) return (a.lv or 0) < (b.lv or 0) end)
    end
    return order, byD
end

local function ShareQuest(e)
    if not e or not InGroup() or InCombat() then return end
    pcall(function()
        if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(e.id)
        elseif SelectQuestLogEntry then SelectQuestLogEntry(e.idx) end
        if QuestLogPushQuest then QuestLogPushQuest() end
    end)
    Chat(L("DQ_SHARED", tostring(e.title)))
end

---------------------------------------------------------------------------
-- 5. Dungeon runs
---------------------------------------------------------------------------
local function XPState()
    return Num(UnitLevel and Safe(UnitLevel, "player")), Num(UnitXP and Safe(UnitXP, "player")),
        Num(UnitXPMax and Safe(UnitXPMax, "player"))
end

local function Money() return Num(GetMoney and Safe(GetMoney)) or 0 end

local function SampleXP()
    local r = Store().cur
    if not r or InCombat() then return end
    local lv, xp, max = XPState()
    if not lv or not xp then return end
    if r.lv and r.xp then
        if lv == r.lv then
            if xp > r.xp then r.gain = (r.gain or 0) + (xp - r.xp) end
        elseif lv > r.lv and r.max then
            r.gain = (r.gain or 0) + math.max(0, r.max - r.xp) + xp
        end
    end
    r.lv, r.xp, r.max = lv, xp, max or r.max
end

local function InstanceName()
    local inside, kind, name = false, nil, nil
    pcall(function()
        inside, kind = IsInInstance()
        if GetInstanceInfo then name = GetInstanceInfo() end
    end)
    if inside and kind == "party" then return Str(name) or Str(GetRealZoneText and Safe(GetRealZoneText)) or "?" end
end

local function RunText(r)
    local mins = math.max(1, math.floor(((r.stop or Now()) - (r.start or Now())) / 60 + 0.5))
    local money = (r.moneyEnd or Money()) - (r.money or 0)
    local mtext = (money < 0 and "-" or "+") .. ((W.CoinText and W.CoinText(math.abs(money))) or tostring(math.abs(money)))
    local shards = (r.shardsEnd or select(3, Bags())) - (r.shards or 0)
    return L("RUN_LINE", tostring(r.name), mins, r.gain or 0, r.kills or 0, mtext, shards, r.deaths or 0)
end

local readyShownFor
local CheckList -- defined below

local function StartRun(name)
    local g = Store()
    local last = g.runs[1]
    -- back in the same dungeon soon after leaving (or after a ghost run): go on with it
    if last and last.name == name and last.stop and Now() - last.stop < RESUME_TIME then
        table.remove(g.runs, 1)
        last.stop, last.moneyEnd, last.shardsEnd = nil, nil, nil
        g.cur = last
        return
    end
    local lv, xp, max = XPState()
    g.cur = { name = name, start = Now(), lv = lv, xp = xp, max = max, gain = 0, kills = 0, deaths = 0,
        money = Money(), shards = select(3, Bags()) }
    if readyShownFor ~= name then
        readyShownFor = name
        if Cfg("readyCheck") and IsWarlock() and C_Timer and C_Timer.After then
            C_Timer.After(4, function() pcall(CheckList, true) end)
        end
    end
end

local function EndRun(silent)
    local g = Store()
    local r = g.cur
    if not r then return end
    SampleXP()
    r.stop, r.moneyEnd, r.shardsEnd = Now(), Money(), select(3, Bags())
    g.cur = nil
    table.insert(g.runs, 1, r)
    while #g.runs > MAX_RUNS do table.remove(g.runs) end
    if not silent and Cfg("runSummary") then Chat(L("RUN_DONE") .. " " .. RunText(r)) end
end

local function CheckInstance()
    local name = InstanceName()
    local g = Store()
    if name then
        if g.cur and g.cur.name ~= name then EndRun() end
        if not g.cur then StartRun(name) end
    elseif g.cur then
        -- a ghost run back to the entrance is not the end of the run
        local dead = false
        pcall(function() dead = UnitIsDeadOrGhost("player") and true or false end)
        if not dead then EndRun() end
    end
end

---------------------------------------------------------------------------
-- Ready check list
---------------------------------------------------------------------------
-- the problems as text lines; empty = all set
local function Problems()
    local out = {}
    local hs, ss, shards = Bags()
    local level = PlayerLevel()
    if level >= 10 and hs == 0 then out[#out + 1] = L("RC_NO_HS") end
    if InGroup() and level >= 18 then
        local holder = SSHolder()
        if not holder then
            local h = Healer()
            if ss > 0 then
                out[#out + 1] = h and L("RC_SS_HEALER", h.name) or L("RC_SS_USE")
            else
                out[#out + 1] = L("RC_NO_SS")
            end
        end
    end
    local pet = false
    pcall(function() pet = UnitExists("pet") and true or false end)
    if level >= 2 and not pet then out[#out + 1] = L("RC_NO_PET") end
    if level >= 10 and shards < 2 then out[#out + 1] = L("RC_SHARDS", shards) end
    return out
end

CheckList = function(auto)
    if not IsWarlock() or InCombat() then return end
    ScanMembers()
    local p = Problems()
    if #p == 0 then
        if not auto then Chat(L("RC_ALL_SET")) end
        return
    end
    Chat(L("RC_TITLE") .. " " .. table.concat(p, ", "))
end

---------------------------------------------------------------------------
-- Text for the report and the tests
---------------------------------------------------------------------------
local function InfoText()
    local r = {}
    r[#r + 1] = (InGroup() and ("group " .. #members) or "solo")
    local h = Healer()
    r[#r + 1] = "healer " .. (h and h.name or "-")
    local holder = SSHolder()
    r[#r + 1] = "SS " .. (holder or "-")
    local hs = Bags()
    r[#r + 1] = "HS " .. hs
    r[#r + 1] = "far " .. #FarMembers()
    local n = 0
    for _ in pairs(Store().dq) do n = n + 1 end
    r[#r + 1] = "dungeon quests " .. n
    local cur = Store().cur
    r[#r + 1] = "run " .. (cur and tostring(cur.name) or "-") .. ", " .. #Store().runs .. " saved"
    return table.concat(r, "; ")
end
W.GroupInfo = InfoText

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame
local rows = {}
local ROW_W = 396
local CLASS_HEX = { WARLOCK = "8787ED", PRIEST = "FFFFFF", MAGE = "40C7EB", ROGUE = "FFF569", DRUID = "FF7D0A",
    HUNTER = "A9D271", SHAMAN = "0070DE", WARRIOR = "C79C6E", PALADIN = "F58CBA" }

local function NewRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ROW_W, 14)
    b.text = W.NewFS(b, W.fonts.small)
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.text:SetWidth(ROW_W)
    b.text:SetJustifyH("LEFT")
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
    local f = CreateFrame("Frame", "WockyGroupFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(424, 200)
    f:SetPoint("CENTER", UIParent, "CENTER", 40, 20)
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
    pcall(function() table.insert(UISpecialFrames, "WockyGroupFrame") end)
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

local function Grey(s) return "|cFF999999" .. s .. "|r" end

local function Fill()
    ScanMembers()
    ScanQuests()
    local n, y = 0, -36
    local function add(text, tip, indent, onClick)
        n = n + 1
        local b = Row(n)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (indent or 0), y)
        b.text:SetWidth(ROW_W - (indent or 0))
        b.text:SetText(text)
        local h = 14
        pcall(function() h = math.max(14, math.ceil(b.text:GetStringHeight() or 14)) end)
        b:SetHeight(h)
        b.tip, b.onClick = tip, onClick
        b:Show()
        y = y - h - 3
    end
    local function head(text)
        y = y - 4
        add("|cFFFFD100" .. text .. "|r")
    end

    frame.title:SetText("|cFF8787EDWockyPro|r - " .. L("GRP_TITLE"))
    local grouped = InGroup()

    -- 1. Group
    head(L("GRP_MEMBERS", #members))
    if not grouped then
        add(L("GRP_SOLO"), nil, 8)
    else
        local healer = Healer()
        local shown = 0
        for _, m in ipairs(members) do
            -- in a raid only the far members are listed (the summon list), to keep it short
            if not InRaid() or m.far then
                shown = shown + 1
                if shown > 8 then
                    add(Grey("..."), nil, 8)
                    break
                end
                local tags = {}
                if healer and m.name == healer.name then tags[#tags + 1] = "|cFF33FF33" .. L("GRP_HEALER") .. "|r" end
                if m.ss then tags[#tags + 1] = "|cFFCC66FF" .. L("GRP_SS") .. "|r" end
                if m.wocky then tags[#tags + 1] = "|cFF8787EDW|r" end
                local where
                if not m.online then where = "|cFF777777" .. L("GRP_OFFLINE") .. "|r"
                elseif m.dead then where = "|cFFFF5555" .. L("GRP_DEAD") .. "|r"
                elseif m.otherZone then where = "|cFFFF8833" .. (m.zone or L("GRP_FAR")) .. "|r"
                elseif m.far then where = "|cFFFFD100" .. L("GRP_FAR") .. "|r"
                else where = Grey(L("GRP_NEAR")) end
                local name = "|cFF" .. (CLASS_HEX[m.cls or ""] or "DDDDDD") .. m.name .. "|r"
                local line = name .. "  " .. Grey(tostring(m.level or "?")) .. "  " .. table.concat(tags, " ") .. "  " .. where
                local mname = m.name
                add(line, L("GRP_CLICK_HEALER") .. (m.wocky and ("\nWockyPro " .. tostring(m.wocky)) or ""), 8,
                    function() SetHealer(mname); Fill() end)
            end
        end
    end

    -- 2. Stones
    head(L("GRP_STONES"))
    local hs, ss = Bags()
    local holder, sure, left = SSHolder()
    if holder then
        local t = sure and L("GRP_SS_ON", holder) or L("GRP_SS_CAST", holder, math.ceil((left or 0) / 60))
        add(t, nil, 8)
    elseif grouped then
        local h = Healer()
        local t = h and L("GRP_SS_NONE_HEALER", h.name) or L("GRP_SS_NONE")
        if ss == 0 then t = t .. Grey(" - " .. L("GRP_SS_MAKE")) end
        add("|cFFFF8833" .. t .. "|r", nil, 8)
    else
        add(Grey(L("GRP_SS_SOLO")), nil, 8)
    end
    local size = grouped and (#members + 1) or 1
    local color = (hs >= size) and "|cFF33FF33" or "|cFFFFFFFF"
    add(color .. L("GRP_HS_COUNT", hs, size) .. "|r", L("GRP_HS_TIP"), 8)

    -- 3. Summon
    head(L("GRP_SUMMON"))
    local far = FarMembers()
    if not KnowsRitual() then
        add(Grey(L("GRP_SUMMON_UNKNOWN")), nil, 8)
    elseif not grouped then
        add(Grey(L("GRP_SOLO")), nil, 8)
    elseif #far == 0 then
        add(L("GRP_SUMMON_NONE"), nil, 8)
    else
        local _, _, shards = Bags()
        add(L("GRP_SUMMON_HINT", #far, shards), nil, 8)
        for i, m in ipairs(far) do
            if i > 6 then break end
            local mname = m.name
            add("|cFFFFFFFF" .. m.name .. "|r  " .. Grey(m.zone or L("GRP_FAR")), L("GRP_SUMMON_CLICK"), 16,
                function() AnnounceSummon(mname) end)
        end
    end

    -- 4. Dungeon quests
    head(L("DQ_TITLE"))
    local order, byD = DungeonQuestList()
    if #order == 0 then
        add(Grey(L("DQ_NONE")), nil, 8)
    else
        local lines = 0
        for _, name in ipairs(order) do
            if lines >= MAX_DQ_LINES then
                add(Grey("..."), nil, 8)
                break
            end
            local d = DungeonOf(name)
            local range = d and (" " .. Grey(d[2] .. "-" .. d[3] .. "  " .. tostring(d[4]))) or ""
            add("|cFF9999FF" .. name .. "|r" .. range, nil, 8)
            lines = lines + 1
            local list = byD[name]
            if #list == 0 then
                add(Grey(L("DQ_EMPTY")), nil, 16)
                lines = lines + 1
            end
            for _, q in ipairs(list) do
                if lines >= MAX_DQ_LINES then break end
                local state
                if q.log and q.log.complete then state = "|cFF33FF33" .. L("DQ_READY") .. "|r"
                elseif q.log then state = "|cFFFFD100" .. L("DQ_IN_LOG") .. "|r"
                else state = Grey(L("DQ_OPEN")) end
                local g = q.giver
                local tip
                local click
                if q.log then
                    tip = L("DQ_CLICK_SHARE")
                    local e = q.log
                    click = function() ShareQuest(e) end
                end
                if type(g) == "table" and g[3] and g[4] and g[5] then
                    local gtext = L("DQ_GIVER", tostring(g[2] or "?"), tostring(g[3]), g[4], g[5])
                    tip = tip and (tip .. "\n" .. gtext) or (gtext .. "\n" .. L("DQ_CLICK_ARROW"))
                    if not click and W.SetArrowTarget then
                        click = function() W.SetArrowTarget(g[3], g[4], g[5], g[2] or q.n, true) end
                    end
                end
                add("- " .. tostring(q.n) .. (q.lv and Grey(" [" .. q.lv .. "]") or "") .. "  " .. state, tip, 16, click)
                lines = lines + 1
            end
        end
    end
    add(Grey(L("DQ_HINT")), nil, 8)

    -- 5. Runs
    head(L("RUN_TITLE"))
    local g = Store()
    if g.cur then
        SampleXP()
        add("|cFF33FF33" .. L("RUN_NOW") .. "|r " .. RunText(g.cur), nil, 8)
    end
    for i, r in ipairs(g.runs) do
        if i > 3 then break end
        add(Grey(RunText(r)), nil, 8)
    end
    if not g.cur and #g.runs == 0 then add(Grey(L("RUN_NONE")), nil, 8) end

    for j = n + 1, #rows do rows[j]:Hide() end
    y = y - 6
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
    frame.hint:SetText(Grey(L("GRP_HINT")))
    local hh = 14
    pcall(function() hh = math.ceil(frame.hint:GetStringHeight() or 14) end)
    frame:SetHeight(math.max(140, -y + hh + 16))
end

local function Refresh()
    if frame and frame:IsShown() and not InCombat() then
        local ok, err = pcall(Fill)
        if not ok and geterrorhandler then pcall(geterrorhandler(), err) end
    end
end

local function ShowGroup()
    if not frame then frame = CreateFrameUI() end
    frame:Show()
    Refresh()
end

local function ToggleGroup()
    if frame and frame:IsShown() then frame:Hide() else ShowGroup() end
end

W.ShowGroupTools = ShowGroup
W.ToggleGroupTools = ToggleGroup

---------------------------------------------------------------------------
-- Reminders in the guide window
---------------------------------------------------------------------------
local baseReminders = W.ExtraReminders
W.ExtraReminders = function(list)
    if baseReminders then pcall(baseReminders, list) end
    if not Cfg("groupMode") or not IsWarlock() or not InGroup() then return end
    pcall(function()
        local level = PlayerLevel()
        local hs, ss = Bags()
        if Cfg("groupSSRemind") and level >= 18 and ss > 0 and not SSHolder() then
            local h = Healer()
            if h then list[#list + 1] = L("REMIND_SS_HEALER", h.name) end
        end
        if Cfg("groupHSRemind") and level >= 10 and InstanceName() and hs < #members + 1 then
            list[#list + 1] = L("REMIND_HS_GROUP", hs, #members + 1)
        end
        if Cfg("groupSummon") then
            local far = 0
            for _, m in ipairs(members) do if m.otherZone and m.online and not m.dead then far = far + 1 end end
            if far > 0 and KnowsRitual() then list[#list + 1] = L("REMIND_SUMMON", far) end
        end
    end)
end

---------------------------------------------------------------------------
-- Right-click on the dungeon line
---------------------------------------------------------------------------
local dbtn = W.dungeonBtn
if dbtn then
    pcall(function()
        dbtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local baseClick = dbtn:GetScript("OnClick")
        dbtn:SetScript("OnClick", function(self, mouse, ...)
            if mouse == "RightButton" then ToggleGroup()
            elseif baseClick then baseClick(self, mouse, ...) end
        end)
        dbtn:HookScript("OnEnter", function()
            GameTooltip:AddLine(L("DQ_RIGHT_CLICK"), 0.45, 0.8, 1)
            GameTooltip:Show()
        end)
    end)
end

---------------------------------------------------------------------------
-- Settings (Group tab)
---------------------------------------------------------------------------
local page = W.pageGroup or W.pageLock
if page then
    W.AddToggle(page, "groupMode", "GRP_OPT_MODE")
    W.AddToggle(page, "groupSSRemind", "GRP_OPT_SS")
    W.AddToggle(page, "groupHSRemind", "GRP_OPT_HS")
    W.AddToggle(page, "groupSummon", "GRP_OPT_SUMMON")
    W.AddToggle(page, "readyCheck", "GRP_OPT_READY")
    W.AddToggle(page, "ssAnnounce", "GRP_OPT_ANNOUNCE")
    W.AddToggle(page, "runSummary", "GRP_OPT_RUNS")
    if W.AddButton then W.AddButton(page, "GRP_OPEN", ShowGroup) end
end

local baseApply = W.OnApply
W.OnApply = function(...)
    if baseApply then pcall(baseApply, ...) end
    Refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
    "UNIT_AURA", "UNIT_CONNECTION", "READY_CHECK", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
    "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
    "PLAYER_UNGHOST", "PLAYER_ALIVE", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_ADDON", "BAG_UPDATE_DELAYED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    local function run()
        queued = false
        if InCombat() then return end
        ScanMembers()
        Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end

ev:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SENT" then
        pcall(OnSpellSent, a1, a2, a3, a4)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        pcall(OnSpellDone, a1, a2, a3)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local r = WockyDB and WockyDB.group and WockyDB.group.cur
        if r then r.kills = (r.kills or 0) + 1 end
    elseif event == "PLAYER_DEAD" then
        local r = WockyDB and WockyDB.group and WockyDB.group.cur
        if r then r.deaths = (r.deaths or 0) + 1 end
    elseif event == "CHAT_MSG_ADDON" then
        if a1 == "WockyPro" then
            local v = Str(a2) and string.match(a2, "^V:(%S+)$")
            local who = ShortName(a4)
            if v and who then wockyUsers[who] = v end
        end
    elseif event == "READY_CHECK" then
        if Cfg("readyCheck") then pcall(CheckList, false) end
        Queue()
    elseif event == "UNIT_AURA" then
        if frame and frame:IsShown() and a1 and (a1 == "player" or string.find(tostring(a1), "^party") or string.find(tostring(a1), "^raid")) then Queue() end
    elseif event == "QUEST_LOG_UPDATE" then
        if not InCombat() then pcall(ScanQuests) end
        if frame and frame:IsShown() then Queue() end
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        pcall(SampleXP)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_UNGHOST"
        or event == "PLAYER_ALIVE" or event == "PLAYER_LOGIN" then
        pcall(CheckInstance)
        Queue()
    elseif event == "PLAYER_REGEN_ENABLED" then
        pcall(SampleXP)
        Queue()
    else
        Queue()
    end
end)

---------------------------------------------------------------------------
-- Slash command and help
---------------------------------------------------------------------------
W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky group", "HELP_GROUP" })
table.insert(W.EXTRA_HELP, { "/wocky ready", "HELP_READY" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "group" or m == "party" or m == "dungeon" or m == "summon" then
        ToggleGroup()
    elseif m == "ready" or m == "check" then
        CheckList(false)
    elseif m == "group runs" or m == "runs" then
        local g = Store()
        if g.cur then Chat(L("RUN_NOW") .. " " .. RunText(g.cur)) end
        for _, r in ipairs(g.runs) do Chat(RunText(r)) end
        if not g.cur and #g.runs == 0 then Chat(L("RUN_NONE")) end
    elseif m == "group end" then
        if Store().cur then EndRun() else Chat(L("RUN_NONE")) end
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._GrpScan = ScanMembers
W._GrpHealer = Healer
W._GrpSSHolder = SSHolder
W._GrpFar = FarMembers
W._GrpProblems = Problems
W._GrpScanQuests = ScanQuests
W._GrpDQ = DungeonQuestList
W._GrpCheckInstance = CheckInstance
W._GrpRunText = RunText
W._GrpSpellSent = OnSpellSent
W._GrpSpellDone = OnSpellDone
