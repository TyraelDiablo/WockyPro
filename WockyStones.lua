-- WockyStones: Firestone icon next to the Healthstone and Soulstone icons.
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

-- runs before the hearthstone update so the hearthstone icon moves to the right
local prevOnExtras = W.OnExtras
function W.OnExtras()
    pcall(UpdateFirestone)
    if prevOnExtras then prevOnExtras() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
    knownAt = -100
    namesCache = nil
    if W.WockyUI:IsShown() then
        local wasShown = fsBtn:IsShown()
        pcall(UpdateFirestone)
        if wasShown ~= fsBtn:IsShown() and W.UpdateWockyGuide then pcall(W.UpdateWockyGuide, W.GetViewLevel and W.GetViewLevel()) end
    end
end)

-- keeps count, glow and cooldown current (same pace as the other stone icons)
local ticker = CreateFrame("Frame")
local elapsedSum = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    elapsedSum = elapsedSum + (elapsed or 0)
    if elapsedSum < 0.5 then return end
    elapsedSum = 0
    if W.WockyUI:IsShown() and W.statusRow:IsShown() then
        local wasShown = fsBtn:IsShown()
        pcall(UpdateFirestone)
        if wasShown ~= fsBtn:IsShown() and W.hearthBtn and W.hearthBtn:IsShown() then
            -- hearthstone icon moves one slot when the Firestone icon appears or goes away
            if W.OnExtras then pcall(W.OnExtras) end
        end
    end
end)
