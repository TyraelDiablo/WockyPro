# WockyPro Changelog

## 5.1.0
- **Group & dungeon window:** `/wocky group`, a right-click on the dungeon line, or the button in the new **Group** tab of the settings. It lists your group with level, zone, healer, Soulstone and who else uses WockyPro. Click a member to pick your healer.
- **Soulstone and Healthstones:** shows who has your Soulstone (and the minutes left after you cast it). In a group the guide window reminds you to Soulstone the healer; in a dungeon it counts your Healthstones against the group size (one per player, they can be traded).
- **Summon helper:** members who are far away or in another zone, with your Soul Shards. Click a name to tell the group whom you summon. A reminder appears when members are in another zone.
- **Dungeon quests:** quests of the dungeons for your level, read from your quest log and the quest recorder (nothing is guessed): ready to turn in, in your log or not taken. Click to share a quest with the group, or to point the arrow to the quest giver.
- **Dungeon runs:** time, XP, kills, money, Soul Shards and deaths for each dungeon visit, in the chat when you leave (a ghost run back does not end it). `/wocky runs` lists the last runs.
- **Ready check list:** on a ready check, when you enter a dungeon, or with `/wocky ready`: Healthstone, Soulstone on the healer, demon and shards.
- **Soulstone announce** (off by default): tells the group whom you gave your Soulstone.
- `/wocky report` has a Group line; the settings window is a little wider for the new tab

## 5.0.0
- **Warlock tools:** a new window for your demons, Soul Shards, trainer and money. Open it with `/wocky lock`, by right-clicking the shard count in the guide window, or with the button in the new **Warlock** tab of the settings.
- **Demon advisor:** shows which of your demons fits right now: Voidwalker when you play alone, Felhunter when your target casts spells, Imp in a group, Succubus for fast kills if you pick "fast" in the settings. When another demon would fit better, a short reminder says so (out of combat only; turn it off in the settings).
- **Soul Shards:** set a "too many shards" limit (default 20). Above it the guide window shows a reminder and you get one chat message. A soul bag reminder appears when 8 or more shards sit in your normal bags.
- **Trainer planner:** open your warlock trainer once and WockyPro saves its spell list with levels and costs. The window then shows what you can learn now, the next level with new spells, and what it costs. Nothing is guessed: the data comes from the game's own trainer window.
- **Money goals:** savings bars for the level 40 and level 60 mounts plus the training costs on the way, also on the money tooltip. Set the mount prices in the settings (Warlock tab); the defaults (100 and 1000 gold) are only placeholders.
- `/wocky report` lists the Warlock tools status
- The settings window is a little wider for the new tab

## 4.2.1
- **Fix: Lua error in combat.** In combat the game hides item and spell cooldowns from addons ("secret values"). The Healthstone, Soulstone and Hearthstone icons tried to count them every half second, so the error repeated and WoW offered to turn addons off. WockyPro now does no cooldown math in combat: the number keeps ticking from the last known time and the dark swipe still shows. Other addons were not the cause.
- **Firestone icon:** a new icon next to the Healthstone and Soulstone icons, in the same style, with count, tooltip and cooldown. It shows when you know Create Firestone or carry a Firestone (in the bags or in your off-hand). It uses the same "Healthstone / Soulstone icons" setting.
- **Pulsing icons:** the Healthstone icon pulses green and the Firestone icon pulses orange-red while you have none, the same way the Soulstone icon already does.
- Fix: the navigation arrow no longer throws a Lua error on maps where the game gives no map size.

## 4.2.0
- **Route plan:** `/wocky plan` opens a small window for the road ahead.
- **Hearthstone:** shows where you are bound, where the route wants your hearthstone for your level, and the next level where it changes. With an English game client it also says when your hearthstone is somewhere else.
- **Next levels:** the coming hubs and zones of your route. Click a line to point the arrow there. Each line says if you already have the flight path there. WockyPro notes flight paths when you open a flight map or find a new one; nothing is guessed.
- **Open steps in this zone:** guide lines of the zone you stand in that are not ticked yet. Click one to tick it.
- New reminders in the guide window: hearthstone not where the route wants it, and steps left open on earlier levels of this zone (levels where you already ticked something). Turn them off in the settings (Map & Talents tab).
- `/wocky report` shows a short route plan line (hearthstone, open steps here, flight points seen)

