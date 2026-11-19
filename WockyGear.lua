-- WockyGear: gear helpers (5.2.0)
--  1. Stat weights per spec (Affliction, Demonology, Destruction), editable
--     in the settings (Gear tab). The tooltip upgrade score uses them.
--  2. Quest reward choice: marks the best reward for you, or the one that
--     sells best when none is an upgrade. Nothing is picked for you.
--  3. Loot alert: a chat line when an item you loot is an upgrade.
--  4. Wand reminder: no wand, or a wand far below your level.
--  5. Upgrade in your bags: a guide reminder, and /wocky gear lists them.
-- Scores are an estimate from your weights. No item use, no casting.
local W = WockyAPI
if not W then return end

local L, Cfg, SetCfg = W.L, W.Cfg, W.SetCfg
local D = W.DEFAULTS
local SPECS = { "Affliction", "Demonology", "Destruction" }
local STATS = { "sp", "sta", "int", "spi", "wand" }
local STAT_KEYS = { sp = "GEAR_W_SP", sta = "GEAR_W_STA", int = "GEAR_W_INT", spi = "GEAR_W_SPI", wand = "GEAR_W_WAND" }
-- starting weights, an estimate for leveling; players change them in the settings
local BASE = {
    Affliction = { sp = 1.0, sta = 0.7, int = 0.4, spi = 0.5, wand = 2.0 },
    Demonology = { sp = 0.8, sta = 1.0, int = 0.5, spi = 0.4, wand = 2.0 },
    Destruction = { sp = 1.0, sta = 0.5, int = 0.6, spi = 0.2, wand = 2.0 }
}
local W_MIN, W_MAX, W_STEP = 0, 3, 0.1
local MIN_GAIN = 0.5      -- smallest score gain worth a reminder or chat line
local MAX_LOOT = 6

for k, v in pairs({ gearSpec = "auto", gearReward = true, gearLoot = true, gearBagRemind = true,
    wandWarn = true, wandGap = 10 }) do
    if D[k] == nil then D[k] = v end
end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function InCombat()
    local a = InCombatLockdown and InCombatLockdown()
    local b = UnitAffectingCombat and UnitAffectingCombat("player")
    return (a == true) or (b == true)
end

-- a plain string addon code may use (never a secret value)
local function Str(v)
    if type(v) ~= "string" or v == "" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function PlayerLevel()
    local ok, l = pcall(UnitLevel, "player")
    if ok and type(l) == "number" then return l end
    return 1
end

local function Round(v) return math.floor(v * 10 + 0.5) / 10 end

---------------------------------------------------------------------------
-- Weights
---------------------------------------------------------------------------
local function Store()
    WockyDB = WockyDB or {}
    WockyDB.gear = WockyDB.gear or {}
    local g = WockyDB.gear
    g.weights = g.weights or {}
    g.loot = g.loot or {}
    return g
end

local function ActiveSpec()
    local pick = Cfg("gearSpec")
    for _, s in ipairs(SPECS) do if pick == s then return s end end
    local spec
    if W.GetBuildSpec then
        local ok, s = pcall(W.GetBuildSpec)
        if ok then spec = s end
    end
    for _, s in ipairs(SPECS) do if spec == s then return s end end
    return "Affliction"
end

local function Weights(spec)
    spec = spec or ActiveSpec()
    local base = BASE[spec] or BASE.Affliction
    local saved = Store().weights[spec]
    local out = {}
    for _, k in ipairs(STATS) do
        local v = saved and saved[k]
        if type(v) ~= "number" then v = base[k] end
        out[k] = v
    end
    return out
end

local function SetWeight(spec, key, value)
    local g = Store()
    g.weights[spec] = g.weights[spec] or {}
    if value < W_MIN then value = W_MIN end
    if value > W_MAX then value = W_MAX end
    g.weights[spec][key] = Round(value)
end

W.GetWeights = function() return Weights() end
W.GearSpecName = ActiveSpec

local function DiffText(diff, empty)
    if empty then return "|cFF00FF00+" .. string.format("%.1f", diff) .. "|r" end
    return (diff >= 0 and "|cFF00FF00+" or "|cFFFF4040") .. string.format("%.1f", diff) .. "|r"
