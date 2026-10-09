-- Bot Brigade: call your alts, pick a mode, and let the team play with you.
-- Core.lua owns saved data, sending (chat, server commands, Dungeon Clear addon
-- messages), party tracking, modes, and reading replies. UI.lua listens with
-- BotBrigade:On(...) and calls the public functions below.

local W = {}
BotBrigade = W
W.version = "1.0.0"

------------------------------------------------------------------------
-- Static data
------------------------------------------------------------------------

-- Class names as the server writes them in "Bot roster:" replies.
local ROSTER_CLASS = {
    Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER", Rogue = "ROGUE",
    Priest = "PRIEST", Shaman = "SHAMAN", Mage = "MAGE", Warlock = "WARLOCK",
    Druid = "DRUID", DeathKnight = "DEATHKNIGHT", ["Death Knight"] = "DEATHKNIGHT",
}

-- Role of each talent tree, in tree order. Druid feral is decided by build name.
W.TAB_ROLES = {
    WARRIOR = { "dps", "dps", "tank" },
    PALADIN = { "heal", "tank", "dps" },
    HUNTER = { "dps", "dps", "dps" },
    ROGUE = { "dps", "dps", "dps" },
    PRIEST = { "heal", "heal", "dps" },
    DEATHKNIGHT = { "tank", "dps", "dps" },
    SHAMAN = { "dps", "dps", "heal" },
    MAGE = { "dps", "dps", "dps" },
    WARLOCK = { "dps", "dps", "dps" },
    DRUID = { "dps", "feral", "heal" },
}

W.ROLE_NAME = { tank = "Tank", heal = "Healer", dps = "Damage" }

-- The six modes on the ring. Top half: out in the world. Bottom half: dungeons,
-- where the tank bot leads (needs the Dungeon Clear server module).
-- pull = Dungeon Clear's wire token for the tank's pull style.
W.MODES = {
    { key = "team", label = "Call Team", group = "world", icon = "Interface\\Icons\\Ability_Warrior_RallyingCry",
      tip = "Brings your chosen characters into your group, next to you. Right-click to choose who comes." },
    { key = "quest", label = "Follow Me", group = "world", icon = "Interface\\Icons\\INV_Misc_Map02",
      tip = "Your team follows you and fights whatever you fight. Use this for questing." },
    { key = "stop", label = "Wait Here", group = "world", icon = "Interface\\Icons\\Spell_Nature_TimeStop",
      tip = "Your team stops and waits where it is. Also stops a dungeon run." },
    { key = "pullback", label = "Careful", group = "dungeon", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", pull = "on",
      tip = "The tank leads the dungeon and pulls every group of enemies back to the team. Slowest, safest." },
    { key = "smart", label = "Smart", group = "dungeon", icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman", pull = "dynamic",
      tip = "The tank leads the dungeon. It charges small groups and pulls big ones back. Recommended." },
    { key = "leeroy", label = "Leeroy", group = "dungeon", icon = "Interface\\Icons\\Ability_Warrior_Charge", pull = "off",
      tip = "The tank leads the dungeon and charges straight into every group. Fastest, riskiest." },
}
W.MODE_BY_KEY = {}
for i, m in ipairs(W.MODES) do
    m.index = i
    W.MODE_BY_KEY[m.key] = m
end

local MAX_PARTY_OTHERS = 4
local SEND_GAP = 0.35
local MAX_QUEUE = 40
local JOIN_WINDOW = 90
local SPEC_WAIT = 5
local DC_REPLY_WAIT = 5

------------------------------------------------------------------------
-- Tiny event bus for the UI
------------------------------------------------------------------------

local listeners = {}

function W:On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function W:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

-- kind: "good" | "warn" | "info"
function W:Status(text, kind)
    self.lastStatus = text
    self:Fire("STATUS", text, kind or "info")
end

------------------------------------------------------------------------
-- Saved data
------------------------------------------------------------------------

local DEFAULTS = {
    scale = 1,
    shown = true,
    locked = false,
    hideChatter = true,
    sound = true,
    autoShare = true,  -- share every quest you accept, so your team can earn it too
    autoGather = true, -- bring teammates back when they fall far behind (travel, getting stuck)
    autoTrain = true,  -- teammates learn new skills when they level up
    autoLoot = true,   -- Free for All while questing (all loot is yours), Need Before Greed in dungeons
    mode = "quest",
    alts = {},   -- [name] = class token, from the server's roster of your own characters
    team = {},   -- [name] = true for the characters Call Team brings (chosen in the team picker)
    roles = {},  -- [name] = "tank" | "heal" | "dps", the role last requested
}

