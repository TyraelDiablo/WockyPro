-- WockyLook: look and profiles (6.0.0), settings tab "Interface"
--  1. Profiles: settings for the whole account or for this character only;
--     copy the settings of another character (or the account) to this one.
--  2. HUD mode: a tiny strip with the next open line and an arrow instead of
--     the big window. Left-click ticks the line, right-click opens the window.
--  3. Themes: Warlock purple, plain, classic WoW frame, flat (ElvUI-like).
--  4. Colorblind mode: other colors plus marks (+++ / ++ / +) for recipe
--     colors, a blue-yellow arrow.
--  5. Window width.
local W = WockyAPI
if not W then return end

local L, Cfg, SetCfg = W.L, W.Cfg, W.SetCfg
local D = W.DEFAULTS
local THEMES = { "purple", "plain", "classic", "flat" }
local THEME_KEYS = { purple = "LK_THEME_PURPLE", plain = "LK_THEME_PLAIN", classic = "LK_THEME_CLASSIC", flat = "LK_THEME_FLAT" }
local BASE_WIDTH = 360
local atan2 = atan2 or math.atan2

for k, v in pairs({ hudMode = false, theme = "purple", colorblind = false, winWidth = BASE_WIDTH }) do
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

local function Num(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return pcall(function() return v + 0 end) and v or nil
end

---------------------------------------------------------------------------
-- Profiles
--   WockyDB.accountCfg: the account settings
--   WockyDB.charCfg[charKey]: settings of a character that uses its own
--   WockyDB.charOwn[charKey] = true: this character uses its own settings
-- WockyDB.cfg always points to the active table while you play.
---------------------------------------------------------------------------
local function CharKey()
    local ok, k = pcall(W.CharKey)
    return ok and k or "?"
end

local function Copy(t)
    local o = {}
    for k, v in pairs(t or {}) do
        if type(v) == "table" then o[k] = Copy(v) else o[k] = v end
    end
    return o
end

local function ActiveSlot()
    WockyDB = WockyDB or {}
    WockyDB.charOwn = WockyDB.charOwn or {}
    WockyDB.charCfg = WockyDB.charCfg or {}
    return WockyDB.charOwn[CharKey()] and "char" or "account"
end

local function PickProfile()
    WockyDB = WockyDB or {}
    -- first start with profiles: the old settings become the account settings
    if type(WockyDB.accountCfg) ~= "table" then WockyDB.accountCfg = WockyDB.cfg or {} end
    if ActiveSlot() == "char" then
        local key = CharKey()
        WockyDB.charCfg[key] = WockyDB.charCfg[key] or Copy(WockyDB.accountCfg)
        WockyDB.cfg = WockyDB.charCfg[key]
    else
        WockyDB.cfg = WockyDB.accountCfg
    end
end
W.BeforeInit = function() pcall(PickProfile) end

-- after "Reset all" the active table is new: put it in its slot
local function KeepSlot()
    if not WockyDB or type(WockyDB.cfg) ~= "table" then return end
    if ActiveSlot() == "char" then
        WockyDB.charCfg[CharKey()] = WockyDB.cfg
    else
        WockyDB.accountCfg = WockyDB.cfg
    end
end

local function SetOwn(on)
    WockyDB = WockyDB or {}
    KeepSlot()
    local key = CharKey()
    WockyDB.charOwn = WockyDB.charOwn or {}
    WockyDB.charCfg = WockyDB.charCfg or {}
    if on then
        WockyDB.charOwn[key] = true
        WockyDB.charCfg[key] = WockyDB.charCfg[key] or Copy(WockyDB.accountCfg or WockyDB.cfg)
        WockyDB.cfg = WockyDB.charCfg[key]
    else
        WockyDB.charOwn[key] = nil
        WockyDB.cfg = WockyDB.accountCfg or WockyDB.cfg
    end
end

-- names you can copy from: "account" and characters with their own settings
local copyFrom = "account"
local function Sources()
    local list = { "account" }
    for key in pairs((WockyDB and WockyDB.charCfg) or {}) do
        if key ~= CharKey() then list[#list + 1] = key end
    end
    table.sort(list, function(a, b)
        if a == "account" then return true end
        if b == "account" then return false end
        return a < b
    end)
    return list
end

local function CopyProfile()
    local src = (copyFrom == "account") and (WockyDB and WockyDB.accountCfg) or (WockyDB and WockyDB.charCfg and WockyDB.charCfg[copyFrom])
    if type(src) ~= "table" then return end
    if copyFrom == "account" and ActiveSlot() == "account" then return end
    local dst = WockyDB.cfg
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(Copy(src)) do dst[k] = v end
    Chat(L("LK_COPIED", copyFrom == "account" and L("LK_ACCOUNT") or copyFrom))
end

-- SavedVariables do not keep shared tables: the next login reads the slots
local logout = CreateFrame("Frame")
pcall(function() logout:RegisterEvent("PLAYER_LOGOUT") end)
logout:SetScript("OnEvent", function()
    pcall(KeepSlot)
    if WockyDB and WockyDB.accountCfg then WockyDB.cfg = WockyDB.accountCfg end
end)

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------
local BACKDROPS = {
    plain = { bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } },
    classic = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } },
    flat = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
}
BACKDROPS.purple = BACKDROPS.plain
local FRAME_NAMES = { "WockyMainFrame", "WockySettingsFrame", "WockyGearFrame", "WockyGearPlanFrame", "WockyRouteEditFrame",
    "WockyStatsFrame", "WockyHUDFrame", "WockyTextBoxFrame", "WockyReportFrame", "WockyGroupFrame", "WockyLockFrame", "WockyPlanFrame" }

