-- Patterns.lua
-- LFG bulletin parser — ENGLISH ONLY.
--
-- Russian / Cyrillic chat is handled by the sister addon RussianTranslator
-- (RT).  When RT is loaded (declared in TOC as OptionalDeps so it loads
-- BEFORE us) its chat filter rewrites incoming Russian messages with an
-- English translation prefix.  Our filter then sees the English version
-- and matches against the patterns below.
--
-- If RT is NOT installed, Russian bulletins won't match.  Acceptable —
-- the project's stated dependency is "use RT for Russian".  Earlier
-- attempts to maintain a parallel Cyrillic pattern set were dropped
-- because (a) Lua's %a/%f boundary doesn't natively cover multibyte
-- bytes, and (b) maintaining two parallel pattern dictionaries doubled
-- the chance of bugs without measurable user benefit when RT works.
--
-- Lua 5.1 / WoW 2.4.3 pattern notes:
--   * Magic chars (-()[]%.+*?$^) need %-escape.
--   * %f[set] is the Lua "frontier" pattern.  We use a permissive set
--     %a\128-\255 so multibyte UTF-8 bytes count as "word-like" — that
--     way an English short token like "bm" isn't falsely accepted next
--     to a multibyte char (e.g., player name with a Cyrillic letter).
--   * %b is NOT a word-boundary; it's balanced match — don't use here.

LFGSpeakerNS = LFGSpeakerNS or {}
local ns = LFGSpeakerNS

-- ---------------------------------------------------------------------------
-- Word boundary wrapper.  Accepts a token, returns a Lua pattern that
-- matches the token only at "word boundaries" — including the case
-- where the surrounding bytes are multibyte UTF-8.  Without the
-- 128-255 byte range in the frontier set, "bm" would match inside a
-- Cyrillic player name (e.g., "Бmthing" if such a thing existed).
-- ---------------------------------------------------------------------------

local function wordBounded(token)
    return "%f[%a\128-\255]" .. token .. "%f[^%a\128-\255]"
end

-- ---------------------------------------------------------------------------
-- Instance dictionary.
--   key      : sound-file basename (ASCII)
--   display  : human-readable label
--   long     : Lua patterns matched as-is (specific phrases)
--   short    : short tokens automatically wrapped with wordBounded()
-- ---------------------------------------------------------------------------