function W:InitDB()
    if type(BotBrigadeDB) ~= "table" then BotBrigadeDB = {} end
    for k, v in pairs(DEFAULTS) do
        if BotBrigadeDB[k] == nil then
            BotBrigadeDB[k] = (type(v) == "table") and {} or v
        end
    end
    if not self.MODE_BY_KEY[BotBrigadeDB.mode] or BotBrigadeDB.mode == "team" then
        BotBrigadeDB.mode = "quest"
    end
    self.db = BotBrigadeDB
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function Clean(text)
    text = text or ""
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
W.Clean = Clean

local function ShortName(name)
    if not name then return nil end
    return (name:match("^([^%-]+)") or name)
end

local function Split(text, sep)
    local parts, start = {}, 1
    while true do
        local pos = text:find(sep, start, true)
        if not pos then
            table.insert(parts, text:sub(start))
            return parts
        end
        table.insert(parts, text:sub(start, pos - 1))
        start = pos + #sep
    end
end

function W:InDungeon()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid")
end

------------------------------------------------------------------------
-- Timers and the send queue
------------------------------------------------------------------------

local queue = {}
local timers = {}
local nextSend = 0
W.recentOut = {}

function W:After(delay, fn)
    table.insert(timers, { at = GetTime() + delay, fn = fn })
end

function W:GroupChannel()
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

local function Enqueue(kind, msg, target)
    if #queue >= MAX_QUEUE then return false end
    if msg:find("[\r\n]") or #msg > 250 then return false end
    table.insert(queue, { kind = kind, msg = msg, target = target })
    return true
end

local function Transmit(item)
    if item.kind == "party" then
        local channel = W:GroupChannel()
        if channel then
            W.recentOut[item.msg:lower()] = GetTime()
            SendChatMessage(item.msg, channel)
        end
    elseif item.kind == "whisper" then
        W.recentOut[item.msg:lower()] = GetTime()
        SendChatMessage(item.msg, "WHISPER", nil, item.target)
    elseif item.kind == "server" then
        SendChatMessage(item.msg, "SAY")
    elseif item.kind == "dc" then
        -- Dungeon Clear's server hook reads "DC\tCMD\t<sub>[\t<param>]" addon messages.
        local channel = W:GroupChannel()
        if channel then
            SendAddonMessage("DC", item.msg, channel)
        else
            SendAddonMessage("DC", item.msg, "WHISPER", UnitName("player"))
        end
    end
end

function W:SendParty(msg) return Enqueue("party", msg) end
function W:SendWhisper(name, msg) return Enqueue("whisper", msg, name) end
function W:SendServer(msg) return Enqueue("server", msg) end
function W:SendDC(sub, param)
    local payload = "CMD\t" .. sub
    if param and param ~= "" then payload = payload .. "\t" .. param end
    return Enqueue("dc", payload)
end

function W:ClearQueue()
    for i = #queue, 1, -1 do queue[i] = nil end
end

local pump = CreateFrame("Frame")
pump:SetScript("OnUpdate", function()
    local t = GetTime()
    if queue[1] and t >= nextSend then
        Transmit(table.remove(queue, 1))
        nextSend = t + SEND_GAP
    end
    for i = #timers, 1, -1 do
        local timer = timers[i]
        if t >= timer.at then
            table.remove(timers, i)
            timer.fn()
        end
    end
end)

------------------------------------------------------------------------
-- Party
------------------------------------------------------------------------

-- Party members other than you, in party order.
function W:Members()
    local list = {}
    local raid = GetNumRaidMembers()
    if raid > 0 then
        for i = 1, raid do
            local unit = "raid" .. i
            if not UnitIsUnit(unit, "player") then
                local _, class = UnitClass(unit)
                table.insert(list, { unit = unit, name = ShortName(UnitName(unit)), class = class })
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local _, class = UnitClass(unit)
            table.insert(list, { unit = unit, name = ShortName(UnitName(unit)), class = class })
        end
    end
    return list
end

function W:Member(name)
    for _, m in ipairs(self:Members()) do
        if m.name == name then return m end
    end
end

function W:FreeSlots()
    if GetNumRaidMembers() > 0 then return 0 end
    return MAX_PARTY_OTHERS - GetNumPartyMembers()
end

W.bots = {}  -- names seen acting as bots this session

function W:IsBot(name)
    name = ShortName(name)
    return name and (self.bots[name] or self.db.alts[name]) and true or false
end

