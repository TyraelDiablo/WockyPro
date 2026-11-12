-- WockyExtras: navigation arrow, leveling helpers, status icons, vendor helper,
-- item upgrade scores, key bindings, addon compartment and help.
local W = WockyAPI
if not W then return end

local L, Cfg, SetCfg = W.L, W.Cfg, W.SetCfg
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

for k, v in pairs({
    showArrow = true, arrowScale = 1, showHearth = true, showDungeons = true,
    showUpgrade = true, autoSellJunk = true, autoRepair = true, autoCheck = true
}) do
    if W.DEFAULTS[k] == nil then W.DEFAULTS[k] = v end
end

local function Chat(msg)
    print("|cFF8787ED[Wocky]|r " .. msg)
end

---------------------------------------------------------------------------
-- Navigation arrow
---------------------------------------------------------------------------
local arrow = CreateFrame("Button", "WockyArrowFrame", UIParent)
arrow:SetSize(140, 84)
arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
arrow:SetFrameStrata("MEDIUM")
arrow:SetMovable(true)
arrow:EnableMouse(true)
arrow:SetClampedToScreen(true)
arrow:RegisterForDrag("LeftButton")
arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
arrow:Hide()

local arrowTex = arrow:CreateTexture(nil, "ARTWORK")
arrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
arrowTex:SetSize(48, 48)
arrowTex:SetPoint("TOP", arrow, "TOP", 0, 0)

local arrowName = W.NewFS(arrow, W.fonts.normal)
arrowName:SetPoint("TOP", arrowTex, "BOTTOM", 0, -1)
arrowName:SetWidth(220)
arrowName:SetJustifyH("CENTER")
pcall(function() arrowName:SetWordWrap(false) end)

local arrowInfo = W.NewFS(arrow, W.fonts.high)
arrowInfo:SetPoint("TOP", arrowName, "BOTTOM", 0, -1)
arrowInfo:SetWidth(220)
arrowInfo:SetJustifyH("CENTER")

local guideTarget, manualTarget

local function ActiveTarget()
    return manualTarget or guideTarget
end

local function RefreshArrowShown()
    local t = ActiveTarget()
    local hide = not Cfg("showArrow") or not t
    if not hide and Cfg("hideCombat") and InCombatLockdown and InCombatLockdown() then hide = true end
    if hide then arrow:Hide() else arrow:Show() end
end

local function MakeTarget(zone, x, y, name, manual)
    local mapID = W.MAP_IDS[zone]
    return { zone = zone, x = (tonumber(x) or 0) / 100, y = (tonumber(y) or 0) / 100, name = name or zone, manual = manual, mapID = mapID }
end

function W.SetArrowTarget(zone, x, y, name, manual)
    if not zone or not x or not y then return end
    if manual then
        manualTarget = MakeTarget(zone, x, y, name, true)
    else
        guideTarget = MakeTarget(zone, x, y, name, false)
    end
    RefreshArrowShown()
end

local mapSizes = {}
local function MapSize(mapID)
    if mapSizes[mapID] ~= nil then return mapSizes[mapID][1], mapSizes[mapID][2] end
    local w, h
    pcall(function()
        if C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
    end)
    if not w or w <= 0 then
        pcall(function()
            local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
            local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
            if a and b then
                w = math.abs(b.y - a.y)
                h = math.abs(b.x - a.x)
            end
        end)
    end
    if w and w > 0 and h and h > 0 then
        mapSizes[mapID] = { w, h }
        return w, h
    end
    mapSizes[mapID] = false
end

local function PlayerPosOn(mapID)
    local px, py
    pcall(function()
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
        end
    end)
    if px and py and px > 0 and px < 1 and py > 0 and py < 1 then return px, py end
end

local function ClearManual(announce)
    manualTarget = nil
    RefreshArrowShown()
    if announce then Chat(L("ARROW_CLEARED")) end
end

