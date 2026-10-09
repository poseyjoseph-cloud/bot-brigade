-- Bot Brigade behaviour checks against the mocked API. Run: lua tests/run.lua
dofile("tests/harness.lua")

local W = BotBrigade
local failures = 0
local function check(cond, label)
    if cond then
        print("PASS  " .. label)
    else
        failures = failures + 1
        print("FAIL  " .. label)
    end
end
local function has(list, pattern)
    for _, line in ipairs(list) do
        if line:find(pattern, 1, true) then return true end
    end
    return false
end
local function show(list) for _, l in ipairs(list) do print("      sent: " .. l) end end

-- Load and enter the world: nothing should be sent.
FIRE("ADDON_LOADED", "BotBrigade")
FIRE("PLAYER_ENTERING_WORLD")
TICK(6)
check(#TAKE() == 0, "sends nothing on load or world entry")
check(BotBrigadeFrame:IsShown(), "medallion is shown")
check(not W:IsOpen(), "medallion starts closed")
check(not PartyMemberFrame1:IsShown() and not PartyMemberFrame4PetFrame:IsShown(), "the game's party frames are hidden")
PartyMemberFrame1:Show()
check(not PartyMemberFrame1:IsShown(), "and they stay hidden")

-- My Team with no known alts: asks the roster, then calls them when it arrives.
W:Choose("team")
TICK(1)
local out = TAKE()
check(has(out, "SAY | .playerbots bot list"), "first My Team asks the server for the roster")
FIRE("CHAT_MSG_SYSTEM", "Bot roster: -Dalia Druid, -Brielle Priest, -Corwin Paladin, -Eamon Warrior")
check(FILTERS.CHAT_MSG_SYSTEM(nil, nil, "Bot roster: -Dalia Druid") == true, "roster reply is hidden from chat")
TICK(1)
out = TAKE()
check(has(out, "SAY | .playerbots bot add Brielle,Corwin,Dalia,Eamon"), "then calls all four alts in one command")
show(out)

-- They join: each is summoned and set to follow.
PARTY = { { "Brielle", "PRIEST" }, { "Corwin", "PALADIN" }, { "Dalia", "DRUID" }, { "Eamon", "WARRIOR" } }
FIRE("PARTY_MEMBERS_CHANGED")
TICK(5)
out = TAKE()
check(has(out, "WHISPER:Eamon | summon") and has(out, "WHISPER:Eamon | follow"), "joined alts are summoned and follow")
check(has(out, "WHISPER:Brielle | summon"), "every joined alt is summoned")

-- Calling again with a full party does nothing.
W:Choose("team")
TICK(1)
check(#TAKE() == 0, "My Team with everyone present sends nothing")

-- Quest: party follow.
W:Choose("quest")
TICK(1)
out = TAKE()
check(has(out, "PARTY | follow"), "Quest tells the party to follow")
check(W:Mode() == "quest", "mode saved as quest")
check(FILTERS.CHAT_MSG_PARTY(nil, nil, "follow", "Arden") == true, "our own 'follow' is hidden from party chat")

-- A dungeon mode outside a dungeon is remembered, team follows meanwhile.
W:Choose("leeroy")
TICK(1)
out = TAKE()
check(not has(out, "ADDON DC"), "Leeroy outside a dungeon sends nothing to Dungeon Clear")
check(W:Mode() == "leeroy", "Leeroy remembered for the next dungeon")

-- Entering a dungeon starts the remembered mode.
IN_DUNGEON = true
FIRE("PLAYER_ENTERING_WORLD")
TICK(6)
out = TAKE()
check(has(out, "ADDON DC PARTY | CMD <tab> pull <tab> off"), "entering a dungeon sets Leeroy pull (off)")
check(has(out, "ADDON DC PARTY | CMD <tab> on"), "and starts the tank-led run")
show(out)

-- No answer from the server: honest message, marked unsupported.
TICK(6)
check(W.dc.supported == false, "silence marks Dungeon Clear as unavailable")
check((W.lastStatus or ""):find("doesn't have the tank%-led dungeon module") ~= nil, "and says so plainly")
TAKE()

-- With the module present: status arrives and the strip shows progress.
W.dc.supported = nil
W:Choose("smart")
TICK(1)
out = TAKE()
check(has(out, "pull <tab> dynamic"), "Smart Pull sends pull dynamic")
FIRE("CHAT_MSG_ADDON", "DC", "STATUS\t1\t123\tPrince Keleseth\t\t0\tmoving\tHeading to Prince Keleseth.\t2\t1", "PARTY", "Eamon")
FIRE("CHAT_MSG_ADDON", "DC", "BOSS_START", "PARTY", "Eamon")
FIRE("CHAT_MSG_ADDON", "DC", "BOSS\t1\t0\tPrince Keleseth\tdead", "PARTY", "Eamon")
FIRE("CHAT_MSG_ADDON", "DC", "BOSS\t2\t1\tSkarvald\talive", "PARTY", "Eamon")
FIRE("CHAT_MSG_ADDON", "DC", "BOSS\t3\t2\tIngvar\talive", "PARTY", "Eamon")
FIRE("CHAT_MSG_ADDON", "DC", "BOSS_END", "PARTY", "Eamon")
TICK(6)
check(W.dc.supported == true, "a STATUS reply confirms Dungeon Clear")
check(W:DungeonProgress() == "Boss 2 of 3", "boss progress reads Boss 2 of 3")

-- Switching to Pull Back while running only changes the pull style.
W:Choose("pullback")
TICK(1)
out = TAKE()
check(has(out, "pull <tab> on") and not has(out, "CMD <tab> on\n"), "Pull Back sends pull on")
local startedAgain = false
for _, l in ipairs(out) do if l:match("| CMD <tab> on$") then startedAgain = true end end
check(not startedAgain, "running run is not restarted")

-- Stop ends the run and holds.
W:Choose("stop")
TICK(1)
out = TAKE()
check(has(out, "CMD <tab> off") and has(out, "PARTY | stay"), "Stop ends the run and the team holds")

-- No tank: clear guidance.
FIRE("CHAT_MSG_ADDON", "DC", "ERROR\tNo tank bot found in your group.", "PARTY", "Arden")
check((W.lastStatus or ""):find("need a tank") ~= nil, "missing tank explained")

-- Roles: build list is read and the matching build applied.
W:SetRole("Eamon", "tank")
TICK(1)
TAKE()
FIRE("CHAT_MSG_WHISPER", "1. arms pve (51-5-15)", "Eamon")
FIRE("CHAT_MSG_WHISPER", "2. prot pve (5-5-61)", "Eamon")
FIRE("CHAT_MSG_WHISPER", "Total 2 specs found", "Eamon")
TICK(1)
out = TAKE()
check(has(out, "WHISPER:Eamon | talents spec prot pve"), "Make Tank picks the protection build")

-- Ring: opens, number key picks, closes.
BotBrigade_Ring()
check(W:IsOpen(), "medallion opens")
BotBrigadeFrame.scripts.OnKeyDown(BotBrigadeFrame, "2")
TICK(1)
out = TAKE()
check(not W:IsOpen(), "medallion closes after a choice")
check(has(out, "PARTY | follow"), "key 2 while open chooses Follow Me")

-- Injection guard.
check(W:SendParty("follow\nbad") == false, "multi-line messages are refused")

-- More characters than places: Call Team asks instead of guessing.
PARTY = {}
FIRE("PARTY_MEMBERS_CHANGED")
TICK(1)
TAKE()
FIRE("CHAT_MSG_SYSTEM", "Bot roster: -Alpha Mage, -Bravo Rogue, -Dalia Druid, -Brielle Priest, -Corwin Paladin, -Eamon Warrior")
W.db.team = {}
LAST_MENU = nil
W:Choose("team")
TICK(1)
check(#TAKE() == 0 and LAST_MENU and LAST_MENU[1].text == "Choose your team", "six characters, none chosen: the picker opens")
-- Tick Eamon and Alpha in the picker, then Call them now.
for _, item in ipairs(LAST_MENU) do
    if item.text:find("Eamon") or item.text:find("Alpha") then item.func() end
end
local callNow
for _, item in ipairs(LAST_MENU) do if item.text == "Call them now" then callNow = item end end
callNow.func()
TICK(1)
out = TAKE()
check(has(out, "SAY | .playerbots bot add Alpha,Eamon"), "Call them now brings only the ticked characters")
-- Later, plain Call Team brings the same chosen pair.
W:Choose("team")
TICK(1)
check(has(TAKE(), "SAY | .playerbots bot add Alpha,Eamon"), "Call Team remembers the chosen team")

-- Quest sharing: accepting a quest shares it; joining teammates get the whole log.
PARTY = { { "Alpha", "MAGE" }, { "Eamon", "WARRIOR" } }
FIRE("PARTY_MEMBERS_CHANGED")
TICK(9)
out = TAKE()
check(has(out, "SHARE | Wolves Across the Border") and has(out, "SHARE | Kobold Camp Cleanup"),
    "teammates who join are given your current quests")
FIRE("QUEST_ACCEPTED", 2)
TICK(1)
check(has(TAKE(), "SHARE | Wolves Across the Border"), "an accepted quest is shared with the team")
W:ShareAllQuests()
TICK(8)
out = TAKE()
check(has(out, "SHARE | Wolves Across the Border") and has(out, "SHARE | Kobold Camp Cleanup")
    and not has(out, "SHARE | Elwynn") and not has(out, "SHARE | A Daily Chore"),
    "share all skips headers and quests that can't be shared")
W.db.autoShare = false
FIRE("QUEST_ACCEPTED", 3)
TICK(1)
check(#TAKE() == 0, "auto-share can be turned off")
W.db.autoShare = true

-- Keeping the team together: a teammate far away for 10 seconds is brought over.
W:Choose("quest")
TICK(1)
TAKE()
FAR.Eamon = true
TICK(5)
check(not has(TAKE(), "WHISPER:Eamon | summon"), "a teammate briefly out of range is left alone")
TICK(7)
check(has(TAKE(), "WHISPER:Eamon | summon"), "a teammate far behind for 10 seconds is brought back")
FAR.Eamon = nil
-- Wait Here: nobody is pulled over.
W:Choose("stop")
TICK(1)
TAKE()
FAR.Alpha = true
TICK(15)
check(not has(TAKE(), "summon"), "Wait Here never pulls teammates over")
FAR.Alpha = nil
W:Choose("quest")
TICK(1)
TAKE()

-- Revive: out of combat it summons the dead; in combat it waits for the fight to end.
DEAD.Alpha = true
IN_COMBAT = true
W:ReviveTeam()
TICK(1)
check(not has(TAKE(), "summon"), "revive waits during combat")
IN_COMBAT = false
FIRE("PLAYER_REGEN_ENABLED")
TICK(4)
check(has(TAKE(), "WHISPER:Alpha | summon"), "revive happens when the fight ends")
DEAD.Alpha = nil

-- Level-up: the teammate learns new skills.
LEVELS.Eamon = 11
FIRE("UNIT_LEVEL", "party2")
TICK(4)
out = TAKE()
check(has(out, "WHISPER:Eamon | maintenance"), "a teammate who levels up learns new skills")
FIRE("UNIT_LEVEL", "party2")
TICK(4)
check(not has(TAKE(), "maintenance"), "no repeat training without a new level")

-- Loot rules: Free for All in the world, Need Before Greed in a dungeon.
IN_DUNGEON = false
LOOT_METHOD = "group"
FIRE("PLAYER_ENTERING_WORLD")
TICK(5)
check(LOOT_METHOD == "freeforall", "questing in the world sets Free for All")
IN_DUNGEON = true
FIRE("PLAYER_ENTERING_WORLD")
TICK(5)
check(LOOT_METHOD == "needbeforegreed", "entering a dungeon sets Need Before Greed")
TAKE()
FIRE("PLAYER_ENTERING_WORLD")
TICK(5)
check(not has(TAKE(), "LOOT |"), "loot rule is not re-sent when already right")
W.db.autoLoot = false
IN_DUNGEON = false
FIRE("PLAYER_ENTERING_WORLD")
TICK(5)
check(LOOT_METHOD == "needbeforegreed", "turning the option off leaves loot alone")
W.db.autoLoot = true

-- Regroup: everyone is teleported to you; key 7 in the open medallion does it too.
PARTY = { { "Alpha", "MAGE" }, { "Eamon", "WARRIOR" }, { "Randa", "PRIEST" } }
FIRE("PARTY_MEMBERS_CHANGED")
TICK(9)
W:Choose("quest")
TICK(1)
TAKE()
BotBrigade_Ring()
BotBrigadeFrame.scripts.OnKeyDown(BotBrigadeFrame, "7")
TICK(1)
out = TAKE()
check(has(out, "PARTY | summon") and has(out, "PARTY | follow"), "Regroup (key 7) summons everyone and they follow")
check(not W:IsOpen(), "the medallion closes after Regroup")

-- Dismiss asks first, then logs out your characters and sends other bots away.
LAST_POPUP = nil
BotBrigade_Ring()
BotBrigadeFrame.scripts.OnKeyDown(BotBrigadeFrame, "8")
TICK(1)
check(LAST_POPUP == "BOTBRIGADE_DISMISS" and #TAKE() == 0, "Dismiss asks for confirmation before doing anything")
StaticPopupDialogs.BOTBRIGADE_DISMISS.OnAccept()
TICK(1)
out = TAKE()
check(has(out, "SAY | .playerbots bot remove Alpha,Eamon"), "your own characters are logged out")
check(has(out, "PARTY | leave"), "other bots are asked to leave the group")

-- Power bars: mana and rage teammates update without errors.
POWER.Alpha = { "MANA", 40 }
POWER.Eamon = { "RAGE", 10 }
local ok = pcall(TICK, 1)
check(ok, "mana and rage bars update without errors")

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