------------------------------------------------------------------------
-- Calling your team (your own characters as bots)
------------------------------------------------------------------------

local pendingAdds = {}  -- [name] = time asked
local rosterAskedAt = 0
local afterRoster = nil -- "call" or "pick": what to do once the server lists your characters

function W:RequestRoster()
    rosterAskedAt = GetTime()
    self:SendServer(".playerbots bot list")
end

function W:RosterAskedRecently()
    return GetTime() - rosterAskedAt < 8
end

-- Your other characters on this account, sorted by name.
function W:AltNames()
    local names = {}
    local me = UnitName("player")
    for name in pairs(self.db.alts) do
        if name ~= me then table.insert(names, name) end
    end
    table.sort(names)
    return names
end

-- The characters chosen in the team picker, sorted by name.
function W:ChosenNames()
    local names = {}
    for _, name in ipairs(self:AltNames()) do
        if self.db.team[name] then table.insert(names, name) end
    end
    return names
end

function W:SetChosen(name, chosen)
    self.db.team[name] = chosen and true or nil
end

local function LookUpCharacters(nextStep)
    afterRoster = nextStep
    W:RequestRoster()
    W:Status("Looking for your characters...", "info")
    W:After(8, function()
        if afterRoster then
            afterRoster = nil
            W:Status("The realm didn't list your characters. Bots may be off for this account.", "warn")
        end
    end)
end

-- Opens the picker (UI listens for PICK). Looks up your characters first if needed.
function W:PickTeam()
    if #self:AltNames() == 0 then
        LookUpCharacters("pick")
        return
    end
    self:Fire("PICK")
end

local function Bring(list)
    local free = W:FreeSlots()
    local names, left = {}, {}
    for _, name in ipairs(list) do
        if not W:Member(name) then
            if #names < free then
                table.insert(names, name)
                pendingAdds[name] = GetTime()
            else
                table.insert(left, name)
            end
        end
    end
    if #names == 0 then
        W:Status(free <= 0 and "Your group is full." or "Your team is already here.", "info")
        return
    end
    W:SendServer(".playerbots bot add " .. table.concat(names, ","))
    local text = "Calling " .. table.concat(names, ", ") .. "..."
    if #left > 0 then text = text .. " No room for " .. table.concat(left, ", ") .. "." end
    W:Status(text, "info")
end

function W:CallTeam()
    local alts = self:AltNames()
    if #alts == 0 then
        LookUpCharacters("call")
        return
    end
    local chosen = self:ChosenNames()
    if #chosen > 0 then
        Bring(chosen)
    elseif #alts <= self:FreeSlots() then
        Bring(alts)
    else
        -- More characters than places and no choice saved yet: ask instead of guessing.
        self:Status("Choose who to bring, then press Call them now.", "info")
        self:Fire("PICK")
    end
end

function W:SendHome(name)
    self:SendServer(".playerbots bot remove " .. name)
    self:Status(name .. " logged out.", "info")
end

function W:Summon(name)
    self:SendWhisper(name, "summon")
    self:SendWhisper(name, "follow")
end

-- "maintenance" asks a bot to train spells, repair, and restock when the realm allows it.
function W:PowerUp(name)
    self:SendWhisper(name, "maintenance")
    self:Status(name .. " is training and repairing.", "info")
end

------------------------------------------------------------------------
-- Quest sharing: bots only earn a quest they have. When you turn a quest in,
-- every teammate holding it completes it with you (server setting SyncQuestWithPlayer).
------------------------------------------------------------------------

local SHARE_GAP = 1.5
local shareAllPending = false

local function HasTeam()
    for _, m in ipairs(W:Members()) do
        if W:IsBot(m.name) then return true end
    end
    return false
end

-- Shares one quest log entry if the game allows it. Returns true when sent.
local function ShareEntry(index)
    if not W:GroupChannel() then return false end
    local previous = GetQuestLogSelection()
    SelectQuestLogEntry(index)
    local ok = GetQuestLogPushable()
    if ok then QuestLogPushQuest() end
    SelectQuestLogEntry(previous or 0)
    return ok and true or false
end

-- Shares everything in your quest log, one quest at a time.
function W:ShareAllQuests(quiet)
    if not self:GroupChannel() then
        if not quiet then self:Status("Call your team first, then share your quests.", "warn") end
        return
    end
    local indexes = {}
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, _, isHeader = GetQuestLogTitle(i)
        if not isHeader then table.insert(indexes, i) end
    end
    local shared = 0
    for n, index in ipairs(indexes) do
        self:After((n - 1) * SHARE_GAP, function()
            if ShareEntry(index) then shared = shared + 1 end
        end)
    end
    self:After(#indexes * SHARE_GAP + 0.5, function()
        if shared > 0 then
            self:Status("Shared " .. shared .. " quests with your team.", "good")
        elseif not quiet then
            self:Status("None of your quests can be shared right now.", "info")
        end
    end)
