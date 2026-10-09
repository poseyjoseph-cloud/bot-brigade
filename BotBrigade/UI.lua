-- Bot Brigade UI: one round medallion. Closed, it shows the banner, your four
-- teammates around it, and the current mode underneath. Clicking the banner
-- opens the same medallion outward to show the six modes. Real game icons,
-- game fonts, gold trim.

local W = BotBrigade
local MEDIA = "Interface\\AddOns\\BotBrigade\\Media\\"

local GOLD = { 1, 0.82, 0 }
local STATUS_COLORS = {
    good = { 0.5, 1, 0.5 },
    warn = { 1, 0.65, 0.3 },
    info = { 1, 1, 1 },
}

-- Geometry (UI units, measured from the medallion's center).
local DISC_CLOSED = 200
local DISC_OPEN = 410
local CREST = 58
local TEAM_RADIUS = 52
local TEAM_SIZE = 36
local TEAM_ANGLES = { 315, 45, 225, 135 }        -- top-left, top-right, bottom-left, bottom-right
local MODE_RADIUS = 150
local MODE_SIZE = 56
local MODE_ANGLES = { -52, 0, 52, 232, 180, 128 } -- world on top, dungeon on the bottom

------------------------------------------------------------------------
-- Small building blocks
------------------------------------------------------------------------

local function Size(f, w, h)
    f:SetWidth(w)
    f:SetHeight(h or w)
end

local function Polar(radius, degrees)
    local a = math.rad(degrees)
    return radius * math.sin(a), radius * math.cos(a)
end

local function PlayIf(sound)
    if W.db and W.db.sound then PlaySound(sound) end
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function FactionBanner()
    return (UnitFactionGroup("player") == "Horde") and "Interface\\Icons\\INV_BannerPVP_01"
        or "Interface\\Icons\\INV_BannerPVP_02"
end

local function Tooltip(owner, title, lines, binding)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    for _, line in ipairs(lines or {}) do
        GameTooltip:AddLine(line, GOLD[1], GOLD[2], GOLD[3], true)
    end
    if binding then
        local key = GetBindingKey(binding)
        if key then GameTooltip:AddLine("Key: " .. key, 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

-- A round picture in a gold ring. The art circle is 80% of the ring so the
-- ring's inner edge covers the art's rim.
local function RoundFrame(parent, size)
    local b = CreateFrame("Button", nil, parent)
    Size(b, size)
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetVertexColor(0, 0, 0, 1)
    Size(back, size * 0.8)
    back:SetPoint("CENTER")
    local art = b:CreateTexture(nil, "ARTWORK")
    Size(art, size * 0.8)
    art:SetPoint("CENTER")
    b.art = art
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(MEDIA .. "RoundFrame")
    ring:SetAllPoints()
    b.ring = ring
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    local hl = b:GetHighlightTexture()
    hl:ClearAllPoints()
    Size(hl, size * 0.8)
    hl:SetPoint("CENTER")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
end

local function Text(parent, template, layer)
    return parent:CreateFontString(nil, layer or "OVERLAY", template)
end

------------------------------------------------------------------------
-- The medallion
------------------------------------------------------------------------

-- The main frame is sized for the open medallion; only its visible parts take
-- the mouse. Clamp insets keep the closed medallion (not the empty space) on screen.
local main = CreateFrame("Frame", "BotBrigadeFrame", UIParent)
Size(main, DISC_OPEN)
main:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 300, 330)
main:SetMovable(true)
main:SetClampedToScreen(true)
do
    local side = (DISC_OPEN - DISC_CLOSED) / 2
    main:SetClampRectInsets(side, -side, -side, side - 48)
end
main:SetFrameStrata("MEDIUM")
main:Hide()

local isOpen = false

local function SavePosition()
    local x, y = main:GetCenter()
    W.db.center = { x, y }
end

local function RestorePosition()
    main:ClearAllPoints()
    local c = W.db.center
    if c then
        main:SetPoint("CENTER", UIParent, "BOTTOMLEFT", c[1], c[2])
    else
        main:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 300, 330)
    end