local arrowElapsed = 0
local arrivedAt
arrow:SetScript("OnUpdate", function(self, elapsed)
    arrowElapsed = arrowElapsed + (elapsed or 0)
    if arrowElapsed < 0.05 then return end
    arrowElapsed = 0
    local t = ActiveTarget()
    if not t then self:Hide() return end
    arrowName:SetText(t.name or "")
    local px, py
    if t.mapID then px, py = PlayerPosOn(t.mapID) end
    if not px then
        arrowTex:Hide()
        arrowInfo:SetText("|cFFFFD100" .. L("ARROW_GOTO", t.zone or "?") .. "|r")
        return
    end
    local w, h = MapSize(t.mapID)
    local east = (t.x - px) * (w or 1000)
    local south = (t.y - py) * (h or 1000)
    local dist = math.sqrt(east * east + south * south)

    if w and dist < 10 then
        arrowTex:Hide()
        arrowInfo:SetText("|cFF00FF00" .. L("ARROW_ARRIVED") .. "|r")
        if t.manual then
            arrivedAt = arrivedAt or GetTime()
            if GetTime() - arrivedAt > 3 then
                arrivedAt = nil
                ClearManual(false)
            end
        end
        return
    end
    arrivedAt = nil

    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing then
        local angle = atan2(-east, -south) - facing
        local a = angle % (2 * math.pi)
        if a > math.pi then a = a - 2 * math.pi end
        local off = math.abs(a) / math.pi
        local r = math.min(1, off * 2)
        local g = math.min(1, (1 - off) * 2)
        pcall(arrowTex.SetRotation, arrowTex, angle)
        arrowTex:SetVertexColor(r, g, 0.1)
        arrowTex:Show()
    else
        arrowTex:Hide()
    end
    if w then
        arrowInfo:SetText(L("ARROW_YARDS", math.floor(dist + 0.5)))
    else
        arrowInfo:SetText("")
    end
end)

arrow:SetScript("OnDragStart", function(self) self:StartMoving() end)
arrow:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if p then
        WockyDB = WockyDB or {}
        WockyDB.arrowPos = { p, rp, x, y }
    end
