-- WockyStones: Firestone and Spellstone icons next to the Healthstone and Soulstone icons.
-- Shown only when you know a Create Firestone spell or carry a Firestone.
-- Pulses orange-red while you have none. No item use or casting from here.
local W = WockyAPI
if not W or not W.MakeStoneButton or not W.statusRow then return end

local L, Cfg = W.L, W.Cfg

-- Classic IDs (Lesser, normal, Greater, Major). Each one is checked in game
-- with GetItemInfo / GetSpellInfo; unknown IDs are simply skipped.
local FS_ITEMS = { 1254, 13699, 13700, 13701 }
local FS_SPELLS = { 6366, 17951, 17952, 17953 }
local OFFHAND_SLOT = 17

local fsBtn = W.MakeStoneButton("Interface\\Icons\\INV_Ammo_FireTar")
W.fsBtn = fsBtn
fsBtn:Hide()
if fsBtn.glowTex then fsBtn.glowTex:SetVertexColor(1, 0.35, 0.1) end

local isFS = {}
for _, id in ipairs(FS_ITEMS) do isFS[id] = true end

local iconSet = false
local knownAt, knownCache = -100, false
local namesCache

local function SpellNames()
    if namesCache then return namesCache end
    local names = {}
    for _, id in ipairs(FS_SPELLS) do
        pcall(function()
            local n
            if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
            if not n and GetSpellInfo then n = GetSpellInfo(id) end
            if type(n) == "string" and n ~= "" then names[n] = true end
        end)
    end
    names["Create Firestone"] = true
    namesCache = names
    return names
end

local function KnowsSpell()
    local now = GetTime and GetTime() or 0
    if now - knownAt < 5 then return knownCache end
    knownAt = now
    local known = false
    for _, id in ipairs(FS_SPELLS) do
        pcall(function()
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then known = true end
        end)
        if known then break end
    end
    if not known then
        -- by name: GetSpellInfo(name) only answers for spells you know
        for n in pairs(SpellNames()) do
            pcall(function()
                local sid
                if GetSpellInfo then sid = select(7, GetSpellInfo(n)) end
                if type(sid) == "number" then
                    if IsPlayerSpell then known = IsPlayerSpell(sid) and true or false else known = true end
                end
            end)
            if known then break end
        end
    end
    knownCache = known
    return known
end

local function FirestoneCounts()
    local bags, equipped = 0, nil
    local counts = W.BagCounts and W.BagCounts() or {}
    for _, id in ipairs(FS_ITEMS) do bags = bags + (counts[id] or 0) end
    pcall(function()
        local id = GetInventoryItemID and GetInventoryItemID("player", OFFHAND_SLOT)
        if id and isFS[id] then equipped = id end
    end)
    return bags, equipped
end

local function ItemName(id)
    local n
    pcall(function()
        if C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(id) end
        if not n and GetItemInfo then n = GetItemInfo(id) end
    end)
    return n
end

local function UpdateFirestone()
    local bags, equipped = FirestoneCounts()
    local has = bags > 0 or equipped ~= nil
    if not Cfg("showStones") or not (has or KnowsSpell()) then
        fsBtn:SetGlow(false)
        fsBtn:Hide()
        return
    end
    if not iconSet then
        local icon = W.ItemIcon(13699) or W.ItemIcon(1254)
        if icon then fsBtn.icon:SetTexture(icon) end
        iconSet = true
    end
    local x = 1
    if W.hsBtn:IsShown() then x = x + 36 end
    if W.ssBtn:IsShown() then x = x + 36 end
    fsBtn:ClearAllPoints()
    fsBtn:SetPoint("TOPLEFT", W.statusRow, "TOPLEFT", x, -1)

    fsBtn.icon:SetDesaturated(not has)
    fsBtn.icon:SetAlpha(has and 1 or 0.45)
    fsBtn.count:SetText(bags > 1 and tostring(bags) or "")

    local r = 0
    if W.BestCD and W.GetItemCD then
        local s, d
        s, d, r = W.BestCD(FS_ITEMS, W.GetItemCD)
        r = W.SetStoneCD(fsBtn, s, d, r) or 0
    end
    -- pulses orange-red while there is no Firestone in the bags or equipped
    fsBtn:SetGlow(not has)

    fsBtn.tipTitle = ItemName(equipped or 13699) or "Firestone"
    local tip
    if equipped then
        tip = L("FS_EQUIPPED")
        if bags > 0 then tip = tip .. "\n" .. L("FS_HAVE", bags) end
    elseif bags > 0 then
        tip = L("FS_HAVE", bags)
    else
        tip = L("FS_NONE")
    end
    if type(r) == "number" and r > 0 then tip = tip .. "\n" .. L("HEARTH_CD", W.LongTime(r)) end
    fsBtn.tipText = tip
    fsBtn:Show()
