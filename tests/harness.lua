-- Mocked WoW 3.3.5 API for loading Bot Brigade outside the game.
-- Run from the folder holding BotBrigade/ and tests/: lua tests/harness.lua

local now = 1000
function GetTime() return now end

-- Generic frame/texture/fontstring object: remembers scripts, ignores the rest.
local Obj = {}
Obj.__index = function(self, key)
    local v = rawget(Obj, key)
    if v then return v end
    -- Methods are capitalised; plain fields that were never set read as nil.
    if type(key) == "string" and key:match("^%u") then return function() return nil end end
    return nil
end
function Obj.new(kind, name)
    local o = setmetatable({ kind = kind, scripts = {}, shown = false, children = {}, name = name, events = {} }, Obj)
    if name then _G[name] = o end
    return o
end
function Obj:SetScript(k, f) self.scripts[k] = f end
function Obj:GetScript(k) return self.scripts[k] end
function Obj:HookScript(k, f) self.scripts[k] = f end
function Obj:Show() self.shown = true end
function Obj:Hide() self.shown = false end
function Obj:IsShown() return self.shown end
function Obj:SetText(t) self.text = t end
function Obj:GetText() return self.text end
function Obj:GetStringWidth() return #(self.text or "") * 6 end
function Obj:GetHeight() return 12 end
function Obj:GetWidth() return 100 end
function Obj:GetTop() return 300 end
function Obj:GetScale() return 1 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetPoint() return "BOTTOM", nil, "BOTTOM", 0, 170 end
function Obj:GetCenter() return 300, 330 end
function Obj:RegisterEvent(e) self.events[e] = true end
function Obj:CreateTexture() return Obj.new("Texture") end
function Obj:CreateFontString() return Obj.new("FontString") end
function Obj:GetHighlightTexture() return Obj.new("Texture") end
function Obj:GetPushedTexture() return Obj.new("Texture") end
function Obj:GetFrameLevel() return 1 end

local frames = {}
function CreateFrame(kind, name)
    local f = Obj.new(kind, name)
    table.insert(frames, f)
    return f
end

UIParent = Obj.new("Frame", "UIParent")
function UIParent:GetHeight() return 768 end
GameTooltip = Obj.new("GameTooltip", "GameTooltip")
UISpecialFrames = {}
StaticPopupDialogs = {}
CANCEL = "Cancel"
function StaticPopup_Show(name) LAST_POPUP = name end
tinsert = table.insert
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
UNKNOWNOBJECT = "Unknown"
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("CHAT:", m) end }

-- Recorded outbound traffic.
SENT = {}
function SendChatMessage(msg, channel, _, target)
    table.insert(SENT, channel .. (target and (":" .. target) or "") .. " | " .. msg)
end
function SendAddonMessage(prefix, msg, channel, target)
    table.insert(SENT, "ADDON " .. prefix .. " " .. channel .. (target and (":" .. target) or "") .. " | " .. msg:gsub("\t", " <tab> "))
end
FILTERS = {}
function ChatFrame_AddMessageEventFilter(event, fn) FILTERS[event] = fn end
function PlaySound() end
function EasyMenu(menu) LAST_MENU = menu end
function CloseDropDownMenus() end
function GetBindingKey() return nil end
function SetPortraitToTexture() end
function SetPortraitTexture() end
function UnitFactionGroup() return "Alliance" end

-- World state the tests control.
PARTY = {}       -- list of { name, class }
IN_DUNGEON = false
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return #PARTY end
function UnitName(unit)
    if unit == "player" then return "Arden" end
    local i = tonumber((unit or ""):match("^party(%d)$"))
    return i and PARTY[i] and PARTY[i][1] or nil
end
function UnitClass(unit)
    local i = tonumber((unit or ""):match("^party(%d)$"))
    if i and PARTY[i] then return PARTY[i][2], PARTY[i][2] end
    return "Warrior", "WARRIOR"
end
function UnitIsUnit(a, b) return a == b end
function UnitExists(unit) return UnitName(unit) ~= nil end
DEAD = {}
FAR = {}
LEVELS = {}
IN_COMBAT = false
LOOT_METHOD = "group"
function IsPartyLeader() return true end
function GetLootMethod() return LOOT_METHOD end
LOOT_LAG = false -- true: the server hasn't confirmed loot changes yet
LOOT_LOG = {}
function SetLootMethod(m)
    if not LOOT_LAG then LOOT_METHOD = m end
    table.insert(SENT, "LOOT | " .. m)
    table.insert(LOOT_LOG, GetTime())
end
OFFLINE = {}
UNINVITED = {}
function UninviteUnit(name) table.insert(UNINVITED, name) end
function UnitOnTaxi() return false end
function UnitAffectingCombat() return IN_COMBAT end
function UnitLevel(unit) return LEVELS[UnitName(unit) or ""] or 10 end
POWER = {}
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 } }
function UnitPowerMax(unit) local p = POWER[UnitName(unit) or ""]; return p and 100 or 0 end
function UnitPower(unit) local p = POWER[UnitName(unit) or ""]; return p and p[2] or 0 end
function UnitPowerType(unit) local p = POWER[UnitName(unit) or ""]; return 0, p and p[1] or "MANA" end
function InCombatLockdown() return IN_COMBAT end
MAX_PARTY_MEMBERS = 4
for i = 1, 4 do
    local f = Obj.new("Frame", "PartyMemberFrame" .. i); f.shown = true
    local pet = Obj.new("Frame", "PartyMemberFrame" .. i .. "PetFrame"); pet.shown = true
end
function UnitHealth() return 50 end
function UnitHealthMax() return 100 end
function UnitIsDeadOrGhost(unit) return DEAD[UnitName(unit) or ""] or false end
function UnitIsConnected(unit) return not OFFLINE[UnitName(unit) or ""] end
function UnitInRange(unit) return not FAR[UnitName(unit) or ""] end
QUESTS = { { "Elwynn", true }, { "Wolves Across the Border" }, { "Kobold Camp Cleanup" }, { "A Daily Chore", false, false } }
local selected = 0
function GetNumQuestLogEntries() return #QUESTS end
function GetQuestLogTitle(i) local q = QUESTS[i]; if q then return q[1], 5, nil, 0, q[2] end end
function SelectQuestLogEntry(i) selected = i end
function GetQuestLogSelection() return selected end
function GetQuestLogPushable() local q = QUESTS[selected]; return q and not q[2] and q[3] ~= false end
function QuestLogPushQuest() table.insert(SENT, "SHARE | " .. QUESTS[selected][1]) end
function IsInInstance() if IN_DUNGEON then return 1, "party" end return nil, "none" end

-- Load the addon in TOC order.
for _, file in ipairs({ "BotBrigade/Core.lua", "BotBrigade/UI.lua" }) do
    local chunk = assert(loadfile(file))
    chunk("BotBrigade", {})
end

-- Helpers for tests.
function FIRE(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function TICK(seconds)
    local step = 0.05
    local t = 0
    while t < seconds do
        now = now + step
        t = t + step
        for _, f in ipairs(frames) do
            if f.scripts.OnUpdate then f.scripts.OnUpdate(f, step) end
        end
    end
end

function TAKE()
    local out = SENT
    SENT = {}
    return out
end
