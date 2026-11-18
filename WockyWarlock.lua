-- WockyWarlock: Warlock tools (5.0.0)
-- /wocky lock (or right-click on the shard count) opens a small window with:
--  1. Demon advisor: which of your demons fits right now (solo, group, enemy caster)
--  2. Soul Shards: count, a "too many" limit with a warning, soul bag reminder
--  3. Trainer planner: spells and costs of your next trainer visits. The list is saved
--     from the game's own trainer window (Forever changed spells, so nothing is guessed)
--  4. Money goals: savings bars for the level 40 and 60 mounts plus training costs
-- No casting, no item use: advice only.
local W = WockyAPI
if not W then return end

local L, Cfg, SetCfg = W.L, W.Cfg, W.SetCfg
local SHARD_ID = 6265
local D = W.DEFAULTS

if D.demonAdvice == nil then D.demonAdvice = true end
if D.demonStyle == nil then D.demonStyle = "safe" end
if D.shardMax == nil then D.shardMax = 20 end
if D.shardWarn == nil then D.shardWarn = true end
if D.soulBagRemind == nil then D.soulBagRemind = true end
if D.moneyGoals == nil then D.moneyGoals = true end
-- Mount prices in gold. Round placeholder amounts, not Forever data: the player sets them
-- in the settings (Warlock tab). TODO: replace with checked Forever prices once known.
if D.goal40 == nil then D.goal40 = 100 end
if D.goal60 == nil then D.goal60 = 1000 end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function Safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function Low(s) return string.lower(tostring(s or "")) end

local function InCombat()
    local c = false
    pcall(function()
        c = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    end)
    return c and true or false
end