end
W.UpdateFirestone = UpdateFirestone

---------------------------------------------------------------------------
-- Spellstone (6.0.0): icon after the Firestone icon, with a frame alarm.
-- Shown when you know Create Spellstone or carry a Spellstone. While you have
-- none, the icon pulses blue, a blue frame blinks around it and (option) the
-- border of the guide window blinks too. Out of combat only for the window.
---------------------------------------------------------------------------
-- Classic IDs (normal, Greater, Major); unknown IDs are simply skipped
local SP_ITEMS = { 5522, 13602, 13603 }
local SP_SPELLS = { 2362, 17727, 17728 }
local isSP = {}
for _, id in ipairs(SP_ITEMS) do isSP[id] = true end

if W.DEFAULTS and W.DEFAULTS.spellAlarm == nil then W.DEFAULTS.spellAlarm = true end

local spBtn = W.MakeStoneButton("Interface\\Icons\\INV_Misc_Gem_Sapphire_01")
W.spBtn = spBtn
spBtn:Hide()
if spBtn.glowTex then spBtn.glowTex:SetVertexColor(0.3, 0.6, 1) end

-- the frame alarm: a blue square around the icon that blinks
local spFrame = CreateFrame("Frame", nil, spBtn)
spFrame:SetPoint("TOPLEFT", spBtn, "TOPLEFT", -3, 3)
spFrame:SetPoint("BOTTOMRIGHT", spBtn, "BOTTOMRIGHT", 3, -3)
pcall(function() spFrame:SetFrameLevel(spBtn:GetFrameLevel() + 6) end)
local edges = {}
for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
    { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
    local t = spFrame:CreateTexture(nil, "OVERLAY")
    t:SetPoint(p[1], spFrame, p[1], 0, 0)
    t:SetPoint(p[2], spFrame, p[2], 0, 0)
    if p[3] then t:SetWidth(p[3]) end
    if p[4] then t:SetHeight(p[4]) end
    t:SetColorTexture(0.3, 0.6, 1, 1)
    edges[i] = t
end
spFrame:Hide()

local spKnownAt, spKnown = -100, false
local function KnowsSpellstone()
    local now = GetTime and GetTime() or 0
    if now - spKnownAt < 5 then return spKnown end
    spKnownAt = now
    local known = false
    for _, id in ipairs(SP_SPELLS) do
        pcall(function()
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then known = true end
        end)
        if known then break end
    end
    if not known then
        pcall(function()
            local sid = GetSpellInfo and select(7, GetSpellInfo("Create Spellstone"))
            if type(sid) == "number" then known = true end
        end)
    end
    spKnown = known
    return known
end

local function SpellstoneCounts()
    local bags, equipped = 0, nil
    local counts = W.BagCounts and W.BagCounts() or {}
    for _, id in ipairs(SP_ITEMS) do bags = bags + (counts[id] or 0) end
    pcall(function()
        local id = GetInventoryItemID and GetInventoryItemID("player", OFFHAND_SLOT)
        if id and isSP[id] then equipped = id end
    end)
    return bags, equipped
end

local spIconSet = false
local spMissing = false
local function UpdateSpellstone()
    local bags, equipped = SpellstoneCounts()
    local has = bags > 0 or equipped ~= nil
    if not Cfg("showStones") or not (has or KnowsSpellstone()) then
        spBtn:SetGlow(false)
        spFrame:Hide()
        spBtn:Hide()
        spMissing = false
        return
    end
    if not spIconSet then
        local icon = W.ItemIcon(5522) or W.ItemIcon(13602)
        if icon then spBtn.icon:SetTexture(icon) end
        spIconSet = true
    end
    local x = 1
    if W.hsBtn:IsShown() then x = x + 36 end
    if W.ssBtn:IsShown() then x = x + 36 end
    if fsBtn:IsShown() then x = x + 36 end
    spBtn:ClearAllPoints()
    spBtn:SetPoint("TOPLEFT", W.statusRow, "TOPLEFT", x, -1)
    spBtn.icon:SetDesaturated(not has)
    spBtn.icon:SetAlpha(has and 1 or 0.45)
    spBtn.count:SetText(bags > 1 and tostring(bags) or "")
    local r = 0
    if W.BestCD and W.GetItemCD then
        local s, d
        s, d, r = W.BestCD(SP_ITEMS, W.GetItemCD)
        r = W.SetStoneCD(spBtn, s, d, r) or 0
    end
    spMissing = not has
    spBtn:SetGlow(not has)
    if not has then spFrame:Show() else spFrame:Hide() end
    spBtn.tipTitle = ItemName(equipped or 5522) or "Spellstone"
    local tip
    if equipped then
        tip = L("SP_EQUIPPED")
        if bags > 0 then tip = tip .. "\n" .. L("FS_HAVE", bags) end
    elseif bags > 0 then
        tip = L("FS_HAVE", bags) .. "\n" .. L("SP_EQUIP")
    else
        tip = L("SP_NONE")
    end
    if type(r) == "number" and r > 0 then tip = tip .. "\n" .. L("HEARTH_CD", W.LongTime(r)) end
    spBtn.tipText = tip
    spBtn:Show()
end
W.UpdateSpellstone = UpdateSpellstone
W.SpellstoneMissing = function() return spMissing end
W.SpellstoneInBags = function()
    local bags, equipped = SpellstoneCounts()
    return bags > 0 and not equipped
end

-- blink: the frame around the icon, and the guide window border (out of combat)
local blink, blinkOn = 0, false
local function InCombat()
    local c = false
    pcall(function() c = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false end)
    return c and true or false
end
local function Blink(elapsed)
    blink = blink + (elapsed or 0)
    if blink < 0.5 then return end
    blink = 0
    blinkOn = not blinkOn
    if spFrame:IsShown() then
        for _, t in ipairs(edges) do t:SetAlpha(blinkOn and 1 or 0.25) end
    end
    local ui = W.WockyUI
    local alarm = spMissing and Cfg("spellAlarm") and spBtn:IsShown() and not InCombat()
    if alarm then
        pcall(function() ui:SetBackdropBorderColor(0.3, 0.6, 1, blinkOn and 1 or 0.35) end)
        W.spAlarmActive = true
    elseif W.spAlarmActive then
        W.spAlarmActive = false
        -- back to the normal border (theme and accent)
        if W.RestoreBorder then pcall(W.RestoreBorder) elseif W.ApplyAll then pcall(W.ApplyAll) end
    end
end

-- runs before the hearthstone update so the hearthstone icon moves to the right
local prevOnExtras = W.OnExtras
function W.OnExtras()
    pcall(UpdateFirestone)
    pcall(UpdateSpellstone)
    if prevOnExtras then prevOnExtras() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
    knownAt = -100
    spKnownAt = -100
    namesCache = nil
    if W.WockyUI:IsShown() then
        local wasShown, wasSP = fsBtn:IsShown(), spBtn:IsShown()
        pcall(UpdateFirestone)
        pcall(UpdateSpellstone)
        if (wasShown ~= fsBtn:IsShown() or wasSP ~= spBtn:IsShown()) and W.UpdateWockyGuide then pcall(W.UpdateWockyGuide, W.GetViewLevel and W.GetViewLevel()) end
    end
end)

