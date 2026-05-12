-- Minimap.lua
-- Draggable minimap button.  Pure 2.4.3 — no LibDBIcon / Ace / Mixin.
--
-- Behavior:
--   * Left-click       : toggle config window
--   * Right-click      : toggle enabled (master on/off)
--   * Shift-left-drag  : move around minimap (angle saved)
--   * Hover            : tooltip with status + recent-match count
--
-- The angle (0..360 deg) is stored in db.minimap.angle.  Default 220
-- (lower-left).  Radius is fixed at 80px from minimap center which is
-- the standard for 2.4.3 default minimap (54px radius + 26px outside).

LFGSpeakerNS = LFGSpeakerNS or {}
local ns = LFGSpeakerNS

local BUTTON_RADIUS = 80
local BUTTON_SIZE   = 32

local button

-- ---------------------------------------------------------------------------
-- Position math
-- ---------------------------------------------------------------------------

local function angleToOffset(angleDeg)
    local rad = math.rad(angleDeg)
    return math.cos(rad) * BUTTON_RADIUS, math.sin(rad) * BUTTON_RADIUS
end

local function offsetToAngle(x, y)
    -- math.atan2 isn't reliably available on 2.4.3 Lua; emulate via atan.
    if x == 0 and y == 0 then return 0 end
    local a
    if x == 0 then
        a = (y > 0) and 90 or 270
    else
        a = math.deg(math.atan(y / x))
        if x < 0 then a = a + 180 end
        if a < 0 then a = a + 360 end
    end
    return a
end

local function applyPosition()
    if not button or not ns.db or not ns.db.minimap then return end
    local x, y = angleToOffset(ns.db.minimap.angle or 220)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ---------------------------------------------------------------------------
-- Drag handling
-- ---------------------------------------------------------------------------

local function updateDrag()
    if not button then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale  = Minimap:GetEffectiveScale()
    local x = px / scale - mx
    local y = py / scale - my
    ns.db.minimap.angle = offsetToAngle(x, y)
    applyPosition()
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

local function showTooltip()
    if not button then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("LFGSpeaker")
    if ns.db and ns.db.enabled then
        GameTooltip:AddLine("|cff55ff55Enabled|r")
    else
        GameTooltip:AddLine("|cffff5555Disabled|r")
    end
    if ns.db and ns.db.matchLog then
        GameTooltip:AddLine("Matches logged: " .. #ns.db.matchLog, 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd200Left-click:|r open config", 1, 1, 1)
    GameTooltip:AddLine("|cffffd200Right-click:|r toggle on/off", 1, 1, 1)
    GameTooltip:AddLine("|cffffd200Drag:|r move around minimap", 1, 1, 1)
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- ---------------------------------------------------------------------------
-- Button creation
-- ---------------------------------------------------------------------------

local function createButton()
    if button then return button end

    button = CreateFrame("Button", "LFGSpeakerMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Icon (using a recognizable Blizzard texture so we don't need a
    -- bundled .tga/.blp on day one — group-finder magnifier icon).
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-PORTRAITICON")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)

    -- Minimap-button ring (the same ring Blizz uses for its own buttons).
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    -- Highlight on hover.
    local hi = button:CreateTexture(nil, "HIGHLIGHT")
    hi:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hi:SetBlendMode("ADD")
    hi:SetAllPoints(button)

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            if ns.ToggleConfig then ns.ToggleConfig() end
        elseif mouseButton == "RightButton" then
            ns.db.enabled = not ns.db.enabled
            if ns.Msg then
                ns.Msg(ns.db.enabled and "ON" or "OFF")
            end
            hideTooltip(); showTooltip()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", updateDrag)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)

    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)

    return button
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

function ns.InitMinimap()
    if not ns.db or not ns.db.minimap then return end
    createButton()
    applyPosition()
    if ns.db.minimap.hide then button:Hide() else button:Show() end
end

function ns.ToggleMinimap()
    if not button then return end
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.db.minimap.hide then button:Hide() else button:Show() end
    if ns.Msg then
        ns.Msg("minimap button " .. (ns.db.minimap.hide and "hidden" or "shown"))
    end
end