ns.INSTANCES = {
    -- ===== TBC 5-mans — Hellfire =====
    { key = "ramp",  display = "Hellfire Ramparts",
      long  = { "hellfire ramparts", "ramparts" },
      short = { "ramp", "ramps" } },
    { key = "bf",    display = "Blood Furnace",
      long  = { "blood furnace" },
      short = { "bf" } },
    { key = "shh",   display = "Shattered Halls",
      long  = { "shattered halls", "shattered" },
      short = { "shh" } },

    -- ===== TBC 5-mans — Coilfang =====
    { key = "sp",    display = "Slave Pens",
      long  = { "slave pens", "slave" },
      short = { "sp" } },
    { key = "ub",    display = "Underbog",
      long  = { "underbog" },
      short = { "ub" } },
    { key = "sv",    display = "Steamvault",
      long  = { "steamvault", "steam vault", "steam%-vault" },
      short = { "sv" } },

    -- ===== TBC 5-mans — Auchindoun =====
    { key = "mt",    display = "Mana-Tombs",
      long  = { "mana%-tombs", "mana tombs", "manatombs" },
      short = { "mt" } },
    { key = "auch",  display = "Auchenai Crypts",
      long  = { "auchenai crypts", "auchenai", "crypts" },
      short = { "ac" } },
    { key = "seh",   display = "Sethekk Halls",
      long  = { "sethekk halls", "sethekk" },
      short = { "sh" } },
    { key = "sl",    display = "Shadow Labyrinth",
      long  = { "shadow labyrinth", "shadow lab", "shadowlab" },
      short = { "sl" } },

    -- ===== TBC 5-mans — Tempest Keep wings =====
    { key = "bot",   display = "The Botanica",
      long  = { "botanica" },
      short = { "bot" } },
    { key = "mech",  display = "The Mechanar",
      long  = { "mechanar" },
      short = { "mech" } },
    { key = "arc",   display = "The Arcatraz",
      long  = { "arcatraz" },
      short = { "arc" } },

    -- ===== TBC 5-mans — Caverns of Time =====
    { key = "oh",    display = "Old Hillsbrad",
      long  = { "old hillsbrad", "hillsbrad" },
      short = { "ohf" } },
    { key = "bm",    display = "Black Morass",
      long  = { "black morass", "morass" },
      short = { "bm" } },

    -- ===== TBC 5-man — Sunwell =====
    { key = "mgt",   display = "Magisters' Terrace",
      long  = { "magisters' terrace", "magisters terrace", "magisters" },
      short = { "mgt" } },

    -- ===== TBC raids =====
    { key = "kara",  display = "Karazhan",
      long  = { "karazhan" },
      short = { "kara" } },
    { key = "gruul", display = "Gruul's Lair",
      long  = { "gruul's lair", "gruuls lair", "gruul" },
      short = {} },
    { key = "magth", display = "Magtheridon",
      long  = { "magtheridon" },
      short = { "magt" } },
    { key = "ssc",   display = "Serpentshrine Cavern",
      long  = { "serpentshrine cavern", "serpentshrine" },
      short = { "ssc" } },
    { key = "tk",    display = "Tempest Keep",
      long  = { "tempest keep", "the eye" },
      short = { "tk" } },
    { key = "hyjal", display = "Hyjal Summit",
      long  = { "hyjal summit", "hyjal" },
      short = { "hs" } },
    { key = "bt",    display = "Black Temple",
      long  = { "black temple" },
      short = { "bt" } },
    { key = "za",    display = "Zul'Aman",
      long  = { "zul'aman", "zulaman" },
      short = {} },
    { key = "swp",   display = "Sunwell Plateau",
      long  = { "sunwell plateau", "sunwell%-plateau", "sunwell" },
      short = { "swp" } },
    -- Note: "sunwell" alone matches here.  Safe because Magisters'
    -- Terrace (mgt) is declared earlier in INSTANCES and its aliases
    -- ("magisters" / "magisters terrace" / "mgt") take precedence in
    -- the iteration if present in the same message.
}

-- ---------------------------------------------------------------------------
-- Difficulty detection.  Heroic checked first so "ramps hc daily"
-- classifies as heroic.  Bracketed short forms catch "(h)" / "(n)"
-- which appeared frequently in the test log.
-- ---------------------------------------------------------------------------

ns.DIFFICULTY_HEROIC_LONG = {
    "heroic",
    "%(hc%)", "%[hc%]", "%{hc%}",
    "%(h%)",  "%[h%]",  "%{h%}",
}
ns.DIFFICULTY_HEROIC_SHORT = { "hc", "hcc" }

ns.DIFFICULTY_NORMAL_LONG = {
    "normal",
    "%(norm%)", "%[norm%]",
    "%(n%)", "%[n%]", "%{n%}",
}
ns.DIFFICULTY_NORMAL_SHORT = { "norm" }

-- ---------------------------------------------------------------------------
-- LFG markers.  A short-alias match (≤ 4 chars) requires one of these
-- OR a role-token match (see parseMessage).
-- ---------------------------------------------------------------------------

ns.LFG_MARKERS_LONG = {
    "looking for",
    "need.-tank", "need.-heal", "need.-dps", "need.-dd",
    "/w me", "/w %+",
}
ns.LFG_MARKERS_SHORT = {
    "lfm", "lfg",
    "lf1m", "lf2m", "lf3m", "lf4m", "lf5m",
    "lf",
}