local function Accent()
    local a = W.ACCENT_RGB and W.ACCENT_RGB() or nil
    if a then return a[1], a[2], a[3] end
    return 0.6, 0.2, 0.8
end

local applied = {}
local function ThemeFrame(f, isMain)
    if not f or not f.SetBackdrop then return end
    local theme = Cfg("theme") or "purple"
    if theme == "purple" and not applied[f] then return end
    local alpha = isMain and (Cfg("alpha") or 0.92) or 0.94
    pcall(function()
        f:SetBackdrop(BACKDROPS[theme] or BACKDROPS.plain)
        if theme == "flat" then
            f:SetBackdropColor(0.06, 0.06, 0.06, alpha)
            f:SetBackdropBorderColor(0, 0, 0, 1)
        elseif theme == "classic" then
            f:SetBackdropColor(1, 1, 1, alpha)
            f:SetBackdropBorderColor(1, 1, 1, 1)
        elseif theme == "plain" then
            f:SetBackdropColor(0, 0, 0, alpha)
            f:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        else
            f:SetBackdropColor(0, 0, 0, alpha)
            f:SetBackdropBorderColor(Accent())
        end
    end)
    applied[f] = (theme ~= "purple") or nil
end

local function ApplyTheme()
    for _, name in ipairs(FRAME_NAMES) do
        local f = rawget(_G, name)
        if f then ThemeFrame(f, name == "WockyMainFrame") end
    end
end
W.ApplyTheme = ApplyTheme
W.RestoreBorder = function()
    local theme = Cfg("theme") or "purple"
    local ui = W.WockyUI
    if theme == "purple" then
        pcall(function() ui:SetBackdropBorderColor(Accent()) end)
    else
        ThemeFrame(ui, true)
    end
end

---------------------------------------------------------------------------
-- Colorblind mode
---------------------------------------------------------------------------
local NORMAL_HEX = {}
for i, v in ipairs(W.COLOR_HEX or {}) do NORMAL_HEX[i] = v end
-- Okabe-Ito based: easy to tell apart for most color vision types
local CB_HEX = { "E69F00", "F0E442", "56B4E9", "999999" }
local CB_MARK = { "+++", "++", "+", "" }

local function ApplyColors()
    local t = W.COLOR_HEX
    if type(t) ~= "table" then return end
    local src = Cfg("colorblind") and CB_HEX or NORMAL_HEX
    for i = 1, 4 do if src[i] then t[i] = src[i] end end