end

local function OnQuestAccepted(index)
    if not (W.db.autoShare and HasTeam()) then return end
    W:After(0.5, function()
        local title = GetQuestLogTitle(index)
        if ShareEntry(index) and title then
            W:Status("Shared \"" .. title .. "\" with your team.", "good")
        end
    end)
end

-- Newly arrived teammates get your current quests once everyone has joined.
local function ShareAfterJoin()
    if not W.db.autoShare or shareAllPending then return end
    shareAllPending = true
    W:After(6, function()
        shareAllPending = false
        W:ShareAllQuests(true)
    end)
end

------------------------------------------------------------------------
-- Keeping the team together, reviving, and training on level-up
------------------------------------------------------------------------

local FAR_WAIT = 10       -- seconds a teammate may be out of range before being brought over
local FAR_WAIT_TRAVEL = 3 -- right after a loading screen or a flight
local SUMMON_COOLDOWN = 30
local farSince, lastSummon, knownLevel = {}, {}, {}
local travelUntil = 0
local reviveAfterCombat = false
local trainAfterCombat = {}

local function BotMembers()
    local list = {}
    for _, m in ipairs(W:Members()) do
        if m.name and W:IsBot(m.name) then table.insert(list, m) end
    end
    return list
end

-- Called after a loading screen or a flight: check sooner for a short while.
function W:JustTraveled()
    travelUntil = GetTime() + 20
    for k in pairs(farSince) do farSince[k] = nil end
end

local function GatherCheck()
    if not (W.db and W.db.autoGather and W:GroupChannel()) then return end
    if W.db.mode == "stop" or W.dc.enabled then return end
    if UnitOnTaxi("player") or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then return end
    local now = GetTime()
    local wait = (now < travelUntil) and FAR_WAIT_TRAVEL or FAR_WAIT
    local brought = {}
    for _, m in ipairs(BotMembers()) do
        local unit = m.unit
        if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and not UnitInRange(unit) then
            farSince[m.name] = farSince[m.name] or now
            if now - farSince[m.name] >= wait and now - (lastSummon[m.name] or 0) >= SUMMON_COOLDOWN then
                lastSummon[m.name] = now
                farSince[m.name] = nil
                W:Summon(m.name)
                table.insert(brought, m.name)
            end
        else
            farSince[m.name] = nil
        end
    end
    if #brought > 0 then
        W:Status("Brought " .. table.concat(brought, ", ") .. " back to you.", "info")
    end
end

function W:DeadTeammates()
    local dead = {}
    for _, m in ipairs(BotMembers()) do
        if UnitIsDeadOrGhost(m.unit) then table.insert(dead, m.name) end
    end
    return dead
end

-- Summoning a dead bot revives it when nobody is fighting (server default).
function W:ReviveTeam()
    local dead = self:DeadTeammates()
    if #dead == 0 then
        self:Status("Nobody needs reviving.", "info")
        return
    end
    if UnitAffectingCombat("player") then
        reviveAfterCombat = true
        self:Status("Your team will be revived when this fight ends.", "info")
        return
    end
    reviveAfterCombat = false
    for _, name in ipairs(dead) do
        lastSummon[name] = GetTime()
        self:Summon(name)
    end
    self:Status("Reviving " .. table.concat(dead, ", ") .. ".", "good")
end

local function Train(name, level)
    if UnitAffectingCombat("player") then
        trainAfterCombat[name] = level
        return
    end
    W:SendWhisper(name, "maintenance")
    W:Status(name .. " reached level " .. level .. " and learned new skills.", "good")
end

local function SeedLevels()
    for _, m in ipairs(W:Members()) do
        if m.name then knownLevel[m.name] = UnitLevel(m.unit) end
    end
end

local function OnUnitLevel(unit)
    if not (unit and unit:match("^party%d$") or unit and unit:match("^raid%d+$")) then return end
    local name = UnitName(unit)
    if not (name and W:IsBot(name)) then return end
    local level = UnitLevel(unit)
    local before = knownLevel[name]
    knownLevel[name] = level
    if W.db.autoTrain and before and level and level > before then
        W:After(3, function() Train(name, level) end)
    end
end