-- keeps count, glow and cooldown current (same pace as the other stone icons)
local ticker = CreateFrame("Frame")
local elapsedSum = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    if W.WockyUI:IsShown() then pcall(Blink, elapsed) end
    elapsedSum = elapsedSum + (elapsed or 0)
    if elapsedSum < 0.5 then return end
    elapsedSum = 0
    if W.WockyUI:IsShown() and W.statusRow:IsShown() then
        local wasShown, wasSP = fsBtn:IsShown(), spBtn:IsShown()
        pcall(UpdateFirestone)
        pcall(UpdateSpellstone)
        if (wasShown ~= fsBtn:IsShown() or wasSP ~= spBtn:IsShown()) and W.hearthBtn and W.hearthBtn:IsShown() then
            -- hearthstone icon moves one slot when the Firestone icon appears or goes away
            if W.OnExtras then pcall(W.OnExtras) end
        end
    end
end)

-- guide reminder: a Spellstone waits in the bags (it works from the off-hand slot)
local prevReminders = W.ExtraReminders
W.ExtraReminders = function(list)
    if prevReminders then pcall(prevReminders, list) end
    pcall(function()
        if Cfg("showStones") and W.SpellstoneInBags() then list[#list + 1] = L("SP_REMIND") end
    end)
end

if W.pageLock then W.AddToggle(W.pageLock, "spellAlarm", "SP_OPT_ALARM") end