end

local function StartMove()
    if not W.db.locked then main:StartMoving() end
end
local function StopMove()
    main:StopMovingOrSizing()
    SavePosition()
    RestorePosition()
end

-- Disc: the dark round background. It grows when the medallion opens.
local disc = CreateFrame("Frame", nil, main)
disc:SetPoint("CENTER")
Size(disc, DISC_CLOSED)
disc:EnableMouse(true)
disc:RegisterForDrag("LeftButton")
disc:SetScript("OnDragStart", StartMove)
disc:SetScript("OnDragStop", StopMove)
local discTex = disc:CreateTexture(nil, "BACKGROUND")
discTex:SetTexture(MEDIA .. "RingDisc")
discTex:SetAllPoints()

-- Banner in the middle: opens and closes the medallion.
local crest = RoundFrame(main, CREST)
crest:SetPoint("CENTER")
crest:SetFrameLevel(disc:GetFrameLevel() + 5)
SetPortraitToTexture(crest.art, FactionBanner())
crest:RegisterForDrag("LeftButton")
crest:SetScript("OnDragStart", StartMove)
crest:SetScript("OnDragStop", StopMove)

-- Title, shown above the open medallion.
local title = Text(main, nil)
title:SetFont("Fonts\\MORPHEUS.ttf", 20)
title:SetShadowOffset(1, -1)
title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
title:SetPoint("BOTTOM", disc, "TOP", 0, 2)
title:SetText("Bot Brigade")
title:Hide()

