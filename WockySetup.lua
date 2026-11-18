-- WockySetup: first-run setup wizard and the update notice window.
-- The wizard opens once on a new install (and with /wocky setup).
-- The update notice opens next to the guide window on the first login after an
-- update, and when a group or guild member runs a newer WockyPro. Closing it
-- only closes the notice; the guide keeps working.
local W = WockyAPI
if not W then return end

local L, Cfg, SetCfg = W.L, W.Cfg, W.SetCfg

if W.DEFAULTS.updateNotice == nil then W.DEFAULTS.updateNotice = true end

local PREFIX = "WockyPro"

-- language names in their own language for the wizard
local NATIVE = {
    enUS = "English", trTR = "Türkçe", deDE = "Deutsch", esES = "Español (España)", esMX = "Español (México)",
    frFR = "Français", itIT = "Italiano", ptBR = "Português (Brasil)", ruRU = "Русский", koKR = "한국어",
    zhCN = "简体中文", zhTW = "繁體中文"
}

-- localized highlights for the update notice; versions not listed here show
-- the first English NEWS lines instead
local HIGHLIGHTS = {
    ["4.2.1"] = { "UPD_421_1", "UPD_421_2", "UPD_421_3" },
    ["4.2.0"] = { "UPD_420_1", "UPD_420_2", "UPD_420_3" },
    ["4.1.0"] = { "UPD_410_1", "UPD_410_2", "UPD_410_3" }
}

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function ParseVersion(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = string.match(v, "^(%d+)%.(%d+)%.(%d+)$")
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if not a or a > 99 or b > 99 or c > 99 then return nil end
    return a * 10000 + b * 100 + c
end

local function Newer(v, than)
    local x, y = ParseVersion(v), ParseVersion(than)
    return x ~= nil and y ~= nil and x > y
end

local function NewPanel(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    pcall(function()
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.95)
        f:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
    end)
    f:Hide()
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.close = close
    return f
end

local function TextButton(parent, w)
    local b = W.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w or 100, 22)
    return b
end

---------------------------------------------------------------------------
-- Setup wizard
---------------------------------------------------------------------------
local wiz = NewPanel("WockySetupFrame", 440, 340)
wiz:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
pcall(table.insert, UISpecialFrames, "WockySetupFrame")

wiz.title = W.NewFS(wiz, W.fonts.large)
wiz.title:SetPoint("TOPLEFT", wiz, "TOPLEFT", 16, -14)
wiz.head = W.NewFS(wiz, W.fonts.normal)
wiz.head:SetPoint("TOPLEFT", wiz, "TOPLEFT", 16, -44)
wiz.head:SetWidth(408)
wiz.head:SetJustifyH("LEFT")
wiz.text = W.NewFS(wiz, W.fonts.high)
wiz.text:SetPoint("TOPLEFT", wiz.head, "BOTTOMLEFT", 0, -8)
wiz.text:SetWidth(408)
wiz.text:SetJustifyH("LEFT")
wiz.text:SetJustifyV("TOP")

wiz.back = TextButton(wiz, 100)
wiz.back:SetPoint("BOTTOMLEFT", wiz, "BOTTOMLEFT", 14, 14)
wiz.nextBtn = TextButton(wiz, 120)
wiz.nextBtn:SetPoint("BOTTOMRIGHT", wiz, "BOTTOMRIGHT", -14, 14)

local page = 1
local PAGES = 4
local rows = {}

-- one row = a label and a button (cycle) or a check line (toggle)
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, wiz)
    r:SetSize(408, 22)
    r:SetPoint("TOPLEFT", wiz, "TOPLEFT", 16, -126 - (i - 1) * 26)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.label = W.NewFS(r, W.fonts.high)
    r.label:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.label:SetWidth(230)
    r.label:SetJustifyH("LEFT")
    r.btn = TextButton(r, 172)
    r.btn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rows[i] = r
    return r
end

local function Cycle(values, cur, mouse)
    local idx = 1
    for i, v in ipairs(values) do if v == cur then idx = i end end
    idx = idx + ((mouse == "RightButton") and -1 or 1)
    if idx < 1 then idx = #values end
    if idx > #values then idx = 1 end
    return values[idx]
end

local Refresh

local function Changed()
    if W.ApplyAll then pcall(W.ApplyAll) end
    Refresh()
end

local ROUTES = { "auto", "SCOURGE", "ORC", "HUMAN", "GNOME" }
local SPECS = { "auto", "Affliction", "Demonology", "Destruction" }

local function CurRoute() return (WockyDB and WockyDB.cfg and WockyDB.cfg.route) or "auto" end
local function CurSpec() return (WockyDB and WockyDB.spec) or "auto" end

