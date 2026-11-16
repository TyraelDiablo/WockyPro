-- WockyTalents: talent map, second (group) build and build sharing strings.
-- /wocky talentmap - small map of the planned talent points for the level you are looking at
-- /wocky build     - window to copy your build as text or import someone else's
-- Build string format: WP1:<A|D|X>:<nodeID>-<rank>.<nodeID>-<rank>...
-- (node IDs are the same in every client language; steps are in pick order)
local W = WockyAPI
if not W then return end

local L, Cfg = W.L, W.Cfg
local TREES = W.TREE_NAMES or { "Affliction", "Demonology", "Destruction" }
local SPEC_CODE = { Affliction = "A", Demonology = "D", Destruction = "X" }
local CODE_SPEC = { A = "Affliction", D = "Demonology", X = "Destruction" }
local MAX_STEPS = 80
local CELL = 30

for k, v in pairs({ groupBuild = false, customBuild = true }) do
    if W.DEFAULTS[k] == nil then W.DEFAULTS[k] = v end
end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

local function Nodes()
    local nodes = {}
    if W.CollectNodes then
        local ok, n = pcall(W.CollectNodes)
        if ok and type(n) == "table" then nodes = n end
    end
    if #nodes > 0 and W.AssignTrees then pcall(W.AssignTrees, nodes) end
    return nodes
end

local function Spec()
    if W.GetBuildSpec then
        local ok, s = pcall(W.GetBuildSpec)
        if ok and type(s) == "string" then return s end
    end
    return "Affliction"
end

---------------------------------------------------------------------------
-- Which build the guide follows
---------------------------------------------------------------------------
local function Imported()
    local c = WockyDB and WockyDB.customBuild
    if type(c) == "table" and type(c.steps) == "table" and #c.steps > 0 then return c end
end

-- "custom", "group" or "solo"
local function BuildKind()
    if Cfg("customBuild") and Imported() then return "custom" end
    if Cfg("groupBuild") and WockyBuildsGroup then return "group" end
    return "solo"
end

local KIND_KEYS = { solo = "BUILD_KIND_SOLO", group = "BUILD_KIND_GROUP", custom = "BUILD_KIND_CUSTOM" }

local function KindName(kind)
    return L(KIND_KEYS[kind or BuildKind()] or "BUILD_KIND_SOLO")
end