-- Mode plaque under the medallion: current mode and what it's doing.
local plaque = CreateFrame("Frame", nil, main)
Size(plaque, 176, 38)
plaque:SetPoint("TOP", disc, "BOTTOM", 0, -6)
plaque:SetBackdrop({
    bgFile = MEDIA .. "Panel",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
plaque:SetBackdropBorderColor(0.78, 0.63, 0.32)
plaque:EnableMouse(true)
plaque:RegisterForDrag("LeftButton")
plaque:SetScript("OnDragStart", StartMove)
plaque:SetScript("OnDragStop", StopMove)
local modeIcon = plaque:CreateTexture(nil, "ARTWORK")
Size(modeIcon, 24)
modeIcon:SetPoint("LEFT", 8, 0)
local modeLabel = Text(plaque, "GameFontNormal")
modeLabel:SetPoint("TOPLEFT", modeIcon, "TOPRIGHT", 7, 1)
local modeDetail = Text(plaque, "GameFontHighlightSmall")
modeDetail:SetPoint("BOTTOMLEFT", modeIcon, "BOTTOMRIGHT", 7, 0)
modeDetail:SetWidth(134)
modeDetail:SetJustifyH("LEFT")

-- Status message above the medallion; fades after a few seconds.
local toast = Text(main, "GameFontHighlight")
toast:SetWidth(360)
local toastTimer = CreateFrame("Frame", nil, main)
local function PlaceToast()
    toast:ClearAllPoints()
    toast:SetPoint("BOTTOM", disc, "TOP", 0, isOpen and 28 or 8)
end
local function ShowToast(text, kind)
    local c = STATUS_COLORS[kind] or STATUS_COLORS.info
    toast:SetTextColor(c[1], c[2], c[3])
    toast:SetText(text)
    toast:SetAlpha(1)
    PlaceToast()
    toastTimer.left = 7
    toastTimer:SetScript("OnUpdate", function(self, elapsed)
        self.left = self.left - elapsed
        if self.left <= 0 then
            toast:SetAlpha(0)
            self:SetScript("OnUpdate", nil)
        elseif self.left < 1 then
            toast:SetAlpha(self.left)
        end
    end)
end

------------------------------------------------------------------------
-- Teammates around the banner
------------------------------------------------------------------------

local slots = {}
for i = 1, #TEAM_ANGLES do
    local x, y = Polar(TEAM_RADIUS, TEAM_ANGLES[i])
    local s = RoundFrame(main, TEAM_SIZE)
    s:SetPoint("CENTER", main, "CENTER", x, y)
    s:SetFrameLevel(disc:GetFrameLevel() + 5)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", StartMove)
    s:SetScript("OnDragStop", StopMove)
    local outward = (y > 0) and 1 or -1 -- top pair: bar and name above; bottom pair: below

    -- Health bar, then a thin power bar (mana, rage, energy, runic power) just outside it.
    local function Bar(height)
        local b = CreateFrame("StatusBar", nil, s)
        Size(b, 40, height)
        b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        b:SetMinMaxValues(0, 1)
        local back = b:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetTexture(0, 0, 0, 0.85)
        return b
    end
    local bar = Bar(4)
    bar:SetPoint("CENTER", s, "CENTER", 0, outward * (TEAM_SIZE / 2 + 4))
    s.bar = bar
    local power = Bar(3)
    power:SetPoint("CENTER", bar, "CENTER", 0, outward * 4.5)
    power:Hide()
    s.power = power

    local name = Text(s, "GameFontNormalSmall")
    name:SetPoint("CENTER", bar, "CENTER", 0, outward * 12)
    s.name = name

    local plus = Text(s, "GameFontDisableLarge")
    plus:SetPoint("CENTER", 0, 1)
    plus:SetText("+")
    s.plus = plus

    -- Speech bubble, styled like a game tooltip, beside the medallion.
    local bubble = CreateFrame("Frame", nil, main)
    bubble:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bubble:SetBackdropColor(0, 0, 0, 0.9)
    bubble:SetBackdropBorderColor(0.5, 0.55, 0.6)
    bubble:SetFrameStrata("HIGH")
    bubble:Hide()
    local said = Text(bubble, "GameFontHighlightSmall")
    said:SetPoint("TOPLEFT", 8, -7)
    said:SetJustifyH("LEFT")
    bubble.text = said
    s.bubble = bubble
    s.offsetY = y
    s.onLeft = x < 0

    slots[i] = s
end

------------------------------------------------------------------------
-- Revive button: appears on the medallion's right edge when a teammate is dead
------------------------------------------------------------------------

local revive = RoundFrame(main, 42)
revive:SetPoint("CENTER", main, "CENTER", DISC_CLOSED / 2 - 4, 0)
revive:SetFrameLevel(disc:GetFrameLevel() + 8)
SetPortraitToTexture(revive.art, "Interface\\Icons\\Spell_Holy_Resurrection")
local reviveGlow = revive:CreateTexture(nil, "BACKGROUND")
reviveGlow:SetTexture(MEDIA .. "RoundGlow")
reviveGlow:SetBlendMode("ADD")
Size(reviveGlow, 84)
reviveGlow:SetPoint("CENTER")
local reviveLabel = Text(revive, "GameFontNormalSmall")
reviveLabel:SetPoint("TOP", revive, "BOTTOM", 0, -1)
reviveLabel:SetText("Revive")
revive:Hide()
revive:SetScript("OnClick", function()
    W:ReviveTeam()
    PlayIf("igMainMenuOptionCheckBoxOn")
end)
revive:SetScript("OnEnter", function(self)
    Tooltip(self, "Revive team", { "Brings your fallen teammates back to life, next to you.",
        "During a fight, it waits until the fight ends." })
end)
revive:SetScript("OnLeave", HideTooltip)
local pulse = 0
revive:SetScript("OnUpdate", function(_, elapsed)
    pulse = pulse + elapsed
    reviveGlow:SetAlpha(0.55 + 0.45 * math.sin(pulse * 4))
end)

local function RefreshRevive()
    if #W:DeadTeammates() > 0 then revive:Show() else revive:Hide() end
end

------------------------------------------------------------------------
-- Modes around the outside (shown when open)
------------------------------------------------------------------------

local modeButtons = {}
local modeWidgets = {} -- everything that only shows while open

local worldCaption = Text(main, "GameFontDisableSmall")
worldCaption:SetPoint("CENTER", 0, 108)
worldCaption:SetText("IN THE WORLD")
local dungeonCaption = Text(main, "GameFontDisableSmall")
dungeonCaption:SetPoint("CENTER", 0, -108)
dungeonCaption:SetText("DUNGEON: TANK LEADS")
table.insert(modeWidgets, worldCaption)
table.insert(modeWidgets, dungeonCaption)
table.insert(modeWidgets, title)

local Close -- defined below

local function Choose(key)
    W:Choose(key)
    PlayIf("igMainMenuOptionCheckBoxOn")
    Close()
end

for i, mode in ipairs(W.MODES) do
    local x, y = Polar(MODE_RADIUS, MODE_ANGLES[i])
    local b = RoundFrame(main, MODE_SIZE)
    b:SetPoint("CENTER", main, "CENTER", x, y)
    b:SetFrameLevel(disc:GetFrameLevel() + 5)
    SetPortraitToTexture(b.art, mode.icon)

    local glow = b:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(MEDIA .. "RoundGlow")
    glow:SetBlendMode("ADD")
    Size(glow, MODE_SIZE * 2)
    glow:SetPoint("CENTER")
    glow:Hide()
    b.glow = glow

    local keyBack = b:CreateTexture(nil, "OVERLAY")
    keyBack:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    keyBack:SetVertexColor(0, 0, 0, 0.85)
    Size(keyBack, 17)
    keyBack:SetPoint("CENTER", b, "TOPRIGHT", -7, -7)
    local key = Text(b, "NumberFontNormalSmall")
    key:SetPoint("CENTER", keyBack, "CENTER", 1, 0)
    key:SetText(i)

    -- Labels sit on the outside so they never cover a button.
    local label = Text(b, "GameFontNormal")
    if mode.group == "world" then
        label:SetPoint("BOTTOM", b, "TOP", 0, 1)
    else
        label:SetPoint("TOP", b, "BOTTOM", 0, -1)
    end
    label:SetText(mode.label)

    b:SetScript("OnClick", function(_, mouse)
        if mode.key == "team" and mouse == "RightButton" then
            Close()
            W:PickTeam()
        else
            Choose(mode.key)
        end
    end)
    b:SetScript("OnEnter", function(self)
        Tooltip(self, mode.label, { mode.tip, "Key while open: " .. i }, "BOTBRIGADE_" .. mode.key:upper())
    end)
    b:SetScript("OnLeave", HideTooltip)
    b:Hide()
    modeButtons[mode.key] = b
    table.insert(modeWidgets, b)
end

-- Team actions on the left and right of the open ring: Regroup and Dismiss.
StaticPopupDialogs["BOTBRIGADE_DISMISS"] = {
    text = "Send your whole team home?\n\nYour characters log out and other bots leave your group.",
    button1 = "Send home",
    button2 = CANCEL,
    OnAccept = function() W:DismissTeam() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local TEAM_ACTIONS = {
    { key = 7, label = "Regroup", angle = 270, icon = "Interface\\Icons\\Spell_Shadow_Twilight",
      tip = "Teleports everyone in your group to you right now. Use it when a teammate is stuck, or to pull the fight back to you.",
      binding = "BOTBRIGADE_REGROUP", run = function() W:Regroup() end },
    { key = 8, label = "Dismiss", angle = 90, icon = "Interface\\Icons\\INV_Misc_Rune_01",
      tip = "Sends your team home: your characters log out and other bots leave the group. Asks first.",
      binding = "BOTBRIGADE_DISMISS", run = function() StaticPopup_Show("BOTBRIGADE_DISMISS") end },
}
local actionByKey = {}

for _, action in ipairs(TEAM_ACTIONS) do
    local x, y = Polar(MODE_RADIUS, action.angle)
    local b = RoundFrame(main, 48)
    b:SetPoint("CENTER", main, "CENTER", x, y)
    b:SetFrameLevel(disc:GetFrameLevel() + 5)
    SetPortraitToTexture(b.art, action.icon)

    local keyBack = b:CreateTexture(nil, "OVERLAY")
    keyBack:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    keyBack:SetVertexColor(0, 0, 0, 0.85)
    Size(keyBack, 17)
    keyBack:SetPoint("CENTER", b, "TOPRIGHT", -6, -6)
    local key = Text(b, "NumberFontNormalSmall")
    key:SetPoint("CENTER", keyBack, "CENTER", 1, 0)
    key:SetText(action.key)

    local label = Text(b, "GameFontNormal")
    label:SetPoint("TOP", b, "BOTTOM", 0, -1)
    label:SetText(action.label)

    local function Run()
        PlayIf("igMainMenuOptionCheckBoxOn")
        Close()
        action.run()
    end
    b:SetScript("OnClick", Run)
    b:SetScript("OnEnter", function(self)
        Tooltip(self, action.label, { action.tip, "Key while open: " .. action.key }, action.binding)
    end)
    b:SetScript("OnLeave", HideTooltip)
    b:Hide()
    actionByKey[action.key] = Run
    table.insert(modeWidgets, b)
end

------------------------------------------------------------------------
-- Opening and closing
------------------------------------------------------------------------

local function SetOpen(open)
    isOpen = open
    for _, w in ipairs(modeWidgets) do
        if open then w:Show() else w:Hide() end
    end
    main:SetFrameStrata(open and "DIALOG" or "MEDIUM")
    main:EnableKeyboard(open)
    PlaceToast()
end

local function AnimateDisc(from, to, duration)
    local t = 0
    Size(disc, from)
    disc:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local p = math.min(1, t / duration)
        p = 1 - (1 - p) * (1 - p) -- ease out
        Size(self, from + (to - from) * p)
        if p >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

local function Open()
    if isOpen then return end
    SetOpen(true)
    AnimateDisc(DISC_CLOSED, DISC_OPEN, 0.14)
    PlayIf("igCharacterInfoOpen")
end

function Close()
    if not isOpen then return end
    SetOpen(false)
    AnimateDisc(DISC_OPEN, DISC_CLOSED, 0.1)
    PlayIf("igCharacterInfoClose")
end

local function ToggleOpen()
    if isOpen then Close() else Open() end
end

-- Number keys pick while open: 1-6 modes, 7 Regroup, 8 Dismiss. Escape closes.
main:SetScript("OnKeyDown", function(_, key)
    local n = tonumber(key)
    if n and W.MODES[n] then
        Choose(W.MODES[n].key)
    elseif n and actionByKey[n] then
        actionByKey[n]()
    elseif key == "ESCAPE" then
        Close()
    end
end)

------------------------------------------------------------------------
-- Menus
------------------------------------------------------------------------

local menuFrame = CreateFrame("Frame", "BotBrigadeMenu", UIParent, "UIDropDownMenuTemplate")
local HidePartyFrames -- defined below, with the refresh code

local function OpenMateMenu(slot)
    local m = slot.member
    if not m then
        W:PickTeam()
        return
    end
    if not UnitIsConnected(m.unit) then
        EasyMenu({
            { text = m.name .. " (logged out)", isTitle = true, notCheckable = true },
            { text = "Log back in", notCheckable = true, func = function() W:Summon(m.name) end },
            { text = "Remove from group", notCheckable = true, func = function() UninviteUnit(m.name) end },
            { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end },
        }, menuFrame, "cursor", 0, 0, "MENU")
        return
    end
    local menu = {
        { text = m.name, isTitle = true, notCheckable = true },
        { text = "Bring to me", notCheckable = true, func = function() W:Summon(m.name) end },
    }
    local can = W:RolesFor(m.class)
    for _, role in ipairs({ "tank", "heal", "dps" }) do
        if can[role] then
            table.insert(menu, {
                text = "Make " .. W.ROLE_NAME[role], checked = (W.db.roles[m.name] == role),
                func = function() W:SetRole(m.name, role) end,
            })
        end
    end
    table.insert(menu, { text = "Train and repair", notCheckable = true, func = function() W:PowerUp(m.name) end })
    table.insert(menu, { text = "Log out", notCheckable = true, func = function() W:SendHome(m.name) end })
    table.insert(menu, { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end })
    EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

-- Team picker: tick which of your characters Call Team brings.
local function OpenPicker()
    local menu = {
        { text = "Choose your team", isTitle = true, notCheckable = true },
    }
    for _, name in ipairs(W:AltNames()) do
        local class = W.db.alts[name]
        local c = RAID_CLASS_COLORS[class]
        local colored = c and string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) or name
        local className = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or ""
        table.insert(menu, {
            text = colored .. "  " .. className,
            checked = W.db.team[name] and true or false,
            keepShownOnClick = true,
            func = function() W:SetChosen(name, not W.db.team[name]) end,
        })
    end
    table.insert(menu, { text = "Call them now", notCheckable = true, func = function() W:CallTeam() end })
    table.insert(menu, { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end })
    EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

local function ApplyScale()
    main:SetScale(W.db.scale)
end

local function OpenOptions()
    local db = W.db
    local menu = {
        { text = "Bot Brigade", isTitle = true, notCheckable = true },
        { text = "Show bot chat in bubbles only", checked = db.hideChatter,
          func = function() db.hideChatter = not db.hideChatter end },
        { text = "Share my quests with my team", checked = db.autoShare,
          func = function() db.autoShare = not db.autoShare end },
        { text = "Share all my quests now", notCheckable = true, func = function() W:ShareAllQuests() end },
        { text = "Bring my team when they fall behind", checked = db.autoGather,
          func = function() db.autoGather = not db.autoGather end },
        { text = "Teammates learn new skills on level-up", checked = db.autoTrain,
          func = function() db.autoTrain = not db.autoTrain end },
        { text = "Hide the game's party frames", checked = db.hidePartyFrames,
          func = function()
              db.hidePartyFrames = not db.hidePartyFrames
              if db.hidePartyFrames then
                  HidePartyFrames()
              else
                  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Bot Brigade|r: type /reload to bring back the game's party frames.")
              end
          end },
        { text = "Set loot rules for me", checked = db.autoLoot,
          func = function() db.autoLoot = not db.autoLoot; W:ApplyLootRule() end },
        { text = "Sounds", checked = db.sound, func = function() db.sound = not db.sound end },
        { text = "Lock position", checked = db.locked, func = function() db.locked = not db.locked end },
        { text = "Larger", notCheckable = true,
          func = function() db.scale = math.min(1.6, db.scale + 0.1); ApplyScale() end },
        { text = "Smaller", notCheckable = true,
          func = function() db.scale = math.max(0.6, db.scale - 0.1); ApplyScale() end },
        { text = "Choose my team", notCheckable = true, func = function() W:PickTeam() end },
        { text = "Find my characters again", notCheckable = true, func = function() W:RequestRoster() end },
        { text = "Reset position", notCheckable = true, func = function() W:Fire("RESET") end },
        { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end },
    }
    EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

crest:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
        OpenOptions()
    else
        ToggleOpen()
    end
end)
crest:SetScript("OnEnter", function(self)
    Tooltip(self, "Bot Brigade", { isOpen and "Click to close." or "Click to tell your team what to do.",
        "Right-click for options. Drag to move." }, "BOTBRIGADE_RING")
end)
crest:SetScript("OnLeave", HideTooltip)

------------------------------------------------------------------------
-- Refreshing
------------------------------------------------------------------------

local function ModeText()
    local mode = W.MODE_BY_KEY[W:Mode()] or W.MODE_BY_KEY.quest
    local detail
    if mode.pull then
        if W.dc.enabled then
            detail = W:DungeonProgress() or "Tank is leading"
            if W.dc.state == "paused" then detail = "Paused" end
        elseif W:InDungeon() then
            detail = (W.dc.supported == false) and "Not on this realm" or "Starting..."
        else
            detail = "Set for next dungeon"
        end
    elseif mode.key == "quest" then
        detail = W:GroupChannel() and "Team follows you" or "Press Call Team"
    elseif mode.key == "stop" then
        detail = "Team is waiting"
    end
    return mode, detail
end

local function RefreshMode()
    local mode, detail = ModeText()
    SetPortraitToTexture(modeIcon, mode.icon)
    modeLabel:SetText(mode.label)
    modeDetail:SetText(detail or "")
    for key, b in pairs(modeButtons) do
        if key == mode.key then b.glow:Show() else b.glow:Hide() end
    end
end

local function RefreshSlots()
    local members = W:Members()
    for i, s in ipairs(slots) do
        local m = members[i]
        s.member = m
        if m then
            s.unit = m.unit
            SetPortraitTexture(s.art, m.unit)
            s.ring:SetVertexColor(1, 1, 1)
            s.plus:Hide()
            s.bar:Show()
            s.name:SetText(m.name or "")
            s.name:SetTextColor(ClassColor(m.class))
            s:SetAlpha(1)
        else
            s.unit = nil
            s.art:SetTexture(nil)
            s.ring:SetVertexColor(0.45, 0.45, 0.45)
            s.plus:Show()
            s.bar:Hide()
            s.power:Hide()
            s.name:SetText("")
            s:SetAlpha(0.6)
            s.bubble:Hide()
        end
    end
end

-- Health, range, and fallen teammates update a few times a second.
local function RefreshLive()
    RefreshRevive()
    for _, s in ipairs(slots) do
        local unit = s.unit
        if unit and UnitExists(unit) then
            local hp, max = UnitHealth(unit), UnitHealthMax(unit)
            local pct = (max and max > 0) and hp / max or 0
            local dead = UnitIsDeadOrGhost(unit)
            local online = UnitIsConnected(unit)
            s.bar:SetValue(pct)
            if pct < 0.35 then
                s.bar:SetStatusBarColor(0.9, 0.15, 0.1)
            else
                s.bar:SetStatusBarColor(0.1, 0.85, 0.1)
            end
            local powerMax = UnitPowerMax(unit)
            if powerMax and powerMax > 0 and not dead then
                local _, token = UnitPowerType(unit)
                local c = (PowerBarColor and PowerBarColor[token]) or { r = 0, g = 0.45, b = 1 }
                s.power:SetStatusBarColor(c.r, c.g, c.b)
                s.power:SetValue(UnitPower(unit) / powerMax)
                s.power:Show()
            else
                s.power:Hide()
            end
            s.art:SetDesaturated(dead or not online)
            if dead then
                s.name:SetText("Dead")
                s.name:SetTextColor(1, 0.25, 0.25)
            elseif not online then
                s.name:SetText("Offline")
                s.name:SetTextColor(0.6, 0.6, 0.6)
            elseif s.member then
                s.name:SetText(s.member.name)
                s.name:SetTextColor(ClassColor(s.member.class))
            end
            s:SetAlpha((dead or not online) and 0.7 or (UnitInRange(unit) and 1 or 0.75))
        end
    end
end

local function ShowBubble(slot, text)
    local b = slot.bubble
    if #text > 100 then text = text:sub(1, 97) .. "..." end
    b.text:SetWidth(0)
    b.text:SetText(slot.member.name .. ": " .. text)
    local w = math.min(b.text:GetStringWidth(), 200)
    b.text:SetWidth(w)
    Size(b, w + 16, b.text:GetHeight() + 14)
    b:ClearAllPoints()
    -- Teammates on the left speak to the left of the medallion; the right side, to the right.
    if slot.onLeft then
        b:SetPoint("RIGHT", disc, "LEFT", -6, slot.offsetY)
    else
        b:SetPoint("LEFT", disc, "RIGHT", 6, slot.offsetY)
    end
    b:SetAlpha(1)
    b.left = 6
    b:Show()
    b:SetScript("OnUpdate", function(self, elapsed)
        self.left = self.left - elapsed
        if self.left <= 0 then
            self:Hide()
            self:SetScript("OnUpdate", nil)
        elseif self.left < 0.8 then
            self:SetAlpha(self.left / 0.8)
        end
    end)
end

for _, s in ipairs(slots) do
    s:SetScript("OnClick", function(self)
        PlayIf("igMainMenuOptionCheckBoxOn")
        OpenMateMenu(self)
    end)
    s:SetScript("OnEnter", function(self)
        local m = self.member
        if m then
            local role = W.db.roles[m.name]
            if UnitIsConnected(m.unit) then
                Tooltip(self, m.name, { (role and (W.ROLE_NAME[role] .. ". ") or "") .. "Click for options." })
            else
                Tooltip(self, m.name, { "Logged out. Click to log them back in, or press Call Team." })
            end
        else
            Tooltip(self, "Empty place", { "Click to choose who joins your team." })
        end
    end)
    s:SetScript("OnLeave", HideTooltip)
end

------------------------------------------------------------------------
-- Wiring to Core
------------------------------------------------------------------------

local function ApplyShown()
    if W.db.shown then
        main:Show()
    else
        Close()
        main:Hide()
    end
end

-- The game's own party frames repeat what the medallion shows, so they're hidden
-- (option, on by default). Protected frames can't be hidden during a fight, so
-- this waits for the fight to end if needed.
local partyFramesHidden, hidePartyAfterCombat = false, false
local function Nothing() end
function HidePartyFrames()
    if partyFramesHidden or not W.db.hidePartyFrames then return end
    if InCombatLockdown() then
        hidePartyAfterCombat = true
        return
    end
    for i = 1, (MAX_PARTY_MEMBERS or 4) do
        for _, name in ipairs({ "PartyMemberFrame" .. i, "PartyMemberFrame" .. i .. "PetFrame" }) do
            local f = _G[name]
            if f then
                f:UnregisterAllEvents()
                f:Hide()
                f.Show = Nothing
            end
        end
    end
    partyFramesHidden = true
end

local function Refresh()
    RefreshSlots()
    RefreshLive()
    RefreshMode()
end

W:On("READY", function()
    HidePartyFrames()
    RestorePosition()
    ApplyScale()
    SetOpen(false)
    ApplyShown()
    Refresh()
end)
W:On("GROUP", Refresh)
W:On("MODE", RefreshMode)
W:On("DUNGEON", RefreshMode)
W:On("STATUS", ShowToast)
W:On("RING", function()
    if not main:IsShown() then
        W.db.shown = true
        ApplyShown()
    end
    ToggleOpen()
end)
W:On("JOINED", function() PlayIf("ReadyCheck") end)
W:On("PICK", OpenPicker)
W:On("CONFIRM_DISMISS", function() StaticPopup_Show("BOTBRIGADE_DISMISS") end)

W:On("SAY", function(sender, text)
    for _, s in ipairs(slots) do
        if s.member and s.member.name == sender then
            if main:IsShown() then ShowBubble(s, text) end
            return
        end
    end
end)

W:On("TOGGLE", function()
    W.db.shown = not W.db.shown
    ApplyShown()
end)

W:On("SCALE", function(value)
    W.db.scale = math.max(0.6, math.min(1.6, value))
    ApplyScale()
end)

W:On("RESET", function()
    W.db.center = nil
    W.db.scale = 1
    W.db.shown = true
    RestorePosition()
    ApplyScale()
    ApplyShown()
end)

-- Open state, for tests and key bindings.
function W:IsOpen() return isOpen end

local ticker = CreateFrame("Frame")
local since = 0
ticker:RegisterEvent("UNIT_PORTRAIT_UPDATE")
ticker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ticker:RegisterEvent("PLAYER_REGEN_ENABLED")
ticker:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if hidePartyAfterCombat then
            hidePartyAfterCombat = false
            HidePartyFrames()
        end
        return
    end
    if event == "UNIT_PORTRAIT_UPDATE" then RefreshSlots() end
    RefreshMode()
end)
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since >= 0.25 then
        since = 0
        if main:IsShown() then RefreshLive() end
    end
end)
