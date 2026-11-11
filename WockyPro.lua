-- WockyPro
-- The version comes from the .toc (filled in from the git tag when packaged).
local VERSION = "3.0.0"
pcall(function()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get("WockyPro", "Version")
    if type(v) == "string" and v ~= "" and not string.find(v, "@", 1, true) then
        VERSION = (string.gsub(v, "^[vV]", ""))
    end
end)
local MAX_LEVEL = 60
local viewLevel = 1
local combatHidden = false

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------
local DEFAULTS = {
    lang = "auto", scale = 1, alpha = 0.92, fontOffset = 0, accent = 1,
    locked = false, minimap = true, minimapAngle = 215,
    showOnLogin = true, hideCombat = false, autoLevel = true,
    showQuests = true, showProf = true, showTalents = true,
    showShards = true, showBags = true, showChar = true,
    openMap = true, printCoords = true, useTomTom = true,
    showXP = true, showReminders = true, shardMin = 3, collapsed = false,
    showStones = true, showMoney = true
}

local function InitDB()
    WockyDB = WockyDB or {}
    WockyDB.done = WockyDB.done or {}
    WockyDB.cfg = WockyDB.cfg or {}
    for k, v in pairs(DEFAULTS) do
        if WockyDB.cfg[k] == nil then WockyDB.cfg[k] = v end
    end
end

local function Cfg(key)
    local c = WockyDB and WockyDB.cfg
    if c and c[key] ~= nil then return c[key] end
    return DEFAULTS[key]
end

local function SetCfg(key, value)
    WockyDB = WockyDB or {}
    WockyDB.cfg = WockyDB.cfg or {}
    WockyDB.cfg[key] = value
end

local ACCENTS = {
    { 0.60, 0.20, 0.80, "8787ED" },
    { 0.20, 0.80, 0.30, "55FF77" },
    { 0.20, 0.50, 1.00, "66AAFF" },
    { 0.90, 0.20, 0.20, "FF6666" },
    { 1.00, 0.55, 0.10, "FF9944" },
    { 1.00, 0.82, 0.00, "FFD100" }
}

---------------------------------------------------------------------------
-- Localization
---------------------------------------------------------------------------
local LANG_CODES = { "auto", "enUS", "trTR", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local LANG_NAMES = {
    auto = "Auto", enUS = "English", trTR = "Turkish", deDE = "German", esES = "Spanish (Spain)",
    esMX = "Spanish (Mexico)", frFR = "French", itIT = "Italian", ptBR = "Portuguese (Brazil)",
    ruRU = "Russian", koKR = "Korean", zhCN = "Chinese (Simplified)", zhTW = "Chinese (Traditional)"
}

local function ActiveLang()
    local l = Cfg("lang")
    if l == "auto" then
        l = (GetLocale and GetLocale()) or "enUS"
        if l == "enGB" then l = "enUS" end
        if not (WockyLocales and WockyLocales[l]) then l = "enUS" end
    end
    if not (WockyLocales and WockyLocales[l]) then l = "enUS" end
    return l
end

local function L(key, ...)
    local tbl = WockyLocales and WockyLocales[ActiveLang()]
    local en = WockyLocales and WockyLocales.enUS
    local s = (tbl and tbl[key]) or (en and en[key]) or key
    if select("#", ...) > 0 then
        local ok, r = pcall(string.format, s, ...)
        if ok then return r end
    end
    return s
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
local FONT_BY_LANG = {
    trTR = "Fonts\\ARIALN.TTF", ruRU = "Fonts\\ARIALN.TTF",
    koKR = "Fonts\\2002.TTF", zhCN = "Fonts\\ARKai_T.ttf", zhTW = "Fonts\\bLEI00D.ttf"
}
local BASE_SIZE = { normal = 12, large = 16, small = 11, high = 12 }
local fonts = {
    normal = CreateFont("WockyFontNormal"),
    large = CreateFont("WockyFontLarge"),
    small = CreateFont("WockyFontSmall"),
    high = CreateFont("WockyFontHighlight")
}
local styledButtons = {}
local currentFontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function ApplyFonts()
    local std = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local alt = FONT_BY_LANG[ActiveLang()]
    local offset = Cfg("fontOffset")
    local usedAlt = false
    for key, f in pairs(fonts) do
        local size = BASE_SIZE[key] + offset
        local ok, valid = false, nil
        if alt then ok, valid = pcall(f.SetFont, f, alt, size, "") end
        if alt and ok and valid ~= false then
            usedAlt = true
        else
            pcall(f.SetFont, f, std, size, "")
        end
    end
    currentFontPath = usedAlt and alt or std
    pcall(function()
        fonts.normal:SetTextColor(1, 0.82, 0)
        fonts.large:SetTextColor(1, 0.82, 0)
        fonts.small:SetTextColor(1, 0.82, 0)
        fonts.high:SetTextColor(1, 1, 1)
    end)
    for _, b in ipairs(styledButtons) do
        pcall(function()
            local fs = b:GetFontString()
            if fs then fs:SetFont(currentFontPath, BASE_SIZE.normal + offset, "") end
        end)
    end
end

local function StyleButton(b)
    styledButtons[#styledButtons + 1] = b
    return b
end

local function NewFS(parent, fontObj)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(fontObj)
    return fs
end

ApplyFonts()

---------------------------------------------------------------------------
-- Map targets
---------------------------------------------------------------------------
local MAP_IDS = {
    ["Tirisfal Glades"] = 1420, ["Undercity"] = 1458, ["Silverpine Forest"] = 1421,
    ["The Barrens"] = 1413, ["Hillsbrad"] = 1424, ["Hillsbrad Foothills"] = 1424,
    ["Thousand Needles"] = 1441, ["Ashenvale"] = 1440, ["Desolace"] = 1443,
    ["Arathi"] = 1417, ["Arathi Highlands"] = 1417, ["Stranglethorn Vale"] = 1434,
    ["Badlands"] = 1418, ["Feralas"] = 1444, ["Tanaris"] = 1446,
    ["The Hinterlands"] = 1425, ["Azshara"] = 1447, ["Searing Gorge"] = 1427,
    ["UnGoro Crater"] = 1449, ["Felwood"] = 1448, ["Western Plaguelands"] = 1422,
    ["Eastern Plaguelands"] = 1423, ["Winterspring"] = 1452, ["Burning Steppes"] = 1428,
    ["Silithus"] = 1451, ["Durotar"] = 1411, ["Orgrimmar"] = 1454, ["Elwynn Forest"] = 1429,
    ["Stormwind City"] = 1453, ["Dun Morogh"] = 1426, ["Ironforge"] = 1455, ["Westfall"] = 1436,
    ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433, ["Duskwood"] = 1431, ["Wetlands"] = 1437,
    ["Darkshore"] = 1439, ["Dustwallow Marsh"] = 1445, ["Stonetalon Mountains"] = 1442,
    ["Alterac Mountains"] = 1416, ["Swamp of Sorrows"] = 1435, ["Blasted Lands"] = 1419
}

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local WockyUI = CreateFrame("Frame", "WockyMainFrame", UIParent, "BackdropTemplate")
WockyUI:SetSize(360, 240)
WockyUI:SetMovable(true)
WockyUI:EnableMouse(true)
WockyUI:RegisterForDrag("LeftButton")
WockyUI:SetScript("OnDragStart", function(self)
    if not Cfg("locked") then self:StartMoving() end
end)
WockyUI:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if p then
        WockyDB = WockyDB or {}
        WockyDB.pos = { p, rp, x, y }
    end
end)
WockyUI:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
WockyUI:SetBackdropColor(0, 0, 0, 0.92)
WockyUI:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)

local title = NewFS(WockyUI, fonts.large)
title:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -12)

local charInfoText = NewFS(WockyUI, fonts.small)
charInfoText:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -34)
charInfoText:SetWidth(200)
charInfoText:SetJustifyH("LEFT")
pcall(function() charInfoText:SetWordWrap(false) end)

local charSpecText = NewFS(WockyUI, fonts.small)
charSpecText:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -47)
charSpecText:SetWidth(200)
charSpecText:SetJustifyH("LEFT")
pcall(function() charSpecText:SetWordWrap(false) end)

