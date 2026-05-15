-- Core.lua
-- LFGSpeaker pipeline — snippet-based playback.
--
-- For each matched bulletin we compose a list of short snippet keys
-- (lfg + instance + difficulty + roles + fill + modifiers) and play
-- them sequentially with a small gap.  Each snippet has a known
-- duration (from ffprobe at build time, stored in Snippets.lua) — we
-- use that to schedule the next PlaySoundFile via OnUpdate, since
-- 2.4.3 has no playback-complete callback.
--
-- See CLAUDE.md for the 2.4.3-specific constraints.

LFGSpeakerNS = LFGSpeakerNS or {}
local ns = LFGSpeakerNS

local PREFIX = "|cffff8800[LFGS]|r "
local function Msg(s)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(s))
    end
end
ns.Msg = Msg

-- ---------------------------------------------------------------------------
-- Channel groups + role choices (used by Config.lua)
-- ---------------------------------------------------------------------------

ns.CHANNEL_GROUPS = {
    { key = "channels",  label = "Channels",
      events = { "CHAT_MSG_CHANNEL" } },
    { key = "guild",     label = "Guild",
      events = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" } },
    { key = "group",     label = "Group",
      events = { "CHAT_MSG_PARTY", "CHAT_MSG_RAID",
                 "CHAT_MSG_RAID_LEADER", "CHAT_MSG_BATTLEGROUND" } },
    { key = "proximity", label = "Local",
      events = { "CHAT_MSG_SAY", "CHAT_MSG_YELL" } },
}

local EVENT_TO_GROUP = {}
for _, grp in ipairs(ns.CHANNEL_GROUPS) do
    for _, ev in ipairs(grp.events) do
        EVENT_TO_GROUP[ev] = grp.key
    end
end

ns.MY_ROLE_CHOICES = {
    { key = "any",  label = "Any role"            },
    { key = "tank", label = "Tank"                },
    { key = "heal", label = "Healer"              },
    { key = "dps",  label = "DPS (any)"           },
    { key = "mdps", label = "DPS - Melee"         },
    { key = "rdps", label = "DPS - Ranged/Caster" },
}

-- ---------------------------------------------------------------------------
-- SavedVariables
-- ---------------------------------------------------------------------------

local db

local function defaultEnabledInstances()
    local t = {}
    for _, inst in ipairs(ns.INSTANCES or {}) do
        t[inst.key] = true
    end
    return t
end

local function InitDB()
    LFGS_DB = LFGS_DB or {}
    db = LFGS_DB
    ns.db = db

    if db.enabled           == nil then db.enabled           = true  end
    if db.cooldownGlobal    == nil then db.cooldownGlobal    = 30    end
    if db.cooldownPerSender == nil then db.cooldownPerSender = 120   end
    if db.debug             == nil then db.debug             = false end
    -- printMatches is a debug toggle (default OFF).  Live feedback in
    -- chat helped during pattern tuning but spams once patterns are
    -- stable.  Enable in Config UI when troubleshooting.
    if db.printMatches      == nil then db.printMatches      = false end
    -- Gap between snippet playback in MILLISECONDS.  Snippets are
    -- short voice clips; this is the silence between them when
    -- assembling a sentence.  180 ms is the conversational default;
    -- tune lower for snappier output, higher for more "spoken word"
    -- pace.
    if db.snippetGapMs      == nil then db.snippetGapMs      = 180   end

    -- Per-instance N/H enable.  Each entry is { N = bool, H = bool }.
    -- For raids (no difficulty distinction) only .N is consulted and
    -- the UI shows a single checkbox.
    -- Migrate old format (boolean per instance + global db.difficulties)
    -- to the new shape automatically.
    db.enabledInstances = db.enabledInstances or {}
    for _, inst in ipairs(ns.INSTANCES or {}) do
        local key = inst.key
        local existing = db.enabledInstances[key]
        if existing == nil then
            db.enabledInstances[key] = { N = true, H = true }
        elseif type(existing) == "boolean" then
            -- legacy v0.2/v0.3: single bool → both diffs set to it
            db.enabledInstances[key] = { N = existing, H = existing }
        elseif type(existing) == "table" then
            if existing.N == nil then existing.N = true end
            if existing.H == nil then existing.H = true end
        end
    end
    -- Old global difficulty filter is gone; per-instance toggles replace it.
    db.difficulties = nil

    db.enabledChannelGroups = db.enabledChannelGroups or {}
    for _, grp in ipairs(ns.CHANNEL_GROUPS) do
        if db.enabledChannelGroups[grp.key] == nil then
            db.enabledChannelGroups[grp.key] = true
        end
    end

    -- v0.4.9+: multi-role.  Migrate old single-string db.myRole into
    -- a table db.myRoles preserving the previous selection.
    if db.myRoles == nil then
        if type(db.myRole) == "string" then
            db.myRoles = { [db.myRole] = true }
        else
            db.myRoles = { any = true }
        end
    end
    db.myRole = nil  -- legacy field; clear after migration

    db.mutedKeys         = db.mutedKeys         or {}
    db.lastFireTimes     = db.lastFireTimes     or {}
    db.lastFireBySender  = db.lastFireBySender  or {}
    db.matchLog          = db.matchLog          or {}

    -- Prune stale sender entries (> 24h old)
    local cutoff = time() - 86400
    for s, t in pairs(db.lastFireBySender) do
        if type(t) == "number" and t < cutoff then
            db.lastFireBySender[s] = nil
        end
    end

    db.minimap = db.minimap or { angle = 220, hide = false }
end

-- ---------------------------------------------------------------------------
-- RussianTranslator integration (soft dep)
-- ---------------------------------------------------------------------------

local function getTranslated(msg)
    if RussianTranslatorNS
       and type(RussianTranslatorNS.TranslatePublic) == "function" then
        local en = RussianTranslatorNS.TranslatePublic(msg)
        if en and en ~= "" then return en end
    end
    return msg
end

-- ---------------------------------------------------------------------------
-- Sentence composition (parsed bulletin -> ordered list of snippet keys)
-- ---------------------------------------------------------------------------

local function snippetExists(key)
    return ns.SNIPPETS and ns.SNIPPETS[key] ~= nil
end

local function composeSentence(parsed)
    local out = {}

    -- 1. Prefix
    table.insert(out, "lfg")

    -- 2. Instance name
    local instKey = "inst_" .. parsed.instance
    table.insert(out, instKey)

    -- 3. Difficulty (5-mans only — raids ignore)
    if not ns.RAID_KEYS[parsed.instance] then
        if parsed.difficulty == "heroic" then
            table.insert(out, "diff_heroic")
        elseif parsed.difficulty == "normal" then
            table.insert(out, "diff_normal")
        end
    end

    -- 4. Roles
    local r = parsed.roles or { tank=0, heal=0, mdps=0, rdps=0, dps=0 }
    local totalDps = r.dps + r.mdps + r.rdps
    local hasAllThree = r.tank > 0 and r.heal > 0 and totalDps > 0

    if hasAllThree then
        table.insert(out, "gen_all_roles")
    else
        local roleClips = {}
        if r.tank == 1 then roleClips[#roleClips+1] = "role_tank_1"
        elseif r.tank >= 2 then roleClips[#roleClips+1] = "role_tank_2" end

        if r.heal == 1 then roleClips[#roleClips+1] = "role_heal_1"
        elseif r.heal >= 2 then roleClips[#roleClips+1] = "role_heal_2" end

        if r.mdps == 1 then roleClips[#roleClips+1] = "role_melee_1"
        elseif r.mdps == 2 then roleClips[#roleClips+1] = "role_melee_2"
        elseif r.mdps >= 3 then roleClips[#roleClips+1] = "role_melee_3" end

        if r.rdps == 1 then roleClips[#roleClips+1] = "role_ranged_1"
        elseif r.rdps == 2 then roleClips[#roleClips+1] = "role_ranged_2"
        elseif r.rdps >= 3 then roleClips[#roleClips+1] = "role_ranged_3" end

        if r.dps >= 5 then roleClips[#roleClips+1] = "role_dps_many"
        elseif r.dps == 4 then roleClips[#roleClips+1] = "role_dps_4"
        elseif r.dps == 3 then roleClips[#roleClips+1] = "role_dps_3"
        elseif r.dps == 2 then roleClips[#roleClips+1] = "role_dps_2"
        elseif r.dps == 1 then roleClips[#roleClips+1] = "role_dps_1" end

        for i, clip in ipairs(roleClips) do
            if i > 1 then table.insert(out, "conn_and") end
            table.insert(out, clip)
        end
        if #roleClips > 0 then
            table.insert(out, "conn_needed")
        end
    end

    -- 5. Group fill ("X out of Y")
    if parsed.groupFill then
        local n = parsed.groupFill.current
        local t = parsed.groupFill.target
        if n and n >= 1 and n <= 15 then
            table.insert(out, "num_" .. n)
            table.insert(out, "fill_out_of")
            if t == 25 then
                table.insert(out, "fill_target_25")
            elseif t == 40 then
                table.insert(out, "fill_target_40")
            elseif t and t >= 1 and t <= 15 then
                table.insert(out, "num_" .. t)
            end
        end
    end

    -- 6. Class-requested suffix
    if parsed.hasClassReq then
        table.insert(out, "mod_class_req")
    end

    -- Drop keys with no corresponding snippet (graceful degrade)
    local filtered = {}
    for _, key in ipairs(out) do
        if snippetExists(key) then
            filtered[#filtered+1] = key
        end
    end
    return filtered
end
ns.composeSentence = composeSentence

-- ---------------------------------------------------------------------------
-- Playback scheduler — OnUpdate accumulator chains snippets with gap.
-- Single global queue (only one sentence plays at a time).
-- ---------------------------------------------------------------------------

-- Gap is read from db.snippetGapMs at startPlayback time (user-tunable).
local playFrame = CreateFrame("Frame")
local playQueue       -- nil = idle, else array of { key, at }
local playCursor = 1
local playElapsed = 0

local function tickPlayback(self, dt)
    if not playQueue then
        self:SetScript("OnUpdate", nil)
        return
    end
    playElapsed = playElapsed + dt
    while playCursor <= #playQueue and playQueue[playCursor].at <= playElapsed do
        local item = playQueue[playCursor]
        local snip = ns.SNIPPETS[item.key]
        if snip then
            PlaySoundFile(ns.SOUND_BASE_PATH .. snip.f)
        end
        playCursor = playCursor + 1
    end
    if playCursor > #playQueue then
        playQueue = nil
        self:SetScript("OnUpdate", nil)
    end
end

local function startPlayback(snippetKeys)
    if not snippetKeys or #snippetKeys == 0 then return false end
    local gap = ((db and db.snippetGapMs) or 180) / 1000
    local q = {}
    local t = 0
    for _, key in ipairs(snippetKeys) do
        local snip = ns.SNIPPETS[key]
        if snip then
            q[#q+1] = { key = key, at = t }
            t = t + snip.d + gap
        end
    end
    if #q == 0 then return false end
    playQueue = q
    playCursor = 1
    playElapsed = 0
    playFrame:SetScript("OnUpdate", tickPlayback)
    return true
end

local function isPlaying()
    return playQueue ~= nil
end

-- Cooldown key: per-instance (raids ignore diff, 5-mans bundle diff into key).
local function cooldownKey(parsed)
    if ns.RAID_KEYS[parsed.instance] then
        return parsed.instance
    end
    return parsed.instance .. "_" .. (parsed.difficulty or "any")
end

local function playSentence(parsed)
    if not db or not db.enabled then return false, "disabled" end

    local cdKey = cooldownKey(parsed)
    if db.mutedKeys[parsed.instance] or db.mutedKeys[cdKey] then
        return false, "muted"
    end
    if isPlaying() then return false, "playing_other" end

    local now  = time()
    local last = db.lastFireTimes[cdKey] or 0
    local cd   = (ns.INSTANCE_COOLDOWN and ns.INSTANCE_COOLDOWN[parsed.instance])
                 or db.cooldownGlobal or ns.DEFAULT_COOLDOWN or 30
    if (now - last) < cd then return false, "cooldown" end

    local snippets = composeSentence(parsed)
    if #snippets == 0 then return false, "empty_compose" end
    if not startPlayback(snippets) then return false, "playback_failed" end

    db.lastFireTimes[cdKey] = now
    return true, "played"
end
ns.playSentence = playSentence

-- ---------------------------------------------------------------------------
-- Match log (ring buffer)
-- ---------------------------------------------------------------------------

local LOG_MAX = 100
local function logMatch(eventName, rawMsg, parsed, snippets, reason)
    if not db.matchLog then return end
    table.insert(db.matchLog, {
        t           = time(),
        event       = eventName,
        msg         = rawMsg,
        instance    = parsed.instance,
        difficulty  = parsed.difficulty,
        roles       = parsed.roles,
        hasClassReq = parsed.hasClassReq,
        groupFill   = parsed.groupFill,
        snippetCount= snippets and #snippets or 0,
        reason      = reason,
    })
    while #db.matchLog > LOG_MAX do
        table.remove(db.matchLog, 1)
    end
end

-- Compact role display
local function fmtRoles(r)
    if not r then return "-" end
    local parts = {}
    if r.tank > 0 then parts[#parts+1] = "T" .. r.tank end
    if r.heal > 0 then parts[#parts+1] = "H" .. r.heal end
    if r.mdps > 0 then parts[#parts+1] = "M" .. r.mdps end
    if r.rdps > 0 then parts[#parts+1] = "R" .. r.rdps end
    if r.dps  > 0 then parts[#parts+1] = "D" .. r.dps  end
    if #parts == 0 then return "(none)" end
    return table.concat(parts, " ")
end
ns.fmtRoles = fmtRoles

local function fmtFill(gf)
    if not gf then return "" end
    return (" %d/%d"):format(gf.current, gf.target)
end

local function liveLine(rawMsg, parsed, snippetCount, reason)
    local cls  = parsed.hasClassReq and " +cls" or ""
    local fill = fmtFill(parsed.groupFill)
    return ("|cffaaaaaa%s|r -> %s/%s [%s]%s%s {%d clips, %s}"):format(
        (rawMsg or ""):sub(1, 48),
        parsed.instance or "?",
        parsed.difficulty or "-",
        fmtRoles(parsed.roles),
        fill,
        cls,
        snippetCount or 0,
        reason or "?")
end

-- ---------------------------------------------------------------------------
-- Chat filter pipeline
-- ---------------------------------------------------------------------------

local function filterImpl(eventName, msg, sender)
    if not db or not db.enabled then return end
    if type(msg) ~= "string" or msg == "" then return end

    -- Channel-group filter
    local groupKey = EVENT_TO_GROUP[eventName]
    if groupKey and not db.enabledChannelGroups[groupKey] then return end

    local translated = getTranslated(msg)
    local parsed = ns.parseMessage and ns.parseMessage(translated)
    if not parsed then return end

    -- Instance + difficulty filter (per-instance N/H toggles).
    local enabled = db.enabledInstances[parsed.instance]
    if not enabled then
        logMatch(eventName, msg, parsed, nil, "disabled_instance")
        return
    end
    if ns.RAID_KEYS[parsed.instance] then
        -- Raids: single toggle, stored as .N
        if not enabled.N then
            logMatch(eventName, msg, parsed, nil, "disabled_instance")
            return
        end
    else
        local diff = parsed.difficulty
        if diff == "heroic" then
            if not enabled.H then
                logMatch(eventName, msg, parsed, nil, "disabled_difficulty")
                return
            end
        elseif diff == "normal" then
            if not enabled.N then
                logMatch(eventName, msg, parsed, nil, "disabled_difficulty")
                return
            end
        else
            -- Unspecified difficulty: play if EITHER N or H is enabled.
            if not enabled.N and not enabled.H then
                logMatch(eventName, msg, parsed, nil, "disabled_difficulty")
                return
            end
        end
    end

    -- My role matches?
    if not ns.roleMatches(parsed.roles, db.myRoles) then
        logMatch(eventName, msg, parsed, nil, "role_mismatch")
        return
    end

    -- Per-sender cooldown: blocks SOUND only.  Print still shows.
    local snippets = composeSentence(parsed)
    local senderInCd = false
    if sender and sender ~= "" and db.cooldownPerSender and db.cooldownPerSender > 0 then
        local last = db.lastFireBySender[sender] or 0
        if (time() - last) < db.cooldownPerSender then
            senderInCd = true
        end
    end

    local reason
    if senderInCd then
        reason = "sender_cd"
    else
        local ok
        ok, reason = playSentence(parsed)
        -- Stamp sender on ANY post-filter outcome (played, cooldown,
        -- empty_compose, no_sound_entry, ...).  Without this, a sender
        -- whose bulletins fail to play (e.g., snippets not loaded) is
        -- never throttled and keeps spamming the feed.
        if sender and sender ~= "" then
            db.lastFireBySender[sender] = time()
        end
    end

    logMatch(eventName, msg, parsed, snippets, reason)
    -- Suppress noisy reasons in the live print:
    --   cooldown      — true duplicate
    --   empty_compose — snippet table missing (install-time issue, not actionable)
    --   playing_other — overlap with an already-playing sentence
    if db.printMatches
       and reason ~= "cooldown"
       and reason ~= "empty_compose"
       and reason ~= "playing_other" then
        Msg(liveLine(msg, parsed, #snippets, reason))
    end
end

local function safeFilter(eventName, msg, sender)
    local ok, err = pcall(filterImpl, eventName, msg, sender)
    if not ok and db and db.debug then
        Msg("filter error in " .. tostring(eventName) .. ": " .. tostring(err))
    end
    return false
end

local function buildFilter(eventName)
    return function(msg, sender) return safeFilter(eventName, msg, sender) end
end

local function registerFilters()
    for _, grp in ipairs(ns.CHANNEL_GROUPS) do
        for _, ev in ipairs(grp.events) do
            ChatFrame_AddMessageEventFilter(ev, buildFilter(ev))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------

local function fmtAge(seconds)
    if seconds < 60 then return seconds .. "s ago" end
    if seconds < 3600 then return math.floor(seconds/60) .. "m ago" end
    return math.floor(seconds/3600) .. "h ago"
end

SLASH_LFGSPEAKER1 = "/lfgspeaker"
SLASH_LFGSPEAKER2 = "/lfgspeak"
SLASH_LFGSPEAKER3 = "/lfgs"
SlashCmdList["LFGSPEAKER"] = function(input)
    input = input or ""
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        if ns.ToggleConfig then ns.ToggleConfig() return end
        cmd = "help"
    end

    if cmd == "help" then
        Msg("commands (aliases: /lfgspeaker, /lfgspeak, /lfgs):")
        Msg("  /lfgs                  - toggle config window")
        Msg("  /lfgs on | off         - enable/disable")
        Msg("  /lfgs say <text>       - parse text + play composed sentence")
        Msg("  /lfgs test <snippet>   - play one snippet (e.g. /lfgs test inst_kara)")
        Msg("  /lfgs parse <text>     - dry-run parser, print result")
        Msg("  /lfgs list             - list all snippets")
        Msg("  /lfgs log [N]          - last N matched bulletins (default 10)")
        Msg("  /lfgs mute <inst>      - mute one instance key (e.g. /lfgs mute bm)")
        Msg("  /lfgs unmute <inst>")
        Msg("  /lfgs cooldown <sec>   - set global cooldown")
        Msg("  /lfgs minimap          - toggle minimap button")
        Msg("  /lfgs debug on|off     - verbose error reporting")
    elseif cmd == "on" then
        db.enabled = true;  Msg("ON")
    elseif cmd == "off" then
        db.enabled = false; Msg("OFF")
    elseif cmd == "say" then
        if rest == "" then Msg("usage: /lfgs say <text>"); return end
        local p = ns.parseMessage(rest)
        if not p then Msg("no match for: " .. rest); return end
        local snippets = composeSentence(p)
        Msg(("composed %d clips: %s"):format(#snippets, table.concat(snippets, " > ")))
        startPlayback(snippets)
    elseif cmd == "test" then
        if rest == "" then Msg("usage: /lfgs test <snippet>"); return end
        local snip = ns.SNIPPETS and ns.SNIPPETS[rest]
        if not snip then Msg("unknown snippet: " .. rest); return end
        PlaySoundFile(ns.SOUND_BASE_PATH .. snip.f)
        Msg(("played: %s  (%.2fs)"):format(rest, snip.d))
    elseif cmd == "parse" then
        if rest == "" then Msg("usage: /lfgs parse <text>"); return end
        local p = ns.parseMessage(rest)
        if not p then Msg("no match"); return end
        local gf = p.groupFill and (" group=" .. p.groupFill.current .. "/" .. p.groupFill.target) or ""
        Msg(("match: instance=%s difficulty=%s alias=%q"):format(
            p.instance, tostring(p.difficulty), p.alias))
        Msg(("       roles=%s classReq=%s%s"):format(
            fmtRoles(p.roles), p.hasClassReq and "yes" or "no", gf))
        local snippets = composeSentence(p)
        Msg(("       would compose %d clips: %s"):format(
            #snippets, table.concat(snippets, " > ")))
    elseif cmd == "list" then
        if not ns.SNIPPETS then Msg("(no snippets loaded)"); return end
        local keys = {}
        for k in pairs(ns.SNIPPETS) do keys[#keys+1] = k end
        table.sort(keys)
        Msg(("snippets (%d total):"):format(#keys))
        for _, key in ipairs(keys) do
            local s = ns.SNIPPETS[key]
            Msg(("  %-20s %.2fs"):format(key, s.d))
        end
    elseif cmd == "log" then
        local n = tonumber(rest) or 10
        if not db.matchLog or #db.matchLog == 0 then Msg("(no matches yet)"); return end
        local from = math.max(1, #db.matchLog - n + 1)
        for i = from, #db.matchLog do
            local r = db.matchLog[i]
            local cls  = r.hasClassReq and " +cls" or ""
            local fill = fmtFill(r.groupFill)
            Msg(("  [%s] %s -> %s/%s [%s]%s%s {%dc, %s}"):format(
                r.event or "?",
                (r.msg or ""):sub(1, 45),
                r.instance or "?",
                r.difficulty or "-",
                fmtRoles(r.roles),
                fill,
                cls,
                r.snippetCount or 0,
                r.reason or "?"))
        end
    elseif cmd == "mute" then
        if rest == "" then Msg("usage: /lfgs mute <instance key>"); return end
        db.mutedKeys[rest] = true; Msg("muted: " .. rest)
    elseif cmd == "unmute" then
        if rest == "" then Msg("usage: /lfgs unmute <instance key>"); return end
        db.mutedKeys[rest] = nil; Msg("unmuted: " .. rest)
    elseif cmd == "cooldown" then
        local s = tonumber(rest)
        if not s or s < 0 then Msg("usage: /lfgs cooldown <seconds>"); return end
        db.cooldownGlobal = s; Msg("global cooldown = " .. s .. "s")
    elseif cmd == "minimap" then
        if ns.ToggleMinimap then ns.ToggleMinimap()
        else Msg("minimap module not loaded") end
    elseif cmd == "debug" then
        if rest == "on" then db.debug = true;  Msg("debug ON")
        elseif rest == "off" then db.debug = false; Msg("debug OFF")
        else Msg("usage: /lfgs debug on|off") end
    else
        Msg("unknown command: " .. cmd .. "  (try /lfgs help)")
    end
end

-- ---------------------------------------------------------------------------
-- Bootstrap
-- ---------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    InitDB()
    registerFilters()
    if ns.InitMinimap then ns.InitMinimap() end
    if ns.InitConfig  then ns.InitConfig()  end
    local snipCount = 0
    if ns.SNIPPETS then for _ in pairs(ns.SNIPPETS) do snipCount = snipCount + 1 end end
    Msg("|cff55ddffLFGSpeaker v0.4.9|r — made by Grzegorz Korycki (Poczwarka)")
    Msg("build 2026-05-15")
    if snipCount == 0 then
        Msg("|cffff5555WARNING: Snippets.lua did NOT load.  Do a full client RESTART (not /reload).  TOC file-list changes need a restart on 2.4.3.|r")
    end
    Msg("type /lfgs help, /lfgs to open config, /lfgs say <text> to test composition")
    self:UnregisterEvent("PLAYER_LOGIN")
end)
