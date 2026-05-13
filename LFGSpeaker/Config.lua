-- Config.lua
-- Programmatic options panel.  No XML — see CLAUDE.md for why we avoid
-- XML loaders on 2.4.3.
--
-- Layout (top → bottom):
--   Title bar with [X] close
--   Master enable
--   Cooldown slider
--   My role     (radio-style: 6 mutually-exclusive checkboxes in 2 rows)
--   Listen on   (4 channel-group checkboxes in 1 row)
--   Difficulty  (3 checkboxes)
--   Instances   (two columns of grouped checkboxes)
--   Footer
--
-- Frame is movable (drag anywhere).  Position is not persisted in v0.2.
-- We use radio-style checkboxes (not UIDropDownMenuTemplate) for role
-- because the 2.4.3 dropdown API has signature differences from modern
-- WoW and is fragile.  Six radios in 2 rows fit cleanly here.

LFGSpeakerNS = LFGSpeakerNS or {}
local ns = LFGSpeakerNS

local PANEL_W, PANEL_H = 700, 700
local PAD, ROW = 14, 22

local panel  -- created lazily

-- Move a slider's value-text label off the default centered position
-- so it doesn't sit on top of the slider bar itself.  fraction=0.75 =>
-- text centered at 75% of slider width.
local function shiftSliderTextRight(slider, fraction)
    local txt = _G[slider:GetName() .. "Text"]
    if not txt then return end
    txt:ClearAllPoints()
    local w = slider:GetWidth() or (PANEL_W - 2*PAD - 8)
    txt:SetPoint("BOTTOM", slider, "TOP", w * (fraction - 0.5), 2)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function makeLabel(parent, text, fontObj)
    local fs = parent:CreateFontString(nil, "ARTWORK", fontObj or "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function makeCheck(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    local txt = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    txt:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    txt:SetText(text)
    cb.label = txt
    cb:SetScript("OnClick", function(self)
        if onClick then onClick(self:GetChecked() and true or false) end
    end)
    return cb
end

-- ---------------------------------------------------------------------------
-- Build the panel
-- ---------------------------------------------------------------------------

local function build()
    panel = CreateFrame("Frame", "LFGSpeakerConfigFrame", UIParent)
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()

    panel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    -- Title
    local title = makeLabel(panel, "LFGSpeaker — Config", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -14)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

    local yCursor = -44

    -- ---- Master enable + Print matches (same row) ----
    local enable = makeCheck(panel, "Enable LFGSpeaker", function(v)
        ns.db.enabled = v
    end)
    enable:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    panel.enable = enable

    local printM = makeCheck(panel, "Debug: print matches to chat", function(v)
        ns.db.printMatches = v
    end)
    printM:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 220, yCursor)
    panel.printMatches = printM
    yCursor = yCursor - ROW - 6

    -- ---- Per-sound cooldown slider ----
    local cdLabel = makeLabel(panel, "Per-sound cooldown (seconds)")
    cdLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    yCursor = yCursor - 16

    local cdSlider = CreateFrame("Slider", "LFGSpeakerCdSlider", panel, "OptionsSliderTemplate")
    cdSlider:SetWidth(PANEL_W - 2*PAD - 8)
    cdSlider:SetHeight(16)
    cdSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    cdSlider:SetMinMaxValues(5, 300)
    cdSlider:SetValueStep(5)
    _G[cdSlider:GetName() .. "Low"]:SetText("5")
    _G[cdSlider:GetName() .. "High"]:SetText("300")
    local cdSliderText = _G[cdSlider:GetName() .. "Text"]
    cdSlider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.cooldownGlobal = v
        cdSliderText:SetText("Cooldown: " .. v .. "s")
    end)
    shiftSliderTextRight(cdSlider, 0.75)
    panel.cdSlider = cdSlider
    yCursor = yCursor - 36

    -- ---- Snippet gap slider ----
    local gapLabel = makeLabel(panel, "Snippet gap (ms between voice clips during a sentence)")
    gapLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    yCursor = yCursor - 16

    local gapSlider = CreateFrame("Slider", "LFGSpeakerGapSlider", panel, "OptionsSliderTemplate")
    gapSlider:SetWidth(PANEL_W - 2*PAD - 8)
    gapSlider:SetHeight(16)
    gapSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    gapSlider:SetMinMaxValues(0, 500)
    gapSlider:SetValueStep(10)
    _G[gapSlider:GetName() .. "Low"]:SetText("0")
    _G[gapSlider:GetName() .. "High"]:SetText("500")
    local gapSliderText = _G[gapSlider:GetName() .. "Text"]
    gapSlider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.snippetGapMs = v
        gapSliderText:SetText("Gap: " .. v .. " ms")
    end)
    shiftSliderTextRight(gapSlider, 0.75)
    panel.gapSlider = gapSlider
    yCursor = yCursor - 36

    -- ---- Per-sender cooldown slider ----
    local sndLabel = makeLabel(panel, "Per-sender sound cooldown (mute spammer's sound; print stays)")
    sndLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    yCursor = yCursor - 16

    local sndSlider = CreateFrame("Slider", "LFGSpeakerSenderCdSlider", panel, "OptionsSliderTemplate")
    sndSlider:SetWidth(PANEL_W - 2*PAD - 8)
    sndSlider:SetHeight(16)
    sndSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    sndSlider:SetMinMaxValues(0, 600)
    sndSlider:SetValueStep(10)
    _G[sndSlider:GetName() .. "Low"]:SetText("0 (off)")
    _G[sndSlider:GetName() .. "High"]:SetText("600")
    local sndSliderText = _G[sndSlider:GetName() .. "Text"]
    sndSlider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.db.cooldownPerSender = v
        if v == 0 then
            sndSliderText:SetText("Sender cooldown: OFF")
        else
            sndSliderText:SetText("Sender cooldown: " .. v .. "s")
        end
    end)
    shiftSliderTextRight(sndSlider, 0.75)
    panel.sndSlider = sndSlider
    yCursor = yCursor - 36

    -- ---- My role (radio-style: clicking one un-checks the others) ----
    local roleLabel = makeLabel(panel, "My role (announce only what wants this role):")
    roleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    yCursor = yCursor - 18

    panel.roleRadios = {}  -- roleKey -> CheckButton
    local function setRole(roleKey)
        ns.db.myRole = roleKey
        for k, cb in pairs(panel.roleRadios) do
            cb:SetChecked(k == roleKey)
        end
    end

    local choices = ns.MY_ROLE_CHOICES or {}
    local PER_ROW = 3
    local cellW = (PANEL_W - 2*PAD) / PER_ROW
    for i, choice in ipairs(choices) do
        local row = math.floor((i - 1) / PER_ROW)
        local col = (i - 1) % PER_ROW
        local cb = makeCheck(panel, choice.label, function()
            setRole(choice.key)
        end)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + col * cellW, yCursor - row * ROW)
        panel.roleRadios[choice.key] = cb
    end
    yCursor = yCursor - 2 * ROW - 8

    -- ---- Listen on (channel groups) ----
    local chLabel = makeLabel(panel, "Listen on:")
    chLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    yCursor = yCursor - 18

    panel.chCheckboxes = {}  -- groupKey -> CheckButton
    local chPerRow = #(ns.CHANNEL_GROUPS or {})
    local chCellW = (PANEL_W - 2*PAD) / chPerRow
    for i, grp in ipairs(ns.CHANNEL_GROUPS or {}) do
        local cb = makeCheck(panel, grp.label, function(v)
            ns.db.enabledChannelGroups[grp.key] = v
        end)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + (i-1) * chCellW, yCursor)
        panel.chCheckboxes[grp.key] = cb
    end
    yCursor = yCursor - ROW - 8

    -- ---- Instances (per-difficulty N/H checkboxes per 5-man) ----
    local instLabel = makeLabel(panel, "Instances to announce  (N = normal, H = heroic):")
    instLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yCursor)
    yCursor = yCursor - 18

    panel.instCheckboxes = {}
    local colW = (PANEL_W - 2*PAD) / 3
    local colX = { PAD, PAD + colW, PAD + 2 * colW }
    local colY = { yCursor, yCursor, yCursor }

    local COL_GROUPS = {
        { 1, 2, 6 },   -- col 1: Hellfire + Coilfang + Sunwell
        { 3, 4, 5 },   -- col 2: Auchindoun + Tempest + CoT
        { 7 },         -- col 3: Raids (single tick each)
    }

    local function makeMiniCheck(parent, onClick)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetScript("OnClick", function(self)
            if onClick then onClick(self:GetChecked() and true or false) end
        end)
        return cb
    end

    local function placeGroup(groupIdx, colNum)
        local group = ns.INSTANCE_GROUPS[groupIdx]
        if not group then return end
        local x, y = colX[colNum], colY[colNum]

        -- Group is raid-only if every key in it is a raid
        local isRaidGroup = true
        for _, k in ipairs(group.keys) do
            if not ns.RAID_KEYS[k] then isRaidGroup = false; break end
        end

        local header = makeLabel(panel, group.name, "GameFontNormal")
        header:SetTextColor(1, 0.82, 0)
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        y = y - 18

        -- For 5-man groups: tiny "N H" column headers on their own row
        -- between the group title and the first checkbox row, so the
        -- letters don't overlap with header text or the first instance.
        if not isRaidGroup then
            local nLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            nLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 6, y)
            nLbl:SetText("N")
            nLbl:SetTextColor(0.7, 0.9, 1)
            local hLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            hLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 28, y)
            hLbl:SetText("H")
            hLbl:SetTextColor(1, 0.7, 0.7)
            y = y - 14
        end

        for _, key in ipairs(group.keys) do
            local inst = ns.INSTANCE_BY_KEY[key]
            if inst then
                if ns.RAID_KEYS[key] then
                    -- Single checkbox for raids — mirror to both .N/.H so
                    -- filter logic (which checks .N for raids) works.
                    local cb = makeCheck(panel, inst.display, function(v)
                        ns.db.enabledInstances[key].N = v
                        ns.db.enabledInstances[key].H = v
                    end)
                    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
                    panel.instCheckboxes[key] = { single = cb }
                else
                    -- Two compact checkboxes N + H per 5-man
                    local cbN = makeMiniCheck(panel, function(v)
                        ns.db.enabledInstances[key].N = v
                    end)
                    cbN:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
                    local cbH = makeMiniCheck(panel, function(v)
                        ns.db.enabledInstances[key].H = v
                    end)
                    cbH:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 22, y)

                    local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    lbl:SetPoint("LEFT", cbH, "RIGHT", 6, 1)
                    lbl:SetText(inst.display)

                    panel.instCheckboxes[key] = { N = cbN, H = cbH }
                end
                y = y - ROW
            end
        end
        y = y - 6
        colY[colNum] = y
    end

    for colNum, groups in ipairs(COL_GROUPS) do
        for _, gi in ipairs(groups) do placeGroup(gi, colNum) end
    end

    -- Footer
    local footer = makeLabel(panel, "v0.4.6  -  /lfgspeaker help for commands", "GameFontDisableSmall")
    footer:SetPoint("BOTTOM", panel, "BOTTOM", 0, 10)