local function OnCombatEnded()
    if reviveAfterCombat then
        W:After(2, function() W:ReviveTeam() end)
    end
    for name, level in pairs(trainAfterCombat) do
        trainAfterCombat[name] = nil
        if W:Member(name) then Train(name, level) end
    end
end

local gatherTicker = CreateFrame("Frame")
local gatherSince, wasOnTaxi = 0, false
gatherTicker:SetScript("OnUpdate", function(_, elapsed)
    gatherSince = gatherSince + elapsed
    if gatherSince < 1 then return end
    gatherSince = 0
    local onTaxi = UnitOnTaxi("player") and true or false
    if wasOnTaxi and not onTaxi then W:JustTraveled() end
    wasOnTaxi = onTaxi
    GatherCheck()
end)

------------------------------------------------------------------------
-- Roles (talent builds the server offers)
------------------------------------------------------------------------

local specRequests = {}  -- [name] = { role, class, specs = {} }

function W:RolesFor(class)
    local tabs = self.TAB_ROLES[class]
    local set = {}
    if not tabs then return set end
    for _, role in ipairs(tabs) do
        if role == "feral" then
            set.tank, set.dps = true, true
        else
            set[role] = true
        end
    end
    return set
end

local function BuildRole(class, spec)
    local counts = { spec.a, spec.b, spec.c }
    local best, bestCount, tie = nil, -1, false
    for i = 1, 3 do
        if counts[i] > bestCount then
            best, bestCount, tie = i, counts[i], false
        elseif counts[i] == bestCount then
            tie = true
        end
    end
    if tie or not best then return nil end
    local role = W.TAB_ROLES[class][best]
    if role == "feral" then
        local lower = spec.name:lower()
        if lower:find("bear") or lower:find("tank") then return "tank" end
        if lower:find("cat") or lower:find("dps") then return "dps" end
        return nil
    end
    return role
end

function W:SetRole(name, role)
    local member = self:Member(name)
    if not member or not member.class then return end
    if not self:RolesFor(member.class)[role] then return end
    specRequests[name] = { role = role, class = member.class, specs = {} }
    self:SendWhisper(name, "talents spec list")
    self:Status("Changing " .. name .. " to " .. self.ROLE_NAME[role] .. "...", "info")
    self:After(SPEC_WAIT, function() self:FinishRole(name) end)
end

function W:FinishRole(name)
    local req = specRequests[name]
    if not req then return end
    specRequests[name] = nil
    local pick
    for _, spec in ipairs(req.specs) do
        if BuildRole(req.class, spec) == req.role then
            pick = spec
            break
        end
    end
    if not pick then
        self:Status(name .. " has no " .. self.ROLE_NAME[req.role] .. " build on this realm.", "warn")
        return
    end
    self:SendWhisper(name, "talents spec " .. pick.name)
    self.db.roles[name] = req.role
    self:Status(name .. " is now your " .. self.ROLE_NAME[req.role] .. ".", "good")
    self:Fire("GROUP")
end

-- True when the whisper was part of a build list (kept out of chat).
local function TakeSpecLine(name, msg)
    local req = specRequests[name]
    if not req then return false end
    local _, specName, a, b, c = msg:match("^(%d+)%. (.-) %((%d+)%-(%d+)%-(%d+)%)$")
    if specName then
        table.insert(req.specs, { name = specName, a = tonumber(a), b = tonumber(b), c = tonumber(c) })
        return true
    end
    if msg:match("^Total %d+ specs? found") then
        W:FinishRole(name)
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Dungeon Clear (separate server module: the tank bot leads the dungeon)
------------------------------------------------------------------------

-- supported: nil = not checked yet, true = the server answered, false = no answer.
W.dc = { supported = nil, enabled = false, state = nil, detail = nil, nextBoss = nil,
         pull = nil, done = 0, total = 0 }
local dcAskedAt = nil
local pendingBosses = nil

local function DcHeard()
    W.dc.supported = true
    dcAskedAt = nil
end

