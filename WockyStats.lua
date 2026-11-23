-- WockyStats: level history and session summary (6.0.0)
--  1. Level history per character: time at each level, XP from quests, from
--     kills and from the rest, money won or spent, deaths.
--  2. /wocky stats: a window with a bar chart (time per level, colored by
--     where the XP came from) and the totals.
--  3. Session summary: this login so far (levels, XP, money, time, deaths);
--     printed in the chat when you log out with /camp or /logout.
-- Only plain numbers from events; nothing is counted from secret values.
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local D = W.DEFAULTS
local MAX = (W.MAX_LEVEL or 60)

if D.sessionSummary == nil then D.sessionSummary = true end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function Num(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return pcall(function() return v + 0 end) and v or nil
end

local function Str(v)
    if type(v) ~= "string" or v == "" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function Call(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return Num(v) end
end

local function Now() return (GetTime and GetTime()) or 0 end
local function Level() return Call(UnitLevel, "player") or 1 end
local function Money() return Call(GetMoney) or 0 end

local function Store()
    WockyDB = WockyDB or {}
    WockyDB.stats = WockyDB.stats or {}
    local key = "?"
    pcall(function() key = W.CharKey() end)
    WockyDB.stats[key] = WockyDB.stats[key] or { levels = {} }
    return WockyDB.stats[key]
end

local function Entry(level)
    local s = Store()
    s.levels[level] = s.levels[level] or { time = 0, quest = 0, kill = 0, other = 0, money = 0, deaths = 0 }
    return s.levels[level]
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------
local session = { start = nil, level = 1, xp = 0, money = 0, deaths = 0, quests = 0, kills = 0 }
local lastXP, lastMax, lastMoney, curLevel
local pendingQuest = 0   -- quest XP told by QUEST_TURNED_IN, matched by the next XP change
local pendingKill = 0

local function SampleXP()
    local xp, max = Call(UnitXP, "player"), Call(UnitXPMax, "player")
    local lv = Level()
    if not xp or not max then return end
    if lastXP and curLevel then
        local gain = 0
        if lv == curLevel then
            gain = xp - lastXP
        elseif lv > curLevel and lastMax then
            gain = (lastMax - lastXP) + xp
        end
        if gain > 0 then
            local e = Entry(curLevel)
            local q = math.min(gain, pendingQuest)
            local k = math.min(gain - q, pendingKill)
            pendingQuest, pendingKill = pendingQuest - q, pendingKill - k
            e.quest = e.quest + q
            e.kill = e.kill + k
            e.other = e.other + (gain - q - k)
            session.xp = session.xp + gain
        end
    end
    lastXP, lastMax = xp, max
end

local function SampleMoney()
    local m = Money()
    if lastMoney and curLevel then
        Entry(curLevel).money = Entry(curLevel).money + (m - lastMoney)
    end
    lastMoney = m
end

local tickAt
local function AddTime()
    local now = Now()
    if tickAt and curLevel then
        local d = now - tickAt
        if d > 0 and d < 120 then Entry(curLevel).time = Entry(curLevel).time + d end
    end
    tickAt = now
end

-- "<mob> dies, you gain <n> experience." in the player's language
local killPatterns
local function KillPatterns()
    if killPatterns then return killPatterns end
    killPatterns = {}
    for _, g in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION2",
        "COMBATLOG_XPGAIN_EXHAUSTION4", "COMBATLOG_XPGAIN_EXHAUSTION5" }) do
        local fmt = rawget(_G, g)
        if type(fmt) == "string" then
            local p = string.gsub(fmt, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            p = string.gsub(p, "%%%%s", ".-")
            -- the first %d is the XP
            p = string.gsub(p, "%%%%d", "(%%d+)", 1)
            p = string.gsub(p, "%%%%d", "%%d+")
            killPatterns[#killPatterns + 1] = "^" .. p
        end
    end
    killPatterns[#killPatterns + 1] = "dies, you gain (%d+) experience"
    return killPatterns
end

local function OnXPMessage(msg)
    msg = Str(msg)
    if not msg then return end
    for _, p in ipairs(KillPatterns()) do
        local n = tonumber(string.match(msg, p))
        if n then
            pendingKill = pendingKill + n
            session.kills = session.kills + 1
            return
        end
    end
end

local function OnLevelUp(newLevel)
    SampleXP()
    AddTime()
    SampleMoney()
    if curLevel then
        local e = Entry(curLevel)
        e.done = true
        e.at = (time and time()) or nil
    end
    curLevel = Num(newLevel) or Level()
    lastXP = Call(UnitXP, "player")
    lastMax = Call(UnitXPMax, "player")
end

local function Start()
    curLevel = Level()
    lastXP = Call(UnitXP, "player")
    lastMax = Call(UnitXPMax, "player")
    lastMoney = Money()
    tickAt = Now()
    session = { start = Now(), level = curLevel, xp = 0, money = Money(), deaths = 0, quests = 0, kills = 0 }
end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
local function Dur(sec)
    sec = math.floor(sec or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%d:%02d h", h, m) end
    return string.format("%d min", m)
end

local function Coins(c)
    local sign = c < 0 and "-" or "+"
    local a = math.abs(c)
    return sign .. ((W.CoinText and W.CoinText(a)) or tostring(a))
end

local function ShortNum(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

local function SessionText()
    AddTime()
    local mins = (session.start and (Now() - session.start)) or 0
    local lv = Level() - (session.level or Level())
    local rate = mins > 60 and (session.xp / mins * 3600) or 0
    return L("ST_SESSION", lv, ShortNum(session.xp), Coins(Money() - (session.money or 0)), Dur(mins), session.deaths or 0, ShortNum(rate))
end
W.SessionText = SessionText

local function Totals()
    local s = Store()
    local t = { time = 0, quest = 0, kill = 0, other = 0, money = 0, deaths = 0, levels = 0, done = 0 }
    for lv, e in pairs(s.levels) do
        t.time = t.time + (e.time or 0)
        t.quest = t.quest + (e.quest or 0)
        t.kill = t.kill + (e.kill or 0)
        t.other = t.other + (e.other or 0)
        t.money = t.money + (e.money or 0)
        t.deaths = t.deaths + (e.deaths or 0)
        t.levels = t.levels + 1
        if e.done then t.done = t.done + 1 end
    end
    return t
end

local function LevelTip(lv, e)
    local xp = (e.quest or 0) + (e.kill or 0) + (e.other or 0)
    local function pct(v) return xp > 0 and math.floor(v / xp * 100 + 0.5) or 0 end
    return {
        { L("ST_LEVEL", lv) .. (e.done and "" or (" |cFF999999(" .. L("ST_NOW") .. ")|r")), 1, 0.82, 0 },
        { L("ST_TIME", Dur(e.time)), 1, 1, 1 },
        { L("ST_XP_SPLIT", pct(e.quest or 0), pct(e.kill or 0), pct(e.other or 0)), 1, 1, 1 },
        { L("ST_MONEY", Coins(e.money or 0)), 1, 1, 1 },
        { L("ST_DEATHS", e.deaths or 0), 1, 1, 1 }
    }
end

W.StatsInfo = function()
    local t = Totals()
    return "levels " .. t.levels .. ", time " .. Dur(t.time) .. ", deaths " .. t.deaths .. "; " .. SessionText()
end

---------------------------------------------------------------------------
-- Stats window with a bar chart
---------------------------------------------------------------------------
local frame
local bars = {}
local CHART_W, CHART_H = 480, 120
local BAR_W = 7
local COLORS = { quest = { 0.95, 0.75, 0.1 }, kill = { 0.85, 0.25, 0.25 }, other = { 0.45, 0.45, 0.9 } }
local CB_COLORS = { quest = { 0.94, 0.89, 0.26 }, kill = { 0.84, 0.37, 0 }, other = { 0.34, 0.71, 0.91 } }

local function Colors() return Cfg("colorblind") and CB_COLORS or COLORS end

local function CreateUI()
    local f = CreateFrame("Frame", "WockyStatsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(CHART_W + 28, CHART_H + 160)
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
        f:SetBackdropColor(0, 0, 0, 0.94)
        f:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
    end)
    pcall(function() table.insert(UISpecialFrames, "WockyStatsFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.title:SetWidth(CHART_W - 40)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    f.chart = CreateFrame("Frame", nil, f)
    f.chart:SetSize(CHART_W, CHART_H)
    f.chart:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    local bg = f.chart:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f.chart)
    bg:SetColorTexture(1, 1, 1, 0.04)
    f.axis = W.NewFS(f, W.fonts.small)
    f.axis:SetPoint("TOPLEFT", f.chart, "BOTTOMLEFT", 0, -2)
    f.axis:SetWidth(CHART_W)
    f.axis:SetJustifyH("LEFT")
    f.legend = W.NewFS(f, W.fonts.small)
    f.legend:SetPoint("TOPLEFT", f.axis, "BOTTOMLEFT", 0, -4)
    f.legend:SetWidth(CHART_W)
    f.legend:SetJustifyH("LEFT")
    f.totals = W.NewFS(f, W.fonts.small)
    f.totals:SetPoint("TOPLEFT", f.legend, "BOTTOMLEFT", 0, -8)
    f.totals:SetWidth(CHART_W)
    f.totals:SetJustifyH("LEFT")
    f.session = W.NewFS(f, W.fonts.small)
    f.session:SetPoint("TOPLEFT", f.totals, "BOTTOMLEFT", 0, -6)
    f.session:SetWidth(CHART_W)
    f.session:SetJustifyH("LEFT")

    for lv = 1, MAX do
        local b = CreateFrame("Button", nil, f.chart)
        b:SetSize(BAR_W, 1)
        b:SetPoint("BOTTOMLEFT", f.chart, "BOTTOMLEFT", (lv - 1) * (BAR_W + 1), 0)
        b.parts = {}
        for i, k in ipairs({ "quest", "kill", "other" }) do
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetWidth(BAR_W)
            b.parts[k] = t
        end
        b:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for _, line in ipairs(self.tip) do GameTooltip:AddLine(line[1], line[2], line[3], line[4]) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        bars[lv] = b
    end
    f:Hide()
    return f
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    AddTime()
    SampleXP()
    local s = Store()
    local maxT = 60
    for _, e in pairs(s.levels) do if (e.time or 0) > maxT then maxT = e.time end end
    local col = Colors()
    for lv = 1, MAX do
        local b = bars[lv]
        local e = s.levels[lv]
        if e and (e.time or 0) > 0 then
            local h = math.max(2, math.floor((e.time / maxT) * CHART_H))
            b:SetHeight(h)
            local xp = (e.quest or 0) + (e.kill or 0) + (e.other or 0)
            local y = 0
            for _, k in ipairs({ "quest", "kill", "other" }) do
                local t = b.parts[k]
                local share = xp > 0 and ((e[k] or 0) / xp) or (k == "other" and 1 or 0)
                local ph = math.floor(h * share + 0.5)
                if k == "other" then ph = h - y end
                t:ClearAllPoints()
                if ph > 0 then
                    t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, y)
                    t:SetHeight(ph)
                    t:SetColorTexture(col[k][1], col[k][2], col[k][3], e.done and 0.95 or 0.55)
                    t:Show()
                else
                    t:Hide()
                end
                y = y + math.max(0, ph)
            end
            b.tip = LevelTip(lv, e)
            b:Show()
        else
            b.tip = nil
            b:Hide()
        end
    end
    frame.title:SetText("|cFF8787EDWockyPro|r - " .. L("ST_TITLE"))
    frame.axis:SetText("|cFF999999" .. L("ST_AXIS", Dur(maxT)) .. "|r")
    -- a small colored square (texture escape with a color)
    local function sw(c)
        return string.format("|TInterface\\Buttons\\WHITE8x8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t", c[1] * 255, c[2] * 255, c[3] * 255)
    end
    frame.legend:SetText(sw(col.quest) .. " " .. L("ST_QUEST") .. "   " .. sw(col.kill) .. " " .. L("ST_KILL") .. "   "
        .. sw(col.other) .. " " .. L("ST_OTHER"))
    local t = Totals()
    local xp = t.quest + t.kill + t.other
    local function pct(v) return xp > 0 and math.floor(v / xp * 100 + 0.5) or 0 end
    local avg = t.done > 0 and (t.time / math.max(1, t.levels)) or t.time
    frame.totals:SetText(L("ST_TOTALS", t.levels, Dur(t.time), Dur(avg), pct(t.quest), pct(t.kill), Coins(t.money), t.deaths))
    frame.session:SetText("|cFFFFD100" .. L("ST_SESSION_HEAD") .. "|r " .. SessionText())
end

local function ShowStats()
    if not frame then frame = CreateUI() end
    if frame:IsShown() then frame:Hide() return end
    frame:Show()
    Refresh()
end
W.ShowStats = ShowStats

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "PLAYER_DEAD",
    "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_CAMPING", "PLAYER_REGEN_ENABLED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
ev:SetScript("OnEvent", function(self, event, a1, a2, a3)
    if event == "PLAYER_LOGIN" then
        pcall(Start)
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        pcall(SampleXP)
    elseif event == "PLAYER_LEVEL_UP" then
        pcall(OnLevelUp, a1)
    elseif event == "PLAYER_MONEY" then
        pcall(SampleMoney)
    elseif event == "PLAYER_DEAD" then
        pcall(function()
            if curLevel then Entry(curLevel).deaths = Entry(curLevel).deaths + 1 end
            session.deaths = (session.deaths or 0) + 1
        end)
    elseif event == "QUEST_TURNED_IN" then
        local xp = Num(a2)
        if xp and xp > 0 then pendingQuest = pendingQuest + xp end
        session.quests = (session.quests or 0) + 1
        -- the XP event may already have come: count it at the next change
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        pcall(OnXPMessage, a1)
    elseif event == "PLAYER_CAMPING" then
        if Cfg("sessionSummary") then pcall(function() Chat(L("ST_SESSION_HEAD") .. " " .. SessionText()) end) end
    end
    if frame and frame:IsShown() then pcall(Refresh) end
end)

local acc = 0
ev:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 10 then return end
    acc = 0
    pcall(AddTime)
end)

if W.pageUI then
    W.AddToggle(W.pageUI, "sessionSummary", "ST_OPT_SUMMARY")
    if W.AddButton then W.AddButton(W.pageUI, "ST_OPEN", function() ShowStats() end) end
end

W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky stats", "HELP_STATS" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "stats" or m == "history" then
        ShowStats()
    elseif m == "session" then
        Chat(L("ST_SESSION_HEAD") .. " " .. SessionText())
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._STEntry = Entry
W._STLevelUp = OnLevelUp
W._STSample = SampleXP
W._STXPMsg = OnXPMessage
W._STTotals = Totals
