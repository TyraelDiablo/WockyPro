-- WockyTools: data check tools.
-- /wocky here   - prints your zone, map ID and coordinates and saves the spot for the report
-- /wocky report - collects version, character, talents, professions, settings and the last Lua error
--                 in a window you can copy from
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local MAX_SPOTS = 20
local MAX_STACK_LINES = 8

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function Safe(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function StripCodes(s)
    s = tostring(s or "")
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|T.-|t", "")
    s = string.gsub(s, "|H.-|h(.-)|h", "%1")
    return s
end

---------------------------------------------------------------------------
-- Last Lua error
---------------------------------------------------------------------------
local lastError

local function ShortStack(stack)
    if type(stack) ~= "string" then return nil end
    local out, n = {}, 0
    for line in string.gmatch(stack, "[^\n]+") do
        n = n + 1
        if n > MAX_STACK_LINES then break end
        out[#out + 1] = line
    end
    return table.concat(out, "\n")
end

local function RecordError(msg)
    local text = tostring(msg or "?")
    local stack = debugstack and Safe(debugstack, 3) or nil
    local e = {
        msg = text,
        stack = ShortStack(stack),
        time = (date and date("%Y-%m-%d %H:%M:%S")) or "",
        version = W.VERSION
    }
    e.wocky = string.find(text, "Wocky", 1, true) ~= nil or (e.stack and string.find(e.stack, "Wocky", 1, true) ~= nil) or false
    lastError = e
    if e.wocky and WockyDB then WockyDB.lastError = e end
end

pcall(function()
    if not geterrorhandler or not seterrorhandler then return end
    local prev = geterrorhandler()
    seterrorhandler(function(msg, ...)
        pcall(RecordError, msg)
        if prev then return prev(msg, ...) end
    end)
end)

-- BugGrabber (BugSack) keeps its own list; use it when it caught something newer
local function BugGrabberError()
    local found
    pcall(function()
        if not BugGrabber or not BugGrabber.GetDB then return end
        local db = BugGrabber:GetDB()
        if type(db) ~= "table" then return end
        for i = #db, 1, -1 do
            local e = db[i]
            local m = e and e.message and tostring(e.message)
            if m and (string.find(m, "Wocky", 1, true) or (e.stack and string.find(tostring(e.stack), "Wocky", 1, true))) then
                found = { msg = m, stack = ShortStack(e.stack and tostring(e.stack)), time = tostring(e.time or ""), wocky = true }
                return
            end
        end
    end)
    return found
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
local function PlayerSpot()
    local spot = {
        zone = (GetRealZoneText and Safe(GetRealZoneText)) or (GetZoneText and Safe(GetZoneText)) or "?",
        sub = (GetSubZoneText and Safe(GetSubZoneText)) or ""
    }
    pcall(function()
        if not C_Map or not C_Map.GetBestMapForUnit then return end
        local mapID = C_Map.GetBestMapForUnit("player")
        if not mapID then return end
        spot.mapID = mapID
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            if x and y and (x > 0 or y > 0) then
                spot.x = math.floor(x * 1000 + 0.5) / 10
                spot.y = math.floor(y * 1000 + 0.5) / 10
            end
        end
        if C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(mapID)
            if info and info.name and info.name ~= "" then spot.mapName = info.name end
        end
    end)
    return spot
end

local function CoordText(x, y)
    if not x or not y then return L("HERE_NO_COORDS") end
    return string.format("%.1f, %.1f", x, y)
end

local function SpotLine(s)
    local place = s.zone or "?"
    if s.sub and s.sub ~= "" and s.sub ~= s.zone then place = place .. " - " .. s.sub end
    local line = place .. "  " .. CoordText(s.x, s.y)
    if s.mapID then line = line .. "  (map " .. s.mapID .. ")" end
    if s.level then line = line .. "  Lvl " .. s.level end
    if s.note and s.note ~= "" then line = line .. "  \"" .. s.note .. "\"" end
    return line
end

local function GuideData(level)
    local key = W.RouteKey and Safe(W.RouteKey)
    local route = key and WockyGuideDB and WockyGuideDB[key]
    return route and route["L" .. tostring(level)], key
end

local function Spots()
    WockyDB = WockyDB or {}
    WockyDB.spots = WockyDB.spots or {}
    return WockyDB.spots
end

local function DoHere(note)
    local s = PlayerSpot()
    s.level = UnitLevel and Safe(UnitLevel, "player") or nil
    s.note = note
    s.time = (date and date("%Y-%m-%d %H:%M")) or ""
    Chat(L("HERE_HEADER"))
    print("  " .. SpotLine(s))
    -- guide data uses English zone names; find it from the map ID so other client languages work too
    local dbZone = s.zone
    if s.mapID and W.MAP_IDS then
        for name, id in pairs(W.MAP_IDS) do
            if id == s.mapID and (dbZone == s.zone or string.len(name) > string.len(dbZone)) then dbZone = name end
        end
    end
    s.dbZone = dbZone
    if s.x and s.y then
        print(string.format("  |cFF999999zone = \"%s\", x = %.1f, y = %.1f|r", dbZone or "?", s.x, s.y))
    end
    local viewLevel = (W.GetViewLevel and Safe(W.GetViewLevel)) or s.level
    local data = GuideData(viewLevel)
    if data and data.zone and data.x and data.y then
        local target = (data.npc or data.zone) .. " - " .. data.zone .. " " .. CoordText(data.x, data.y)
        print("  " .. L("HERE_GUIDE", viewLevel or 0, target))
        local targetMap = W.MAP_IDS and W.MAP_IDS[data.zone]
        local same
        if targetMap and s.mapID then same = (targetMap == s.mapID) else same = (data.zone == s.zone or data.zone == dbZone) end
        if s.x and s.y and same then
            local dx, dy = s.x - data.x, s.y - data.y
            print("  " .. L("HERE_DIFF", string.format("%.1f", math.sqrt(dx * dx + dy * dy))))
        elseif not same then
            print("  " .. L("HERE_OTHER_ZONE"))
        end
    end
    local list = Spots()
    table.insert(list, 1, s)
    while #list > MAX_SPOTS do table.remove(list) end
    print("  |cFF999999" .. L("HERE_SAVED", #list) .. "|r")
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function CfgDiffs()
    local out = {}
    local cfg = WockyDB and WockyDB.cfg
    if type(cfg) ~= "table" then return out end
    for k, v in pairs(cfg) do
        local d = W.DEFAULTS and W.DEFAULTS[k]
        if type(v) ~= "table" and v ~= d and not (d == nil and v == "auto") then out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    end
    table.sort(out)
    return out
end

local function OtherAddons()
    local names = {}
    pcall(function()
        local num = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
        local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        for i = 1, num do
            local name = getInfo and getInfo(i)
            if name and name ~= "WockyPro" and isLoaded and isLoaded(name) then names[#names + 1] = name end
        end
    end)
    table.sort(names)
    return names
end

local function BuildReport()
    local r = {}
    local function add(s) r[#r + 1] = s end
    add("WockyPro " .. tostring(W.VERSION) .. " report")
    add(L("REPORT_WRITE"))
    add("")
    pcall(function()
        local version, build, _, toc = GetBuildInfo()
        add("Client: " .. tostring(version) .. " (" .. tostring(build) .. "), Interface " .. tostring(toc))
    end)
    local lang = (W.ActiveLang and Safe(W.ActiveLang)) or "?"
    add("Locale: " .. tostring(GetLocale and Safe(GetLocale) or "?") .. ", WockyPro language: " .. tostring(lang))
    pcall(function()
        local race, raceEn = UnitRace("player")
        local class, classEn = UnitClass("player")
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        add("Character: Lvl " .. tostring(UnitLevel("player")) .. " " .. tostring(race) .. " (" .. tostring(raceEn) .. ") "
            .. tostring(class) .. " (" .. tostring(classEn) .. "), " .. tostring(faction))
    end)
    local key = W.RouteKey and Safe(W.RouteKey)
    local pick = (Cfg and Safe(Cfg, "route")) or "auto"
    add("Route: " .. tostring(key) .. " (" .. tostring(pick) .. "), viewing Lvl " .. tostring(W.GetViewLevel and Safe(W.GetViewLevel)))
    add("Talents: " .. StripCodes((W.GetSpecText and Safe(W.GetSpecText)) or "?")
        .. ((WockyDB and WockyDB.spec) and (" (set by hand: " .. tostring(WockyDB.spec) .. ")") or ""))
    local profs = {}
    pcall(function()
        for _, p in pairs(W.DetectProfessions() or {}) do
            profs[#profs + 1] = tostring(p.name) .. " " .. tostring(p.rank) .. "/" .. tostring(p.max)
        end
    end)
    table.sort(profs)
    add("Professions: " .. (#profs > 0 and table.concat(profs, ", ") or "-"))
    add("Here: " .. SpotLine(PlayerSpot()))
    local diffs = CfgDiffs()
    add("Changed settings: " .. (#diffs > 0 and table.concat(diffs, ", ") or "-"))
    local addons = OtherAddons()
    add("Other addons (" .. #addons .. "): " .. (#addons > 0 and table.concat(addons, ", ") or "-"))
    add("")
    local e = BugGrabberError()
    if lastError and lastError.wocky then e = lastError end
    if not e and WockyDB and WockyDB.lastError then e = WockyDB.lastError end
    if e then
        add("Last WockyPro error (" .. tostring(e.time) .. (e.version and (", " .. tostring(e.version)) or "") .. "):")
        add(StripCodes(e.msg))
        if e.stack and e.stack ~= "" then add(StripCodes(e.stack)) end
    elseif lastError then
        add("No WockyPro error. Last error from another addon:")
        add(StripCodes(lastError.msg))
    else
        add("No Lua error caught.")
    end
    local list = Spots()
    if #list > 0 then
        add("")
        add("Saved spots (/wocky here):")
        for _, s in ipairs(list) do add("  " .. tostring(s.time or "") .. "  " .. SpotLine(s)) end
    end
    return table.concat(r, "\n")
end

local copyFrame, copyBox, copyTitle
local function CreateCopyFrame()
    local f = CreateFrame("Frame", "WockyReportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, 380)
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
    pcall(function() table.insert(UISpecialFrames, "WockyReportFrame") end)

    copyTitle = W.NewFS(f, W.fonts.normal)
    copyTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    copyTitle:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    copyTitle:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    local scroll
    pcall(function() scroll = CreateFrame("ScrollFrame", "WockyReportScroll", f, "UIPanelScrollFrameTemplate") end)
    if not scroll then scroll = CreateFrame("ScrollFrame", "WockyReportScroll", f) end
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 40)

    copyBox = CreateFrame("EditBox", nil, scroll)
    copyBox:SetMultiLine(true)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject(ChatFontNormal or W.fonts.normal)
    copyBox:SetWidth(470)
    copyBox:SetScript("OnEscapePressed", function() f:Hide() end)
    -- read only: any typing puts the report back
    copyBox:SetScript("OnTextChanged", function(self, user)
        if user and f.text then self:SetText(f.text); self:HighlightText() end
    end)
    scroll:SetScrollChild(copyBox)

    local sel = W.StyleButton(CreateFrame("Button", nil, f, "UIPanelButtonTemplate"))
    sel:SetSize(150, 22)
    sel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    sel:SetScript("OnClick", function() copyBox:SetFocus(); copyBox:HighlightText() end)
    f.selButton = sel

    local done = W.StyleButton(CreateFrame("Button", nil, f, "UIPanelButtonTemplate"))
    done:SetSize(100, 22)
    done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    done:SetScript("OnClick", function() f:Hide() end)
    f.doneButton = done

    f:Hide()
    return f
end

local function ShowReport()
    if not copyFrame then copyFrame = CreateCopyFrame() end
    local text = BuildReport()
    copyFrame.text = text
    copyTitle:SetText("|cFF8787EDWockyPro|r - " .. L("REPORT_TITLE"))
    copyFrame.selButton:SetText(L("REPORT_SELECT"))
    copyFrame.doneButton:SetText(L("REPORT_CLOSE"))
    copyBox:SetText(text)
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
    Chat(L("REPORT_HINT"))
end

W.BuildReport = BuildReport
W.ShowReport = ShowReport
W.PlayerSpot = PlayerSpot

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local raw = strtrim(msg or "")
    local m = string.lower(raw)
    if m == "here clear" then
        WockyDB = WockyDB or {}
        WockyDB.spots = {}
        Chat(L("HERE_CLEARED"))
    elseif m == "here" or string.sub(m, 1, 5) == "here " then
        local note = strtrim(string.sub(raw, 6) or "")
        DoHere(note ~= "" and string.sub(note, 1, 60) or nil)
    elseif m == "report" or m == "bug" then
        ShowReport()
    elseif baseSlash then
        baseSlash(msg)
    end
end