end
W.ColorMark = function(c)
    if not Cfg("colorblind") then return nil end
    return CB_MARK[c]
end
-- green / red for "better" / "worse" in other modules
W.GoodHex = function() return Cfg("colorblind") and "56B4E9" or "00FF00" end
W.BadHex = function() return Cfg("colorblind") and "E69F00" or "FF4040" end

---------------------------------------------------------------------------
-- Window width
---------------------------------------------------------------------------
local lastWidth = BASE_WIDTH
local function ApplyWidth()
    local w = tonumber(Cfg("winWidth")) or BASE_WIDTH
    if w < 300 then w = 300 end
    if w > 560 then w = 560 end
    if w ~= lastWidth then
        lastWidth = w
        -- the line heights change with the width: lay the guide out again
        if C_Timer and C_Timer.After and W.UpdateWockyGuide then
            C_Timer.After(0, function() pcall(W.UpdateWockyGuide, W.GetViewLevel()) end)
        end
    end
    local inner = w - 32
    pcall(function() W.WockyUI:SetWidth(w) end)
    local function set(o, width) if o and o.SetWidth then pcall(o.SetWidth, o, width) end end
    set(W.xpBar, inner); set(W.xpText, inner); set(W.remindText, inner); set(W.statusRow, inner)
    set(W.dungeonBtn, inner); set(W.dungeonText, inner); set(W.togetherText, inner)
    for _, b in ipairs(W.questButtons or {}) do
        set(b, inner + 2)
        if b.html then set(b.html, inner - 28) end
    end
    for _, list in ipairs({ W.profRows or {}, W.talentRows or {}, W.questStepRows or {} }) do
        for _, b in ipairs(list) do set(b, inner); if b.text then set(b.text, inner) end end
    end
end
W.ApplyWidth = ApplyWidth

---------------------------------------------------------------------------
-- HUD strip
---------------------------------------------------------------------------
local hud = CreateFrame("Button", "WockyHUDFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
hud:SetSize(300, 24)
hud:SetPoint("TOP", UIParent, "TOP", 0, -60)
hud:SetFrameStrata("MEDIUM")
hud:SetMovable(true)
hud:EnableMouse(true)
hud:SetClampedToScreen(true)
hud:RegisterForDrag("LeftButton")
hud:RegisterForClicks("LeftButtonUp", "RightButtonUp")
pcall(function()
    hud:SetBackdrop(BACKDROPS.plain)
    hud:SetBackdropColor(0, 0, 0, 0.8)
    hud:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
end)
hud:Hide()
local hudArrow = hud:CreateTexture(nil, "ARTWORK")
hudArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
hudArrow:SetSize(20, 20)
hudArrow:SetPoint("LEFT", hud, "LEFT", 4, 0)
local hudText = W.NewFS(hud, W.fonts.small)
hudText:SetPoint("LEFT", hud, "LEFT", 26, 0)
hudText:SetPoint("RIGHT", hud, "RIGHT", -6, 0)
hudText:SetJustifyH("LEFT")
pcall(function() hudText:SetWordWrap(false) end)

hud:SetScript("OnDragStart", function(self) if not Cfg("locked") then self:StartMoving() end end)
hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if p then WockyDB = WockyDB or {}; WockyDB.hudPos = { p, rp, x, y } end
end)

local hudStep -- { level, index, text }
local function PlayerLevel()
    local ok, l = pcall(UnitLevel, "player")
    return (ok and Num(l)) or 1
end

local function NextStep()
    local level = PlayerLevel()
    local lines = (W.GuideLines and W.GuideLines(level)) or {}
    local t = W.DoneTable and W.DoneTable() or {}
    for i, l in ipairs(lines) do
        if not t["Q" .. level .. ":" .. i] then return { level = level, index = i, text = l } end
    end
    return { level = level, text = nil }
end