-- page content: list of row specs
local function PageRows(p)
    if p == 1 then
        return { {
            label = L("LANGUAGE"),
            text = function()
                local cur = Cfg("lang")
                if cur == "auto" then return L("LANG_AUTO") end
                return NATIVE[cur] or cur
            end,
            click = function(mouse) SetCfg("lang", Cycle(W.LANG_CODES or { "auto", "enUS" }, Cfg("lang"), mouse)) end
        } }
    elseif p == 2 then
        return {
            { label = L("ROUTE"),
                text = function()
                    local v = CurRoute()
                    if v == "auto" then return L("ROUTE_AUTO", UnitRace("player") or "?") end
                    return (W.ROUTE_NAMES and W.ROUTE_NAMES[v]) or v
                end,
                click = function(mouse) SetCfg("route", Cycle(ROUTES, CurRoute(), mouse)) end },
            { label = L("TALENT_BUILD"),
                text = function()
                    local v = CurSpec()
                    if v == "auto" then return L("BUILD_AUTO") end
                    return v
                end,
                click = function(mouse)
                    WockyDB = WockyDB or {}
                    local v = Cycle(SPECS, CurSpec(), mouse)
                    if v == "auto" then WockyDB.spec = nil else WockyDB.spec = v end
                end }
        }
    elseif p == 3 then
        return {
            { toggle = "showQuests", label = "SHOW_QUESTS" }, { toggle = "showProf", label = "SHOW_PROF" },
            { toggle = "showTalents", label = "SHOW_TALENTS" }, { toggle = "showDungeons", label = "SHOW_DUNGEONS" },
            { toggle = "showXP", label = "SHOW_XP" }, { toggle = "showChar", label = "SHOW_CHAR" }
        }
    end
    return {
        { toggle = "autoCheck", label = "AUTO_CHECK" }, { toggle = "showArrow", label = "SHOW_ARROW" },
        { toggle = "autoSellJunk", label = "AUTO_SELL" }, { toggle = "autoRepair", label = "AUTO_REPAIR" },
        { toggle = "guideTranslate", label = "GUIDE_TRANSLATE" }, { toggle = "updateNotice", label = "UPD_TOGGLE" }
    }
end

local HEADS = { "SETUP_P1_HEAD", "SETUP_P2_HEAD", "SETUP_P3_HEAD", "SETUP_P4_HEAD" }
local TEXTS = { "SETUP_P1_TEXT", "SETUP_P2_TEXT", "SETUP_P3_TEXT", "SETUP_P4_TEXT" }

Refresh = function()
    if not wiz:IsShown() then return end
    wiz.title:SetText("|cFF8787EDWockyPro|r - " .. L("SETUP_TITLE", page, PAGES))
    wiz.head:SetText(L(HEADS[page]))
    wiz.text:SetText(L(TEXTS[page]))
    local list = PageRows(page)
    for i, spec in ipairs(list) do
        local r = Row(i)
        if spec.toggle then
            local key = spec.toggle
            r.btn:Hide()
            r.label:SetWidth(400)
            r.label:SetText((Cfg(key) and "|cFF00FF00[X]|r " or "|cFFFFFFFF[ ]|r ") .. L(spec.label))
            r:SetScript("OnClick", function()
                SetCfg(key, not Cfg(key))
                Changed()
            end)
            r.btn:SetScript("OnClick", nil)
        else
            r.btn:Show()
            r.label:SetWidth(230)
            r.label:SetText(spec.label)
            r.btn:SetText(spec.text())
            local function click(_, mouse)
                spec.click(mouse)
                Changed()
            end
            r.btn:SetScript("OnClick", click)
            r:SetScript("OnClick", click)
        end
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    wiz.back:SetText(L("SETUP_BACK"))
    if page > 1 then wiz.back:Show() else wiz.back:Hide() end
    wiz.nextBtn:SetText(L(page < PAGES and "SETUP_NEXT" or "SETUP_DONE"))
end

local function Finish()
    WockyDB = WockyDB or {}
    WockyDB.setupDone = true
    wiz:Hide()
end

wiz.back:SetScript("OnClick", function()
    if page > 1 then page = page - 1 end
    Refresh()
end)
wiz.nextBtn:SetScript("OnClick", function()
    if page < PAGES then
        page = page + 1
        Refresh()
    else
        Finish()
    end
end)
-- closing with the X (or Escape) also counts as done, so it does not open again
wiz:SetScript("OnHide", function()
    WockyDB = WockyDB or {}
    WockyDB.setupDone = true
end)

function W.OpenSetup()
    page = 1
    wiz:Show()
    Refresh()
end

---------------------------------------------------------------------------
-- Update notice
---------------------------------------------------------------------------
local note = NewPanel("WockyUpdateFrame", 300, 160)
note.title = W.NewFS(note, W.fonts.normal)
note.title:SetPoint("TOPLEFT", note, "TOPLEFT", 14, -14)
note.title:SetWidth(250)
note.title:SetJustifyH("LEFT")
note.text = W.NewFS(note, W.fonts.high)
note.text:SetPoint("TOPLEFT", note.title, "BOTTOMLEFT", 0, -8)
note.text:SetWidth(272)
note.text:SetJustifyH("LEFT")
note.text:SetJustifyV("TOP")
note.ok = TextButton(note, 90)
note.ok:SetPoint("BOTTOMRIGHT", note, "BOTTOMRIGHT", -12, 12)
note.ok:SetScript("OnClick", function() note:Hide() end)

