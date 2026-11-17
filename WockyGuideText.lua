-- WockyGuideText: shows the route guide text in the player's language.
-- The translations live in WockyGuide_<locale>.lua. Each line is found by a short
-- code made from the English text, so a changed English line simply shows in
-- English until it is translated again. NPC and place names stay in English.
local W = WockyAPI
if not W then return end

local L = W.L

if W.DEFAULTS.guideTranslate == nil then W.DEFAULTS.guideTranslate = true end

-- class hub texts the Alliance routes put into "{CLASSHUB}" (see WithHub in WockyDatabase.lua)
local HUBS = { "the Slaughtered Lamb in Stormwind", "the Forlorn Cavern in Ironforge" }

local function Hash(s)
    local x = 5381
    for i = 1, #s do
        x = (x * 33 + string.byte(s, i)) % 4294967296
    end
    return string.format("%08x", x)
end
W.GuideHash = Hash

local cache, cacheLang = {}, nil

local function Lookup(tbl, text)
    local t = tbl[Hash(text)]
    if t then return t end
    for _, hub in ipairs(HUBS) do
        local s = string.find(text, hub, 1, true)
        if s then
            local template = string.sub(text, 1, s - 1) .. "{CLASSHUB}" .. string.sub(text, s + #hub)
            local tt = tbl[Hash(template)]
            if tt then
                local hubText = tbl[Hash(hub)] or hub
                local a, b = string.find(tt, "{CLASSHUB}", 1, true)
                if a then return string.sub(tt, 1, a - 1) .. hubText .. string.sub(tt, b + 1) end
            end
        end
    end
    return nil
end

-- line: one guide line, with or without the "[ ] " prefix
function W.TranslateLine(line)
    if type(line) ~= "string" or line == "" then return line end
    if not W.Cfg("guideTranslate") then return line end
    local lang = (W.ActiveLang and W.ActiveLang()) or "enUS"
    if lang == "enUS" then return line end
    local tbl = WockyGuideText and WockyGuideText[lang]
    if type(tbl) ~= "table" then return line end
    if cacheLang ~= lang then
        cache, cacheLang = {}, lang
    end
    local hit = cache[line]
    if hit ~= nil then return hit or line end
    local prefix, body = string.match(line, "^(%[ %] )(.*)$")
    if not prefix then prefix, body = "", line end
    local t = Lookup(tbl, body)
    local out = t and (prefix .. t) or false
    cache[line] = out
    return out or line
end

-- how many guide lines of a route are translated, for /wocky report
function W.GuideCoverage(lang)
    local tbl = WockyGuideText and WockyGuideText[lang or ((W.ActiveLang and W.ActiveLang()) or "enUS")]
    local route = WockyGuideDB and W.RouteKey and WockyGuideDB[W.RouteKey()]
    if not route then return 0, 0 end
    local total, done = 0, 0
    for lvl = 1, W.MAX_LEVEL or 60 do
        local e = route["L" .. lvl]
        for line in string.gmatch((e and e.quest) or "", "[^\n]+") do
            total = total + 1
            local body = string.match(line, "^%[ %] (.*)$") or line
            if type(tbl) == "table" and Lookup(tbl, body) then done = done + 1 end
        end
    end
    return done, total
end

W.AddToggle(W.pageGeneral, "guideTranslate", "GUIDE_TRANSLATE")