local function RefreshHUD()
    if not hud:IsShown() then return end
    hudStep = NextStep()
    local text
    if hudStep.text then
        text = hudStep.text
        if W.TranslateLine then
            local ok, tr = pcall(W.TranslateLine, text)
            if ok and type(tr) == "string" then text = tr end
        end
    else
        text = "|cFF00FF00" .. L("HUD_DONE") .. "|r"
    end
    hudText:SetText("|cFFFFD100" .. hudStep.level .. "|r  " .. text)
end
W.RefreshHUD = RefreshHUD

local hudTick = 0
hud:SetScript("OnUpdate", function(self, elapsed)
    hudTick = hudTick + (elapsed or 0)
    if hudTick < 0.1 then return end
    hudTick = 0
    local t = W.ArrowTarget and W.ArrowTarget()
    local shown = false
    if t and t.mapID and W.ArrowPlayerPos then
        local px, py = W.ArrowPlayerPos(t.mapID)
        local facing = GetPlayerFacing and Num(GetPlayerFacing())
        if px and py and facing then
            local w, h = 1000, 1000
            if W.ArrowMapSize then
                local mw, mh = W.ArrowMapSize(t.mapID)
                if mw then w, h = mw, mh end
            end
            local east, south = (t.x - px) * w, (t.y - py) * h
            if math.sqrt(east * east + south * south) >= 10 then
                local angle = atan2(-east, -south) - facing
                pcall(hudArrow.SetRotation, hudArrow, angle)
                local a = angle % (2 * math.pi)
                if a > math.pi then a = a - 2 * math.pi end
                local off = math.abs(a) / math.pi
                if Cfg("colorblind") then
                    hudArrow:SetVertexColor(0.3 + 0.7 * off, 0.6 + 0.25 * off, 1 - 0.9 * off)
                else
                    hudArrow:SetVertexColor(math.min(1, off * 2), math.min(1, (1 - off) * 2), 0.1)
                end
                shown = true
            end
        end
    end
    if shown then hudArrow:Show() else hudArrow:Hide() end
end)

hud:SetScript("OnClick", function(self, mouse)
    if mouse == "RightButton" then
        SetCfg("hudMode", false)
        if W.ApplyAll then W.ApplyAll() end
        W.WockyUI:Show()
        return
    end
    if hudStep and hudStep.index and W.DoneTable then
        local t = W.DoneTable()
        local key = "Q" .. hudStep.level .. ":" .. hudStep.index
        t[key] = not t[key]
        if W.UpdateWockyGuide then pcall(W.UpdateWockyGuide, W.GetViewLevel()) end
    end
    RefreshHUD()
end)
hud:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("WockyPro")
    if hudStep and hudStep.text then GameTooltip:AddLine(hudText:GetText(), 1, 1, 1, true) end
    GameTooltip:AddLine(L("HUD_TIP"), 0.45, 0.8, 1, true)
    GameTooltip:Show()
end)
hud:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- in HUD mode the strip shows wherever the window would show
local switching = false
pcall(function()
    W.WockyUI:HookScript("OnShow", function()
        if Cfg("hudMode") and not switching then
            switching = true
            W.WockyUI:Hide()
            switching = false
            hud:Show()
            RefreshHUD()
        end
    end)
end)

local function PlaceHUD()
    local pos = WockyDB and WockyDB.hudPos
    hud:ClearAllPoints()
    if pos and pos[1] then
        hud:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    else
        hud:SetPoint("TOP", UIParent, "TOP", 0, -60)
    end
end

local function ApplyHUD()
    hud:SetScale(Cfg("scale") or 1)
    hud:SetWidth(math.max(240, (tonumber(Cfg("winWidth")) or BASE_WIDTH) - 40))
    if Cfg("hudMode") then
        if W.WockyUI:IsShown() then
            switching = true
            W.WockyUI:Hide()
            switching = false
            hud:Show()
        end
        RefreshHUD()
    elseif hud:IsShown() then
        hud:Hide()
        W.WockyUI:Show()
    end
end

local function ToggleHUD()
    SetCfg("hudMode", not Cfg("hudMode"))
    if Cfg("hudMode") then
        switching = true
        W.WockyUI:Hide()
        switching = false
        hud:Show()
        RefreshHUD()
        Chat(L("HUD_ON"))
    else
        hud:Hide()
        W.WockyUI:Show()
    end
    if W.ApplyAll then W.ApplyAll() end