end

local function Diff(link)
    if not link or not W.UpgradeDiff then return nil end
    local ok, diff, empty, minLevel, new = pcall(W.UpgradeDiff, link)
    if ok then return diff, empty, minLevel, new end
end

local function ItemName(link)
    return Str(link) and string.match(link, "%[(.-)%]") or tostring(link)
end

---------------------------------------------------------------------------
-- Bag upgrades and the wand (scanned out of combat only)
---------------------------------------------------------------------------
local bagUps = {}      -- { link, diff, minLevel }
local wandInfo = nil   -- { link, dps, minLevel } or false for no wand

local function ContainerLink(bag, slot)
    local link
    pcall(function()
        if C_Container and C_Container.GetContainerItemLink then
            link = C_Container.GetContainerItemLink(bag, slot)
        elseif GetContainerItemLink then
            link = GetContainerItemLink(bag, slot)
        end
    end)
    return Str(link)
end

local function NumSlots(bag)
    local n = 0
    pcall(function()
        if C_Container and C_Container.GetContainerNumSlots then n = C_Container.GetContainerNumSlots(bag)
        elseif GetContainerNumSlots then n = GetContainerNumSlots(bag) end
    end)
    return type(n) == "number" and n or 0
end

local function ScanBags()
    local level = PlayerLevel()
    local list, seen = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) do
            local link = ContainerLink(bag, slot)
            if link and not seen[link] then
                seen[link] = true
                local diff, empty, minLevel = Diff(link)
                if diff and (diff >= MIN_GAIN or (empty and diff > 0)) and (not minLevel or minLevel <= level) then
                    list[#list + 1] = { link = link, diff = diff, empty = empty, minLevel = minLevel }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.diff > b.diff end)
    bagUps = list
end

local function ScanWand()
    local link = Str(GetInventoryItemLink and GetInventoryItemLink("player", 18))
    if not link then wandInfo = false; return end
    local info = { link = link, dps = 0, minLevel = nil }
    pcall(function()
        local stats = (C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link))
        if type(stats) == "table" then
            for k, v in pairs(stats) do
                if string.find(string.upper(tostring(k)), "DAMAGE_PER_SECOND") and type(v) == "number" then info.dps = v end
            end
        end
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local v = select(5, get(link))
        if type(v) == "number" then info.minLevel = v end
    end)
    -- only a wand counts (the ranged slot can hold other things)
    local isWand = false
    pcall(function()
        local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local _, _, _, _, _, c, s = get(link)
        isWand = (c == 2 and s == 19)
    end)
    wandInfo = isWand and info or false
end

local scanQueued = false
local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    local function run()
        scanQueued = false
        if InCombat() then return end
        pcall(ScanBags)
        pcall(ScanWand)
        if W.RefreshGear then pcall(W.RefreshGear) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end

---------------------------------------------------------------------------
-- Quest reward choice
---------------------------------------------------------------------------
local badges = {}

local function RewardButton(i)
    local b
    pcall(function()
        local f = QuestInfoRewardsFrame
        if f and f.RewardButtons and f.RewardButtons[i] then b = f.RewardButtons[i] end
    end)
    b = b or _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
    return b
end

local function HideBadges()
    for _, fs in pairs(badges) do pcall(fs.Hide, fs) end
end

local function Badge(button, text, r, g, b)
    if not button or not button.CreateFontString then return end
    local fs = badges[button]
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", 2, 4)
        badges[button] = fs
    end
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    fs:Show()
end