-- WoW Forever: UnitName("player") returns first name + surname (other clients: name + realm)
local function GetPlayerFullName()
    local first, surname
    pcall(function()
        local realm = (GetRealmName and GetRealmName()) or ""
        local realmNoSpace = string.gsub(realm, "[%s%-]", "")
        local function usable(s)
            return type(s) == "string" and s ~= "" and s ~= realm and s ~= realmNoSpace
        end
        local a, b = UnitName("player")
        first = a
        if usable(b) then surname = b end
        if not surname and UnitFullName then
            local _, b2 = UnitFullName("player")
            if usable(b2) then surname = b2 end
        end
        if not surname and GetUnitName and first then
            local full = GetUnitName("player", true)
            if type(full) == "string" and string.sub(full, 1, #first + 1) == first .. " " then
                local rest = string.sub(full, #first + 2)
                if usable(rest) then surname = rest end
            end
        end
    end)
    first = first or "Player"
    if surname then return first .. " " .. surname end
    return first
end

local shardText = NewFS(WockyUI, fonts.normal)
shardText:SetPoint("TOPRIGHT", WockyUI, "TOPRIGHT", -16, -14)

local bagButton = StyleButton(CreateFrame("Button", "WockyBagButton", WockyUI, "UIPanelButtonTemplate"))
bagButton:SetSize(70, 20)
bagButton:SetPoint("TOPRIGHT", WockyUI, "TOPRIGHT", -16, -32)
bagButton:SetScript("OnClick", function()
    if ToggleAllBags then ToggleAllBags() end
end)

local gearButton = StyleButton(CreateFrame("Button", "WockyGearButton", WockyUI, "UIPanelButtonTemplate"))
gearButton:SetSize(22, 20)
gearButton:SetPoint("RIGHT", bagButton, "LEFT", -4, 0)
gearButton:SetText("S")

local questHeader = NewFS(WockyUI, fonts.normal)
local profHeader = NewFS(WockyUI, fonts.normal)
local talentHeader = NewFS(WockyUI, fonts.normal)

local collapseButton = StyleButton(CreateFrame("Button", "WockyCollapseButton", WockyUI, "UIPanelButtonTemplate"))
collapseButton:SetSize(22, 20)
collapseButton:SetPoint("RIGHT", gearButton, "LEFT", -4, 0)

local xpBar = CreateFrame("StatusBar", nil, WockyUI)
xpBar:SetSize(328, 10)
xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
xpBar:SetStatusBarColor(0.58, 0.0, 0.55)
xpBar:SetMinMaxValues(0, 1)
xpBar:SetValue(0)
local xpBg = xpBar:CreateTexture(nil, "BACKGROUND")
xpBg:SetAllPoints(xpBar)
xpBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
local xpRestTex = xpBar:CreateTexture(nil, "BORDER")
xpRestTex:SetPoint("TOPLEFT", xpBar, "TOPLEFT", 0, 0)
xpRestTex:SetPoint("BOTTOMLEFT", xpBar, "BOTTOMLEFT", 0, 0)
xpRestTex:SetColorTexture(0.0, 0.39, 0.88, 0.6)
xpRestTex:SetWidth(1)
local xpText = NewFS(WockyUI, fonts.small)
xpText:SetWidth(328)
xpText:SetJustifyH("LEFT")

local remindText = NewFS(WockyUI, fonts.small)
remindText:SetWidth(328)
remindText:SetJustifyH("LEFT")
remindText:SetJustifyV("TOP")

-- Status row: Healthstone / Soulstone icons on the left, money on the right
local statusRow = CreateFrame("Frame", nil, WockyUI)
statusRow:SetSize(328, 30)

local function MakeStoneButton(iconPath)
    local b = CreateFrame("Button", nil, statusRow)
    b:SetSize(28, 28)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    local cd
    pcall(function() cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate") end)
    if not cd then pcall(function() cd = CreateFrame("Cooldown", nil, b) end) end
    if cd then
        cd:SetAllPoints(b)
        pcall(function() cd:SetHideCountdownNumbers(true) end)
        pcall(function() cd:SetDrawEdge(false) end)
        cd:Hide()
    end
    b.cd = cd

    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints(b)
    pcall(function() over:SetFrameLevel(b:GetFrameLevel() + 5) end)
    local timer = over:CreateFontString(nil, "OVERLAY")
    timer:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.timer = timer
    local count = over:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.count = count

    local glow = over:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    glow:SetSize(54, 54)
    glow:SetVertexColor(0.8, 0.4, 1)
    glow:Hide()
    local anim
    pcall(function()
        anim = glow:CreateAnimationGroup()
        local a = anim:CreateAnimation("Alpha")
        if a.SetFromAlpha then
            a:SetFromAlpha(1)
            a:SetToAlpha(0.2)
        else
            a:SetChange(-0.8)
        end
        a:SetDuration(0.6)
        anim:SetLooping("BOUNCE")
    end)
    b.SetGlow = function(self, on)
        if on and not self.glowing then
            glow:Show()
            if anim then pcall(anim.Play, anim) end
        elseif not on and self.glowing then
            if anim then pcall(anim.Stop, anim) end
            glow:Hide()
        end
        self.glowing = on and true or false
    end

    b:SetScript("OnEnter", function(self)
        if not self.tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tipTitle)
        if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local hsBtn = MakeStoneButton("Interface\\Icons\\INV_Stone_04")
hsBtn:SetPoint("TOPLEFT", statusRow, "TOPLEFT", 1, -1)
local ssBtn = MakeStoneButton("Interface\\Icons\\Spell_Shadow_SoulGem")
ssBtn:SetPoint("TOPLEFT", statusRow, "TOPLEFT", 37, -1)

local moneyText = NewFS(statusRow, fonts.normal)
moneyText:SetPoint("RIGHT", statusRow, "RIGHT", 0, 0)
moneyText:SetJustifyH("RIGHT")
local moneyBtn = CreateFrame("Button", nil, statusRow)
moneyBtn:SetAllPoints(moneyText)

---------------------------------------------------------------------------
-- Shards and talents
---------------------------------------------------------------------------
local function BagCounts()
    local counts = {}
    pcall(function()
        local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
        local getID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
        if not getSlots or not getID then return end
        for bag = 0, 4 do
            local slots = getSlots(bag) or 0
            for slot = 1, slots do
                local id = getID(bag, slot)
                if id then counts[id] = (counts[id] or 0) + 1 end
            end
        end
    end)
    return counts
end

local function CountShards()
    return BagCounts()[6265] or 0
end

local HEALTHSTONE_IDS = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }
local SOULSTONE_IDS = { 5232, 16892, 16893, 16895, 16896 }

local function HasAny(counts, ids)
    for _, id in ipairs(ids) do
        if counts[id] then return true end
    end
    return false
end

local function UpdateShards()
    shardText:SetText(L("SHARD") .. ": |cFF8787ED" .. CountShards() .. "|r")
end

local TREE_NAMES = { "Affliction", "Demonology", "Destruction" }
local nodeNameCache = {}

local function NormName(s)
    return (string.gsub(string.lower(s or ""), "[^%w]", ""))
end

local function SpellNameIcon(spellID)
    if not spellID then return nil, nil end
    local name, icon
    pcall(function()
        if C_Spell and C_Spell.GetSpellInfo then
            local si = C_Spell.GetSpellInfo(spellID)
            if type(si) == "table" then name, icon = si.name, si.iconID or si.originalIconID end
        end
    end)
    if not name then
        pcall(function()
            local n, _, ic = GetSpellInfo(spellID)
            name, icon = n, icon or ic
        end)
    end
    if not icon then pcall(function() icon = GetSpellTexture(spellID) end) end
    return name, icon
end

local function NodeNameIcon(cfg, nodeID, ni)
    local c = nodeNameCache[nodeID]
    if c then return c.name, c.icon end
    local name, icon
    pcall(function()
        local entryID = (ni.activeEntry and ni.activeEntry.entryID) or (ni.entryIDs and ni.entryIDs[1])
        if not entryID then return end
        local ei = C_Traits.GetEntryInfo(cfg, entryID)
        if not ei or not ei.definitionID then return end
        local di = C_Traits.GetDefinitionInfo(ei.definitionID)
        if not di then return end
        if di.overrideName and di.overrideName ~= "" then name = di.overrideName end
        local sn, si = SpellNameIcon(di.spellID or di.overriddenSpellID)
        name = name or sn
        icon = di.overrideIcon or si
    end)
    if name then nodeNameCache[nodeID] = { name = name, icon = icon } end
    return name, icon
end

local function CollectNodes()
    local nodes = {}
    pcall(function()
        local cfg = C_ClassTalents.GetActiveConfigID()
        if not cfg then return end
        local ci = C_Traits.GetConfigInfo(cfg)
        if not ci or not ci.treeIDs then return end
        for _, treeID in ipairs(ci.treeIDs) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
                local ni = C_Traits.GetNodeInfo(cfg, nodeID)
                if ni and ni.posX then
                    local pts = ni.ranksPurchased
                    if type(pts) ~= "number" then pts = ni.currentRank or 0 end
                    local name, icon = NodeNameIcon(cfg, nodeID, ni)
                    nodes[#nodes + 1] = {
                        id = nodeID, x = ni.posX, y = ni.posY or 0, pts = pts,
                        max = ni.maxRanks or 1, name = name, icon = icon,
                        key = name and NormName(name),
                        avail = ni.isAvailable, edges = ni.meetsEdgeRequirements
                    }
                end
            end
        end
    end)
    return nodes
end

local function FindSplits(nodes)
    local seen, xs = {}, {}
    for _, n in ipairs(nodes) do
        if not seen[n.x] then seen[n.x] = true; xs[#xs + 1] = n.x end
    end
    table.sort(xs)
    local gaps = {}
    for i = 1, #xs - 1 do gaps[#gaps + 1] = { size = xs[i + 1] - xs[i], at = (xs[i] + xs[i + 1]) / 2 } end
    table.sort(gaps, function(a, b) return a.size > b.size end)
    if #gaps < 2 then return nil, xs, gaps end
    local s1, s2 = gaps[1].at, gaps[2].at
    if s1 > s2 then s1, s2 = s2, s1 end
    return { s1, s2 }, xs, gaps
end

-- Puts every node in tree 1-3 (by X position) and row 0-n (by Y position inside its tree)
local function AssignTrees(nodes)
    local splits = FindSplits(nodes)
    local ysByTree = { {}, {}, {} }
    for _, n in ipairs(nodes) do
        local idx = 1
        if splits then
            if n.x > splits[2] then idx = 3 elseif n.x > splits[1] then idx = 2 end
        end
        n.tree = idx
        ysByTree[idx][n.y] = true
    end
    for tr = 1, 3 do
        local ys = {}
        for y in pairs(ysByTree[tr]) do ys[#ys + 1] = y end
        table.sort(ys)
        local rowOf = {}
        for i, y in ipairs(ys) do rowOf[y] = i - 1 end
        ysByTree[tr] = rowOf
    end
    for _, n in ipairs(nodes) do n.row = ysByTree[n.tree][n.y] or 0 end
    return splits ~= nil
end

local function GetTreePoints(nodes)
    nodes = nodes or CollectNodes()
    local split = AssignTrees(nodes)
    local pts, total = { 0, 0, 0 }, 0
    for _, n in ipairs(nodes) do
        if n.pts > 0 then
            total = total + n.pts
            pts[n.tree] = pts[n.tree] + n.pts
        end
    end
    return pts, total, split
end

local function GetBuildSpec()
    if WockyDB and WockyDB.spec then return WockyDB.spec end
    local pts, total, split = GetTreePoints()
    if total > 0 and split then
        local best, bestPts = 1, -1
        for i = 1, 3 do
            if pts[i] > bestPts then best = i; bestPts = pts[i] end
        end
        return TREE_NAMES[best]
    end
    return "Affliction"
end

-- Character line: always shows the same spec the talent guide uses
local function GetSpecText()
    local pts, total, split = GetTreePoints()
    local manual = WockyDB and WockyDB.spec
    if total == 0 and not manual then return L("NO_TALENTS") end
    if not split and not manual then return "Talents " .. total end
    return GetBuildSpec() .. " (" .. pts[1] .. "/" .. pts[2] .. "/" .. pts[3] .. ")"
end

-- Walks the build priority list against the real tree.
-- fromZero = plan for a fresh character, otherwise start from the points you have now.
local function PlanTalents(spec, nodes, count, fromZero)
    local build = WockyBuilds and WockyBuilds[spec]
    local picks, missing = {}, {}
    if not build then return picks, missing end
    local byKey = {}
    for _, n in ipairs(nodes) do
        if n.key then byKey[n.key] = n end
    end
    local seenMissing = {}
    for _, step in ipairs(build) do
        if not byKey[NormName(step[1])] and not seenMissing[step[1]] then
            seenMissing[step[1]] = true
            missing[#missing + 1] = step[1]
        end
    end
    local ranks, treePts = {}, { 0, 0, 0 }
    for _, n in ipairs(nodes) do
        local r = fromZero and 0 or n.pts
        ranks[n] = r
        treePts[n.tree] = treePts[n.tree] + r
    end
    local function pick(useLive, useGate)
        for _, step in ipairs(build) do
            local n = byKey[NormName(step[1])]
            if n and ranks[n] < math.min(step[2], n.max) then
                local ok = true
                if useGate and treePts[n.tree] < (n.row or 0) * 5 then ok = false end
                if useLive and (n.avail == false or n.edges == false) then ok = false end
                if ok then return n end
            end
        end
    end
    for i = 1, count do
        local n
        if not fromZero and i == 1 then n = pick(true, true) end
        n = n or pick(false, true) or pick(false, false)
        if not n then break end
        ranks[n] = ranks[n] + 1
        treePts[n.tree] = treePts[n.tree] + 1
        picks[#picks + 1] = { node = n, rank = ranks[n] }
    end
    return picks, missing
end

-- Old fixed-order fallback, used only if the talent API is not available
local function GetTalentLine(spec, level)
    local build = WockyBuilds and WockyBuilds[spec]
    if not build then return L("NO_BUILD", spec) end
    if level < 10 then return L("TALENT_NONE_YET") end
    local idx, n, have = level - 9, 0, {}
    for _, step in ipairs(build) do
        local from = have[step[1]] or 0
        local add = step[2] - from
        if add > 0 then
            if idx <= n + add then
                return L("TALENT_TAKE", "|cFFFFD100" .. step[1] .. "|r", from + (idx - n), step[2], step[3])
            end
            n = n + add
            have[step[1]] = step[2]
        end
    end
    return L("TALENT_DONE")
end

local function TalentIcon(n)
    if n and n.icon then return "|T" .. n.icon .. ":14:14:0:0|t " end
    return ""
end

local function TalentTip(n, rank)
    return {
        { n.name, 1, 0.82, 0 },
        { TREE_NAMES[n.tree] .. "  " .. rank .. "/" .. n.max, 1, 1, 1 }
    }
end

-- Returns rows for the talent section and the number of unspent points
local function TalentRows(spec, level)
    local rows = {}
    if level < 10 then
        rows[1] = { text = L("TALENT_NONE_YET") }
        return rows, nil
    end
    local nodes = CollectNodes()
    if #nodes == 0 then
        rows[1] = { text = GetTalentLine(spec, level) }
        return rows, nil
    end
    AssignTrees(nodes)
    local pLevel = UnitLevel("player") or 1
    local spent = 0
    for _, n in ipairs(nodes) do spent = spent + n.pts end
    local unspent = math.max(0, math.max(0, pLevel - 9) - spent)

    if level == pLevel then
        local picks, missing = PlanTalents(spec, nodes, 3, false)
        if #picks == 0 then
            if spent >= 51 then
                rows[1] = { text = L("TALENT_DONE") }
            elseif #missing > 0 then
                rows[1] = { text = "|cFFFF6666" .. L("TALENT_MISSING", table.concat(missing, ", ")) .. "|r" }
            else
                rows[1] = { text = L("TALENT_BUILD_DONE") }
            end
            return rows, unspent
        end
        local first = picks[1]
        rows[1] = {
            text = TalentIcon(first.node) .. L("TALENT_TAKE", "|cFFFFD100" .. first.node.name .. "|r", first.rank, first.node.max, TREE_NAMES[first.node.tree]),
            tip = TalentTip(first.node, first.rank)
        }
        if #picks > 1 then
            local rest = {}
            for i = 2, #picks do
                local p = picks[i]
                rest[#rest + 1] = TalentIcon(p.node) .. p.node.name .. " (" .. p.rank .. "/" .. p.node.max .. ")"
            end
            rows[2] = { text = "|cFFAAAAAA" .. L("TALENT_THEN", table.concat(rest, ", ")) .. "|r" }
        end
        return rows, unspent
    end

    local picks = PlanTalents(spec, nodes, level - 9, true)
    local p = picks[level - 9]
    if p then
        rows[1] = {
            text = TalentIcon(p.node) .. L("TALENT_PLAN", level, "|cFFFFD100" .. p.node.name .. "|r", p.rank, p.node.max, TREE_NAMES[p.node.tree]),
            tip = TalentTip(p.node, p.rank)
        }
    else
        rows[1] = { text = L("TALENT_BUILD_DONE") }
    end
    return rows, nil
end

local function SetMapPing(zone, x, y, npcName)
    if Cfg("printCoords") then
        print("|cFF8787ED[Wocky]|r " .. npcName .. " -> |cFF00FFFF" .. zone .. " (" .. x .. "," .. y .. ")|r")
    end
    local mapID = MAP_IDS[zone]

    if Cfg("useTomTom") and TomTom and TomTom.AddWaypoint and mapID then
        pcall(function() TomTom:AddWaypoint(mapID, x / 100, y / 100, { title = npcName }) end)
    end

    if mapID and C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
    end

    if Cfg("openMap") then
        pcall(function()
            if WorldMapFrame and not WorldMapFrame:IsShown() then ToggleWorldMap() end
            if WorldMapFrame and mapID and WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
        end)
    end
end

---------------------------------------------------------------------------
-- Inline links and checkbox lines
---------------------------------------------------------------------------
local LOC_LIST = {}
do
    local seen = {}
    local function add(name, zone, x, y)
        if name and zone and x and y and not seen[name] then
            seen[name] = true
            LOC_LIST[#LOC_LIST + 1] = { name = name, zone = zone, x = x, y = y }
        end
    end
    if WockyPlaces then
        for name, v in pairs(WockyPlaces) do add(name, v[1], v[2], v[3]) end
    end
    if WockyGuideDB then
        for _, raceData in pairs(WockyGuideDB) do
            for _, d in pairs(raceData) do add(d.npc, d.zone, d.x, d.y) end
        end
    end
    table.sort(LOC_LIST, function(a, b)
        if #a.name ~= #b.name then return #a.name > #b.name end
        return a.name < b.name
    end)
end

local function ReplacePlain(text, name, token)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(text, name, pos, true)
        if not s then break end
        out[#out + 1] = string.sub(text, pos, s - 1) .. token
        pos = e + 1
    end
    out[#out + 1] = string.sub(text, pos)
    return table.concat(out)
end

local function Tokenize(line)
    local text = string.gsub(line, "&", "&amp;")
    for i, loc in ipairs(LOC_LIST) do
        if string.find(text, loc.name, 1, true) then
            text = ReplacePlain(text, loc.name, "@@" .. i .. "@@")
        end
    end
    return text
end

local function Expand(tokenText, done)
    local reopen = done and "|cFF888888" or ""
    local body = string.gsub(tokenText, "@@(%d+)@@", function(n)
        local loc = LOC_LIST[tonumber(n)]
        return "|cFF00FFFF|Hwocky:" .. n .. "|h" .. loc.name .. "|h|r" .. reopen
    end)
    if done then body = "|cFF888888" .. body .. "|r" end
    return "<html><body><p>" .. body .. "</p></body></html>"
end

local function VisibleLength(s)
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|H.-|h", "")
    s = string.gsub(s, "|h", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "<.->", "")
    return #s
end

local function MakeLineWidgets(count)
    local list = {}
    for i = 1, count do
        local b = CreateFrame("Frame", nil, WockyUI)
        b:SetSize(330, 14)

        local check = CreateFrame("Button", nil, b)
        check:SetSize(20, 14)
        check:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        local ct = NewFS(check, fonts.high)
        ct:SetPoint("TOPLEFT", check, "TOPLEFT", 0, 0)
        check.text = ct

        local html = CreateFrame("SimpleHTML", nil, b)
        html:SetSize(300, 14)
        html:SetPoint("TOPLEFT", b, "TOPLEFT", 24, 0)
        pcall(function() html:SetFontObject("p", fonts.high) end)
        pcall(function() html:SetFontObject(fonts.high) end)
        html:SetHyperlinksEnabled(true)
        html:SetScript("OnHyperlinkClick", function(self, link)
            local n = tonumber(string.match(link or "", "wocky:(%d+)"))
            local loc = n and LOC_LIST[n]
            if loc then SetMapPing(loc.zone, loc.x, loc.y, loc.name) end
        end)

        b.check = check
        b.html = html
        b:Hide()
        list[i] = b
    end
    return list
end

local questButtons = MakeLineWidgets(3)

-- Simple rows with an icon in the text and a tooltip (professions, talents)
local function MakeInfoRows(count)
    local list = {}
    for i = 1, count do
        local b = CreateFrame("Button", nil, WockyUI)
        b:SetSize(328, 14)
        local fs = NewFS(b, fonts.high)
        fs:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        fs:SetWidth(328)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        b.text = fs
        b:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for _, line in ipairs(self.tip) do
                GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        list[i] = b
    end
    return list
end

local function SetInfoRows(rows, data)
    for i, b in ipairs(rows) do
        local d = data[i]
        if d then
            b.text:SetText(d.text)
            b.tip = d.tip
            b:Show()
        else
            b.tip = nil
            b:Hide()
        end
    end
    return math.min(#data, #rows)
end

local profRows = MakeInfoRows(5)
local talentRows = MakeInfoRows(2)

local DoneTable
local function RenderLines(buttons, keyPrefix, level, text, stripPattern)
    local doneT = DoneTable()
    local i = 0
    for line in string.gmatch(text or "", "[^\n]+") do
        i = i + 1
        if i > #buttons then break end
        local b = buttons[i]
        local key = keyPrefix .. level .. ":" .. i
        local tokenText = Tokenize((string.gsub(line, stripPattern, "")))
        b.tokenText = tokenText
        local function Draw()
            local done = doneT[key]
            b.check.text:SetText(done and "|cFF00FF00[X]|r" or "|cFFFFFFFF[ ]|r")
            b.html:SetText(Expand(tokenText, done))
        end
        b.check:SetScript("OnClick", function()
            doneT[key] = not doneT[key]
            Draw()
        end)
        Draw()
        b:Show()
    end
    for j = i + 1, #buttons do buttons[j]:Hide() end
    return math.min(i, #buttons)
end

local function LineHeight(b)
    local h
    pcall(function() h = b.html:GetContentHeight() end)
    if not h or h < 1 then
        local perLine = math.max(30, math.floor(50 * 12 / (BASE_SIZE.normal + Cfg("fontOffset"))))
        h = math.ceil(VisibleLength(b.tokenText or "") / perLine) * (14 + Cfg("fontOffset"))
    end
    local minH = 14 + Cfg("fontOffset")
    if h < minH then h = minH end
    return math.ceil(h)
end

local function StackLines(buttons, count, y)
    for i = 1, count do
        local b = buttons[i]
        local h = LineHeight(b)
        b:SetHeight(h)
        b.html:SetHeight(h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        y = y + h + 3
    end
    return y
end

local function TextH(fs)
    local h
    pcall(function() h = fs:GetStringHeight() end)
    if not h or h < 10 then h = 12 + Cfg("fontOffset") end
    return math.ceil(h)
end

local function StackInfo(rows, count, y)
    for i = 1, count do
        local b = rows[i]
        local h = TextH(b.text)
        if h < 16 then h = 16 end
        b:SetHeight(h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        y = y + h + 3
    end
    return y
end

local lastQ, lastP, lastT = 0, 0, 0
local function Layout(questCount, profCount, talentCount)
    lastQ, lastP, lastT = questCount, profCount, talentCount
    local y = Cfg("showChar") and 64 or 42
    if xpBar:IsShown() then
        xpBar:ClearAllPoints()
        xpBar:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        y = y + 12
        xpText:ClearAllPoints()
        xpText:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        y = y + TextH(xpText) + 4
    end
    local stonesVisible = hsBtn:IsShown() or ssBtn:IsShown()
    local moneyVisible = moneyText:IsShown()
    if stonesVisible or moneyVisible then
        local h = stonesVisible and 30 or 16
        statusRow:SetHeight(h)
        statusRow:ClearAllPoints()
        statusRow:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        statusRow:Show()
        y = y + h + 4
    else
        statusRow:Hide()
    end
    if remindText:IsShown() then
        remindText:ClearAllPoints()
        remindText:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        y = y + TextH(remindText) + 4
    end
    y = y + 2
    local collapsed = Cfg("collapsed")
    local function Section(header, buttons, count, enabled, stackFn)
        if not enabled or collapsed then
            header:Hide()
            for _, b in ipairs(buttons) do b:Hide() end
            return
        end
        header:Show()
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", WockyUI, "TOPLEFT", 16, -y)
        y = y + 18
        for i, b in ipairs(buttons) do
            if i <= count then b:Show() else b:Hide() end
        end
        y = stackFn(buttons, count, y)
        y = y + 4
    end
    Section(questHeader, questButtons, questCount, Cfg("showQuests"), StackLines)
    Section(profHeader, profRows, profCount, Cfg("showProf"), StackInfo)
    Section(talentHeader, talentRows, talentCount, Cfg("showTalents"), StackInfo)
    for _, name in ipairs({ "WockyBackButton", "WockyNowButton", "WockyNextButton" }) do
        local b = _G[name]
        if b then
            if collapsed then b:Hide() else b:Show() end
        end
    end
    collapseButton:SetText(collapsed and "+" or "-")
    if collapsed then
        WockyUI:SetHeight(y + 8)
    else
        WockyUI:SetHeight(y + 40)
    end
end

---------------------------------------------------------------------------
-- XP tracking and warlock reminders
---------------------------------------------------------------------------
local xpSession = { start = nil, gained = 0, last = 0, lastMax = 0 }

local function TrackXP()
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    if not xpSession.start then
        xpSession.start = GetTime()
        xpSession.last, xpSession.lastMax = cur, max
        return
    end
    local diff = cur - xpSession.last
    if diff < 0 then diff = (xpSession.lastMax - xpSession.last) + cur end
    if diff > 0 then xpSession.gained = xpSession.gained + diff end
    xpSession.last, xpSession.lastMax = cur, max
end

local function ShortNum(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

local function CharKey()
    local realm = (GetRealmName and GetRealmName()) or ""
    return GetPlayerFullName() .. "-" .. realm
end

-- Checkmarks are saved per character; old shared marks move to the first character that logs in
DoneTable = function()
    WockyDB = WockyDB or {}
    WockyDB.doneByChar = WockyDB.doneByChar or {}
    local key = CharKey()
    local t = WockyDB.doneByChar[key]
    if not t then
        t = {}
        if WockyDB.done and not WockyDB.doneMigrated then
            for k, v in pairs(WockyDB.done) do t[k] = v end
            WockyDB.doneMigrated = true
        end
        WockyDB.doneByChar[key] = t
    end
    return t
end

-- Which leveling route to show: your race, or the one picked in the settings
local ROUTE_NAMES = { SCOURGE = "Undead", ORC = "Orc / Troll", HUMAN = "Human", GNOME = "Gnome" }
local function RouteKey()
    local pick = WockyDB and WockyDB.cfg and WockyDB.cfg.route
    if pick and pick ~= "auto" and WockyGuideDB and WockyGuideDB[pick] then return pick end
    local _, raceEn = UnitRace("player")
    raceEn = raceEn and string.upper(raceEn)
    if raceEn and WockyGuideDB and WockyGuideDB[raceEn] then return raceEn end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" then return "HUMAN" end
    if faction == "Horde" then return "ORC" end
    return "SCOURGE"
end

local function UpdateXP()
    local level = UnitLevel("player") or 1
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    if not Cfg("showXP") or level >= MAX_LEVEL or max <= 0 then
        xpBar:Hide()
        xpText:Hide()
        return
    end
    xpBar:Show()
    xpText:Show()
    xpBar:SetMinMaxValues(0, max)
    xpBar:SetValue(cur)
    local rested = (GetXPExhaustion and GetXPExhaustion()) or 0
    local restEnd = math.min(cur + rested, max)
    local w = xpBar:GetWidth()
    if not w or w <= 0 then w = 328 end
    if rested > 0 then
        xpRestTex:SetWidth(math.max(1, w * restEnd / max))
        xpRestTex:Show()
    else
        xpRestTex:Hide()
    end

    local parts = { string.format("%d%%  (%s / %s)", math.floor(cur / max * 100), ShortNum(cur), ShortNum(max)) }
    if rested > 0 then
        parts[#parts + 1] = "|cFF4D9FFF" .. L("XP_RESTED", math.floor(rested / max * 100)) .. "|r"
    end
    local elapsed = xpSession.start and (GetTime() - xpSession.start) or 0
    if elapsed > 60 and xpSession.gained > 0 then
        local rate = xpSession.gained / elapsed * 3600
        parts[#parts + 1] = L("XP_RATE", ShortNum(rate))
        local secs = (max - cur) / rate * 3600
        if secs > 0 and secs < 360000 then
            local hrs = math.floor(secs / 3600)
            local mins = math.floor((secs % 3600) / 60)
            parts[#parts + 1] = L("XP_ETA", string.format("%d:%02d", hrs, mins))
        end
    end
    xpText:SetText(table.concat(parts, "  |cFF666666|||r  "))
end

local function BuildReminders()
    local list = {}
    pcall(function()
        local level = UnitLevel("player") or 1
        local counts = BagCounts()
        if not Cfg("showStones") then
            if level >= 10 and not HasAny(counts, HEALTHSTONE_IDS) then list[#list + 1] = L("REMIND_HS") end
            if level >= 18 and not HasAny(counts, SOULSTONE_IDS) then list[#list + 1] = L("REMIND_SS") end
        end
        local shards = counts[6265] or 0
        if level >= 10 and shards < Cfg("shardMin") then list[#list + 1] = L("REMIND_SHARDS", shards) end
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
        local mounted = IsMounted and IsMounted()
        local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
        if level >= 2 and not dead and not mounted and not onTaxi and not (UnitExists and UnitExists("pet")) then
            list[#list + 1] = L("REMIND_PET")
        end
        local pending = WockyDB and WockyDB.train and WockyDB.train[CharKey()]
        if pending then list[#list + 1] = L("REMIND_TRAIN", pending) end
    end)
    return list
end

local function UpdateReminders()
    if not Cfg("showReminders") then
        remindText:Hide()
        return
    end
    local list = BuildReminders()
    if #list == 0 then
        remindText:Hide()
        return
    end
    remindText:SetText("|cFFFF7D0A! " .. table.concat(list, "   ! ") .. "|r")
    remindText:Show()
end

---------------------------------------------------------------------------
-- Healthstone / Soulstone icons
---------------------------------------------------------------------------
local SS_USE_SPELLS = { [20707] = true, [20762] = true, [20763] = true, [20764] = true, [20765] = true }
local SS_CREATE_SPELLS = { 693, 20752, 20755, 20756, 20757 }
local SS_COOLDOWN = 1800

local function GetItemCD(id)
    local s, d = 0, 0
    pcall(function()
        if C_Container and C_Container.GetItemCooldown then s, d = C_Container.GetItemCooldown(id) end
        if (not d or d == 0) and GetItemCooldown then s, d = GetItemCooldown(id) end
    end)
    return s or 0, d or 0
end

local function GetSpellCD(id)
    local s, d = 0, 0
    pcall(function()
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(id)
            if type(info) == "table" then
                s, d = info.startTime or 0, info.duration or 0
                return
            end
        end
        if GetSpellCooldown then s, d = GetSpellCooldown(id) end
    end)
    return s or 0, d or 0
end

local function CDRemaining(s, d)
    if not s or not d or s <= 0 or d <= 1.5 then return 0 end
    local r = s + d - GetTime()
    if r < 0 then r = 0 end
    return r
end

local function BestCD(ids, getter)
    local bs, bd, br = 0, 0, 0
    for _, id in ipairs(ids) do
        local s, d = getter(id)
        local r = CDRemaining(s, d)
        if r > br then bs, bd, br = s, d, r end
    end
    return bs, bd, br
end

local function TrackedSoulstoneCD()
    local used = WockyDB and WockyDB.ssUsed and WockyDB.ssUsed[CharKey()]
    if not used or not time then return 0, 0, 0 end
    local ago = time() - used
    if ago < 0 or ago >= SS_COOLDOWN then return 0, 0, 0 end
    return GetTime() - ago, SS_COOLDOWN, SS_COOLDOWN - ago
end

local function ShortTime(r)
    if r >= 3600 then return math.ceil(r / 3600) .. "h" end
    if r >= 60 then return math.ceil(r / 60) .. "m" end
    return tostring(math.ceil(r))
end

local function LongTime(r)
    r = math.ceil(r)
    return string.format("%d:%02d", math.floor(r / 60), r % 60)
end

local function SetStoneCD(b, s, d, r)
    if r > 0 then
        if b.cd and b.cdStart ~= s then
            pcall(b.cd.SetCooldown, b.cd, s, d)
            b.cd:Show()
            b.cdStart = s
        end
        b.timer:SetText(ShortTime(r))
    else
        if b.cd and b.cdStart then
            pcall(b.cd.SetCooldown, b.cd, 0, 0)
            b.cd:Hide()
        end
        b.cdStart = nil
        b.timer:SetText("")
    end
end

local function ItemIcon(id)
    local icon
    pcall(function()
        if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
        if not icon and GetItemIcon then icon = GetItemIcon(id) end
    end)
    return icon
end

local stoneIconsSet = false
local function UpdateStones()
    local level = UnitLevel("player") or 1
    local show = Cfg("showStones")
    if not stoneIconsSet then
        local hi, si = ItemIcon(5512), ItemIcon(5232)
        if hi then hsBtn.icon:SetTexture(hi) end
        if si then ssBtn.icon:SetTexture(si) end
        stoneIconsSet = true
    end
    local counts = BagCounts()

    if show and level >= 10 then
        local n = 0
        for _, id in ipairs(HEALTHSTONE_IDS) do n = n + (counts[id] or 0) end
        hsBtn.icon:SetDesaturated(n == 0)
        hsBtn.icon:SetAlpha(n == 0 and 0.45 or 1)
        hsBtn.count:SetText(n > 1 and tostring(n) or "")
        local s, d, r = BestCD(HEALTHSTONE_IDS, GetItemCD)
        SetStoneCD(hsBtn, s, d, r)
        hsBtn.tipTitle = "Healthstone"
        hsBtn.tipText = (n > 0) and L("HS_HAVE", n) or L("HS_NONE")
        hsBtn:Show()
    else
        hsBtn:Hide()
    end

    if show and level >= 18 then
        local has = HasAny(counts, SOULSTONE_IDS)
        local s, d, r = BestCD(SOULSTONE_IDS, GetItemCD)
        local s2, d2, r2 = BestCD(SS_CREATE_SPELLS, GetSpellCD)
        if r2 > r then s, d, r = s2, d2, r2 end
        local s3, d3, r3 = TrackedSoulstoneCD()
        if r3 > r then s, d, r = s3, d3, r3 end
        SetStoneCD(ssBtn, s, d, r)
        ssBtn.icon:SetDesaturated(not has)
        ssBtn.icon:SetAlpha(has and 1 or 0.6)
        -- Glow when the cooldown is over and there is no soulstone yet; stops once you make one
        ssBtn:SetGlow(r == 0 and not has)
        ssBtn.tipTitle = "Soulstone"
        if r > 0 then
            ssBtn.tipText = L("SS_CD", LongTime(r))
        elseif has then
            ssBtn.tipText = L("SS_HAVE")
        else
            ssBtn.tipText = L("SS_NONE")
        end
        ssBtn:Show()
    else
        ssBtn:SetGlow(false)
        ssBtn:Hide()
    end
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------
local sessionMoney
local COIN_GOLD = "Interface\\MoneyFrame\\UI-GoldIcon"
local COIN_SILVER = "Interface\\MoneyFrame\\UI-SilverIcon"
local COIN_COPPER = "Interface\\MoneyFrame\\UI-CopperIcon"

local function CoinText(c)
    c = math.floor(math.abs(c or 0))
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cp = c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = "|cFFFFFFFF" .. g .. "|r|T" .. COIN_GOLD .. ":12:12:2:0|t" end
    if g > 0 or s > 0 then parts[#parts + 1] = "|cFFFFFFFF" .. s .. "|r|T" .. COIN_SILVER .. ":12:12:2:0|t" end
    parts[#parts + 1] = "|cFFFFFFFF" .. cp .. "|r|T" .. COIN_COPPER .. ":12:12:2:0|t"
    return table.concat(parts, " ")
end

local function UpdateMoney()
    if not Cfg("showMoney") then
        moneyText:Hide()
        moneyBtn:Hide()
        return
    end
    local m = (GetMoney and GetMoney()) or 0
    if not sessionMoney then sessionMoney = m end
    moneyText:SetText(CoinText(m))
    moneyText:Show()
    moneyBtn:Show()
end

moneyBtn:SetScript("OnEnter", function(self)
    local m = (GetMoney and GetMoney()) or 0
    local diff = m - (sessionMoney or m)
    local sign = diff < 0 and "|cFFFF6666-|r" or "|cFF00FF00+|r"
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(CoinText(m))
    GameTooltip:AddLine(L("MONEY_SESSION", sign .. CoinText(diff)), 1, 1, 1)
    GameTooltip:Show()
end)
moneyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateExtras(relayout)
    UpdateXP()
    UpdateStones()
    UpdateMoney()
    UpdateReminders()
    if relayout then Layout(lastQ, lastP, lastT) end
end

-- Keeps the cooldown numbers on the stone icons ticking
local stoneTicker = CreateFrame("Frame")
local stoneElapsed = 0
stoneTicker:SetScript("OnUpdate", function(self, elapsed)
    stoneElapsed = stoneElapsed + (elapsed or 0)
    if stoneElapsed < 0.5 then return end
    stoneElapsed = 0
    if WockyUI:IsShown() and statusRow:IsShown() and (hsBtn:IsShown() or ssBtn:IsShown()) then
        UpdateStones()
    end
end)

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
local UpdateWockyGuide
local SECONDARY_PROFS = { 185, 129, 356 }
local PROF_BY_NAME = {}
if WockyProfGuides then
    for id, g in pairs(WockyProfGuides) do PROF_BY_NAME[string.lower(g.name)] = id end
end

local function DetectProfessions()
    local found = {}
    local function add(id, name, rank, maxRank, icon)
        if not id and name then id = PROF_BY_NAME[string.lower(name)] end
        if not id or not (WockyProfGuides and WockyProfGuides[id]) or found[id] then return end
        found[id] = { id = id, name = name, rank = rank or 0, max = maxRank or 0, icon = icon }
    end
    pcall(function()
        if not GetProfessions or not GetProfessionInfo then return end
        local a, b, c, d, e, f = GetProfessions()
        for _, idx in pairs({ a, b, c, d, e, f }) do
            local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
            add(skillLine, name, rank, maxRank, icon)
        end
    end)
    pcall(function()
        if not GetNumSkillLines or not GetSkillLineInfo then return end
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if name and not isHeader then add(nil, name, rank, maxRank, nil) end
        end
    end)
    return found
end

local function ProfStepIndex(guide, rank)
    for i, s in ipairs(guide.steps) do
        if rank < s[2] then return i end
    end
    return #guide.steps + 1
end

-- Recipe / node colors: 1 orange, 2 yellow, 3 green, 4 gray
local COLOR_HEX = { "FF8040", "FFFF00", "40BF40", "808080" }
local GATHER_PROFS = { [182] = true, [186] = true, [393] = true }
local NO_COLOR_PROFS = { [356] = true }

local function Colorize(text, c)
    return "|cFF" .. (COLOR_HEX[c] or "FFFFFF") .. text .. "|r"
end

local function ColorName(c)
    return L("COLOR_" .. (c or 2))
end

local function ProfMinColor(id)
    local t = WockyDB and WockyDB.cfg and WockyDB.cfg.profColor
    local c = t and t[id]
    if c == 1 or c == 2 or c == 3 then return c end
    return 2
end

local function PrimaryProfessions(found)
    local primaries = {}
    for id, p in pairs(found) do
        if WockyProfGuides[id] and WockyProfGuides[id].primary then primaries[#primaries + 1] = p end
    end
    table.sort(primaries, function(a, b) return a.id < b.id end)
    return primaries
end

-- Gathering: color from the gap between your skill and the node requirement
local function GatherColor(skill, req)
    local d = skill - req
    if d < 0 then return nil end
    if d < 25 then return 1 elseif d < 50 then return 2 elseif d < 100 then return 3 end
    return 4
end

local function GatherList(id, rank, minC)
    local list = {}
    for _, n in ipairs((WockyGatherNodes and WockyGatherNodes[id]) or {}) do
        local c = GatherColor(rank, n[2])
        if c and c <= minC then list[#list + 1] = { name = n[1], req = n[2], zone = n[3], color = c } end
    end
    table.sort(list, function(a, b)
        if a.color ~= b.color then return a.color < b.color end
        return a.req > b.req
    end)
    return list
end

-- Skinning: skill needed for a beast of a level
local function SkinReq(lvl)
    if lvl <= 10 then return 1 elseif lvl <= 20 then return (lvl - 10) * 10 end
    return lvl * 5
end

local function SkinRange(skill, minC)
    local band = ({ 25, 50, 100 })[minC] or 50
    local lo, hi
    for lvl = 1, 63 do
        local req = SkinReq(lvl)
        if req <= skill and skill - req < band then
            lo = lo or lvl
            hi = lvl
        end
    end
    return lo, hi
end

-- Live recipe colors, saved when you open a profession window
local function ProfScanData(id)
    local all = WockyDB and WockyDB.profScan and WockyDB.profScan[CharKey()]
    return all and all[id]
end

local function CraftCandidates(id, rank, minC)
    local data = ProfScanData(id)
    if not data or not data.recipes then return nil end
    local preferred = {}
    for _, s in ipairs(WockyProfGuides[id].steps) do preferred[string.lower(s[3])] = true end
    local fresh, stale = {}, {}
    for name, r in pairs(data.recipes) do
        if r.color and r.color <= minC then
            local e = { name = name, color = r.color, avail = r.avail or 0, seen = r.seen or data.rank or 0 }
            if e.seen >= rank then fresh[#fresh + 1] = e else stale[#stale + 1] = e end
        end
    end
    local function better(a, b)
        if a.color ~= b.color then return a.color < b.color end
        local aa, ba = a.avail > 0, b.avail > 0
        if aa ~= ba then return aa end
        local ap, bp = preferred[string.lower(a.name)] or false, preferred[string.lower(b.name)] or false
        if ap ~= bp then return ap end
        return a.name < b.name
    end
    table.sort(fresh, better)
    table.sort(stale, better)
    return fresh, stale, data
end

local function KnownRecipeTip(tip, data)
    if not data or not data.recipes then return end
    local list = {}
    for name, r in pairs(data.recipes) do list[#list + 1] = { name = name, color = r.color or 4, avail = r.avail or 0 } end
    table.sort(list, function(a, b)
        if a.color ~= b.color then return a.color < b.color end
        return a.name < b.name
    end)
    tip[#tip + 1] = { " " }
    tip[#tip + 1] = { L("PROF_KNOWN"), 0.7, 0.7, 0.7 }
    for i = 1, math.min(10, #list) do
        local e = list[i]
        local hex = COLOR_HEX[e.color] or "FFFFFF"
        local r = tonumber(string.sub(hex, 1, 2), 16) / 255
        local g = tonumber(string.sub(hex, 3, 4), 16) / 255
        local b = tonumber(string.sub(hex, 5, 6), 16) / 255
        tip[#tip + 1] = { e.name .. (e.avail > 0 and ("  x" .. e.avail) or ""), r, g, b }
    end
    if #list > 10 then tip[#tip + 1] = { L("PROF_MORE", #list - 10), 0.6, 0.6, 0.6 } end
end

local function ProfRow(id, p)
    local guide = WockyProfGuides[id]
    local icon = (p and p.icon) or guide.icon
    local ic = "|T" .. icon .. ":16:16:0:0|t "
    local name = (p and p.name) or guide.name
    local rank = p and p.rank or 0
    local maxRank = p and p.max or 0
    local idx = ProfStepIndex(guide, rank)
    local minC = ProfMinColor(id)

    local tip = { { name, 1, 0.82, 0 } }
    if not NO_COLOR_PROFS[id] then
        tip[#tip + 1] = { L("PROF_MIN_COLOR", ColorName(minC)), 0.8, 0.8, 0.8 }
    end
    tip[#tip + 1] = { " " }
    tip[#tip + 1] = { L("PROF_ROADMAP"), 0.7, 0.7, 0.7 }
    for i, s in ipairs(guide.steps) do
        local r, g, b = 1, 1, 1
        if i < idx then r, g, b = 0.5, 0.5, 0.5 elseif i == idx then r, g, b = 0, 1, 0 end
        tip[#tip + 1] = { s[1] .. "-" .. s[2] .. "  " .. s[3], r, g, b }
    end

    if not p then
        return { text = ic .. "|cFFFFD100" .. name .. "|r  |cFF888888" .. L("PROF_NOT_LEARNED") .. "|r", tip = tip }
    end

    local text = ic .. "|cFFFFD100" .. name .. "|r " .. rank .. "/" .. maxRank .. "  "
    local step = guide.steps[idx]

    if rank >= 300 or (not step and not GATHER_PROFS[id]) then
        text = text .. "|cFF00FF00" .. L("PROF_MAX") .. "|r"
    elseif id == 393 then
        local lo, hi = SkinRange(rank, minC)
        if lo then
            text = text .. Colorize(L("SKIN_RANGE", lo, hi), minC)
            local olo, ohi = SkinRange(rank, 1)
            if olo then
                table.insert(tip, 3, { L("SKIN_RANGE", olo, ohi) .. " - " .. ColorName(1), 1, 0.5, 0.25 })
            end
        end
        if step then text = text .. " |cFF888888- " .. step[3] .. "|r" end
    elseif GATHER_PROFS[id] then
        local list = GatherList(id, rank, minC)
        local prefix = ""
        if #list == 0 then
            list = GatherList(id, rank, 3)
            prefix = "|cFFFF6666" .. L("PROF_NO_NODE", ColorName(minC)) .. "|r "
        end
        if #list > 0 then
            local parts = {}
            for i = 1, math.min(2, #list) do parts[#parts + 1] = Colorize(list[i].name, list[i].color) end
            text = text .. prefix .. table.concat(parts, ", ") .. " |cFF888888- " .. list[1].zone .. "|r"
        else
            text = text .. prefix
        end
        -- node colors for the tooltip
        tip[#tip + 1] = { " " }
        tip[#tip + 1] = { L("PROF_NODES"), 0.7, 0.7, 0.7 }
        for _, n in ipairs((WockyGatherNodes and WockyGatherNodes[id]) or {}) do
            local c = GatherColor(rank, n[2])
            if c and c < 4 then
                local hex = COLOR_HEX[c]
                tip[#tip + 1] = { n[1] .. " (" .. n[2] .. ")  " .. n[3],
                    tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255 }
            end
        end
        -- Mining can also level by smelting
        if id == 186 then
            local fresh = CraftCandidates(id, rank, minC)
            if fresh and fresh[1] and (#list == 0 or fresh[1].color < list[1].color) then
                text = text .. " |cFF888888/|r " .. Colorize(fresh[1].name, fresh[1].color)
            end
            KnownRecipeTip(tip, ProfScanData(id))
        end
    elseif NO_COLOR_PROFS[id] then
        text = text .. step[3]
    else
        local fresh, stale, data = CraftCandidates(id, rank, minC)
        if not data then
            text = text .. step[3] .. " |cFF888888(" .. step[1] .. "-" .. step[2] .. ") - " .. L("PROF_OPEN_WINDOW") .. "|r"
        else
            local list, isStale = fresh, false
            if #fresh == 0 and #stale > 0 then list, isStale = stale, true end
            if #list == 0 then
                text = text .. "|cFFFF6666" .. L("PROF_NO_RECIPE", ColorName(minC)) .. "|r"
            else
                local best = list[1]
                text = text .. Colorize(best.name, best.color)
                if best.avail > 0 then text = text .. " |cFFFFFFFFx" .. best.avail .. "|r" end
                if #list > 1 then text = text .. " |cFF888888(" .. L("PROF_MORE", #list - 1) .. ")|r" end
                if isStale then text = text .. " |cFF888888(" .. L("PROF_SEEN_AT", best.seen) .. ")|r" end
            end
            if data.needsRefresh then text = text .. " |cFF888888(" .. L("PROF_REFRESH") .. ")|r" end
            KnownRecipeTip(tip, data)
        end
    end

    if maxRank > 0 and maxRank < 300 and rank >= maxRank - 25 then
        text = text .. "  |cFFFF7D0A" .. L("PROF_TRAIN", maxRank + 75) .. "|r"
    end
    return { text = text, tip = tip }
end

local function ProfessionRows()
    local rows = {}
    if not WockyProfGuides then return rows end
    local found = DetectProfessions()
    local primaries = PrimaryProfessions(found)
    for i = 1, 2 do
        local p = primaries[i]
        if p then
            rows[#rows + 1] = ProfRow(p.id, p)
        else
            rows[#rows + 1] = {
                text = "|TInterface\\Icons\\INV_Misc_QuestionMark:16:16:0:0|t |cFF888888" .. L("PROF_EMPTY") .. "|r  " .. L("PROF_EMPTY_HINT"),
                tip = { { L("PROF_EMPTY"), 1, 0.82, 0 }, { L("PROF_EMPTY_HINT"), 1, 1, 1 } }
            }
        end
    end
    for _, id in ipairs(SECONDARY_PROFS) do
        rows[#rows + 1] = ProfRow(id, found[id])
    end
    return rows
end

---------------------------------------------------------------------------
-- Profession window scanning (live recipe colors)
---------------------------------------------------------------------------
local DIFF_BY_NAME = { optimal = 1, medium = 2, easy = 3, trivial = 4 }

local function DiffToColor(d)
    if type(d) == "number" then
        if d >= 0 and d <= 3 then return d + 1 end
        return nil
    end
    if type(d) == "string" then return DIFF_BY_NAME[string.lower(d)] end
end

local function ScanTradeSkill()
    local profName, rank, pid, recipes = nil, nil, nil, {}
    pcall(function()
        if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
        local ids = C_TradeSkillUI.GetAllRecipeIDs()
        if not ids or #ids == 0 then return end
        pcall(function()
            local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
            if info then
                profName = info.professionName
                rank = info.skillLevel
                pid = info.professionID
            end
        end)
        if not profName and C_TradeSkillUI.GetTradeSkillLine then
            local a, b, c = C_TradeSkillUI.GetTradeSkillLine()
            if type(a) == "number" then
                pid, profName, rank = a, b, c
            else
                profName, rank = a, b
            end
        end
        for _, rid in ipairs(ids) do
            local ri = C_TradeSkillUI.GetRecipeInfo(rid)
            if ri and ri.name and ri.learned ~= false then
                local d = ri.relativeDifficulty
                if d == nil then d = ri.difficulty end
                local col = DiffToColor(d)
                if col then recipes[#recipes + 1] = { name = ri.name, color = col, avail = ri.numAvailable or 0 } end
            end
        end
    end)
    if #recipes == 0 then
        pcall(function()
            if not (GetNumTradeSkills and GetTradeSkillInfo) then return end
            local n = GetNumTradeSkills() or 0
            if n == 0 then return end
            if GetTradeSkillLine then profName, rank = GetTradeSkillLine() end
            for i = 1, n do
                local name, kind, avail = GetTradeSkillInfo(i)
                local col = DiffToColor(kind)
                if name and col then recipes[#recipes + 1] = { name = name, color = col, avail = avail or 0 } end
            end
        end)
    end
    if #recipes == 0 then
        -- Classic Enchanting uses the craft window
        pcall(function()
            if not (GetNumCrafts and GetCraftInfo) then return end
            local n = GetNumCrafts() or 0
            if n == 0 then return end
            if GetCraftDisplaySkillLine then profName, rank = GetCraftDisplaySkillLine() end
            for i = 1, n do
                local name, _, kind, avail = GetCraftInfo(i)
                local col = DiffToColor(kind)
                if name and col then recipes[#recipes + 1] = { name = name, color = col, avail = avail or 0 } end
            end
        end)
    end
    return profName, rank, pid, recipes
end

local scanQueued = false
local function DoProfScan()
    scanQueued = false
    local profName, rank, pid, recipes = ScanTradeSkill()
    if #recipes == 0 then return end
    local id
    if pid and WockyProfGuides[pid] then id = pid end
    if not id and type(profName) == "string" then id = PROF_BY_NAME[string.lower(profName)] end
    if not id then return end
    rank = tonumber(rank)
    if not rank then
        local p = DetectProfessions()[id]
        rank = p and p.rank or 0
    end
    WockyDB.profScan = WockyDB.profScan or {}
    local key = CharKey()
    WockyDB.profScan[key] = WockyDB.profScan[key] or {}
    local data = WockyDB.profScan[key][id] or {}
    data.recipes = data.recipes or {}
    for _, r in ipairs(recipes) do
        data.recipes[r.name] = { color = r.color, avail = r.avail, seen = rank }
    end
    data.rank = rank
    data.needsRefresh = nil
    WockyDB.profScan[key][id] = data
    UpdateWockyGuide(viewLevel)
end

local function QueueProfScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.3, DoProfScan)
end

local function MarkProfRefresh(onlyId)
    local all = WockyDB and WockyDB.profScan and WockyDB.profScan[CharKey()]
    if not all then return end
    for id, data in pairs(all) do
        if not onlyId or onlyId == id then data.needsRefresh = true end
    end
end

UpdateWockyGuide = function(level)

    if level < 1 then level = 1 end
    if level > MAX_LEVEL then level = MAX_LEVEL end
    viewLevel = level

    local pLevel = UnitLevel("player") or 1
    local raceName = UnitRace("player")
    local raceTag = ""
    if type(raceName) == "string" and raceName ~= "" then raceTag = " |cFFBBBBBB(" .. raceName .. ")|r" end
    charInfoText:SetText("|cFFFFFFFF" .. GetPlayerFullName() .. "|r" .. raceTag)
    charSpecText:SetText("Lvl " .. pLevel .. " - " .. GetSpecText())
    UpdateShards()

    local spec = GetBuildSpec()
    questHeader:SetText("|cFFFFD100[" .. L("QUESTS_HEADER", level) .. "]|r")
    profHeader:SetText("|cFF00FF00[" .. L("PROF_HEADER", level) .. "]|r")

    local raceData = WockyGuideDB and WockyGuideDB[RouteKey()]
    local data = raceData and raceData["L" .. level]

    local qCount
    if data then
        qCount = RenderLines(questButtons, "Q", level, data.quest, "^%[ %] ")
    else
        qCount = RenderLines(questButtons, "Q", level, L("NO_DATA"), "^$")
    end
    local pCount = SetInfoRows(profRows, ProfessionRows())
    local tData, unspent = TalentRows(spec, level)
    local tCount = SetInfoRows(talentRows, tData)
    local tHeader = L("TALENT_HEADER", spec, level)
    if unspent and unspent > 0 then
        tHeader = tHeader .. " |cFF00FF00- " .. L("TALENT_UNSPENT", unspent) .. "|r"
    end
    talentHeader:SetText("|cFFFF7D0A[" .. tHeader .. "]|r")
    UpdateExtras(false)
    Layout(qCount, pCount, tCount)
    C_Timer.After(0.05, function() Layout(lastQ, lastP, lastT) end)
end

local backButton = StyleButton(CreateFrame("Button", "WockyBackButton", WockyUI, "UIPanelButtonTemplate"))
backButton:SetSize(100, 22)
backButton:SetPoint("BOTTOMLEFT", WockyUI, "BOTTOMLEFT", 16, 14)

local nowButton = StyleButton(CreateFrame("Button", "WockyNowButton", WockyUI, "UIPanelButtonTemplate"))
nowButton:SetSize(70, 22)
nowButton:SetPoint("BOTTOM", WockyUI, "BOTTOM", 0, 14)

local nextButton = StyleButton(CreateFrame("Button", "WockyNextButton", WockyUI, "UIPanelButtonTemplate"))
nextButton:SetSize(100, 22)
nextButton:SetPoint("BOTTOMRIGHT", WockyUI, "BOTTOMRIGHT", -16, 14)

backButton:SetScript("OnClick", function()
    local l = viewLevel - 1
    if l < 1 then l = MAX_LEVEL end
    UpdateWockyGuide(l)
end)
nextButton:SetScript("OnClick", function()
    local l = viewLevel + 1
    if l > MAX_LEVEL then l = 1 end
    UpdateWockyGuide(l)
end)
nowButton:SetScript("OnClick", function()
    UpdateWockyGuide(UnitLevel("player") or 1)
end)

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local ApplyAll
local Settings = CreateFrame("Frame", "WockySettingsFrame", UIParent, "BackdropTemplate")
Settings:SetSize(536, 440)
Settings:SetPoint("CENTER", UIParent, "CENTER", -260, 0)
Settings:SetFrameStrata("DIALOG")
Settings:SetMovable(true)
Settings:EnableMouse(true)
Settings:RegisterForDrag("LeftButton")
Settings:SetScript("OnDragStart", Settings.StartMoving)
Settings:SetScript("OnDragStop", Settings.StopMovingOrSizing)
Settings:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
Settings:SetBackdropColor(0, 0, 0, 0.95)
Settings:SetBackdropBorderColor(0.6, 0.2, 0.8, 1)
Settings:Hide()

local settingsTitle = NewFS(Settings, fonts.large)
settingsTitle:SetPoint("TOPLEFT", Settings, "TOPLEFT", 16, -12)

local settingsRows = {}
local settingsPages = {}
local settingsTabs = {}
local openMenu = nil

local function RefreshSettings()
    local a = ACCENTS[Cfg("accent")] or ACCENTS[1]
    settingsTitle:SetText("|cFF" .. a[4] .. "Wocky - " .. L("SETTINGS") .. "|r")
    for _, r in ipairs(settingsRows) do r.refresh() end
    for i, t in ipairs(settingsTabs) do
        local name = L(t.key)
        t:SetText(t.selected and ("|cFFFFD100" .. name .. "|r") or name)
    end
end

local function NewPage()
    local page = CreateFrame("Frame", nil, Settings)
    page:SetPoint("TOPLEFT", Settings, "TOPLEFT", 14, -72)
    page:SetSize(506, 320)
    page.y = 0
    page:Hide()
    settingsPages[#settingsPages + 1] = page
    return page
end

local function NextRow(page, height)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(506, height or 22)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y)
    page.y = page.y + (height or 22) + 4
    return row
end

local function AddToggle(page, key, labelKey)
    local row = NextRow(page)
    local b = CreateFrame("Button", nil, row)
    b:SetAllPoints(row)
    local fs = NewFS(b, fonts.high)
    fs:SetPoint("LEFT", b, "LEFT", 0, 0)
    fs:SetWidth(400)
    fs:SetJustifyH("LEFT")
    b:SetScript("OnClick", function()
        SetCfg(key, not Cfg(key))
        ApplyAll()
    end)
    settingsRows[#settingsRows + 1] = { refresh = function()
        fs:SetText((Cfg(key) and "|cFF00FF00[X]|r " or "|cFFFFFFFF[ ]|r ") .. L(labelKey))
    end }
end

local function AddStepper(page, key, labelKey, minv, maxv, step, fmt)
    local row = NextRow(page)
    local fs = NewFS(row, fonts.high)
    fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    fs:SetWidth(230)
    fs:SetJustifyH("LEFT")

    local minus = StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    minus:SetSize(24, 20)
    minus:SetPoint("RIGHT", row, "RIGHT", -112, 0)
    minus:SetText("-")

    local valueFS = NewFS(row, fonts.high)
    valueFS:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    valueFS:SetWidth(56)
    valueFS:SetJustifyH("CENTER")

    local plus = StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    plus:SetSize(24, 20)
    plus:SetPoint("LEFT", valueFS, "RIGHT", 4, 0)
    plus:SetText("+")

    local function change(delta)
        local v = Cfg(key) + delta * step
        v = math.floor(v / step + 0.5) * step
        v = math.floor(v * 100 + 0.5) / 100
        if v < minv then v = minv end
        if v > maxv then v = maxv end
        SetCfg(key, v)
        ApplyAll()
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)

    settingsRows[#settingsRows + 1] = { refresh = function()
        fs:SetText(L(labelKey))
        valueFS:SetText(fmt(Cfg(key)))
    end }
end

local function AddCycle(page, labelKey, values, getFn, setFn, textFn)
    local row = NextRow(page)
    local fs = NewFS(row, fonts.high)
    fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    fs:SetWidth(210)
    fs:SetJustifyH("LEFT")

    local b = StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    b:SetSize(184, 22)
    b:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        local cur = getFn()
        local idx = 1
        for i, v in ipairs(values) do if v == cur then idx = i end end
        if mouse == "RightButton" then idx = idx - 1 else idx = idx + 1 end
        if idx < 1 then idx = #values end
        if idx > #values then idx = 1 end
        setFn(values[idx])
        ApplyAll()
    end)
    settingsRows[#settingsRows + 1] = { refresh = function()
        fs:SetText(L(labelKey))
        b:SetText(textFn(getFn()))
    end }
end

local function CloseMenu()
    if openMenu then openMenu:Hide() end
    openMenu = nil
end

local function AddLanguageMenu(page)
    local row = NextRow(page)
    local fs = NewFS(row, fonts.high)
    fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    fs:SetWidth(210)
    fs:SetJustifyH("LEFT")

    local b = StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    b:SetSize(184, 22)
    b:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local menu = CreateFrame("Frame", nil, Settings, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetSize(190, #LANG_CODES * 22 + 12)
    menu:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
    menu:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    menu:SetBackdropColor(0, 0, 0, 1)
    menu:Hide()

    for i, code in ipairs(LANG_CODES) do
        local item = StyleButton(CreateFrame("Button", nil, menu, "UIPanelButtonTemplate"))
        item:SetSize(176, 20)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 7, -6 - (i - 1) * 22)
        item.langCode = code
        item:SetText(code == "auto" and L("LANG_AUTO") or LANG_NAMES[code])
        item:SetScript("OnClick", function()
            SetCfg("lang", code)
            CloseMenu()
            ApplyAll()
        end)
        menu["item" .. i] = item
    end

    b:SetScript("OnClick", function()
        if openMenu == menu then
            CloseMenu()
        else
            CloseMenu()
            menu:Show()
            openMenu = menu
        end
    end)

    settingsRows[#settingsRows + 1] = { refresh = function()
        fs:SetText(L("LANGUAGE"))
        local cur = Cfg("lang")
        b:SetText(cur == "auto" and L("LANG_AUTO") or LANG_NAMES[cur] or cur)
        menu.item1:SetText(L("LANG_AUTO"))
    end }
end

local function AddButton(page, labelKey, fn)
    local row = NextRow(page, 24)
    local b = StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    b:SetSize(300, 22)
    b:SetPoint("LEFT", row, "LEFT", 0, 0)
    b:SetScript("OnClick", fn)
    settingsRows[#settingsRows + 1] = { refresh = function() b:SetText(L(labelKey)) end }
end

local function ResetPosition()
    WockyDB.pos = nil
    WockyUI:ClearAllPoints()
    WockyUI:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local pageGeneral = NewPage()
AddStepper(pageGeneral, "scale", "SCALE", 0.6, 1.6, 0.05, function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
AddStepper(pageGeneral, "alpha", "OPACITY", 0.3, 1.0, 0.05, function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
AddStepper(pageGeneral, "fontOffset", "FONT_SIZE", -2, 4, 1, function(v) return string.format("%+d", v) end)
AddCycle(pageGeneral, "ACCENT", { 1, 2, 3, 4, 5, 6 },
    function() return Cfg("accent") end,
    function(v) SetCfg("accent", v) end,
    function(v) local a = ACCENTS[v] or ACCENTS[1]; return "|cFF" .. a[4] .. "######|r" end)
AddToggle(pageGeneral, "locked", "LOCK")
AddToggle(pageGeneral, "minimap", "MINIMAP")
AddToggle(pageGeneral, "showOnLogin", "SHOW_ON_LOGIN")
AddToggle(pageGeneral, "hideCombat", "HIDE_COMBAT")
AddToggle(pageGeneral, "autoLevel", "AUTO_LEVEL")

local pageDisplay = NewPage()
AddToggle(pageDisplay, "showQuests", "SHOW_QUESTS")
AddToggle(pageDisplay, "showProf", "SHOW_PROF")
AddToggle(pageDisplay, "showTalents", "SHOW_TALENTS")
AddToggle(pageDisplay, "showShards", "SHOW_SHARDS")
AddToggle(pageDisplay, "showBags", "SHOW_BAGS")
AddToggle(pageDisplay, "showChar", "SHOW_CHAR")
AddToggle(pageDisplay, "showXP", "SHOW_XP")
AddToggle(pageDisplay, "showReminders", "SHOW_REMINDERS")
AddStepper(pageDisplay, "shardMin", "SHARD_MIN", 0, 20, 1, function(v) return tostring(v) end)
AddToggle(pageDisplay, "showStones", "SHOW_STONES")
AddToggle(pageDisplay, "showMoney", "SHOW_MONEY")

local pageMap = NewPage()
AddToggle(pageMap, "openMap", "OPEN_MAP")
AddToggle(pageMap, "printCoords", "PRINT_COORDS")
AddToggle(pageMap, "useTomTom", "USE_TOMTOM")
AddCycle(pageMap, "TALENT_BUILD", { "auto", "Affliction", "Demonology", "Destruction" },
    function() return (WockyDB and WockyDB.spec) or "auto" end,
    function(v) WockyDB = WockyDB or {}; if v == "auto" then WockyDB.spec = nil else WockyDB.spec = v end end,
    function(v) if v == "auto" then return L("BUILD_AUTO") end return v end)
AddCycle(pageMap, "ROUTE", { "auto", "SCOURGE", "ORC", "HUMAN", "GNOME" },
    function() return (WockyDB and WockyDB.cfg and WockyDB.cfg.route) or "auto" end,
    function(v) SetCfg("route", v) end,
    function(v)
        if v == "auto" then
            local raceName = UnitRace("player") or "?"
            return L("ROUTE_AUTO", raceName)
        end
        return ROUTE_NAMES[v] or v
    end)

local pageProf = NewPage()
do
    local row = NextRow(pageProf, 44)
    local help = NewFS(row, fonts.high)
    help:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    help:SetWidth(500)
    help:SetJustifyH("LEFT")
    help:SetJustifyV("TOP")
    settingsRows[#settingsRows + 1] = { refresh = function()
        help:SetText(L("PROF_COLOR_HELP") .. "\n" .. Colorize(ColorName(1), 1) .. "  " .. Colorize(ColorName(2), 2) .. "  "
            .. Colorize(ColorName(3), 3) .. "  " .. Colorize(ColorName(4), 4))
    end }
end

-- slot = 1 or 2 for your primary professions, or a skill line ID
local function AddProfColorRow(page, slot)
    local row = NextRow(page)
    local fs = NewFS(row, fonts.high)
    fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    fs:SetWidth(300)
    fs:SetJustifyH("LEFT")
    local b = StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    b:SetSize(184, 22)
    b:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local function Resolve()
        local found = DetectProfessions()
        if type(slot) == "number" and slot > 2 then return slot, found[slot] end
        local p = PrimaryProfessions(found)[slot]
        return p and p.id, p
    end

    b:SetScript("OnClick", function(self, mouse)
        local id = Resolve()
        if not id then return end
        local c = ProfMinColor(id)
        if mouse == "RightButton" then c = c - 1 else c = c + 1 end
        if c < 1 then c = 3 end
        if c > 3 then c = 1 end
        WockyDB.cfg.profColor = WockyDB.cfg.profColor or {}
        WockyDB.cfg.profColor[id] = c
        ApplyAll()
    end)

    settingsRows[#settingsRows + 1] = { refresh = function()
        local id, p = Resolve()
        if id then
            local g = WockyProfGuides[id]
            local icon = (p and p.icon) or g.icon
            local name = (p and p.name) or g.name
            fs:SetText("|T" .. icon .. ":16:16:0:0|t " .. name)
            local c = ProfMinColor(id)
            b:SetText(Colorize(ColorName(c), c))
            b:Enable()
        else
            fs:SetText("|TInterface\\Icons\\INV_Misc_QuestionMark:16:16:0:0|t |cFF888888" .. L("PROF_SLOT", slot) .. " (" .. L("PROF_SLOT_EMPTY") .. ")|r")
            b:SetText("-")
            b:Disable()
        end
    end }
end
AddProfColorRow(pageProf, 1)
AddProfColorRow(pageProf, 2)
AddProfColorRow(pageProf, 185)
AddProfColorRow(pageProf, 129)
do
    local row = NextRow(pageProf, 30)
    local note = NewFS(row, fonts.high)
    note:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    note:SetWidth(500)
    note:SetJustifyH("LEFT")
    settingsRows[#settingsRows + 1] = { refresh = function()
        local g = WockyProfGuides and WockyProfGuides[356]
        note:SetText("|T" .. ((g and g.icon) or "") .. ":16:16:0:0|t |cFF888888" .. L("PROF_FISH_NOTE") .. "|r")
    end }
end

local pageLang = NewPage()
AddLanguageMenu(pageLang)
AddButton(pageLang, "RESET_POS", function() ResetPosition() end)
AddButton(pageLang, "RESET_CHECKS", function()
    WockyDB.doneByChar = WockyDB.doneByChar or {}
    WockyDB.doneByChar[CharKey()] = {}
    UpdateWockyGuide(viewLevel)
end)
AddButton(pageLang, "RESET_ALL", function()
    WockyDB.cfg = nil
    WockyDB.spec = nil
    InitDB()
    ResetPosition()
    ApplyAll()
end)

local TAB_KEYS = { "TAB_GENERAL", "TAB_DISPLAY", "TAB_MAPTALENT", "TAB_PROF", "TAB_LANG" }
local function SelectTab(index)
    CloseMenu()
    for i, page in ipairs(settingsPages) do
        if i == index then page:Show() else page:Hide() end
        settingsTabs[i].selected = (i == index)
    end
    RefreshSettings()
end
for i, key in ipairs(TAB_KEYS) do
    local t = StyleButton(CreateFrame("Button", nil, Settings, "UIPanelButtonTemplate"))
    t:SetSize(100, 22)
    t:SetPoint("TOPLEFT", Settings, "TOPLEFT", 14 + (i - 1) * 102, -40)
    t.key = key
    t:SetScript("OnClick", function() SelectTab(i) end)
    settingsTabs[i] = t
end

local closeButton = StyleButton(CreateFrame("Button", nil, Settings, "UIPanelButtonTemplate"))
closeButton:SetSize(110, 22)
closeButton:SetPoint("BOTTOM", Settings, "BOTTOM", 0, 14)
closeButton:SetScript("OnClick", function() CloseMenu(); Settings:Hide() end)
settingsRows[#settingsRows + 1] = { refresh = function() closeButton:SetText(L("CLOSE")) end }

Settings:SetScript("OnHide", CloseMenu)

local function ToggleSettings()
    if Settings:IsShown() then
        Settings:Hide()
    else
        Settings:Show()
        SelectTab(1)
    end
end
gearButton:SetScript("OnClick", ToggleSettings)

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local WOCKY_ICON = "Interface\\AddOns\\WockyPro\\WockyIcon"

-- Same size, art and placement as standard LibDBIcon minimap buttons
local mini = CreateFrame("Button", "WockyMinimapButton", Minimap)
mini:SetSize(31, 31)
mini:SetFrameStrata("MEDIUM")
mini:SetFrameLevel(8)
pcall(function() mini:SetFixedFrameStrata(true) end)
pcall(function() mini:SetFixedFrameLevel(true) end)
pcall(function() mini:SetClampedToScreen(true) end)

local miniBorder = mini:CreateTexture(nil, "OVERLAY")
miniBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
miniBorder:SetSize(50, 50)
miniBorder:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, 0)

local miniBg = mini:CreateTexture(nil, "BACKGROUND")
miniBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
miniBg:SetSize(24, 24)
miniBg:SetPoint("CENTER", mini, "CENTER", 0, 0)

local miniIcon = mini:CreateTexture(nil, "ARTWORK")
miniIcon:SetTexture(WOCKY_ICON)
miniIcon:SetSize(18, 18)
miniIcon:SetPoint("CENTER", mini, "CENTER", 0, 0)
miniIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
pcall(function() miniIcon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end)

mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mini:RegisterForDrag("LeftButton")

-- Which quarters of the minimap are round for each minimap shape (from LibDBIcon)
local MINIMAP_SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false }
}

local function PositionMinimapButton()
    local angle = math.rad(Cfg("minimapAngle") or 225)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = "ROUND"
    pcall(function() if GetMinimapShape then shape = GetMinimapShape() or "ROUND" end end)
    local quad = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES["ROUND"]
    local mw, mh = 140, 140
    pcall(function()
        mw = tonumber(Minimap:GetWidth()) or 140
        mh = tonumber(Minimap:GetHeight()) or 140
    end)
    if mw < 50 then mw = 140 end
    if mh < 50 then mh = 140 end
    local w = mw / 2 + 5
    local h = mh / 2 + 5
    if quad[q] then
        x, y = x * w, y * h
    else
        local dw = math.sqrt(2 * w * w) - 10
        local dh = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Follow the minimap if it is resized (Edit Mode, other addons)
pcall(function() Minimap:HookScript("OnSizeChanged", function() PositionMinimapButton() end) end)

mini:SetScript("OnClick", function(self, mouse)
    if mouse == "RightButton" then
        ToggleSettings()
    else
        if WockyUI:IsShown() then WockyUI:Hide() else WockyUI:Show() end
    end
end)
mini:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        cx, cy = cx / s, cy / s
        SetCfg("minimapAngle", math.deg(atan2(cy - my, cx - mx)))
        PositionMinimapButton()
    end)
end)
mini:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)
mini:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|T" .. WOCKY_ICON .. ":16:16:0:0|t Wocky Guide " .. VERSION)
    GameTooltip:AddLine(L("MINI_LEFT"), 1, 1, 1)
    GameTooltip:AddLine(L("MINI_RIGHT"), 1, 1, 1)
    GameTooltip:AddLine(L("MINI_DRAG"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

gearButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L("SETTINGS"))
    GameTooltip:Show()
end)
gearButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

collapseButton:SetScript("OnClick", function()
    SetCfg("collapsed", not Cfg("collapsed"))
    Layout(lastQ, lastP, lastT)
end)
collapseButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L("COLLAPSE"))
    GameTooltip:Show()
end)
collapseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Apply everything
---------------------------------------------------------------------------
ApplyAll = function()
    ApplyFonts()
    local a = ACCENTS[Cfg("accent")] or ACCENTS[1]

    WockyUI:SetScale(Cfg("scale"))
    WockyUI:SetBackdropColor(0, 0, 0, Cfg("alpha"))
    WockyUI:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    Settings:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    title:SetText("|cFF" .. a[4] .. "Wocky Guide v" .. VERSION .. "|r")

    if Cfg("showShards") then shardText:Show() else shardText:Hide() end
    if Cfg("showBags") then bagButton:Show() else bagButton:Hide() end
    if Cfg("showChar") then
        charInfoText:Show()
        charSpecText:Show()
    else
        charInfoText:Hide()
        charSpecText:Hide()
    end

    bagButton:SetText(L("BAGS"))
    backButton:SetText(L("PREV"))
    nowButton:SetText(L("NOW"))
    nextButton:SetText(L("NEXT"))

    if Cfg("minimap") then mini:Show() else mini:Hide() end
    PositionMinimapButton()

    UpdateWockyGuide(viewLevel)
    RefreshSettings()
end

---------------------------------------------------------------------------
-- Slash commands and events
---------------------------------------------------------------------------
SLASH_WOCKY1 = "/wocky"
SlashCmdList["WOCKY"] = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "settings" or msg == "config" or msg == "options" then
        ToggleSettings()
        return
    end
    if msg == "talents" then
        local nodes = CollectNodes()
        AssignTrees(nodes)
        table.sort(nodes, function(a, b)
            if a.tree ~= b.tree then return a.tree < b.tree end
            if a.row ~= b.row then return a.row < b.row end
            return a.x < b.x
        end)
        print("|cFF8787ED[Wocky talents]|r " .. #nodes)
        for _, n in ipairs(nodes) do
            print(TREE_NAMES[n.tree] .. " r" .. n.row .. ": " .. (n.name or "?") .. " " .. n.pts .. "/" .. n.max)
        end
        for _, spec in ipairs(TREE_NAMES) do
            local _, missing = PlanTalents(spec, nodes, 1, true)
            if #missing > 0 then print("|cFFFF6666" .. spec .. " missing:|r " .. table.concat(missing, ", ")) end
        end
        return
    end
    local routeArg = string.match(msg, "^route%s+(%a+)$")
    if routeArg then
        local map = { auto = "auto", undead = "SCOURGE", orc = "ORC", troll = "ORC", human = "HUMAN", gnome = "GNOME" }
        if map[routeArg] then
            SetCfg("route", map[routeArg])
            print("|cFF8787ED[Wocky]|r " .. L("ROUTE") .. ": " .. (map[routeArg] == "auto" and L("ROUTE_AUTO", UnitRace("player") or "?") or ROUTE_NAMES[map[routeArg]]))
            ApplyAll()
        else
            print("|cFF8787ED[Wocky]|r /wocky route auto | undead | orc | troll | human | gnome")
        end
        return
    end
    if msg == "prof" then
        local found = DetectProfessions()
        print("|cFF8787ED[Wocky prof]|r")
        for id, p in pairs(found) do
            print(id .. " " .. tostring(p.name) .. " " .. tostring(p.rank) .. "/" .. tostring(p.max))
        end
        return
    end
    if msg == "debug3" then
        local nodes = CollectNodes()
        local splits, xs, gaps = FindSplits(nodes)
        print("|cFF8787ED[Wocky debug3]|r nodes: " .. #nodes)
        print("distinct X: " .. table.concat(xs, ", "))
        for i = 1, math.min(4, #gaps) do print("gap " .. i .. ": size " .. gaps[i].size .. " at " .. gaps[i].at) end
        local pts, total = GetTreePoints()
        print("points: " .. pts[1] .. "/" .. pts[2] .. "/" .. pts[3] .. " total " .. total)
        return
    end
    local arg = string.match(msg, "^spec%s+(%a+)$")
    if arg then
        local map = { aff = "Affliction", affliction = "Affliction", demo = "Demonology", demonology = "Demonology", destro = "Destruction", destruction = "Destruction" }
        WockyDB = WockyDB or {}
        if arg == "auto" then
            WockyDB.spec = nil
        elseif map[arg] then
            WockyDB.spec = map[arg]
        else
            print("|cFF8787ED[Wocky]|r /wocky spec aff | demo | destro | auto")
        end
        UpdateWockyGuide(viewLevel)
        RefreshSettings()
        return
    end
    if WockyUI:IsShown() then WockyUI:Hide() else WockyUI:Show() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(function() eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE") end)
pcall(function() eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED") end)
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "CRAFT_SHOW", "CRAFT_UPDATE", "NEW_RECIPE_LEARNED", "TRAINER_CLOSED" }) do
    pcall(function() eventFrame:RegisterEvent(ev) end)
end
local lastTrainerWasProf = false
for _, ev in ipairs({ "PLAYER_MONEY", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "UNIT_SPELLCAST_SUCCEEDED",
    "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "TRAIT_NODE_CHANGED" }) do
    pcall(function() eventFrame:RegisterEvent(ev) end)
end
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "UNIT_PET", "TRAINER_SHOW",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_GAINED" }) do
    pcall(function() eventFrame:RegisterEvent(ev) end)
end
eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        InitDB()
        local _, className = UnitClass("player")
        WockyUI:ClearAllPoints()
        local pos = WockyDB.pos
        if pos and pos[1] then
            WockyUI:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
        else
            WockyUI:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        viewLevel = UnitLevel("player") or 1
        ApplyAll()
        if className == "WARLOCK" and Cfg("showOnLogin") then
            WockyUI:Show()
        else
            WockyUI:Hide()
        end
        WockyDB.train = WockyDB.train or {}
        WockyDB.ssUsed = WockyDB.ssUsed or {}
        sessionMoney = (GetMoney and GetMoney()) or 0
        TrackXP()
        C_Timer.After(0.5, function() UpdateWockyGuide(viewLevel) end)
        C_Timer.After(3, function()
            UpdateWockyGuide(viewLevel)
            PositionMinimapButton()
        end)
        if C_Timer.NewTicker then
            C_Timer.NewTicker(5, function()
                if WockyUI:IsShown() then UpdateExtras(true) end
            end)
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(arg1) or UnitLevel("player") or 1
        if newLevel % 2 == 0 then
            WockyDB.train = WockyDB.train or {}
            WockyDB.train[CharKey()] = newLevel
        end
        if Cfg("autoLevel") then
            UpdateWockyGuide(tonumber(arg1) or UnitLevel("player") or 1)
        else
            UpdateWockyGuide(viewLevel)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateShards()
        UpdateExtras(true)
    elseif event == "PLAYER_MONEY" then
        UpdateMoney()
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        UpdateWockyGuide(viewLevel)
        QueueProfScan()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        QueueProfScan()
    elseif event == "NEW_RECIPE_LEARNED" then
        local skillLine
        pcall(function()
            if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe then
                skillLine = C_TradeSkillUI.GetTradeSkillLineForRecipe(arg1)
            end
        end)
        MarkProfRefresh(skillLine and WockyProfGuides[skillLine] and skillLine or nil)
        QueueProfScan()
        UpdateWockyGuide(viewLevel)
    elseif event == "TRAINER_CLOSED" then
        if lastTrainerWasProf then
            MarkProfRefresh(nil)
            UpdateWockyGuide(viewLevel)
        end
        lastTrainerWasProf = false
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" and SS_USE_SPELLS[tonumber(arg3) or 0] and time then
            WockyDB.ssUsed = WockyDB.ssUsed or {}
            WockyDB.ssUsed[CharKey()] = time()
            UpdateStones()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        UpdateStones()
    elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
        TrackXP()
        UpdateExtras(true)
    elseif event == "TRAINER_SHOW" then
        local isProfession = false
        pcall(function() isProfession = IsTradeskillTrainer and IsTradeskillTrainer() end)
        lastTrainerWasProf = isProfession and true or false
        if not isProfession and WockyDB.train then
            WockyDB.train[CharKey()] = nil
            UpdateExtras(true)
        end
    elseif event == "UNIT_PET" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
        or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_CONTROL_GAINED" then
        if event ~= "UNIT_PET" or arg1 == "player" then
            C_Timer.After(0.2, function() UpdateExtras(true) end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Cfg("hideCombat") and WockyUI:IsShown() then
            combatHidden = true
            WockyUI:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if combatHidden then
            combatHidden = false
            WockyUI:Show()
        end
    else
        UpdateWockyGuide(viewLevel)
    end
end)