## 4.1.0
- **Setup wizard:** on the first start a small wizard asks for your language, route, talent spec, what the window shows and which automatic helpers you want. `/wocky setup` (or the button in the settings, Display tab) opens it again.
- **Guide in every language:** the route texts are now translated into all 12 languages of the addon (English, Turkish, German, Spanish for Spain and Mexico, French, Italian, Portuguese, Russian, Korean, Simplified and Traditional Chinese). NPC and place names stay in English so the map links keep working. A line without a translation shows in English. You can turn it off in the settings (General tab) to read the English text. Translators: see `WockyGuide_enUS.lua`.
- **Update notice:** after WockyPro is updated, a small window opens next to the guide on your first login and lists what is new, in your language. The close button only closes the notice; the guide keeps working. Addons cannot go online, so WockyPro learns about a newer version from group and guild members who use it, and shows "New version" in the same window. Turn it off in the settings (Display tab); `/wocky update` shows it again.
- `/wocky here` without a note only prints your spot; add a note (`/wocky here <note>`) to save it
- Build import: a build with more than 51 talent points now says so, `wp1:` in small letters works too, and the talent header shows the spec of an imported build
- `/wocky build group` / `solo` tells you when an imported build is active and how to remove it
- Clicking the dungeon line for Blackrock Depths and Blackrock Spire opens the Burning Steppes map
- Undead level 21 points to Tarren Mill; the settings window is a little taller so the new options fit

## 4.0.0
- **Quest recorder (first step of the quest engine):** while you play, WockyPro saves the ID, name and level of every quest you accept or turn in, plus the giver and turn-in NPC (name, NPC ID, zone and coordinates). Type `/wocky quests` to see everything as text you can copy, including draft route steps in the order you played them. `/wocky quests off` / `on` turns it off or on (also in the settings, Map & Talents tab), `/wocky quests clear` removes the list. This is how the real Forever quest data will be collected.
- **Quest steps:** a route level can now list steps tied to real quest IDs: accept, complete, turn in, plus go to / learn / fly. Quest steps tick themselves from your quest log, show live objectives (for example "8/10 Hillsbrad Farmer") and say when a quest is ready to turn in. Go / learn / fly steps are ticked with a click. The quest data itself comes later, after it is collected with the recorder.
- The arrow points to the next open quest step when the level has steps
- `/wocky report` shows the quest recorder status
- The settings window is a little taller so every option fits
- **Route fix:** the Hillsbrad and Arathi steps of the Undead, Orc and Troll routes use the full zone names (Hillsbrad Foothills, Arathi Highlands). The arrow, the step tooltip and `/wocky here` now show the right zone name.
- A mistyped `/wocky` command now says "Unknown command" and points to `/wocky help` instead of hiding the guide. `/wocky show` and `/wocky hide` work too.
- `/wocky route` and `/wocky spec` without a choice list their options
- `/wocky build import` without text opens the build window
- The talent map title shows the spec of an imported build (it showed your own spec before)

## 3.3.0
- **Talent map:** click the small book next to the talent header (or type `/wocky talentmap`) to see the planned talent points as a map of the three trees. Use `<` and `>` to see the plan for any level. Gold = planned, green = you already have it, gray = not in the plan.
- **Second build for every spec:** a group / dungeon build for Affliction, Demonology and Destruction. Turn it on in the settings (Map & Talents tab) or with `/wocky build group` (`/wocky build solo` switches back). The group order is a first version and will be checked in game.
- **Build sharing:** `/wocky build` opens a window with your talents as a short text (`WP1:...`) to copy and share. Paste a friend's text and click Import, and the guide follows that build. "Remove import" goes back to the guide's own build. The game's own loadout text is shown too when the client offers it.
- The talent header shows which build the guide follows (Group or Imported)
- `/wocky report` lists the active build and your build text
- Talent names in other client languages are matched correctly for imported builds

## 3.2.0
- **`/wocky here`:** prints your zone, subzone, map ID and coordinates, plus a line in the guide's own format. Compares your spot with the guide target of the level you are looking at.
- `/wocky here <note>` saves the spot with a short note (up to 20 spots per account), `/wocky here clear` removes them
- **`/wocky report`:** opens a window with everything a bug report needs: WockyPro and client version, language, race, class, level, route, talents, professions, changed settings, other loaded addons, the last WockyPro Lua error and your saved spots. Select all, Ctrl+C, paste.
- WockyPro remembers its last Lua error across `/reload` (also reads BugSack / BugGrabber if you use it)
- `/wocky help` lists the new commands

## 3.1.1
- Clicking the dungeon line opens the world map again (the click did nothing in 3.1.0)
- Opening your warlock trainer no longer ticks class quest steps such as "Talk to your warlock trainer for the Voidwalker quest"
- Kills to level counts only the XP from kills; quest and exploration XP no longer change the estimate
- The Hearthstone icon tooltip shows the item name in your game language
- `/wocky news` also lists the changes of the previous version