local function CheckRewards(tries)
    HideBadges()
    if not Cfg("gearReward") then return end
    local n = (GetNumQuestChoices and GetNumQuestChoices()) or 0
    if type(n) ~= "number" or n < 1 then return end
    local best, bestDiff, sell, sellValue, missing = nil, MIN_GAIN, nil, 0, false
    for i = 1, n do
        local link = Str(GetQuestItemLink and GetQuestItemLink("choice", i))
        if not link then
            missing = true
        else
            local diff = Diff(link)
            if diff and diff > bestDiff then best, bestDiff = i, diff end
            local count = 1
            pcall(function()
                local c = select(3, GetQuestItemInfo("choice", i))
                if type(c) == "number" and c > 0 then count = c end
            end)
            local price
            pcall(function()
                local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                price = select(11, get(link))
            end)
            if price == nil then missing = true end
            if type(price) == "number" and price * count > sellValue then sell, sellValue = i, price * count end
        end
    end
    -- item data not loaded yet: try again shortly
    if missing and (tries or 0) < 3 and C_Timer and C_Timer.After then
        C_Timer.After(0.4, function() pcall(CheckRewards, (tries or 0) + 1) end)
        return
    end
    if best then
        local link = GetQuestItemLink("choice", best)
        Badge(RewardButton(best), L("GEAR_BADGE_BEST"), 0.2, 1, 0.2)
        if n > 1 then Chat(L("GEAR_REWARD_BEST", link, DiffText(bestDiff))) end
    elseif sell and n > 1 then
        local link = GetQuestItemLink("choice", sell)
        Badge(RewardButton(sell), L("GEAR_BADGE_SELL"), 1, 0.82, 0)
        Chat(L("GEAR_REWARD_SELL", link, (W.CoinText and W.CoinText(sellValue)) or tostring(sellValue)))
    end
end

