# WockyPro Changelog

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