end

-- ---------------------------------------------------------------------------
-- Pull current db state into widgets
-- ---------------------------------------------------------------------------

local function refresh()
    if not panel then return end
    panel.enable:SetChecked(ns.db.enabled)
    panel.printMatches:SetChecked(ns.db.printMatches and true or false)
    panel.cdSlider:SetValue(ns.db.cooldownGlobal or 30)
    panel.gapSlider:SetValue(ns.db.snippetGapMs or 180)
    panel.sndSlider:SetValue(ns.db.cooldownPerSender or 120)

    -- Role radios
    local myRole = ns.db.myRole or "any"
    for k, cb in pairs(panel.roleRadios) do
        cb:SetChecked(k == myRole)
    end

    -- Channel groups
    for k, cb in pairs(panel.chCheckboxes) do
        cb:SetChecked(ns.db.enabledChannelGroups[k] and true or false)
    end

    for key, cbset in pairs(panel.instCheckboxes) do
        local entry = ns.db.enabledInstances[key] or { N = true, H = true }
        if cbset.single then
            cbset.single:SetChecked(entry.N and true or false)
        else
            if cbset.N then cbset.N:SetChecked(entry.N and true or false) end
            if cbset.H then cbset.H:SetChecked(entry.H and true or false) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function ns.InitConfig()
end

function ns.ToggleConfig()
    if not panel then build() end
    if panel:IsShown() then
        panel:Hide()
    else
        refresh()
        panel:Show()
    end
end
