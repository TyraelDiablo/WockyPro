-- WockyGearData: checked gear lists for "Gear by level" (5.3.0)
-- Only items that were checked in WoW: Forever go here. Nothing is guessed:
-- Forever changes items, so lists from other WoW versions are not copied.
--
-- How to fill it: play with "Save good items you can wear" on (settings,
-- Gear tab), then type /wocky items export and copy the text. The lines are
-- already in the format below. Check each item in game, then paste it here.
--
-- ranges["20-29"] = {
--     { id = 1234, lvl = 22, src = "quest", where = "Quest name" },
--     { id = 5678, lvl = 25, src = "dungeon", where = "Wailing Caverns" },
--     -- src: "quest", "dungeon", "craft", "vendor" or "drop"
-- }
-- dungeons["Wailing Caverns"] = { 1234, 5678 }   -- item IDs, English dungeon name
--
-- TODO: no checked Forever items yet. Fill from /wocky items export after testing.
local W = WockyAPI
if not W then return end

W.GEAR_DATA = {
    ranges = {
        ["10-19"] = {},
        ["20-29"] = {},
        ["30-39"] = {},
        ["40-49"] = {},
        ["50-60"] = {}
    },
    dungeons = {}
}