-- Called by PlanTalents in WockyPro.lua. Returns a build list or nil (= solo build).
function W.GetBuild(spec, nodes)
    local kind = BuildKind()
    if kind == "custom" then
        if type(nodes) ~= "table" or #nodes == 0 then return nil end
        local byId = {}
        for _, n in ipairs(nodes) do byId[n.id] = n end
        local list = {}
        for _, st in ipairs(Imported().steps) do
            local n = byId[st[1]]
            if n and n.name then list[#list + 1] = { n.name, st[2], TREES[n.tree or 1] or "?" } end
        end
        if #list > 0 then return list end
        return nil
    elseif kind == "group" then
        return WockyBuildsGroup and WockyBuildsGroup[spec]
    end
    return nil
end

function W.BuildSuffix()
    local kind = BuildKind()
    if kind == "solo" then return nil end
    return " - " .. KindName(kind)
end

---------------------------------------------------------------------------
-- Build strings
---------------------------------------------------------------------------
local function EncodeSteps(spec, steps)
    local parts = {}
    for _, st in ipairs(steps) do parts[#parts + 1] = st[1] .. "-" .. st[2] end
    return "WP1:" .. (SPEC_CODE[spec] or "A") .. ":" .. table.concat(parts, ".")
end

-- your current points, lowest rows first so the order is always learnable
local function MineSteps(nodes)
    local have = {}
    for _, n in ipairs(nodes) do
        if (n.pts or 0) > 0 then have[#have + 1] = n end
    end
    table.sort(have, function(a, b)
        if (a.row or 0) ~= (b.row or 0) then return (a.row or 0) < (b.row or 0) end
        if (a.tree or 0) ~= (b.tree or 0) then return (a.tree or 0) < (b.tree or 0) end
        return (a.x or 0) < (b.x or 0)
    end)
    local steps = {}
    for _, n in ipairs(have) do steps[#steps + 1] = { n.id, n.pts } end
    return steps
end

-- planned ranks per node at a level (fromZero plan), and the pick order
local function PlanAt(spec, nodes, level)
    local ranks, order = {}, {}
    local count = math.max(0, math.min(51, (level or 60) - 9))
    if count == 0 or not W.PlanTalents then return ranks, order end
    local ok, picks = pcall(W.PlanTalents, spec, nodes, count, true)
    if not ok or type(picks) ~= "table" then return ranks, order end
    for _, p in ipairs(picks) do
        ranks[p.node] = p.rank
        local last = order[#order]
        if last and last[1] == p.node.id then last[2] = p.rank else order[#order + 1] = { p.node.id, p.rank } end
    end
    return ranks, order
end

local function TotalPoints(steps)
    local seen, total = {}, 0
    for _, st in ipairs(steps) do
        local before = seen[st[1]] or 0
        if st[2] > before then total = total + (st[2] - before); seen[st[1]] = st[2] end
    end
    return total
end

-- returns spec, steps or nil
local function Decode(text)
    if type(text) ~= "string" then return nil end
    local code, body = string.match(text, "WP1:(%a):([%d%.%-]+)")
    local spec = code and CODE_SPEC[string.upper(code)]
    if not spec then return nil end
    local steps = {}
    for id, rank in string.gmatch(body, "(%d+)%-(%d+)") do
        id, rank = tonumber(id), tonumber(rank)
        if not id or not rank or rank < 1 or rank > 5 then return nil end
        steps[#steps + 1] = { id, rank }
        if #steps > MAX_STEPS then return nil end
    end
    if #steps == 0 or TotalPoints(steps) > 61 then return nil end
    return spec, steps
end

local function GameString()
    local s
    pcall(function()
        if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GenerateImportString then
            local cfg = C_ClassTalents.GetActiveConfigID()
            if cfg then s = C_Traits.GenerateImportString(cfg) end
        end
    end)
    if type(s) == "string" and s ~= "" then return s end
end

local function ImportText(text)
    local spec, steps = Decode(text)
    if not spec then return false, L("SHARE_BAD") end
    local nodes = Nodes()
    local missing = 0
    if #nodes > 0 then
        local byId = {}
        for _, n in ipairs(nodes) do byId[n.id] = true end
        for _, st in ipairs(steps) do
            if not byId[st[1]] then missing = missing + 1 end
        end
        if missing == #steps then return false, L("SHARE_MISSING", missing) end
    end
    WockyDB = WockyDB or {}
    WockyDB.customBuild = { spec = spec, steps = steps, text = EncodeSteps(spec, steps) }
    W.SetCfg("customBuild", true)
    local msg = L("SHARE_OK", spec, TotalPoints(steps))
    if missing > 0 then msg = msg .. " " .. L("SHARE_MISSING", missing) end
    return true, msg
end

-- for /wocky report
function W.BuildInfo()
    local kind = BuildKind()
    local line = KindName(kind)
    local c = Imported()
    if c then line = line .. ", imported " .. tostring(c.spec) .. ": " .. tostring(c.text or EncodeSteps(c.spec, c.steps)) end
    local nodes = Nodes()
    if #nodes > 0 then
        local steps = MineSteps(nodes)
        if #steps > 0 then line = line .. ", mine: " .. EncodeSteps(Spec(), steps) end
    end
    return line
end

---------------------------------------------------------------------------
-- Small windows
---------------------------------------------------------------------------
local function MakeWindow(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
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
    pcall(function() table.insert(UISpecialFrames, name) end)
    f.title = W.NewFS(f, W.fonts.normal)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.title:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    f:Hide()
    return f
end

local function Btn(parent, w)
    local b = W.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w, 22)
    return b
end

---------------------------------------------------------------------------
-- Talent map
---------------------------------------------------------------------------
local map, mapLevel
local mapCells = {}

local function CellTip(self)
    local c = self.info
    if not c then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.name or "?", 1, 0.82, 0)
    GameTooltip:AddLine(TREES[c.tree or 1] or "", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L("TMAP_TIP_PLAN", c.plan, c.max), 1, 0.82, 0)
    GameTooltip:AddLine(L("TMAP_TIP_HAVE", c.pts, c.max), 0.3, 1, 0.3)
    GameTooltip:Show()
end

local function GetCell(i)
    local b = mapCells[i]
    if b then return b end
    b = CreateFrame("Button", nil, map)
    b:SetSize(CELL - 4, CELL - 4)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.text = W.NewFS(b, W.fonts.small)
    b.text:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b:SetScript("OnEnter", CellTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapCells[i] = b
    return b
end

local function RefreshMap()
    if not map then return end
    local nodes = Nodes()
    for _, b in ipairs(mapCells) do b:Hide() end
    if #nodes == 0 then
        map.title:SetText("|cFF8787EDWockyPro|r - " .. L("TMAP_NO_DATA"))
        for t = 1, 3 do map.heads[t]:SetText("") end
        return
    end
    local spec = Spec()
    local level = mapLevel or W.GetViewLevel() or 60
    local ranks = PlanAt(spec, nodes, level)
    -- an imported build may be for another spec than yours; name the one the map shows
    local kind = BuildKind()
    local shownSpec = spec
    if kind == "custom" then shownSpec = tostring(Imported().spec or spec) end
    map.title:SetText("|cFF8787EDWockyPro|r - " .. L("TMAP_TITLE", level, shownSpec .. " / " .. KindName(kind)))

    -- column index per tree from the X positions
    local xsByTree = { {}, {}, {} }
    local maxRow = 0
    for _, n in ipairs(nodes) do
        local t = n.tree or 1
        xsByTree[t][n.x or 0] = true
        if (n.row or 0) > maxRow then maxRow = n.row or 0 end
    end
    local colOf, cols = { {}, {}, {} }, { 0, 0, 0 }
    for t = 1, 3 do
        local xs = {}
        for x in pairs(xsByTree[t]) do xs[#xs + 1] = x end
        table.sort(xs)
        for i, x in ipairs(xs) do colOf[t][x] = i - 1 end
        cols[t] = math.max(1, #xs)
    end
    local planPts = { 0, 0, 0 }
    local left = { 12, 0, 0 }
    left[2] = left[1] + cols[1] * CELL + 16
    left[3] = left[2] + cols[2] * CELL + 16
    for i, n in ipairs(nodes) do
        local t = n.tree or 1
        local plan = ranks[n] or 0
        planPts[t] = planPts[t] + plan
        local b = GetCell(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", map, "TOPLEFT", left[t] + (colOf[t][n.x or 0] or 0) * CELL, -52 - (n.row or 0) * CELL)
        b.icon:SetTexture(n.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        pcall(function() b.icon:SetDesaturated(plan == 0 and (n.pts or 0) == 0) end)
        b.icon:SetAlpha((plan > 0 or (n.pts or 0) > 0) and 1 or 0.35)
        local color = "|cFFFFD100"
        if plan > 0 and (n.pts or 0) >= plan then color = "|cFF33FF33" elseif plan == 0 then color = "|cFF999999" end
        local shown = plan > 0 and plan or (n.pts or 0)
        b.text:SetText((shown > 0 or plan > 0) and (color .. shown .. "|r") or "")
        b.info = { name = n.name, tree = t, plan = plan, pts = n.pts or 0, max = n.max or 1 }
        b:Show()
    end
    for t = 1, 3 do
        map.heads[t]:ClearAllPoints()
        map.heads[t]:SetPoint("TOPLEFT", map, "TOPLEFT", left[t], -32)
        map.heads[t]:SetText("|cFFFFD100" .. (TREES[t] or "?") .. "|r " .. planPts[t])
    end
    local w = left[3] + cols[3] * CELL + 12
    local h = 52 + (maxRow + 1) * CELL + 56
    map:SetSize(math.max(w, 380), math.max(h, 200))
end

local function CreateMap()
    map = MakeWindow("WockyTalentMapFrame", 420, 360)
    map.heads = {}
    for t = 1, 3 do
        map.heads[t] = W.NewFS(map, W.fonts.normal)
        map.heads[t]:SetJustifyH("LEFT")
    end
    map.legend = W.NewFS(map, W.fonts.small)
    map.legend:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 12, 36)
    map.legend:SetPoint("RIGHT", map, "RIGHT", -12, 0)
    map.legend:SetJustifyH("LEFT")
    local prev = Btn(map, 30)
    prev:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 12, 10)
    prev:SetText("<")
    prev:SetScript("OnClick", function()
        mapLevel = math.max(10, (mapLevel or 60) - 1)
        RefreshMap()
    end)
    local nxt = Btn(map, 30)
    nxt:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    nxt:SetText(">")
    nxt:SetScript("OnClick", function()
        mapLevel = math.min(W.MAX_LEVEL or 60, (mapLevel or 60) + 1)
        RefreshMap()
    end)
    map.shareBtn = Btn(map, 120)
    map.shareBtn:SetPoint("LEFT", nxt, "RIGHT", 8, 0)
    map.closeBtn = Btn(map, 90)
    map.closeBtn:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -12, 10)
    map.closeBtn:SetScript("OnClick", function() map:Hide() end)
end

local ShowShare

local function ShowMap()
    if not map then CreateMap() end
    if map:IsShown() then map:Hide() return end
    mapLevel = math.max(10, W.GetViewLevel() or 10)
    map.legend:SetText(L("TMAP_LEGEND"))
    map.shareBtn:SetText(L("SHARE_TITLE"))
    map.shareBtn:SetScript("OnClick", function() ShowShare() end)
    map.closeBtn:SetText(L("REPORT_CLOSE"))
    map:Show()
    RefreshMap()
    if #Nodes() == 0 then Chat(L("TMAP_NO_DATA")) end
end
W.ShowTalentMap = ShowMap

---------------------------------------------------------------------------
-- Build sharing window
---------------------------------------------------------------------------
local share, shareBox

local function SetStatus(text)
    if share then share.status:SetText(text or "") end
end

local function FillMine()
    local nodes = Nodes()
    local steps = MineSteps(nodes)
    if #steps == 0 then
        shareBox:SetText("")
        SetStatus(L("SHARE_NONE"))
        return
    end
    local text = EncodeSteps(Spec(), steps)
    local game = GameString()
    if game then text = text .. "\n\n" .. L("SHARE_GAME") .. "\n" .. game end
    shareBox:SetText(text)
    shareBox:SetFocus()
    shareBox:HighlightText()
    SetStatus(L("SHARE_HINT"))
end

local function FillPlan()
    local nodes = Nodes()
    if #nodes == 0 then
        shareBox:SetText("")
        SetStatus(L("TMAP_NO_DATA"))
        return
    end
    local spec = Spec()
    local _, order = PlanAt(spec, nodes, W.MAX_LEVEL or 60)
    if #order == 0 then
        shareBox:SetText("")
        SetStatus(L("SHARE_NONE"))
        return
    end
    shareBox:SetText(EncodeSteps(spec, order))
    shareBox:SetFocus()
    shareBox:HighlightText()
    SetStatus(L("SHARE_HINT"))
end

local function Refresh()
    if W.UpdateWockyGuide then pcall(W.UpdateWockyGuide, W.GetViewLevel()) end
    if W.RefreshSettings then pcall(W.RefreshSettings) end
    if map and map:IsShown() then RefreshMap() end
end

local function CreateShare()
    share = MakeWindow("WockyBuildShareFrame", 520, 230)
    local scroll
    pcall(function() scroll = CreateFrame("ScrollFrame", "WockyBuildShareScroll", share, "UIPanelScrollFrameTemplate") end)
    if not scroll then scroll = CreateFrame("ScrollFrame", "WockyBuildShareScroll", share) end
    scroll:SetPoint("TOPLEFT", share, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", share, "BOTTOMRIGHT", -32, 64)
    shareBox = CreateFrame("EditBox", nil, scroll)
    shareBox:SetMultiLine(true)
    shareBox:SetAutoFocus(false)
    shareBox:SetFontObject(ChatFontNormal or W.fonts.normal)
    shareBox:SetWidth(470)
    shareBox:SetScript("OnEscapePressed", function() share:Hide() end)
    scroll:SetScrollChild(shareBox)
    share.status = W.NewFS(share, W.fonts.small)
    share.status:SetPoint("BOTTOMLEFT", share, "BOTTOMLEFT", 12, 40)
    share.status:SetPoint("RIGHT", share, "RIGHT", -12, 0)
    share.status:SetJustifyH("LEFT")
    share.mine = Btn(share, 100)
    share.mine:SetPoint("BOTTOMLEFT", share, "BOTTOMLEFT", 12, 10)
    share.mine:SetScript("OnClick", FillMine)
    share.plan = Btn(share, 100)
    share.plan:SetPoint("LEFT", share.mine, "RIGHT", 4, 0)
    share.plan:SetScript("OnClick", FillPlan)
    share.import = Btn(share, 90)
    share.import:SetPoint("LEFT", share.plan, "RIGHT", 4, 0)
    share.import:SetScript("OnClick", function()
        local ok, msg = ImportText(shareBox:GetText())
        SetStatus((ok and "|cFF33FF33" or "|cFFFF6666") .. msg .. "|r")
        Chat(msg)
        if ok then Refresh() end
    end)
    share.clear = Btn(share, 110)
    share.clear:SetPoint("LEFT", share.import, "RIGHT", 4, 0)
    share.clear:SetScript("OnClick", function()
        if WockyDB then WockyDB.customBuild = nil end
        SetStatus(L("SHARE_CLEARED"))
        Chat(L("SHARE_CLEARED"))
        Refresh()
    end)
    share.closeBtn = Btn(share, 80)
    share.closeBtn:SetPoint("BOTTOMRIGHT", share, "BOTTOMRIGHT", -12, 10)
    share.closeBtn:SetScript("OnClick", function() share:Hide() end)
end

ShowShare = function()
    if not share then CreateShare() end
    share.title:SetText("|cFF8787EDWockyPro|r - " .. L("SHARE_TITLE"))
    share.mine:SetText(L("SHARE_MINE"))
    share.plan:SetText(L("SHARE_PLAN"))
    share.import:SetText(L("SHARE_IMPORT"))
    share.clear:SetText(L("SHARE_CLEAR"))
    share.closeBtn:SetText(L("REPORT_CLOSE"))
    share:Show()
    FillMine()
end
W.ShowBuildShare = ShowShare

---------------------------------------------------------------------------
-- Small map button next to the talent header
---------------------------------------------------------------------------
pcall(function()
    local header = W.talentHeader
    if not header then return end
    local b = CreateFrame("Button", "WockyTalentMapButton", W.WockyUI)
    b:SetSize(16, 16)
    b:SetPoint("RIGHT", W.WockyUI, "RIGHT", -12, 0)
    b:SetPoint("TOP", header, "TOP", 0, 2)
    pcall(function() b:SetFrameLevel(W.WockyUI:GetFrameLevel() + 5) end)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.2)
    b:SetScript("OnClick", ShowMap)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("TMAP_BUTTON"), 0.45, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pcall(hooksecurefunc, header, "Show", function() b:Show() end)
    pcall(hooksecurefunc, header, "Hide", function() b:Hide() end)
    if not header:IsShown() then b:Hide() end
end)

---------------------------------------------------------------------------
-- Settings, events and slash commands
---------------------------------------------------------------------------
W.AddToggle(W.pageMap, "groupBuild", "GROUP_BUILD")
W.AddToggle(W.pageMap, "customBuild", "CUSTOM_BUILD")

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
ev:SetScript("OnEvent", function()
    if map and map:IsShown() then C_Timer.After(0.2, RefreshMap) end
end)

W.EXTRA_HELP = W.EXTRA_HELP or {}
table.insert(W.EXTRA_HELP, { "/wocky talentmap", "HELP_TALENTMAP" })
table.insert(W.EXTRA_HELP, { "/wocky build", "HELP_BUILD" })

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local raw = strtrim(msg or "")
    local m = string.lower(raw)
    if m == "talentmap" or m == "tmap" or m == "map talents" then
        ShowMap()
    elseif m == "build" or m == "share" or m == "build export" or m == "build import" then
        ShowShare()
    elseif string.sub(m, 1, 13) == "build import " then
        local ok, text = ImportText(strtrim(string.sub(raw, 14)))
        Chat(text)
        if ok then Refresh() end
    elseif m == "build clear" then
        if WockyDB then WockyDB.customBuild = nil end
        Chat(L("SHARE_CLEARED"))
        Refresh()
    elseif m == "build group" or m == "build solo" then
        W.SetCfg("groupBuild", m == "build group")
        Chat(L("TALENT_BUILD") .. ": " .. KindName())
        Refresh()
    elseif baseSlash then
        baseSlash(msg)
    end
end

-- for tests
W._BuildDecode = Decode
W._BuildEncode = EncodeSteps