-- a plain number that addon code may use (never a secret value)
local function Num(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    local ok = pcall(function() return v + 0 end)
    return ok and v or nil
end

local function PlayerLevel()
    return Num(UnitLevel and Safe(UnitLevel, "player")) or 1
end

local function IsWarlock()
    local _, cls = nil, nil
    pcall(function() _, cls = UnitClass("player") end)
    return cls == "WARLOCK"
end

local function Money()
    return Num(GetMoney and Safe(GetMoney)) or 0
end

local function Gold(c) return (W.CoinText and W.CoinText(c)) or tostring(c) end

---------------------------------------------------------------------------
-- 1. Demon advisor
---------------------------------------------------------------------------
-- Summon spells (Classic IDs, each checked in game; an unknown ID is skipped)
local DEMONS = {
    { key = "imp", spell = 688, en = "Imp", name = "DEMON_IMP", use = "DEMON_USE_IMP" },
    { key = "void", spell = 697, en = "Voidwalker", name = "DEMON_VOID", use = "DEMON_USE_VOID" },
    { key = "succ", spell = 712, en = "Succubus", name = "DEMON_SUCC", use = "DEMON_USE_SUCC" },
    { key = "felh", spell = 691, en = "Felhunter", name = "DEMON_FELH", use = "DEMON_USE_FELH" }
}
local DEMON_BY_KEY = {}
for _, d in ipairs(DEMONS) do DEMON_BY_KEY[d.key] = d end

local function SpellName(id)
    local n
    pcall(function()
        if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
        if not n and GetSpellInfo then n = GetSpellInfo(id) end
    end)
    if type(n) == "string" and n ~= "" then return n end
end

local function KnowsSpell(id)
    local known = false
    pcall(function()
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then known = true end
    end)
    if not known then
        -- by name: GetSpellInfo(name) only answers for spells in your spellbook
        local n = SpellName(id)
        if n then
            pcall(function()
                local sid = GetSpellInfo and select(7, GetSpellInfo(n))
                if type(sid) == "number" then known = true end
            end)
        end
    end
    return known
end

local knownCache, knownAt = nil, -100
local function KnownDemons()
    local now = (GetTime and Safe(GetTime)) or 0
    if knownCache and now - knownAt < 10 then return knownCache end
    local k = {}
    for _, d in ipairs(DEMONS) do
        if KnowsSpell(d.spell) then k[d.key] = true end
    end
    knownCache, knownAt = k, now
    return k
end

-- the demon you have out now: "imp" ... "felh", "other" or nil
local function CurrentDemon()
    local out
    pcall(function()
        if not (UnitExists and UnitExists("pet")) then return end
        local fam = UnitCreatureFamily and UnitCreatureFamily("pet")
        out = "other"
        if type(fam) ~= "string" or fam == "" then return end
        local f = Low(fam)
        for _, d in ipairs(DEMONS) do
            local sn = SpellName(d.spell)
            if f == Low(d.en) or (sn and string.find(Low(sn), f, 1, true)) then
                out = d.key
                return
            end
        end
    end)
    return out
end

local function InGroup()
    local g = false
    pcall(function()
        if IsInGroup then g = IsInGroup() and true or false
        elseif GetNumGroupMembers then g = (GetNumGroupMembers() or 0) > 0
        elseif GetNumPartyMembers then g = (GetNumPartyMembers() or 0) > 0 end
    end)
    return g
end

-- an enemy that uses mana is a caster
local function TargetIsCaster()
    local caster = false
    pcall(function()
        if not (UnitExists and UnitExists("target")) then return end
        if UnitIsDead and UnitIsDead("target") then return end
        if UnitCanAttack and not UnitCanAttack("player", "target") then return end
        local pt = Num(UnitPowerType and UnitPowerType("target"))
        caster = (pt == 0)
    end)
    return caster
end

local lastAdvice
-- { key, why } or nil when you know no demon yet. In combat: the last advice, nothing new.
local function Advise()
    if InCombat() then return lastAdvice end
    local k = KnownDemons()
    local pick, why
    if k.felh and TargetIsCaster() then
        pick, why = "felh", "DEMON_WHY_CASTER"
    elseif k.imp and InGroup() then
        pick, why = "imp", "DEMON_WHY_GROUP"
    elseif k.succ and Cfg("demonStyle") == "fast" then
        pick, why = "succ", "DEMON_WHY_FAST"
    elseif k.void then
        pick, why = "void", "DEMON_WHY_SOLO"
    elseif k.imp then
        pick, why = "imp", "DEMON_WHY_LOW"
    end
    lastAdvice = pick and { key = pick, why = why } or nil
    return lastAdvice
end

local function DemonName(key)
    local d = DEMON_BY_KEY[key]
    return d and L(d.name) or "?"
end

---------------------------------------------------------------------------
-- 2. Soul Shards
---------------------------------------------------------------------------
local SOUL_BAG_FLAG = 4 -- bag family bit for soul bags

local function HasFlag(v, flag)
    v = Num(v)
    if not v then return false end
    return math.floor(v / flag) % 2 == 1
end

-- total shards, shards in normal bags, soul bag present
local function ShardInfo()
    local total, inNormal, soulBag = 0, 0, false
    pcall(function()
        local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
        local getID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
        local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
        if not getSlots or not getID then return end
        for bag = 0, 4 do
            local isSoul = false
            if bag > 0 and getFree then
                local _, bagType = getFree(bag)
                isSoul = HasFlag(bagType, SOUL_BAG_FLAG)
                if isSoul then soulBag = true end
            end
            local slots = Num(getSlots(bag)) or 0
            for slot = 1, slots do
                if getID(bag, slot) == SHARD_ID then
                    total = total + 1
                    if not isSoul then inNormal = inNormal + 1 end
                end
            end
        end
    end)
    return total, inNormal, soulBag
end

-- chat message once when the count passes the limit; again only after it dropped below
local warnedAbove, warnedMax = false, nil
local function CheckShardChat()
    if not Cfg("shardWarn") or not IsWarlock() or InCombat() then return end
    local total = ShardInfo()
    local max = Cfg("shardMax") or 20
    if max ~= warnedMax then warnedAbove = false end
    warnedMax = max
    if total > max then
        if not warnedAbove then
            warnedAbove = true
            Chat(L("SHARD_CHAT_MAX", total, max))
        end
    else
        warnedAbove = false
    end
end

---------------------------------------------------------------------------
-- 3. Trainer planner (data saved from the trainer window)
---------------------------------------------------------------------------
local function TrainerDB()
    WockyDB = WockyDB or {}
    local t = WockyDB.lockTrainer
    if type(t) ~= "table" then
        t = {}
        WockyDB.lockTrainer = t
    end
    t.spells = t.spells or {}
    t.used = t.used or {}
    return t
end

local function UsedSet()
    local t = TrainerDB()
    local key = (W.CharKey and Safe(W.CharKey)) or "?"
    t.used[key] = t.used[key] or {}
    return t.used[key]
end

local function ScanTrainer()
    if not IsWarlock() or not GetNumTrainerServices then return 0 end
    local isProf = false
    pcall(function() isProf = IsTradeskillTrainer and IsTradeskillTrainer() end)
    if isProf then return 0 end
    local t, used, n = TrainerDB(), UsedSet(), 0
    pcall(function()
        local count = Num(GetNumTrainerServices()) or 0
        for i = 1, count do
            local name, rank, category = GetTrainerServiceInfo(i)
            if type(name) == "string" and name ~= "" and category ~= "header" then
                local key = name .. "|" .. tostring(rank or "")
                local lv = GetTrainerServiceLevelReq and Num(GetTrainerServiceLevelReq(i))
                local cost = GetTrainerServiceCost and Num(GetTrainerServiceCost(i))
                local e = t.spells[key] or {}
                e.n, e.r = name, (rank ~= "" and rank) or nil
                if lv then e.lv = lv end
                if cost then e.c = cost end
                t.spells[key] = e
                if category == "used" then used[key] = true end
                n = n + 1
            end
        end
        if time then t.seen = time() end
    end)
    return n
end

-- spells you have not learned with fromLv <= level <= toLv: list, total cost
local function TrainPlan(fromLv, toLv)
    local t, used = TrainerDB(), UsedSet()
    local list, cost = {}, 0
    for key, e in pairs(t.spells) do
        if type(e) == "table" and not used[key] and e.lv and e.lv >= fromLv and e.lv <= toLv then
            list[#list + 1] = e
            cost = cost + (e.c or 0)
        end
    end
    table.sort(list, function(a, b)
        if a.lv ~= b.lv then return a.lv < b.lv end
        return tostring(a.n) < tostring(b.n)
    end)
    return list, cost
end

local function TrainCount()
    local n = 0
    for _ in pairs(TrainerDB().spells) do n = n + 1 end
    return n
end

-- the next level above `level` that has spells to learn
local function NextTrainLevel(level)
    local best
    local used = UsedSet()
    for key, e in pairs(TrainerDB().spells) do
        if type(e) == "table" and e.lv and e.lv > level and not used[key] and (not best or e.lv < best) then best = e.lv end
    end
    return best
end

---------------------------------------------------------------------------
-- 4. Money goals
---------------------------------------------------------------------------
local function Goals()
    local level = PlayerLevel()
    local out = {}
    for _, g in ipairs({ { 40, "goal40", "LOCK_GOAL_40" }, { 60, "goal60", "LOCK_GOAL_60" } }) do
        if level < g[1] then
            local _, train = TrainPlan(1, g[1])
            local need = (Num(Cfg(g[2])) or 0) * 10000 + train
            local have = Money()
            local pct = need > 0 and math.min(100, math.floor(have * 100 / need)) or 100
            out[#out + 1] = { level = g[1], label = L(g[3]), need = need, have = have, pct = pct, train = train }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Text for the report and the tests
---------------------------------------------------------------------------
local function InfoText()
    local r = {}
    local adv = Advise()
    r[#r + 1] = "Demon: " .. tostring(CurrentDemon() or "-") .. " / best " .. (adv and (adv.key .. " (" .. adv.why .. ")") or "-")
    local total, inNormal, soulBag = ShardInfo()
    r[#r + 1] = "Shards: " .. total .. "/" .. tostring(Cfg("shardMax")) .. (soulBag and ", soul bag" or ", no soul bag") .. ", " .. inNormal .. " in normal bags"
    local level = PlayerLevel()
    local now, nowCost = TrainPlan(1, level)
    r[#r + 1] = "Trainer list: " .. TrainCount() .. " spells, learn now " .. #now .. " (" .. nowCost .. "c)"
    for _, g in ipairs(Goals()) do r[#r + 1] = "Goal L" .. g.level .. ": " .. g.pct .. "%" end
    return table.concat(r, "; ")
end
W.WarlockInfo = InfoText

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
    b.barBg = b:CreateTexture(nil, "BACKGROUND")
    b.barBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    b.barBg:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.barBg:SetHeight(5)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetColorTexture(0.6, 0.2, 0.8, 1)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.bar:SetHeight(5)
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
    local f = CreateFrame("Frame", "WockyLockFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(424, 200)
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
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
    end)
    pcall(function() table.insert(UISpecialFrames, "WockyLockFrame") end)

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

local MAX_TRAIN_LINES = 8

local function Fill()
    local level = PlayerLevel()
    local n, y = 0, -36
    local function add(text, tip, indent, pct)
        n = n + 1
        local b = Row(n)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (indent or 0), y)
        b.text:SetWidth(ROW_W - (indent or 0))
        b.text:SetText(text)
        local h = 14
        pcall(function() h = math.max(14, math.ceil(b.text:GetStringHeight() or 14)) end)
        if pct then
            local w = ROW_W - (indent or 0)
            b.barBg:SetWidth(w)
            b.bar:SetWidth(math.max(1, w * math.min(100, pct) / 100))
            if pct >= 100 then b.bar:SetColorTexture(0.2, 0.8, 0.3, 1) else b.bar:SetColorTexture(0.6, 0.2, 0.8, 1) end
            b.barBg:Show()
            b.bar:Show()
            h = h + 7
        else
            b.barBg:Hide()
            b.bar:Hide()
        end
        b:SetHeight(h)
        b.tip = tip
        b:Show()
        y = y - h - 3
    end
    local function head(text)
        y = y - 4
        add("|cFFFFD100" .. text .. "|r")
    end

    frame.title:SetText("|cFF8787EDWockyPro|r - " .. L("LOCK_TITLE", level))

    -- 1. Demon
    head(L("LOCK_DEMON"))
    local cur = CurrentDemon()
    if cur and cur ~= "other" then
        add(L("LOCK_DEMON_NOW", DemonName(cur)), nil, 8)
    elseif cur == "other" then
        add(L("LOCK_DEMON_NOW", "?"), nil, 8)
    else
        add(L("LOCK_DEMON_NONE"), nil, 8)
    end
    local adv = Advise()
    if adv then
        local mark = (cur == adv.key) and ("  |cFF33FF33" .. L("LOCK_DEMON_OK") .. "|r") or ""
        add(L("LOCK_DEMON_BEST", "|cFFFFFFFF" .. DemonName(adv.key) .. "|r", L(adv.why)) .. mark, nil, 8)
    end
    local k = KnownDemons()
    for _, d in ipairs(DEMONS) do
        if k[d.key] then add("|cFF999999- " .. L(d.use) .. "|r", nil, 16) end
    end

    -- 2. Shards
    head(L("LOCK_SHARDS"))
    local total, inNormal, soulBag = ShardInfo()
    local max = Cfg("shardMax") or 20
    local color = total > max and "|cFFFF8833" or "|cFFFFFFFF"
    add(color .. L("LOCK_SHARD_COUNT", total, max) .. "|r", nil, 8)
    if soulBag then
        add(L("LOCK_SOULBAG_YES", inNormal), nil, 8)
    else
        add(L("LOCK_SOULBAG_NO", inNormal), nil, 8)
    end

    -- 3. Trainer
    head(L("LOCK_TRAINER"))
    if TrainCount() == 0 then
        add(L("LOCK_TRAIN_NONE"), nil, 8)
    else
        local now, nowCost = TrainPlan(1, level)
        if #now == 0 then
            add(L("LOCK_TRAIN_NOTHING"), nil, 8)
        else
            local have = Money()
            add(L("LOCK_TRAIN_NOW", #now, Gold(nowCost)), nil, 8)
            if nowCost > have then
                add("|cFFFF6666" .. L("LOCK_TRAIN_SHORT") .. "|r " .. Gold(nowCost - have), nil, 8)
            end
            for i, e in ipairs(now) do
                if i > MAX_TRAIN_LINES then
                    add("|cFF999999...|r", nil, 16)
                    break
                end
                add("|cFF999999- " .. tostring(e.n) .. (e.r and (" (" .. e.r .. ")") or "") .. "|r", nil, 16)
            end
        end
        local nxt = NextTrainLevel(level)
        if nxt then
            local list, cost = TrainPlan(nxt, nxt)
            local names = {}
            for i, e in ipairs(list) do
                if i <= 4 then names[#names + 1] = tostring(e.n) .. (e.r and (" " .. e.r) or "") end
            end
            add(L("LOCK_TRAIN_NEXT", nxt, #list, Gold(cost)), table.concat(names, "\n"), 8)
        end
        add("|cFF999999" .. L("LOCK_TRAIN_HINT") .. "|r", nil, 8)
    end

    -- 4. Money goals
    if Cfg("moneyGoals") then
        head(L("LOCK_MONEY"))
        local goals = Goals()
        for _, g in ipairs(goals) do
            if g.pct >= 100 then
                add(L("LOCK_GOAL_DONE", g.label), nil, 8, 100)
            else
                add(L("LOCK_GOAL_LINE", g.label, Gold(g.have), Gold(g.need), g.pct), L("LOCK_GOAL_TIP", Gold(g.train)), 8, g.pct)
            end
        end
        add("|cFF999999" .. L("LOCK_GOAL_HINT") .. "|r", nil, 8)
    end

    for j = n + 1, #rows do rows[j]:Hide() end
    y = y - 6
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
    frame.hint:SetText("|cFF999999" .. L("LOCK_HINT") .. "|r")
    local hh = 14
    pcall(function() hh = math.ceil(frame.hint:GetStringHeight() or 14) end)
    frame:SetHeight(math.max(140, -y + hh + 16))
end

local function Refresh()
    if frame and frame:IsShown() then
        local ok, err = pcall(Fill)
        if not ok and geterrorhandler then pcall(geterrorhandler(), err) end
    end
end

local function ShowLock()
    if not frame then frame = CreateFrameUI() end
    frame:Show()
    Refresh()
end

local function ToggleLock()
    if frame and frame:IsShown() then frame:Hide() else ShowLock() end
end

W.ShowWarlockTools = ShowLock
W.ToggleWarlockTools = ToggleLock

---------------------------------------------------------------------------
-- Reminders in the guide window
---------------------------------------------------------------------------
local baseReminders = W.ExtraReminders
W.ExtraReminders = function(list)
    if baseReminders then pcall(baseReminders, list) end
    if not IsWarlock() then return end
    pcall(function()
        local level = PlayerLevel()
        if level >= 10 then
            local total, inNormal, soulBag = ShardInfo()
            local max = Cfg("shardMax") or 20
            if total > max then list[#list + 1] = L("REMIND_SHARDS_MAX", total) end
            if Cfg("soulBagRemind") and not soulBag and inNormal >= 8 then list[#list + 1] = L("REMIND_SOULBAG") end
        end
        if Cfg("demonAdvice") then
            local cur = CurrentDemon()
            local adv = Advise()
            -- only when a demon is out (no demon at all already has its own reminder)
            if adv and cur and cur ~= adv.key then
                list[#list + 1] = L("REMIND_DEMON", DemonName(adv.key), L(adv.why))
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Money tooltip, right-click on the shard count
---------------------------------------------------------------------------
if W.moneyBtn and W.moneyBtn.HookScript then
    W.moneyBtn:HookScript("OnEnter", function()
        if not Cfg("moneyGoals") or not IsWarlock() then return end
        pcall(function()
            for _, g in ipairs(Goals()) do
                GameTooltip:AddLine(L("MONEY_GOAL_TIP", g.label, g.pct), 0.8, 0.6, 1)
            end
            GameTooltip:Show()
        end)
    end)
end

local overlay = W.shardOverlay
if overlay then
    pcall(function()
        overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local baseClick = overlay:GetScript("OnClick")
        overlay:SetScript("OnClick", function(self, mouse, ...)
            if mouse == "RightButton" then
                if W.shardText:IsShown() then ToggleLock() end
            elseif baseClick then
                baseClick(self, mouse, ...)
            end
        end)
        overlay:HookScript("OnEnter", function()
            if not W.shardText:IsShown() then return end
            GameTooltip:AddLine(L("SHARD_RIGHT_CLICK"), 0.45, 0.8, 1)
            GameTooltip:Show()
        end)
    end)
end

---------------------------------------------------------------------------
-- Settings (Warlock tab)
---------------------------------------------------------------------------
local page = W.pageLock
if page then
    W.AddToggle(page, "demonAdvice", "DEMON_ADVICE")
    if W.AddCycle then
        W.AddCycle(page, "DEMON_STYLE", { "safe", "fast" },
            function() return Cfg("demonStyle") end,
            function(v) SetCfg("demonStyle", v) end,
            function(v) return v == "fast" and L("DEMON_STYLE_FAST") or L("DEMON_STYLE_SAFE") end)
    end
    W.AddStepper(page, "shardMax", "SHARD_MAX", 5, 40, 1, function(v) return tostring(v) end)
    W.AddToggle(page, "shardWarn", "SHARD_WARN")
    W.AddToggle(page, "soulBagRemind", "SOULBAG_REMIND")
    W.AddToggle(page, "moneyGoals", "MONEY_GOALS")
    W.AddStepper(page, "goal40", "GOAL_40", 0, 2000, 10, function(v) return tostring(v) end)
    W.AddStepper(page, "goal60", "GOAL_60", 0, 5000, 50, function(v) return tostring(v) end)
    if W.AddButton then W.AddButton(page, "LOCK_OPEN", ShowLock) end
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
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "BAG_UPDATE_DELAYED", "UNIT_PET", "PLAYER_TARGET_CHANGED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_ENABLED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
local queued = false
local function Queue()
    if queued then return end
    queued = true
    local function run()
        queued = false
        Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        pcall(ScanTrainer)
        Queue()
    elseif event == "BAG_UPDATE_DELAYED" then
        pcall(CheckShardChat)
        Queue()
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_LEVEL_UP" then
        knownCache = nil
        Queue()
    elseif event == "UNIT_PET" then
        if arg1 == "player" then Queue() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        pcall(CheckShardChat)
        Queue()
    else
        if frame and frame:IsShown() and not InCombat() then Queue() end
    end
end)

---------------------------------------------------------------------------
-- Slash command and help
---------------------------------------------------------------------------
W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky lock", "HELP_LOCK" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "lock" or m == "warlock" or m == "demon" or m == "shards" or m == "trainer" or m == "goals" then
        ToggleLock()
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._LockAdvise = Advise
W._LockCurrentDemon = CurrentDemon
W._LockShardInfo = ShardInfo
W._LockScanTrainer = ScanTrainer
W._LockTrainPlan = TrainPlan
W._LockGoals = Goals
W._LockNum = Num