---------------------------------------------------------------------------
-- Loot alert
---------------------------------------------------------------------------
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = string.gsub(fmt, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = string.gsub(p, "%%%%s", "(.+)")
    p = string.gsub(p, "%%%%d", "%%d+")
    return "^" .. p .. "$"
end

local selfPatterns
local function SelfPatterns()
    if selfPatterns then return selfPatterns end
    selfPatterns = {}
    for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
        "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
        local p = ToPattern(rawget(_G, g))
        if p then selfPatterns[#selfPatterns + 1] = p end
    end
    return selfPatterns
end

local pendingLoot = {}
local lastLoot = {}

local function ProcessLoot(link)
    local diff, empty, minLevel = Diff(link)
    if not diff or (diff < MIN_GAIN and not (empty and diff > 0)) then return end
    local now = GetTime and GetTime() or 0
    if lastLoot[link] and now - lastLoot[link] < 5 then return end
    lastLoot[link] = now
    local level = PlayerLevel()
    if minLevel and minLevel > level then
        Chat(L("GEAR_LOOT_LATER", minLevel, link, DiffText(diff, empty)))
    else
        Chat(L("GEAR_LOOT_UP", link, DiffText(diff, empty)))
    end
    local g = Store()
    table.insert(g.loot, 1, { link = link, diff = Round(diff), level = level })
    while #g.loot > MAX_LOOT do table.remove(g.loot) end
end

local function FlushLoot()
    if InCombat() then return end
    local list = pendingLoot
    pendingLoot = {}
    for _, link in ipairs(list) do pcall(ProcessLoot, link) end
    QueueScan()
end

local function OnLoot(msg)
    if not Cfg("gearLoot") then return end
    msg = Str(msg)
    if not msg then return end
    local mine = false
    for _, p in ipairs(SelfPatterns()) do
        if string.find(msg, p) then mine = true; break end
    end
    if not mine then return end
    local link = string.match(msg, "(|c%x+|Hitem:.-|h%[.-%]|h|r)") or string.match(msg, "(|Hitem:.-|h%[.-%]|h)")
    if not link then return end
    if #pendingLoot < 10 then pendingLoot[#pendingLoot + 1] = link end
    -- item data may still load: wait a moment, and never in combat
    if C_Timer and C_Timer.After then C_Timer.After(0.6, FlushLoot) else FlushLoot() end
end

---------------------------------------------------------------------------
-- Guide reminders
---------------------------------------------------------------------------
local baseReminders = W.ExtraReminders
W.ExtraReminders = function(list)
    if baseReminders then pcall(baseReminders, list) end
    pcall(function()
        local level = PlayerLevel()
        if Cfg("wandWarn") and level >= 5 and wandInfo ~= nil then
            if wandInfo == false then
                list[#list + 1] = L("REMIND_NO_WAND")
            elseif wandInfo.minLevel and level - wandInfo.minLevel >= (Cfg("wandGap") or 10) then
                list[#list + 1] = L("REMIND_OLD_WAND", wandInfo.minLevel)
            end
        end
        if Cfg("gearBagRemind") and bagUps[1] then
            list[#list + 1] = L("REMIND_BAG_UPGRADE", ItemName(bagUps[1].link))
        end
    end)
end

---------------------------------------------------------------------------
-- Gear window (/wocky gear)
---------------------------------------------------------------------------
local frame
local lines = {}
local ROW_W = 380

local function CreateFrameUI()
    local f = CreateFrame("Frame", "WockyGearFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(408, 200)
    f:SetPoint("CENTER", UIParent, "CENTER", 60, 40)
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
    pcall(function() table.insert(UISpecialFrames, "WockyGearFrame") end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    f.title:SetWidth(ROW_W - 20)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    f:Hide()
    return f
end

local function Line(i)
    if not lines[i] then
        local fs = W.NewFS(frame, W.fonts.small)
        fs:SetWidth(ROW_W)
        fs:SetJustifyH("LEFT")
        lines[i] = fs
    end
    return lines[i]
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    local spec = ActiveSpec()
    frame.title:SetText("|cFF8787EDWockyPro|r - " .. L("GEAR_TITLE", spec))
    local t = {}
    local wt = Weights(spec)
    t[#t + 1] = L("GEAR_WEIGHTS", tostring(wt.sp), tostring(wt.sta), tostring(wt.int), tostring(wt.spi), tostring(wt.wand))
    t[#t + 1] = ""
    if wandInfo then
        t[#t + 1] = L("GEAR_WAND", ItemName(wandInfo.link), wandInfo.dps or 0, wandInfo.minLevel or 0)
    elseif wandInfo == false then
        t[#t + 1] = L("GEAR_NO_WAND")
    end
    t[#t + 1] = "|cFFFFD100" .. L("GEAR_BAG_HEAD") .. "|r"
    if #bagUps == 0 then t[#t + 1] = "  |cFF999999" .. L("GEAR_NONE") .. "|r" end
    for i = 1, math.min(5, #bagUps) do
        local u = bagUps[i]
        t[#t + 1] = "  " .. u.link .. " " .. DiffText(u.diff, u.empty)
    end
    t[#t + 1] = "|cFFFFD100" .. L("GEAR_LOOT_HEAD") .. "|r"
    local loot = Store().loot
    if #loot == 0 then t[#t + 1] = "  |cFF999999" .. L("GEAR_NONE") .. "|r" end
    for i = 1, math.min(MAX_LOOT, #loot) do
        local e = loot[i]
        t[#t + 1] = "  " .. tostring(e.link) .. " " .. DiffText(e.diff or 0) .. " |cFF999999(" .. tostring(e.level or "?") .. ")|r"
    end
    t[#t + 1] = ""
    t[#t + 1] = "|cFF999999" .. L("GEAR_HINT") .. "|r"

    local y = 34
    for i, text in ipairs(t) do
        local fs = Line(i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -y)
        fs:SetText(text)
        fs:Show()
        y = y + math.max(14, (fs:GetStringHeight() or 14)) + 2
    end
    for i = #t + 1, #lines do lines[i]:Hide() end
    frame:SetHeight(y + 12)
end
W.RefreshGear = Refresh

local function ShowGear()
    if not frame then frame = CreateFrameUI() end
    frame:Show()
    if not InCombat() then pcall(ScanBags); pcall(ScanWand) end
    Refresh()
end

local function ToggleGear()
    if frame and frame:IsShown() then frame:Hide() else ShowGear() end
end
W.ShowGear = ShowGear

---------------------------------------------------------------------------
-- Settings (Gear tab)
---------------------------------------------------------------------------
local weightRows = {}

local function RefreshWeightRows()
    local spec = ActiveSpec()
    local wt = Weights(spec)
    for _, r in ipairs(weightRows) do
        r.label:SetText(L(STAT_KEYS[r.key]))
        r.value:SetText(string.format("%.1f", wt[r.key] or 0))
    end
end

local function AddWeightRow(page, key)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(506, 22)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(page.y or 0))
    page.y = (page.y or 0) + 26
    local label = W.NewFS(row, W.fonts.high)
    label:SetPoint("LEFT", row, "LEFT", 16, 0)
    label:SetWidth(214)
    label:SetJustifyH("LEFT")
    local minus = W.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    minus:SetSize(24, 20)
    minus:SetPoint("RIGHT", row, "RIGHT", -112, 0)
    minus:SetText("-")
    local value = W.NewFS(row, W.fonts.high)
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(56)
    value:SetJustifyH("CENTER")
    local plus = W.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    plus:SetSize(24, 20)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    plus:SetText("+")
    local function change(delta)
        local spec = ActiveSpec()
        SetWeight(spec, key, (Weights(spec)[key] or 0) + delta * W_STEP)
        RefreshWeightRows()
        if W.RefreshGear then pcall(W.RefreshGear) end
        QueueScan()
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)
    weightRows[#weightRows + 1] = { key = key, label = label, value = value }
end

local page = W.pageGear
if page then
    if W.AddCycle then
        W.AddCycle(page, "GEAR_SPEC", { "auto", "Affliction", "Demonology", "Destruction" },
            function() return Cfg("gearSpec") end,
            function(v) SetCfg("gearSpec", v); QueueScan() end,
            function(v)
                if v == "auto" then return L("GEAR_SPEC_AUTO", ActiveSpec()) end
                return tostring(v)
            end)
    end
    for _, k in ipairs(STATS) do AddWeightRow(page, k) end
    if W.AddButton then
        W.AddButton(page, "GEAR_RESET", function()
            Store().weights[ActiveSpec()] = nil
            RefreshWeightRows()
            QueueScan()
            if W.RefreshGear then pcall(W.RefreshGear) end
        end)
    end
    W.AddToggle(page, "gearReward", "GEAR_OPT_REWARD")
    W.AddToggle(page, "gearLoot", "GEAR_OPT_LOOT")
    W.AddToggle(page, "gearBagRemind", "GEAR_OPT_BAGS")
    W.AddToggle(page, "wandWarn", "GEAR_OPT_WAND")
    W.AddStepper(page, "wandGap", "GEAR_WAND_GAP", 5, 20, 1, function(v) return tostring(v) end)
    if W.AddButton then W.AddButton(page, "GEAR_OPEN", ShowGear) end
    pcall(page.HookScript, page, "OnShow", RefreshWeightRows)
end

local baseApply = W.OnApply
W.OnApply = function(...)
    if baseApply then pcall(baseApply, ...) end
    pcall(RefreshWeightRows)
    Refresh()
end

---------------------------------------------------------------------------
-- Report line
---------------------------------------------------------------------------
W.GearInfo = function()
    local wt = Weights()
    local s = ActiveSpec() .. " weights sp " .. wt.sp .. " sta " .. wt.sta .. " int " .. wt.int .. " spi " .. wt.spi .. " wand " .. wt.wand
    if wandInfo then
        s = s .. ", wand " .. string.format("%.1f", wandInfo.dps or 0) .. " dps lvl " .. tostring(wandInfo.minLevel or "?")
    elseif wandInfo == false then
        s = s .. ", no wand"
    end
    s = s .. ", bag upgrades " .. #bagUps
    return s
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "PLAYER_REGEN_ENABLED", "QUEST_COMPLETE", "QUEST_FINISHED", "CHAT_MSG_LOOT", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end

ev:SetScript("OnEvent", function(self, event, a1)
    if event == "CHAT_MSG_LOOT" then
        pcall(OnLoot, a1)
    elseif event == "QUEST_COMPLETE" then
        pcall(CheckRewards, 0)
    elseif event == "QUEST_FINISHED" then
        pcall(HideBadges)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if #pendingLoot > 0 then FlushLoot() else QueueScan() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if frame and frame:IsShown() then QueueScan() end
    else
        QueueScan()
    end
end)

---------------------------------------------------------------------------
-- Slash command and help
---------------------------------------------------------------------------
W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky gear", "HELP_GEAR" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "gear" or m == "loot" or m == "wand" or m == "weights" or string.find(m, "^gear ") then
        ToggleGear()
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._GearWeights = Weights
W._GearSetWeight = SetWeight
W._GearScan = function() ScanBags(); ScanWand(); return bagUps, wandInfo end
W._GearRewards = CheckRewards
W._GearLoot = OnLoot