local function OnDcMessage(message)
    local parts = Split(message, "\t")
    local kind = parts[1]
    local dc = W.dc
    if kind == "STATUS" then
        DcHeard()
        dc.enabled = parts[2] == "1"
        dc.nextBoss = (parts[4] and parts[4] ~= "None") and parts[4] or nil
        dc.state = parts[7]
        dc.detail = (parts[8] and parts[8] ~= "") and parts[8] or nil
        dc.pull = tonumber(parts[9] or "")
        W:Fire("DUNGEON")
    elseif kind == "BOSS_START" then
        DcHeard()
        pendingBosses = { done = 0, total = 0 }
    elseif kind == "BOSS" and pendingBosses then
        pendingBosses.total = pendingBosses.total + 1
        local status = parts[5]
        if status == "dead" or status == "skipped" then
            pendingBosses.done = pendingBosses.done + 1
        end
    elseif kind == "BOSS_END" and pendingBosses then
        if pendingBosses.total > 0 then
            dc.done, dc.total = pendingBosses.done, pendingBosses.total
        end
        pendingBosses = nil
        W:Fire("DUNGEON")
    elseif kind == "ERROR" then
        DcHeard()
        local text = parts[2] or ""
        if text:find("No tank bot") then
            W:Status("Dungeon modes need a tank in your team. Right-click a teammate to make them a Tank.", "warn")
        elseif text:find("disabled") then
            W.dc.supported = false
            W:Status("The tank-led dungeon mode is turned off on this realm.", "warn")
        else
            W:Status(text, "warn")
        end
        W:Fire("DUNGEON")
    end
end

local function CheckDcAnswered()
    if dcAskedAt and GetTime() - dcAskedAt >= DC_REPLY_WAIT - 0.1 then
        dcAskedAt = nil
        if W.dc.supported ~= true then
            W.dc.supported = false
            W:Status("This realm doesn't have the tank-led dungeon module. Use Follow Me instead.", "warn")
            W:Fire("DUNGEON")
        end
    end
end

local function AskDc()
    if W.dc.supported ~= true then
        dcAskedAt = GetTime()
        W:After(DC_REPLY_WAIT, CheckDcAnswered)
    end
end

function W:DungeonProgress()
    local dc = self.dc
    if dc.total > 0 then
        return "Boss " .. math.min(dc.done + 1, dc.total) .. " of " .. dc.total
    end
    return dc.nextBoss and ("Next: " .. dc.nextBoss) or nil
end

------------------------------------------------------------------------
-- Modes (what the ring buttons do)
------------------------------------------------------------------------

-- Loot rules. Bots loot any item their own quests ask for, but with quest sync they
-- finish on your turn-in without it. Free for All stops bots looting entirely
-- (server default), so quest items and drops are yours; Need Before Greed in
-- dungeons lets teammates roll on gear they can use.
local LOOT_NAMES = { freeforall = "Free for All", needbeforegreed = "Need Before Greed" }

function W:ApplyLootRule()
    if not (self.db and self.db.autoLoot) then return end
    if GetNumRaidMembers() > 0 or GetNumPartyMembers() == 0 or not IsPartyLeader() then return end
    local wanted = self:InDungeon() and "needbeforegreed" or "freeforall"
    if GetLootMethod() == wanted then return end
    SetLootMethod(wanted)
    if wanted == "freeforall" then
        self:Status("Loot set to Free for All: quest items and drops are all yours.", "info")
    else
        self:Status("Loot set to Need Before Greed: your team can roll on gear in here.", "info")
    end
end

function W:Mode()
    return self.db.mode
end

local function SetSavedMode(key)
    W.db.mode = key
    W:Fire("MODE", key)
end

function W:Choose(key)
    local mode = self.MODE_BY_KEY[key]
    if not mode then return end

    if key == "team" then
        self:CallTeam()
        return
    end

    if not self:GroupChannel() then
        self:Status("Call your team first: press Call Team.", "warn")
        return
    end

    if key == "quest" then
        if self.dc.enabled then
            self:SendDC("off")
            self.dc.enabled = false
        end
        self:SendParty("follow")
        SetSavedMode("quest")
        self:Status("Your team is following you.", "good")
    elseif key == "stop" then
        if self.dc.enabled then
            self:SendDC("off")
            self.dc.enabled = false
        end
        self:SendParty("stay")
        SetSavedMode("stop")
        self:Status("Your team is waiting here.", "info")
    else
        if not self:InDungeon() then
            SetSavedMode(key)
            self:SendParty("follow")
            self:Status(mode.label .. " is set for the next dungeon. Until then your team follows you.", "info")
            return
        end
        if self.dc.supported == false then
            self:Status("This realm doesn't have the tank-led dungeon module. Use Follow Me instead.", "warn")
            return
        end
        self:SendDC("pull", mode.pull)
        if not self.dc.enabled then
            self:SendDC("on")
        elseif self.dc.state == "paused" then
            self:SendDC("pause", "resume")
        end
        self:SendDC("status", "addon")
        self:SendDC("bosses", "addon")
        AskDc()
        SetSavedMode(key)
        self:Status(mode.label .. ": the tank is leading the dungeon.", "good")
    end