-- ---------------------------------------------------------------------------
-- Anti-LFG markers.  Trade, profession, guild recruitment, AND solo
-- players offering themselves (the inverse of recruiting).
--
-- Solo-offer detection: a role token followed by "lf" (with word-end
-- boundary so it doesn't catch "lfm") means a single player is
-- looking for a group, not assembling one.  Examples:
--   "tank lf bm hc"   -> player IS a tank, wants someone to invite
--   "dps lf kara"     -> player IS dps, wants Karazhan invite
--   "lf tank for bm"  -> recruiter, KEEP (lf before role)
-- The frontier %f[^%a\128-\255] after "lf" rejects "lfm/lfg/lf2m".
-- ---------------------------------------------------------------------------

ns.ANTI_LFG_LONG = {
    -- Guild-recruitment ads (these dominate Global on raid-heavy realms).
    -- We match SPECIFIC recruitment phrases rather than a bare "guild"
    -- word so legitimate "guild run BM HC" type bulletins still trigger.
    "guild.-recruit",                 -- "guild is recruiting", "guild looking to recruit"
    "recruiting players",
    "recruiting active",
    "recruiting all",
    "recruiting%s+%a+%s+for",         -- "recruiting <class> for ..."
    "join our guild",
    "join my guild",
    "dkp system",
    "dkp loot",
    "loot council",
    "raid time%s+%a+/%a+",            -- "raid time Mo/Wed" pattern
    "progress:%s+%a",                 -- "progress: Gruul 2/2, SSC..."
    -- Solo-offer: role + " lf" (with non-letter boundary after lf)
    "tank%s+lf%f[^%a\128-\255]",
    "tanks%s+lf%f[^%a\128-\255]",
    "heal%s+lf%f[^%a\128-\255]",
    "healer%s+lf%f[^%a\128-\255]",
    "healers%s+lf%f[^%a\128-\255]",
    "dps%s+lf%f[^%a\128-\255]",
    "dd%s+lf%f[^%a\128-\255]",
    "melee%s+lf%f[^%a\128-\255]",
    "ranged%s+lf%f[^%a\128-\255]",
    "mdps%s+lf%f[^%a\128-\255]",
    "rdps%s+lf%f[^%a\128-\255]",
    -- Solo-offer: "I'll go" / "ill go" / "im going" — common in chat
    "i'll go", "ill go",
    "i'm going", "im going",
    "ima go",
    -- GM / bug-report / help-request chatter — never LFG
    "bug on", "bug in", "bug with", "bug at",
    "report a bug", "report bug",
    "is broken", "doesn't work", "isn't working", "not working",
    "anyone know",
}
ns.ANTI_LFG_SHORT = { "wts", "wtb", "wtt", "bug" }

-- ---------------------------------------------------------------------------
-- Role detection.  See ROLES_ORDERED comment for the consume strategy.
-- "spd" = "spell DPS" (caster).  We deliberately don't accept bare
-- "melee" or "range" because they appear constantly in distance/combat
-- chatter — require the role suffix.
-- ---------------------------------------------------------------------------

ns.ROLES_ORDERED = { "mdps", "rdps", "tank", "heal", "dps" }

ns.ROLE_TOKENS = {
    mdps = {
        long  = { "melee dps", "mili dps", "melee dd", "mili dd" },
        short = { "mdps", "mdd" },
    },
    rdps = {
        long  = { "ranged dps", "range dps", "ranged dd", "range dd",
                  "spell dps" },
        short = { "rdps", "rdd", "spd" },
    },
    tank = {
        long  = { "tanks", "tanker" },
        short = { "tank" },
    },
    heal = {
        long  = { "healers", "healer", "heals" },
        short = { "heal" },
    },
    dps = {
        long  = { "dpser" },
        short = { "dps", "dd" },
    },
}

-- ---------------------------------------------------------------------------
-- Class mention.  Boolean only — "did someone reference a class/spec".
-- Tokens chosen to be unambiguous: long enough to avoid incidental hits.
-- "bm" is excluded because it collides with Black Morass.
-- ---------------------------------------------------------------------------

ns.CLASS_TOKENS_LONG = {
    "warrior", "paladin", "hunter", "rogue", "priest", "shaman",
    "warlock", "druid",
    "fury", "arms",
    "holy", "retri", "prot",
    "disc", "shadow",
    "feral", "balance", "boomkin", "balon", "resto",
    "elem", "enhance", "enhanc",
    "frost", "arcane",
    "afflic", "demono", "destro",
    "marks", "survi",
}
ns.CLASS_TOKENS_SHORT = {
    "war", "pal", "ret", "fer", "enx", "aff", "demo", "rog",
}

-- ---------------------------------------------------------------------------
-- Compile
-- ---------------------------------------------------------------------------

local function compileShort(list)
    local out = {}
    for _, w in ipairs(list) do
        out[#out + 1] = wordBounded(w)
    end
    return out
end

local function finalize()
    for _, inst in ipairs(ns.INSTANCES) do
        inst.patterns = {}
        for _, p in ipairs(inst.long  or {}) do
            inst.patterns[#inst.patterns+1] = { p = p, o = p }
        end
        for _, w in ipairs(inst.short or {}) do
            inst.patterns[#inst.patterns+1] = { p = wordBounded(w), o = w }
        end
        table.sort(inst.patterns, function(a, b) return #a.p > #b.p end)
    end
    ns.INSTANCE_BY_KEY = {}
    for _, inst in ipairs(ns.INSTANCES) do
        ns.INSTANCE_BY_KEY[inst.key] = inst
    end

    ns.DIFFICULTY_HEROIC = {}
    for _, p in ipairs(ns.DIFFICULTY_HEROIC_LONG)  do ns.DIFFICULTY_HEROIC[#ns.DIFFICULTY_HEROIC+1] = p end
    for _, p in ipairs(compileShort(ns.DIFFICULTY_HEROIC_SHORT)) do
        ns.DIFFICULTY_HEROIC[#ns.DIFFICULTY_HEROIC+1] = p
    end

    ns.DIFFICULTY_NORMAL = {}
    for _, p in ipairs(ns.DIFFICULTY_NORMAL_LONG)  do ns.DIFFICULTY_NORMAL[#ns.DIFFICULTY_NORMAL+1] = p end
    for _, p in ipairs(compileShort(ns.DIFFICULTY_NORMAL_SHORT)) do
        ns.DIFFICULTY_NORMAL[#ns.DIFFICULTY_NORMAL+1] = p
    end

    ns.LFG_MARKERS = {}
    for _, p in ipairs(ns.LFG_MARKERS_LONG)  do ns.LFG_MARKERS[#ns.LFG_MARKERS+1] = p end
    for _, p in ipairs(compileShort(ns.LFG_MARKERS_SHORT)) do
        ns.LFG_MARKERS[#ns.LFG_MARKERS+1] = p
    end

    ns.ANTI_LFG = {}
    for _, p in ipairs(ns.ANTI_LFG_LONG)  do ns.ANTI_LFG[#ns.ANTI_LFG+1] = p end
    for _, p in ipairs(compileShort(ns.ANTI_LFG_SHORT)) do
        ns.ANTI_LFG[#ns.ANTI_LFG+1] = p
    end

    ns.ROLE_PATTERNS = {}
    for _, role in ipairs(ns.ROLES_ORDERED) do
        local entries = {}
        for _, p in ipairs(ns.ROLE_TOKENS[role].long or {}) do
            entries[#entries+1] = { p = p, o = p }
        end
        for _, w in ipairs(ns.ROLE_TOKENS[role].short or {}) do
            entries[#entries+1] = { p = wordBounded(w), o = w }
        end
        table.sort(entries, function(a, b) return #a.p > #b.p end)
        ns.ROLE_PATTERNS[role] = entries
    end

    ns.CLASS_PATTERNS = {}
    for _, p in ipairs(ns.CLASS_TOKENS_LONG)  do
        ns.CLASS_PATTERNS[#ns.CLASS_PATTERNS+1] = p
    end
    for _, w in ipairs(ns.CLASS_TOKENS_SHORT) do
        ns.CLASS_PATTERNS[#ns.CLASS_PATTERNS+1] = wordBounded(w)
    end
end

-- ---------------------------------------------------------------------------
-- Parsing primitives
-- ---------------------------------------------------------------------------

local function findAny(text, patternList)
    for _, p in ipairs(patternList) do
        if text:find(p) then return p end
    end
    return nil
end

local function detectInstance(text)
    for _, inst in ipairs(ns.INSTANCES) do
        for _, entry in ipairs(inst.patterns) do
            if text:find(entry.p) then
                return inst.key, entry.o
            end
        end
    end
    return nil
end

function ns.hasAnyRoleToken(text)
    for _, role in ipairs(ns.ROLES_ORDERED) do
        for _, entry in ipairs(ns.ROLE_PATTERNS[role]) do
            if text:find(entry.p) then return true end
        end
    end
    return false
end

function ns.parseRoles(text)
    local counts = { tank = 0, heal = 0, mdps = 0, rdps = 0, dps = 0 }
    local working = text
    for _, role in ipairs(ns.ROLES_ORDERED) do
        for _, entry in ipairs(ns.ROLE_PATTERNS[role]) do
            local n = working:match("(%d+)%s*x?%s*" .. entry.p)
            if n then
                local count = tonumber(n) or 1
                if count > counts[role] then counts[role] = count end
                working = working:gsub(entry.p, "", 1)
            elseif working:find(entry.p) then
                if counts[role] < 1 then counts[role] = 1 end
                working = working:gsub(entry.p, "", 1)
            end
        end
    end
    return counts
end

function ns.hasClassMention(text)
    return findAny(text, ns.CLASS_PATTERNS) ~= nil
end

-- Group-fill detection: bulletins often include progress markers like
-- "Kara 6/10", "BM HC 4/5", "7/10+++".  We extract { current, target }
-- only when target is a known group/raid size to avoid false hits on
-- timestamps ("20:00") or rolls ("100/100").
--
-- Returns { current = N, target = M } or nil.
local VALID_TARGETS = { [5] = true, [10] = true, [25] = true, [40] = true }

function ns.parseGroupFill(text)
    for c, t in text:gmatch("(%d+)/(%d+)") do
        local current, target = tonumber(c), tonumber(t)
        if target and VALID_TARGETS[target]
           and current and current >= 0 and current <= target then
            return { current = current, target = target }
        end
    end
    return nil
end

function ns.roleMatches(roles, myRole)
    if not myRole or myRole == "any" then return true end
    local total = roles.tank + roles.heal + roles.mdps + roles.rdps + roles.dps
    if total == 0 then return true end  -- recruit-everyone bulletin
    if myRole == "tank" then return roles.tank > 0 end
    if myRole == "heal" then return roles.heal > 0 end
    if myRole == "dps"  then return (roles.dps + roles.mdps + roles.rdps) > 0 end
    if myRole == "mdps" then return roles.mdps > 0 or roles.dps > 0 end
    if myRole == "rdps" then return roles.rdps > 0 or roles.dps > 0 end
    return true
end

function ns.parseMessage(rawMsg)
    if type(rawMsg) ~= "string" or rawMsg == "" then return nil end
    local text = rawMsg:lower()

    if findAny(text, ns.ANTI_LFG) then return nil end

    local instanceKey, alias = detectInstance(text)
    if not instanceKey then return nil end

    -- Short alias (≤ 4 chars) requires either an explicit LFG marker
    -- OR at least one role token in the message.  Long aliases like
    -- "karazhan" / "ramparts" are specific enough to imply LFG intent
    -- by themselves.
    local needsMarker = (#alias <= 4)
    if needsMarker
       and not findAny(text, ns.LFG_MARKERS)
       and not ns.hasAnyRoleToken(text) then
        return nil
    end

    local difficulty
    if findAny(text, ns.DIFFICULTY_HEROIC) then difficulty = "heroic"
    elseif findAny(text, ns.DIFFICULTY_NORMAL) then difficulty = "normal"
    end

    return {
        instance    = instanceKey,
        difficulty  = difficulty,
        alias       = alias,
        roles       = ns.parseRoles(text),
        hasClassReq = ns.hasClassMention(text),
        groupFill   = ns.parseGroupFill(text),  -- nil or { current, target }
    }
end

finalize()