end)
arrow:SetScript("OnClick", function(self, button)
    if button ~= "RightButton" then
        local t = ActiveTarget()
        if t and W.OpenMapZone then W.OpenMapZone(t.zone) end
        return
    end
    if manualTarget then
        ClearManual(true)
    else
        SetCfg("showArrow", false)
        RefreshArrowShown()
        Chat(L("ARROW_HIDDEN"))
        if W.RefreshSettings then W.RefreshSettings() end
    end
end)
arrow:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local t = ActiveTarget()
    if t then
        GameTooltip:AddLine(t.name or "")
        GameTooltip:AddLine(string.format("%s (%d, %d)", t.zone or "?", math.floor(t.x * 100 + 0.5), math.floor(t.y * 100 + 0.5)), 1, 1, 1)
    end
    GameTooltip:AddLine(L("ARROW_TIP_LEFT"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L("ARROW_TIP_DRAG"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L("ARROW_TIP_RIGHT"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ToggleArrow()
    SetCfg("showArrow", not Cfg("showArrow"))
    RefreshArrowShown()
    if W.RefreshSettings then W.RefreshSettings() end
end

---------------------------------------------------------------------------
-- Kills to level (average XP of your recent kills)
---------------------------------------------------------------------------
local killXP = {}

local function RecordKillXP(msg)
    local n = tonumber(string.match(msg or "", "(%d+)"))
    if n and n > 0 then
        killXP[#killXP + 1] = n
        if #killXP > 15 then table.remove(killXP, 1) end
    end
end

function W.XPExtra(cur, max)
    if #killXP == 0 or not cur or not max then return nil end
    local sum = 0
    for _, v in ipairs(killXP) do sum = sum + v end
    local avg = sum / #killXP
    local left = max - cur
    if avg <= 0 or left <= 0 then return nil end
    return L("XP_KILLS", math.ceil(left / avg))
end

---------------------------------------------------------------------------
-- Route progress and dungeon suggestions
---------------------------------------------------------------------------
function W.QuestSuffix()
    local route = WockyGuideDB and WockyGuideDB[W.RouteKey()]
    if not route then return "" end
    local doneT = W.DoneTable()
    local total, done = 0, 0
    for lvl = 1, W.MAX_LEVEL do
        local e = route["L" .. lvl]
        if e and e.quest then
            local i = 0
            for _ in string.gmatch(e.quest, "[^\n]+") do
                i = i + 1
                total = total + 1
                if doneT["Q" .. lvl .. ":" .. i] then done = done + 1 end
            end
        end
    end
    if total == 0 then return "" end
    return " |cFF888888" .. math.floor(done / total * 100 + 0.5) .. "%|r"
end

local dungeonBtn = CreateFrame("Button", nil, W.WockyUI)
dungeonBtn:SetSize(328, 14)
dungeonBtn:Hide()
local dungeonText = W.NewFS(dungeonBtn, W.fonts.small)
dungeonText:SetPoint("TOPLEFT", dungeonBtn, "TOPLEFT", 0, 0)
dungeonText:SetWidth(328)
dungeonText:SetJustifyH("LEFT")
local dungeonTip = {}

local function DungeonsFor(level)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local list = {}
    for _, d in ipairs(WockyDungeons or {}) do
        if level >= d[2] and level <= d[3] and (not d[5] or not faction or d[5] == faction) then
            list[#list + 1] = d
        end
    end
    return list
end

local function UpdateDungeons(level)
    local list = DungeonsFor(level)
    if not Cfg("showDungeons") or #list == 0 then
        dungeonText:SetText("")
        dungeonTip = {}
        return
    end
    local names = {}
    for i = 1, math.min(3, #list) do names[#names + 1] = list[i][1] end
    dungeonZone = list[1][4]
    local text = "|cFF9999FF" .. L("DUNGEONS") .. ":|r " .. table.concat(names, ", ")
    if #list > 3 then text = text .. " |cFF888888+" .. (#list - 3) .. "|r" end
    dungeonText:SetText(text)
    dungeonTip = { { L("DUNGEON_TIP", level), 1, 0.82, 0 } }
    for _, d in ipairs(list) do
        dungeonTip[#dungeonTip + 1] = { d[1] .. "  " .. d[2] .. "-" .. d[3] .. "  |cFF888888" .. d[4] .. "|r", 1, 1, 1 }
    end
    dungeonTip[#dungeonTip + 1] = { L("CLICK_MAP"), 0.45, 0.8, 1 }
end

dungeonBtn:SetScript("OnEnter", function(self)
    if #dungeonTip == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for _, line in ipairs(dungeonTip) do GameTooltip:AddLine(line[1], line[2], line[3], line[4]) end
    GameTooltip:Show()
end)
dungeonBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
local dungeonZone
dungeonBtn:SetScript("OnClick", function()
    if dungeonZone and W.OpenMapZone then W.OpenMapZone(dungeonZone) end
end)

function W.ExtraLayout(y)
    if Cfg("collapsed") or not Cfg("showDungeons") or (dungeonText:GetText() or "") == "" then
        dungeonBtn:Hide()
        return y
    end
    local h = W.TextH(dungeonText)
    dungeonBtn:SetHeight(h)
    dungeonBtn:ClearAllPoints()
    dungeonBtn:SetPoint("TOPLEFT", W.WockyUI, "TOPLEFT", 16, -y)
    dungeonBtn:Show()
    return y + h + 4
end

function W.OnGuide(level, data)
    UpdateDungeons(level)
    if data and data.zone and data.x and data.y then
        W.SetArrowTarget(data.zone, data.x, data.y, data.npc or data.zone, false)
    end
end

---------------------------------------------------------------------------
-- Hearthstone icon, free bag slots, extra reminders
---------------------------------------------------------------------------
local HEARTHSTONE = 6948
local hearthBtn = W.MakeStoneButton("Interface\\Icons\\INV_Misc_Rune_01")
W.hearthBtn = hearthBtn
local hearthIconSet = false

local function UpdateHearth()
    if not Cfg("showHearth") then
        hearthBtn:Hide()
        return
    end
    if not hearthIconSet then
        local icon = W.ItemIcon(HEARTHSTONE)
        if icon then hearthBtn.icon:SetTexture(icon) end
        hearthIconSet = true
    end
    local x = 1
    if W.hsBtn:IsShown() then x = x + 36 end
    if W.ssBtn:IsShown() then x = x + 36 end
    hearthBtn:ClearAllPoints()
    hearthBtn:SetPoint("TOPLEFT", W.statusRow, "TOPLEFT", x, -1)

    local has = (W.BagCounts()[HEARTHSTONE] or 0) > 0
    hearthBtn.icon:SetDesaturated(not has)
    hearthBtn.icon:SetAlpha(has and 1 or 0.45)
    local s, d = W.GetItemCD(HEARTHSTONE)
    local r = 0
    if s and d and s > 0 and d > 1.5 then r = math.max(0, s + d - GetTime()) end
    W.SetStoneCD(hearthBtn, s, d, r)

    local bind = (GetBindLocation and GetBindLocation()) or "?"
    hearthBtn.tipTitle = "Hearthstone"
    if not has then
        hearthBtn.tipText = L("HEARTH_NONE") .. "\n" .. L("HEARTH_BIND", bind)
    elseif r > 0 then
        hearthBtn.tipText = L("HEARTH_BIND", bind) .. "\n" .. L("HEARTH_CD", W.LongTime(r))
    else
        hearthBtn.tipText = L("HEARTH_BIND", bind) .. "\n|cFF00FF00" .. L("HEARTH_READY") .. "|r"
    end
    hearthBtn:Show()
end

local function FreeBagSlots()
    local free = 0
    pcall(function()
        local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
        for bag = 0, 4 do
            local n, bagType = getFree(bag)
            if n and (bagType == nil or bagType == 0) then free = free + n end
        end
    end)
    return free
end

local function UpdateBagButton()
    local b = W.bagButton
    if not b then return end
    b:SetSize(86, 20)
    local free = FreeBagSlots()
    local color = free < 3 and "|cFFFF4040" or (free < 8 and "|cFFFFD100" or "|cFFFFFFFF")
    b:SetText(L("BAGS") .. " " .. color .. "(" .. free .. ")|r")
    W.charInfoText:SetWidth(186)
    W.charSpecText:SetWidth(186)
end

local function QuestLogCount()
    local n, max = nil, nil
    pcall(function()
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            local _, q = C_QuestLog.GetNumQuestLogEntries()
            n = q
        elseif GetNumQuestLogEntries then
            local _, q = GetNumQuestLogEntries()
            n = q
        end
    end)
    pcall(function()
        if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then max = C_QuestLog.GetMaxNumQuestsCanAccept() end
    end)
    return n, max or MAX_QUESTLOG_QUESTS or 20
end

function W.ExtraReminders(list)
    local free = FreeBagSlots()
    if free < 3 then list[#list + 1] = L("REMIND_BAGS", free) end
    local n, max = QuestLogCount()
    if n and max and n >= max - 1 then list[#list + 1] = L("REMIND_QUESTLOG", n, max) end
end

function W.OnExtras()
    UpdateHearth()
    UpdateBagButton()
end

function W.OnApply()
    UpdateBagButton()
    arrow:SetScale(Cfg("arrowScale") or 1)
    RefreshArrowShown()
end

-- keeps the hearthstone cooldown number ticking
local hearthTicker = CreateFrame("Frame")
local hearthElapsed = 0
hearthTicker:SetScript("OnUpdate", function(self, elapsed)
    hearthElapsed = hearthElapsed + (elapsed or 0)
    if hearthElapsed < 1 then return end
    hearthElapsed = 0
    if hearthBtn:IsShown() and W.WockyUI:IsShown() then UpdateHearth() end
end)

---------------------------------------------------------------------------
-- Vendor helper: sell gray items, repair
---------------------------------------------------------------------------
local function ContainerItem(bag, slot)
    local quality, link, count, noValue
    pcall(function()
        if C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                quality, link, count, noValue = info.quality, info.hyperlink, info.stackCount, info.hasNoValue
            end
        elseif GetContainerItemInfo then
            local _, c, _, q, _, _, l, _, nv = GetContainerItemInfo(bag, slot)
            quality, link, count, noValue = q, l, c, nv
        end
    end)
    return quality, link, count or 1, noValue
end

local function Repair()
    if not Cfg("autoRepair") then return end
    pcall(function()
        if not (CanMerchantRepair and CanMerchantRepair()) then return end
        local cost, need = GetRepairAllCost()
        if not need or not cost or cost <= 0 then return end
        if GetMoney() >= cost then
            RepairAllItems()
            Chat(L("REPAIRED", W.CoinText(cost)))
        else
            Chat(L("REPAIR_NO_MONEY", W.CoinText(cost)))
        end
    end)
end

local function SellJunk()
    if not Cfg("autoSellJunk") then return 0 end
    local items, total = {}, 0
    local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local use = (C_Container and C_Container.UseContainerItem) or UseContainerItem
    if not getSlots or not use then return 0 end
    for bag = 0, 4 do
        for slot = 1, (getSlots(bag) or 0) do
            local quality, link, count, noValue = ContainerItem(bag, slot)
            if quality == 0 and link and not noValue then
                local price = 0
                pcall(function() price = select(11, GetItemInfo(link)) or 0 end)
                if price > 0 then
                    items[#items + 1] = { bag, slot }
                    total = total + price * count
                end
            end
        end
    end
    for i, it in ipairs(items) do
        C_Timer.After(0.15 * (i - 1), function()
            if MerchantFrame and MerchantFrame.IsShown and not MerchantFrame:IsShown() then return end
            pcall(use, it[1], it[2])
        end)
    end
    if #items > 0 then Chat(L("SOLD_JUNK", #items, W.CoinText(total))) end
    return #items
end

local function OnMerchantShow()
    local sold = SellJunk()
    C_Timer.After(0.15 * sold + 0.3, Repair)
end

---------------------------------------------------------------------------
-- Item upgrade score on tooltips (leveling Warlock weights, an estimate)
---------------------------------------------------------------------------
local WEIGHTS = { sp = 1.0, sta = 0.6, int = 0.5, spi = 0.3, wand = 2.0 }
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }
}
-- Warlocks: cloth armor and misc slots; daggers, one-hand swords, staves and wands
local USABLE = { [4] = { [0] = true, [1] = true }, [2] = { [7] = true, [10] = true, [15] = true, [19] = true } }

local function ItemInstant(link)
    local equipLoc, classID, subclassID
    pcall(function()
        local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local _, _, _, loc, _, c, s = get(link)
        equipLoc, classID, subclassID = loc, c, s
    end)
    return equipLoc, classID, subclassID
end

local function Score(link, equipLoc)
    if not link then return 0 end
    local stats
    pcall(function()
        stats = (C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link))
    end)
    if type(stats) ~= "table" then return 0 end
    local s = 0
    for k, v in pairs(stats) do
        local key = string.upper(tostring(k))
        local w
        if string.find(key, "STAMINA") then w = WEIGHTS.sta
        elseif string.find(key, "INTELLECT") then w = WEIGHTS.int
        elseif string.find(key, "SPIRIT") then w = WEIGHTS.spi
        elseif string.find(key, "DAMAGE_PER_SECOND") then
            if equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_RANGED" then w = WEIGHTS.wand end
        elseif string.find(key, "SPELL") and (string.find(key, "POWER") or string.find(key, "DAMAGE")) then w = WEIGHTS.sp
        end
        if w and type(v) == "number" then s = s + v * w end
    end
    return s
end

local function AddUpgradeLine(tooltip)
    if not Cfg("showUpgrade") or not tooltip or not tooltip.GetItem then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = tooltip:GetItem()
    if not link then return end
    local equipLoc, classID, subclassID = ItemInstant(link)
    local slots = equipLoc and SLOTS[equipLoc]
    if not slots then return end
    if USABLE[classID] and not USABLE[classID][subclassID] then return end
    if not USABLE[classID] then return end

    local new = Score(link, equipLoc)
    local worst, worstLink, empty = nil, nil, false
    for _, slot in ipairs(slots) do
        local eq = GetInventoryItemLink("player", slot)
        if eq == link then return end
        if not eq then
            empty = true
            worst = 0
        else
            local sc = Score(eq, equipLoc)
            if equipLoc == "INVTYPE_2HWEAPON" then
                local off = GetInventoryItemLink("player", 17)
                if off then sc = sc + Score(off, "INVTYPE_HOLDABLE") end
            end
            if not empty and (worst == nil or sc < worst) then worst, worstLink = sc, eq end
        end
    end
    if new == 0 and (worst or 0) == 0 then return end
    local diff = new - (worst or 0)
    local text
    if empty then
        text = string.format("|cFF00FF00+%.1f|r |cFF888888(%s)|r", new, L("UPGRADE_EMPTY"))
    elseif diff > 0.05 then
        text = string.format("|cFF00FF00+%.1f|r", diff)
    elseif diff < -0.05 then
        text = string.format("|cFFFF4040%.1f|r", diff)
    else
        text = "|cFFAAAAAA=|r"
    end
    tooltip:AddLine("|cFF8787EDWocky:|r " .. text)
end

local tooltipHooked = false
local function HookTooltips()
    if tooltipHooked then return end
    tooltipHooked = true
    local done = false
    pcall(function()
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) pcall(AddUpgradeLine, tt) end)
            done = true
        end
    end)
    if not done then
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(AddUpgradeLine, self) end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Opening game windows from the guide
---------------------------------------------------------------------------
local function TryCalls(list)
    for _, fn in ipairs(list) do
        local ok, done = pcall(fn)
        if ok and done ~= false then return true end
    end
    return false
end

function W.OpenTalents()
    local ok = TryCalls({
        function() if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() return true end return false end,
        function() if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then PlayerSpellsUtil.OpenToClassTalentsTab() return true end return false end,
        function() if ToggleTalentFrame then ToggleTalentFrame() return true end return false end
    })
    if not ok then Chat(L("OPEN_FAILED")) end
end

function W.OpenMapZone(zone)
    local mapID = zone and W.MAP_IDS[zone]
    pcall(function()
        if WorldMapFrame and not WorldMapFrame:IsShown() then ToggleWorldMap() end
        if WorldMapFrame and mapID and WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end)
end

local function OpenSpellbook()
    return TryCalls({
        function() if ToggleProfessionsBook then ToggleProfessionsBook() return true end return false end,
        function() if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_PROFESSION or BOOKTYPE_SPELL or "spell") return true end return false end
    })
end

-- Opening a profession uses the game's own (unprotected) function when it exists;
-- otherwise the spellbook opens so you can click the profession there.
local lastTradeShow = 0
function W.OpenProfession(id, name)
    local clickedAt = GetTime()
    local called = false
    pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
            C_TradeSkillUI.OpenTradeSkill(id)
            called = true
        end
    end)
    local function fallback()
        if lastTradeShow >= clickedAt then return end
        OpenSpellbook()
        Chat(L("OPEN_PROF_HINT", name or "?"))
    end
    if called then C_Timer.After(0.5, fallback) else fallback() end
end

local function OpenQuestLog()
    TryCalls({
        function() if ToggleQuestLog then ToggleQuestLog() return true end return false end,
        function() if QuestLogFrame then ToggleFrame(QuestLogFrame) return true end return false end
    })
end

local function OpenCharacter()
    pcall(function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end)
end

local function OpenBags()
    pcall(function() if ToggleAllBags then ToggleAllBags() end end)
end

-- invisible click areas on top of text labels
local function ClickOverlay(region, onClick, hintKey)
    if not region then return end
    local b = CreateFrame("Button", nil, W.WockyUI)
    b:SetAllPoints(region)
    pcall(function() b:SetFrameLevel(W.WockyUI:GetFrameLevel() + 3) end)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.07)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() local f = W.WockyUI:GetScript("OnDragStart"); if f then f(W.WockyUI) end end)
    b:SetScript("OnDragStop", function() local f = W.WockyUI:GetScript("OnDragStop"); if f then f(W.WockyUI) end end)
    b:SetScript("OnClick", function() if region:IsShown() then pcall(onClick) end end)
    b:SetScript("OnEnter", function(self)
        if not region:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L(hintKey), 0.45, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pcall(hooksecurefunc, region, "Show", function() b:Show() end)
    pcall(hooksecurefunc, region, "Hide", function() b:Hide() end)
    if not region:IsShown() then b:Hide() end
    return b
end

ClickOverlay(W.questHeader, OpenQuestLog, "CLICK_QUESTLOG")
ClickOverlay(W.profHeader, OpenSpellbook, "CLICK_SPELLBOOK")
ClickOverlay(W.talentHeader, W.OpenTalents, "CLICK_TALENTS")
ClickOverlay(W.charInfoText, OpenCharacter, "CLICK_CHAR")
ClickOverlay(W.charSpecText, W.OpenTalents, "CLICK_TALENTS")
ClickOverlay(W.shardText, OpenBags, "CLICK_BAGS")
if W.moneyBtn then
    W.moneyBtn:SetScript("OnClick", OpenBags)
    W.moneyBtn:HookScript("OnEnter", function()
        GameTooltip:AddLine(L("CLICK_BAGS"), 0.45, 0.8, 1)
        GameTooltip:Show()
    end)
end

-- mouse wheel over the window flips through the levels
W.WockyUI:EnableMouseWheel(true)
W.WockyUI:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then WockyPro_Prev() else WockyPro_Next() end
end)

---------------------------------------------------------------------------
-- Steps that tick themselves (hearthstone, trainer, flight path)
---------------------------------------------------------------------------
local function AutoCheck(pattern, extra)
    if not Cfg("autoCheck") then return end
    local route = WockyGuideDB and WockyGuideDB[W.RouteKey()]
    if not route then return end
    local doneT = W.DoneTable()
    local levels = { UnitLevel("player") or 1 }
    local vl = W.GetViewLevel()
    if vl ~= levels[1] then levels[2] = vl end
    local changed = {}
    for _, lvl in ipairs(levels) do
        local e = route["L" .. lvl]
        if e and e.quest then
            local i = 0
            for line in string.gmatch(e.quest, "[^\n]+") do
                i = i + 1
                local low = string.lower(line)
                if string.find(low, pattern, 1, true) and (not extra or extra == "" or string.find(low, string.lower(extra), 1, true)) then
                    local key = "Q" .. lvl .. ":" .. i
                    if not doneT[key] then
                        doneT[key] = true
                        changed[#changed + 1] = (string.gsub(line, "^%[ %] ", ""))
                    end
                end
            end
        end
    end
    if #changed > 0 then
        for _, text in ipairs(changed) do Chat(L("AUTO_CHECKED", text)) end
        W.UpdateWockyGuide(W.GetViewLevel())
    end
end

---------------------------------------------------------------------------
-- Settings rows
---------------------------------------------------------------------------
W.AddToggle(W.pageGeneral, "autoSellJunk", "AUTO_SELL")
W.AddToggle(W.pageGeneral, "autoRepair", "AUTO_REPAIR")
W.AddToggle(W.pageGeneral, "showUpgrade", "SHOW_UPGRADE")
W.AddToggle(W.pageDisplay, "showDungeons", "SHOW_DUNGEONS")
W.AddToggle(W.pageMap, "showArrow", "SHOW_ARROW")
W.AddStepper(W.pageMap, "arrowScale", "ARROW_SCALE", 0.6, 1.6, 0.1, function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
W.AddToggle(W.pageMap, "showHearth", "SHOW_HEARTH")
W.AddToggle(W.pageMap, "autoCheck", "AUTO_CHECK")

---------------------------------------------------------------------------
-- Key bindings, addon compartment, Blizzard settings entry
---------------------------------------------------------------------------
BINDING_HEADER_WOCKY = "WockyPro"
BINDING_NAME_WOCKY_TOGGLE = L("BIND_TOGGLE")
BINDING_NAME_WOCKY_NEXT = L("BIND_NEXT")
BINDING_NAME_WOCKY_PREV = L("BIND_PREV")
BINDING_NAME_WOCKY_ARROW = L("BIND_ARROW")

function WockyPro_Toggle()
    if W.WockyUI:IsShown() then W.WockyUI:Hide() else W.WockyUI:Show() end
end
function WockyPro_Next()
    if WockyNextButton then WockyNextButton:Click() end
end
function WockyPro_Prev()
    if WockyBackButton then WockyBackButton:Click() end
end
function WockyPro_ToggleArrow()
    ToggleArrow()
end

function WockyPro_OnAddonCompartmentClick(addonName, button)
    if button == "RightButton" then W.ToggleSettings() else WockyPro_Toggle() end
end
function WockyPro_OnAddonCompartmentEnter(addonName, frame)
    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine("WockyPro " .. W.VERSION)
    GameTooltip:AddLine(L("MINI_LEFT"), 1, 1, 1)
    GameTooltip:AddLine(L("MINI_RIGHT"), 1, 1, 1)
    GameTooltip:Show()
end
function WockyPro_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local function RegisterOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "WockyPro"
    local t = W.NewFS(panel, W.fonts.large)
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    t:SetText("WockyPro " .. W.VERSION)
    local b = W.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    b:SetSize(240, 24)
    b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
    b:SetText(L("OPEN_SETTINGS"))
    b:SetScript("OnClick", function()
        pcall(function() if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end end)
        pcall(function() if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end end)
        if not WockySettingsFrame or not WockySettingsFrame:IsShown() then W.ToggleSettings() end
    end)
    local ok = pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(panel, "WockyPro")
            Settings.RegisterAddOnCategory(cat)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
    return ok
end

---------------------------------------------------------------------------
-- Help, news and the update notice
---------------------------------------------------------------------------
local NEWS = {
    "Click a talent to open the talent window, click a profession to open its window",
    "Clickable headers and labels: quest log, professions, character, bags, map",
    "Mouse wheel over the window flips through the levels",
    "Steps tick themselves when you set your hearthstone, visit your trainer or find a flight path",
    "Navigation arrow that points to the current step or any map link you click",
    "Kills to level on the XP line",
    "Dungeon suggestions for your level",
    "Route progress in percent",
    "Hearthstone icon with bind location and cooldown",
    "Free bag slots on the Bags button, bag and quest log warnings",
    "Sells gray items and repairs at vendors",
    "Upgrade score on item tooltips",
    "Key bindings, addon compartment and Blizzard options entry",
    "/wocky help and /wocky news"
}

local function PrintHelp()
    Chat(L("HELP_HEADER"))
    local cmds = {
        { "/wocky", "HELP_TOGGLE" }, { "/wocky settings", "HELP_SETTINGS" },
        { "/wocky spec aff|demo|destro|auto", "HELP_SPEC" }, { "/wocky route auto|undead|orc|troll|human|gnome", "HELP_ROUTE" },
        { "/wocky arrow", "HELP_ARROW" }, { "/wocky news", "HELP_NEWS" },
        { "/wocky talents", "HELP_TALENTS" }, { "/wocky prof", "HELP_PROF" }
    }
    for _, c in ipairs(cmds) do print("  |cFFFFD100" .. c[1] .. "|r - " .. L(c[2])) end
end

local function PrintNews()
    Chat(L("NEWS_HEADER", W.VERSION))
    for _, line in ipairs(NEWS) do print("  - " .. line) end
end

local baseSlash = SlashCmdList["WOCKY"]
SlashCmdList["WOCKY"] = function(msg)
    local m = string.lower(strtrim(msg or ""))
    if m == "help" or m == "?" then
        PrintHelp()
    elseif m == "news" then
        PrintNews()
    elseif m == "arrow" then
        ToggleArrow()
    elseif baseSlash then
        baseSlash(msg)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "CHAT_MSG_COMBAT_XP_GAIN", "MERCHANT_SHOW", "HEARTHSTONE_BOUND", "QUEST_LOG_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "TRADE_SKILL_SHOW", "CRAFT_SHOW",
    "TRAINER_SHOW", "UI_INFO_MESSAGE" }) do
    pcall(function() ev:RegisterEvent(e) end)
end
local questLogQueued = false
ev:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        HookTooltips()
        RegisterOptionsPanel()
        WockyDB = WockyDB or {}
        local pos = WockyDB.arrowPos
        if pos and pos[1] then
            arrow:ClearAllPoints()
            arrow:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
        end
        arrow:SetScale(Cfg("arrowScale") or 1)
        if WockyDB.lastVersion and WockyDB.lastVersion ~= W.VERSION then
            C_Timer.After(4, function() Chat(L("UPDATED", W.VERSION)) end)
        end
        WockyDB.lastVersion = W.VERSION
        C_Timer.After(1, function()
            UpdateBagButton()
            RefreshArrowShown()
        end)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        RecordKillXP(arg1)
    elseif event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "HEARTHSTONE_BOUND" then
        UpdateHearth()
        C_Timer.After(0.5, function() AutoCheck("hearthstone", GetBindLocation and GetBindLocation()) end)
    elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        lastTradeShow = GetTime()
    elseif event == "TRAINER_SHOW" then
        local isProfession = false
        pcall(function() isProfession = IsTradeskillTrainer and IsTradeskillTrainer() end)
        if not isProfession then AutoCheck("train") end
    elseif event == "UI_INFO_MESSAGE" then
        local msg = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil
        if msg and ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH then AutoCheck("flight path") end
    elseif event == "QUEST_LOG_UPDATE" then
        if not questLogQueued then
            questLogQueued = true
            C_Timer.After(1, function()
                questLogQueued = false
                if W.WockyUI:IsShown() then W.UpdateWockyGuide(W.GetViewLevel()) end
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0, RefreshArrowShown)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        RefreshArrowShown()
    end
end)