end

---------------------------------------------------------------------------
-- Apply, settings tab, events, slash
---------------------------------------------------------------------------
local baseApply = W.OnApply
W.OnApply = function(...)
    if baseApply then pcall(baseApply, ...) end
    pcall(KeepSlot)
    pcall(ApplyColors)
    pcall(ApplyWidth)
    pcall(ApplyTheme)
    pcall(ApplyHUD)
    pcall(function() if W.settingsFrame and Cfg("theme") == "purple" then W.settingsFrame:SetBackdropBorderColor(Accent()) end end)
end

-- the guide size changes with the width: lay it out again after a width change
local baseOnGuide = W.OnGuide
W.OnGuide = function(level, data)
    if baseOnGuide then pcall(baseOnGuide, level, data) end
    pcall(RefreshHUD)
end

local page = W.pageUI
if page then
    if W.AddCycle then
        W.AddCycle(page, "LK_PROFILE", { "account", "char" },
            function() return ActiveSlot() end,
            function(v) SetOwn(v == "char") end,
            function(v) return v == "char" and L("LK_PROFILE_CHAR") or L("LK_PROFILE_ACCOUNT") end)
        local sources = { "account" }
        W.AddCycle(page, "LK_COPY_FROM", sources,
            function() return copyFrom end,
            function(v) copyFrom = v end,
            function(v)
                -- the list of characters is read when you look at it
                local fresh = Sources()
                for i = #sources, 1, -1 do sources[i] = nil end
                for i, s in ipairs(fresh) do sources[i] = s end
                if v == "account" then return L("LK_ACCOUNT") end
                return tostring(v)
            end)
    end
    if W.AddButton then W.AddButton(page, "LK_COPY", function() CopyProfile(); if W.ApplyAll then W.ApplyAll() end end) end
    W.AddToggle(page, "hudMode", "LK_OPT_HUD")
    if W.AddCycle then
        W.AddCycle(page, "LK_THEME", THEMES,
            function() return Cfg("theme") or "purple" end,
            function(v) SetCfg("theme", v) end,
            function(v) return L(THEME_KEYS[v] or "LK_THEME_PURPLE") end)
    end
    W.AddToggle(page, "colorblind", "LK_OPT_CB")
    W.AddStepper(page, "winWidth", "LK_WIDTH", 300, 560, 20, function(v) return tostring(v) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
local hiddenInCombat = false
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        PlaceHUD()
        -- the class check of the main window decides; the strip follows it
        if C_Timer and C_Timer.After then C_Timer.After(0.6, function() pcall(ApplyHUD); pcall(ApplyTheme) end) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Cfg("hideCombat") and hud:IsShown() then hiddenInCombat = true; hud:Hide() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hiddenInCombat then hiddenInCombat = false; if Cfg("hudMode") then hud:Show(); RefreshHUD() end end
    else
        if not InCombat() then pcall(RefreshHUD) end
    end
end)

W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky hud", "HELP_HUD" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "hud" then
        ToggleHUD()
    elseif Cfg("hudMode") and (m == "" or m == "toggle" or m == "show" or m == "hide") then
        -- the window commands move the strip in HUD mode
        if m == "hide" or (m ~= "show" and hud:IsShown()) then hud:Hide() else hud:Show(); RefreshHUD() end
    elseif baseSlash then
        baseSlash(msg)
    end
end

W.LookInfo = function()
    return "theme " .. tostring(Cfg("theme")) .. ", width " .. tostring(Cfg("winWidth")) .. ", hud " .. (Cfg("hudMode") and "on" or "off")
        .. ", colorblind " .. (Cfg("colorblind") and "on" or "off") .. ", profile " .. ActiveSlot()
end

-- for tests
W._LKPick = PickProfile
W._LKSetOwn = SetOwn
W._LKCopy = function(from) copyFrom = from; CopyProfile() end
W._LKKeep = KeepSlot
W._LKNext = NextStep
W._LKHud = hud