## 3.1.0
- **Clickable guide:** click a talent row to open the talent window, click a profession to open that profession's window (if the game does not allow it, your spellbook opens instead). Clicking Herbalism shows the best zone on the map.
- **Clickable labels:** quest header opens the quest log, profession header your professions, talent header and spec line the talent window, your name the character window, Soul Shards and money your bags, the dungeon line the map. Hover any of them to see what a click does.
- **Mouse wheel** over the window flips through the levels
- **Steps tick themselves:** setting your hearthstone, opening your warlock trainer or finding a new flight path checks the matching route step (can be turned off)
- Left-click the arrow to see its target on the world map
- **Navigation arrow:** points to the current step's target, or to any NPC or place name you click. Shows the distance in yards, says "Travel to ..." when the target is in another zone, and turns green when you face the right way. Drag to move, right-click to clear the target or hide it, size in the settings, `/wocky arrow` to toggle.
- **Kills to level:** estimate on the XP line, based on your recent kills
- **Dungeon suggestions:** dungeons for the level you are looking at (hover for level ranges and locations)
- **Route progress:** percentage of route steps you have checked
- **Hearthstone icon:** bind location and cooldown
- **Bags button:** shows your free bag slots (soul bags not counted)
- New reminders when your bags or quest log are almost full
- **Vendor helper:** sells gray items and repairs automatically (both can be turned off in the settings)
- **Upgrade score on item tooltips:** compares an item with what you wear, using leveling Warlock stat weights. Only shown for gear a Warlock can use.
- **Key bindings:** show/hide the guide, next and previous level, show/hide the arrow (Key Bindings > AddOns)
- **Addon compartment and Blizzard settings:** WockyPro can be opened from the addon compartment and from the game's options menu
- `/wocky help` lists all commands, `/wocky news` shows what is new; a chat notice appears after an update
- Version number now comes from the release tag

## 3.0.0
- Leveling routes for every Warlock race in WoW: Forever, picked automatically from your race:
  - Undead: Deathknell, Tirisfal Glades, Silverpine Forest
  - Orc and Troll: Valley of Trials, Durotar, The Barrens
  - Human: Northshire, Elwynn Forest, Westfall
  - Gnome: Coldridge Valley, Dun Morogh, Loch Modan
- New Alliance route from level 15 to 60
- Class quests (Voidwalker, Succubus, Felhunter, Felsteed) point to your own race's warlock trainers: Undercity, Orgrimmar, Stormwind or Ironforge
- A race without its own route uses its faction's route
- Choose another route in the settings or with `/wocky route`
- Step checkmarks are now saved per character (they used to be shared)
- Map support for the new zones

## 2.3.0
- Profession guide reads the real recipe colors (orange, yellow, green, gray) from the game when you open a profession window
- Suggests the best recipe that still gives skill points, and switches as soon as you learn a better one
- Lowest suggested color (orange, yellow or green) can be set per profession; yellow is the default
- Shows how many of the suggested item you can craft with your bags
- Herbalism and Mining: herbs and ore colored for your skill, with zones
- Mining also suggests smelting when it gives more points
- Skinning: beast level range that still gives points
- New Professions tab in the settings
- Notice when you learn new recipes and the window should be reopened

## 2.2.2
- Character line shows your full WoW: Forever name (first name and surname)
- Your race is shown after your name
- Character info split into two lines so it no longer runs under the buttons

## 2.2.1
- Minimap button now sits on the minimap border like other addon buttons, with the standard size
- Minimap button follows the minimap when it is resized
- New addon icon, shown in the AddOns list, on the minimap button and in its tooltip

## 2.2.0
- Talent builds rewritten with the WoW: Forever talent names
- Talent advice reads your real talents and suggests the next best point, plus the two after it
- Shows unspent talent points
- Spec on the character line now matches the talent guide
- Profession section shows 2 primary professions plus Cooking, First Aid and Fishing, with roadmaps
- Healthstone and Soulstone icons; the Soulstone icon shows its cooldown and glows when it is ready and you have none
- Money display with gold, silver and copper icons, plus this session's gain or loss
- `/wocky talents` and `/wocky prof` for bug reports

## 2.1.0
- XP bar with rested XP, XP per hour and time to level
- Warlock reminders: Healthstone, Soulstone, low Soul Shards, no demon, new spells at your trainer
- Collapse button to shrink the window
- New display settings for the XP bar, reminders and the low-shard warning

## 2.0.0
- Settings window: scale, opacity, text size, accent color, window lock, combat hiding, which sections to show, map and TomTom options, reset options
- Minimap button (left-click: guide, right-click: settings, drag: move)
- Interface in 12 languages: English, Turkish, German, Spanish (EU and MX), French, Italian, Portuguese (BR), Russian, Korean, Chinese (Simplified and Traditional)
- Window position is saved

## 1.9.0
- New talent section with a suggested talent for each level
- `/wocky spec` to choose the build

## 1.8.0
- NPC and place names are clickable inside the steps and open the world map

## 1.7.0
- Window height follows its content
- Checkboxes for the profession tips

## 1.6.x
- Soul Shard counter and bag button
- Clickable checkboxes for each step
- Character line with name, level and spec
- Spec detection for the WoW: Forever talent tree
- Now button and the `/wocky` command

## 1.5.1
- First working version: level 1 to 60 guide window with Prev and Next level buttons