end

-- Entering a dungeon with a dungeon mode already chosen starts it once the team is inside.
local function ResumeDungeonMode()
    local mode = W.MODE_BY_KEY[W.db.mode]
    if mode and mode.pull and W:InDungeon() and W:GroupChannel() then
        W.dc.enabled, W.dc.done, W.dc.total = false, 0, 0
        W:Choose(mode.key)
    end
end

------------------------------------------------------------------------
-- Watching the party change
------------------------------------------------------------------------

local lastMembers = {}

local function SeedMembers()
    lastMembers = {}
    for _, m in ipairs(W:Members()) do
        if m.name then lastMembers[m.name] = true end
    end
end

local function OnJoined(member)
    local asked = pendingAdds[member.name]
    if not (asked and GetTime() - asked < JOIN_WINDOW) then return end
    pendingAdds[member.name] = nil
    W.bots[member.name] = true
    W:Status(member.name .. " joined.", "good")
    W:Fire("JOINED", member.name)
    ShareAfterJoin()
    -- Bring them over, then fall in behind you.
    W:After(1.5, function()
        if W:Member(member.name) then W:Summon(member.name) end
    end)
end

function W:OnGroupChanged()
    local current = {}
    for _, m in ipairs(self:Members()) do
        if m.name and m.name ~= UNKNOWNOBJECT then
            current[m.name] = true
            if not lastMembers[m.name] then OnJoined(m) end
        end
    end
    lastMembers = current
    self:After(1, function() self:ApplyLootRule() end)
    for _, m in ipairs(self:Members()) do
        if m.name and not knownLevel[m.name] then knownLevel[m.name] = UnitLevel(m.unit) end
    end
    self:Fire("GROUP")
end

------------------------------------------------------------------------
-- Reading what the server and bots say
------------------------------------------------------------------------

local function ParseRoster(msg)
    local body = msg:match("^Bot roster: (.*)$")
    if not body then return false end
    local found = 0
    for entry in (body .. ", "):gmatch("(.-), ") do
        local _, name, className = entry:match("^([%+%-])(%S+) (.+)$")
        local class = className and ROSTER_CLASS[className]
        if name and class then
            W.db.alts[name] = class
            found = found + 1
        end
    end
    W:Fire("ROSTER")
    if afterRoster then
        local nextStep = afterRoster
        afterRoster = nil
        if found == 0 then
            W:Status("No other characters found on this account.", "warn")
        elseif nextStep == "pick" then
            W:Fire("PICK")
        else
            W:CallTeam()
        end
    end
    return true
end

local SYSTEM_REPLIES = {
    { "^add: (%S+) %- ok", function(n) return n .. " is logging in.", "good" end },
    { "^add: (%S+) %- player already logged in", function(n) return n .. " is already online.", "info" end },
    { "^add: (%S+) %- character not found", function(n) return "Couldn't find " .. n .. ".", "warn" end },
    { "^add: (%S+) %- you can only add bots", function(n) return n .. " isn't on this account.", "warn" end },
    { "^remove: (%S+) %- ok", function(n) return n .. " logged out.", "info" end },
    { "^Failure: You have added too many bots", function() return "This realm's limit on bots has been reached.", "warn" end },
    { "^bot system is disabled", function() return "Bots are turned off on this realm.", "warn" end },
}

local function OnSystem(msg)
    if ParseRoster(msg) then return end
    for _, rule in ipairs(SYSTEM_REPLIES) do
        local a = msg:match(rule[1])
        if a then
            W:Status(rule[2](a))
            return
        end
    end
end

local function OnBotSpeech(sender, msg)
    sender = ShortName(sender)
    if not sender or sender == UnitName("player") then return end
    W:Fire("SAY", sender, Clean(msg))
end

local function OnWhisper(msg, sender)
    sender = ShortName(sender)
    if TakeSpecLine(sender, msg) then return end
    if W:Member(sender) or W:IsBot(sender) then
        if W:Member(sender) then W.bots[sender] = true end
        OnBotSpeech(sender, msg)
    end
end

------------------------------------------------------------------------
-- Keeping the chat window calm (option, on by default)
------------------------------------------------------------------------

local function SentRecently(msg)
    local t = W.recentOut[(msg or ""):lower()]
    return t and GetTime() - t < 4
end