local noteMode, noteVersion

local function NewsLines(version)
    local keys = HIGHLIGHTS[version]
    local out = {}
    if keys then
        for _, k in ipairs(keys) do out[#out + 1] = L(k) end
        return out
    end
    for _, entry in ipairs(W.NEWS or {}) do
        if entry[1] == version then
            for i = 1, math.min(3, #entry[2]) do out[#out + 1] = entry[2][i] end
        end
    end
    return out
end

local function FillNote()
    if noteMode == "newer" then
        note.title:SetText("|cFF8787EDWockyPro|r - " .. L("UPD_NEW_TITLE", noteVersion or "?"))
        note.text:SetText(L("UPD_NEW_TEXT", W.VERSION))
    else
        note.title:SetText("|cFF8787EDWockyPro|r - " .. L("UPD_TITLE", W.VERSION))
        local lines = {}
        for _, l in ipairs(NewsLines(W.VERSION)) do lines[#lines + 1] = "- " .. l end
        lines[#lines + 1] = "|cFF999999" .. L("UPD_NEWS") .. "|r"
        note.text:SetText(table.concat(lines, "\n"))
    end
    note.ok:SetText(L("UPD_CLOSE"))
    local h = 0
    pcall(function() h = note.text:GetStringHeight() or 0 end)
    note:SetHeight(math.max(120, math.min(320, 64 + h + 30)))
end

local function PlaceNote()
    note:ClearAllPoints()
    local ui = W.WockyUI
    if ui and ui:IsShown() then
        note:SetPoint("TOPLEFT", ui, "TOPRIGHT", 8, 0)
    else
        note:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
end

function W.ShowUpdateNotice(mode, version, force)
    if not force and not Cfg("updateNotice") then return end
    noteMode, noteVersion = mode or "updated", version
    PlaceNote()
    note:Show()
    FillNote()
end

---------------------------------------------------------------------------
-- Version check with group and guild members (addons cannot go online)
---------------------------------------------------------------------------
local lastSend = 0
local shownNewer = nil

local function SendVersion()
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local now = GetTime and GetTime() or 0
    if now - lastSend < 60 then return end
    lastSend = now
    local msg = "V:" .. tostring(W.VERSION)
    pcall(function()
        if IsInGuild and IsInGuild() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD") end
    end)
    pcall(function()
        if IsInRaid and IsInRaid() then
            C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
        elseif IsInGroup and IsInGroup() then
            C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
        end
    end)
end

local function OnVersion(v)
    if not Newer(v, W.VERSION) then return end
    WockyDB = WockyDB or {}
    if not WockyDB.newestSeen or Newer(v, WockyDB.newestSeen) then WockyDB.newestSeen = v end
    if shownNewer ~= WockyDB.newestSeen then
        shownNewer = WockyDB.newestSeen
        W.ShowUpdateNotice("newer", shownNewer)
    end
end

---------------------------------------------------------------------------
-- Events, settings, slash command
---------------------------------------------------------------------------
local prevVersion, freshInstall

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
ev:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == "WockyPro" then
        -- read before WockyExtras stores the new version at PLAYER_LOGIN
        prevVersion = WockyDB and WockyDB.lastVersion
        freshInstall = not (WockyDB and (WockyDB.lastVersion or WockyDB.setupDone))
        pcall(function()
            if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        end)
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            WockyDB = WockyDB or {}
            if freshInstall and not WockyDB.setupDone then
                W.OpenSetup()
            elseif prevVersion and prevVersion ~= W.VERSION then
                W.ShowUpdateNotice("updated")
            elseif WockyDB.newestSeen and Newer(WockyDB.newestSeen, W.VERSION) then
                shownNewer = WockyDB.newestSeen
                W.ShowUpdateNotice("newer", WockyDB.newestSeen)
            end
            -- an older "newest seen" is cleared once you have updated
            if WockyDB.newestSeen and not Newer(WockyDB.newestSeen, W.VERSION) then WockyDB.newestSeen = nil end
        end)
        C_Timer.After(15, SendVersion)
    elseif event == "GROUP_ROSTER_UPDATE" then
        SendVersion()
    elseif event == "CHAT_MSG_ADDON" and arg1 == PREFIX then
        local v = type(arg2) == "string" and string.match(arg2, "^V:(%S+)$")
        if v then OnVersion(v) end
    end
end)

-- keep both windows in the chosen language
local prevApply = W.OnApply
W.OnApply = function()
    if prevApply then pcall(prevApply) end
    if wiz:IsShown() then Refresh() end
    if note:IsShown() then FillNote() end
end

W.AddToggle(W.pageDisplay, "updateNotice", "UPD_TOGGLE")
if W.AddButton then W.AddButton(W.pageDisplay, "SETUP_OPEN", function() W.OpenSetup() end) end

W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky setup", "HELP_SETUP" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "setup" then
        W.OpenSetup()
    elseif m == "update" then
        W.ShowUpdateNotice("updated", nil, true)
    elseif baseSlash then
        baseSlash(msg)
    end
end