local function FilterWhisper(_, _, msg, sender)
    sender = ShortName(sender)
    if specRequests[sender] and (msg:match("^%d+%. .- %(%d+%-%d+%-%d+%)$") or msg:match("^Total %d+ specs? found")) then
        return true
    end
    return W.db.hideChatter and W:IsBot(sender) and W:Member(sender) ~= nil
end

local function FilterWhisperInform(_, _, msg, target)
    return W.db.hideChatter and SentRecently(msg) and W:IsBot(target)
end

local function FilterGroup(_, _, msg, sender)
    sender = ShortName(sender)
    if sender == UnitName("player") then
        return W.db.hideChatter and SentRecently(msg)
    end
    return W.db.hideChatter and W:IsBot(sender)
end

local function FilterSystem(_, _, msg)
    if msg:match("^Bot roster: ") then return W:RosterAskedRecently() end
    if not W.db.hideChatter then return false end
    for _, rule in ipairs(SYSTEM_REPLIES) do
        if msg:match(rule[1]) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PARTY_MEMBERS_CHANGED",
    "RAID_ROSTER_UPDATE", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON", "QUEST_ACCEPTED", "UNIT_LEVEL", "PLAYER_REGEN_ENABLED", "PARTY_LEADER_CHANGED" }) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 == "BotBrigade" then
            W:InitDB()
            ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", FilterWhisper)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", FilterWhisperInform)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", FilterGroup)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", FilterGroup)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", FilterGroup)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", FilterGroup)
            ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", FilterSystem)
            W:Fire("READY")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        SeedMembers()
        SeedLevels()
        W:JustTraveled()
        W.dc.enabled, W.dc.state, W.dc.done, W.dc.total, W.dc.nextBoss = false, nil, 0, 0, nil
        W:Fire("GROUP")
        W:Fire("DUNGEON")
        -- A chosen dungeon mode picks up once the loading screen is over.
        W:After(4, ResumeDungeonMode)
        W:After(2, function() W:ApplyLootRule() end)
    elseif event == "PLAYER_LEAVING_WORLD" then
        W:ClearQueue()
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        W:OnGroupChanged()
    elseif event == "CHAT_MSG_WHISPER" then
        OnWhisper(arg1, arg2)
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystem(arg1)
    elseif event == "PARTY_LEADER_CHANGED" then
        W:After(1, function() W:ApplyLootRule() end)
    elseif event == "UNIT_LEVEL" then
        OnUnitLevel(arg1)
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnded()
    elseif event == "QUEST_ACCEPTED" then
        OnQuestAccepted(arg1)
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == "DC" then OnDcMessage(arg2 or "") end
    else
        if W:IsBot(arg2) then OnBotSpeech(arg2, arg1) end
    end
end)

------------------------------------------------------------------------
-- Key bindings and slash command
------------------------------------------------------------------------

BINDING_HEADER_BOTBRIGADE = "Bot Brigade"
BINDING_NAME_BOTBRIGADE_RING = "Open or close the ring"
BINDING_NAME_BOTBRIGADE_TEAM = "Call Team"
BINDING_NAME_BOTBRIGADE_PICK = "Choose my team"
BINDING_NAME_BOTBRIGADE_QUEST = "Follow Me"
BINDING_NAME_BOTBRIGADE_SMART = "Smart (dungeon)"
BINDING_NAME_BOTBRIGADE_LEEROY = "Leeroy (dungeon)"
BINDING_NAME_BOTBRIGADE_PULLBACK = "Careful (dungeon)"
BINDING_NAME_BOTBRIGADE_STOP = "Wait Here"

function BotBrigade_Choose(key) W:Choose(key) end
function BotBrigade_Ring() W:Fire("RING") end
function BotBrigade_Pick() W:PickTeam() end

SLASH_BOTBRIGADE1 = "/brigade"
SLASH_BOTBRIGADE2 = "/bb"
SlashCmdList.BOTBRIGADE = function(input)
    local cmd, rest = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        W:Fire("TOGGLE")
    elseif W.MODE_BY_KEY[cmd] then
        W:Choose(cmd)
    elseif cmd == "scale" and tonumber(rest) then
        W:Fire("SCALE", tonumber(rest))
    elseif cmd == "reset" then
        W:Fire("RESET")
    elseif cmd == "revive" then
        W:ReviveTeam()
    elseif cmd == "share" then
        W:ShareAllQuests()
    elseif cmd == "pick" or cmd == "choose" then
        W:PickTeam()
    elseif cmd == "find" then
        W:RequestRoster()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Bot Brigade|r: /bb shows or hides it. /bb team, quest, smart, leeroy, pullback, stop. /bb scale 1.2. /bb reset.")
    end
end
