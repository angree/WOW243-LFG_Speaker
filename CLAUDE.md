# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project goal

**LFG (Looking-For-Group) bulletin board addon for World of Warcraft 2.4.3 (The Burning Crusade, build 8606) — TTS-on-detection.** Listens to chat events, matches Russian/English LFG recruitment messages against an instance/role pattern set, and plays a pre-recorded TTS sound clip when a match is detected. Built for Russian-speaking TBC private servers (primary target: **Moonwell x5**) where Russian chat dominates and the user wants audio cues without having to read every line.

**Companion script approach is impossible** — WoW 2.4.3 `/chatlog` (LoggingChat) only flushes the buffer to `WoWChatLog.txt` on clean logout or `/reload`. No live IPC. So all TTS must be **pre-baked OGG/MP3 files bundled with the addon**, triggered by in-game `PlaySoundFile`.

**Iteration model**: ship a base set of sound clips for the 30-50 most common LFG patterns, then analyse user's saved chat log after sessions to find missed bulletins and add new sounds + patterns.

## Sister project: Russian Translator

This addon is designed to coexist with **wow243-russiantranslator** (the user's other project at `i:\PROGRAMOWANIE_CLAUDE\Addon_Russian_Translator\`, GitHub `angree/wow243-russiantranslator`). When RussianTranslator is installed, this addon reads its translation output via the shared global `RussianTranslatorNS` namespace (soft dependency — works without it too, just patterns must match Cyrillic directly).

Integration point: RussianTranslator exposes (or will expose) `RussianTranslatorNS.TranslatePublic(rawMsg)` returning the English translation, or nil if the message wasn't Russian. We call that first, then run pattern matching on the English text — which is way easier than matching declined Russian noun forms.

If RussianTranslator isn't loaded, fall back to matching against the raw Cyrillic message directly — patterns must include the most common Russian word forms (нужен танк, ищем хила, etc.).

## CRITICAL: read `WOW_2_4_3_ADDON_GUIDE.md` first

**Before writing any Lua/XML/TOC**, read `WOW_2_4_3_ADDON_GUIDE.md` in this repo. Its §11 compatibility table is the source of truth for what APIs/events/templates exist on 2.4.3. Don't copy snippets from modern Wowpedia — many APIs that look documented there (`C_*` namespace, `COMBAT_LOG_EVENT_UNFILTERED`, `C_Timer`, `AnimationGroup`, `BackdropTemplate`, multi-line `## Interface`, `Mixin`, `Enum`, `RegisterAddonMessagePrefix`) **do not exist on 2.4.3 and will silently break or error**.

## Hard 2.4.3 constraints (do not forget — these cost hours each in the sister project)

### Source files

- **TOC files**: single line `## Interface: 20400`, UTF-8 **without BOM**, blank line between metadata and file list. A BOM character at the start of the .toc silently breaks parsing.
- **Lua files**: UTF-8 **without BOM**. Lua 5.1 sandbox. No `io`, no `package`, no `os.execute`, no network.
- **Namespace pattern**: NEVER write `local addonName, ns = ...` at file top. That tuple is empty on 2.4.3 and fails silently (the `...` returning addon name + namespace was added in WotLK 3.0.2). Use **shared global table**:
  ```lua
  LFGReaderNS = LFGReaderNS or {}
  local ns = LFGReaderNS
  ```
  Same pattern in every file. They all see the same shared table.

### Chat filter signature

```lua
-- WRONG (modern, post-3.0):
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(self, event, msg, ...) end)

-- RIGHT (2.4.3):
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(msg, ...) end)
```

No `self`, no `event`. If you need to know which event fired, capture it via closure at registration time:

```lua
local function buildFilter(eventName)
    return function(msg, ...) return filterImpl(eventName, msg, ...) end
end
for _, ev in ipairs(EVENTS) do
    ChatFrame_AddMessageEventFilter(ev, buildFilter(ev))
end
```

### Tables silently truncate at 262,144 entries

Lua 5.1 on 2.4.3 has a hard cap of **2^18 = 262,144** entries per table. Inserts past that are dropped with no error. The sister project hit this with a 500k-entry dictionary; the solution was **multiple sub-tables iterated at lookup time**. We probably won't hit it here (few hundred sound mappings max) but be aware.

### TOC file-list is cached at client start

`/reload` re-runs Lua but does NOT re-read the TOC's file list. When you **ADD, REMOVE, or RENAME** a file in the TOC's file list, the user must **full-restart the client** (or toggle the addon at the character-select screen + reload). Editing existing file contents only? `/reload` is enough.

This bit the sister project hard during chunked-dict development. Mention it upfront whenever you tell the user to test a change that involves new files.

### XML loader via TOC doesn't work reliably

The sister project tried using `.xml` for frame definitions and ran into silent-load failures across multiple TBC clients. **Use plain `.lua` and create frames programmatically** via `CreateFrame`. There is no need for XML in a pre-baked-TTS addon.

### No `C_Timer.After`

For delayed actions (e.g., cooldown on repeated sound, throttling): use an `OnUpdate` accumulator. Pattern:

```lua
local f = CreateFrame("Frame")
local elapsed = 0
f:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed > 5 then
        -- do something every 5s
        elapsed = 0
    end
end)
```

Or for one-shot delay:

```lua
local function After(seconds, fn)
    local f = CreateFrame("Frame")
    local t = 0
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t >= seconds then self:SetScript("OnUpdate", nil); fn() end
    end)
end
```

### No combat-log subscription

`COMBAT_LOG_EVENT_UNFILTERED` was added in 3.0. Subscribe to `CHAT_MSG_SPELL_*` and friends if needed. For this addon we only care about chat events, so this is informational.

### `print` exists but is unreliable in early sessions

Use a `Msg(...)` helper that writes via `DEFAULT_CHAT_FRAME:AddMessage` with a colour prefix. Wrap all diagnostic `Msg` in `pcall` — a Lua error inside a registered event handler will silently abort the rest of the handler chain on 2.4.3.

## Hard pitfalls specific to this addon (PlaySoundFile, sounds bundle)

### Sound file format

- **OGG Vorbis** (`.ogg`) — recommended. Best size, supported.
- **MP3** — supported but heavier and rarely better than OGG for voice.
- **WAV** — supported but ENORMOUS for voice (uncompressed). Avoid for >1s clips.
- **OGG Opus** — NOT supported. Pre-2010 codec era. Convert Opus → Vorbis before bundling.
- Voice TTS: **mono, 22050 Hz, 32-48 kbps Vorbis**. ~30-60 KB per 2-3s clip. Bundling 50 clips → ~3 MB total addon size. Acceptable.

### Sound file paths

Use forward slashes or escaped backslashes in Lua strings — but Blizzard's API wants Windows-style paths:

```lua
PlaySoundFile("Interface\\AddOns\\LFGReader\\sounds\\kara_tank.ogg")
-- or
PlaySoundFile([[Interface\AddOns\LFGReader\sounds\kara_tank.ogg]])
```

Long-bracket literals (`[[...]]`) avoid the double-backslash mess. Prefer them for path literals.

### Sound file names

- **ASCII only.** Cyrillic in filenames fails to load on 2.4.3 client. Use transliterated names (`kara_tank.ogg`, not `кара_танк.ogg`).
- **Case-insensitive on Windows** (which is what TBC clients run on for end users). Don't rely on case differences.
- **No spaces** — replace with underscores. Spaces in paths break on some 2.4.3 versions.

### `PlaySoundFile` return value

On 2.4.3 the API returns nothing useful (no handle to stop the sound). On modern WoW it returns `(willPlay, soundHandle)` — DO NOT depend on this on 2.4.3. To "stop" a sound mid-play you can't; just don't trigger a new one until the previous finished (use cooldown logic on call-side).

### Volume

`PlaySoundFile` plays at the **Master sound volume** on 2.4.3. No per-call volume control. The user can adjust their game's master/ambient/sound sliders. We can add a `db.volumeLevel` only as documentation ("turn your sound up").

### `PlaySoundFile` is not blocked by the addon-blocked-action mechanism

Unlike `SendChatMessage` (which is taint-checked), `PlaySoundFile` works fine in any context — combat lockdown irrelevant.

## Why pre-baked instead of live TTS

Companion / external-process TTS would be ideal (read live chat → speak via SAPI/edge-tts/Azure) but is structurally impossible on 2.4.3:

1. **`/chatlog` (LoggingChat) only flushes on logout or /reload**, not in real time. The buffer accumulates in memory and writes once. A Python script tailing `WoWChatLog.txt` would see chat with minutes-to-hours of latency.
2. **No alternative IPC.** Lua sandbox has no `io`, no socket, no exec. SavedVariables file is also only written on logout/reload.
3. **No screen-OCR loophole.** Chat frame text isn't extractable from outside the process without OCR, which is brittle and slow.

So all TTS must be **pre-rendered to disk before the user plays**, and the addon's job is just **pattern-match → trigger sound**.

The iteration loop is then:
1. Ship 30-50 base sound clips covering common LFG patterns.
2. User plays sessions on Moonwell.
3. On logout, `WoWChatLog.txt` has all chat including LFG bulletins.
4. We analyse the log offline to find: (a) bulletins we missed entirely (no pattern matched), (b) bulletins that matched a pattern but had no corresponding sound (e.g., new instance/role combo).
5. Add patterns + generate new sounds + sync to game.
6. Repeat.

## Architecture (target)

```
LFGReader/
├── LFGReader.toc           single-line ## Interface: 20400, no BOM
├── Core.lua                event registration, chat filter, cooldown logic
├── Patterns.lua            instance/role pattern table (ns.PATTERNS)
├── Sounds.lua              pattern-key → sound file map (ns.SOUNDS) + cooldown defaults
└── sounds/
    ├── kara_tank.ogg
    ├── kara_dps.ogg
    ├── kara_heal.ogg
    ├── gruul.ogg
    ├── magth.ogg
    ├── ssc.ogg
    ├── tk.ogg
    ├── hyjal.ogg
    ├── bt.ogg
    └── ...                 ~50 base clips
```

### Pattern table format

```lua
ns.PATTERNS = {
    -- { match (string.find pattern), tag, soundKey }
    { "karazhan",  "kara",  "kara"  },   -- English (after RT translates)
    { "кара",      "kara",  "kara"  },   -- Cyrillic fallback (when RT isn't loaded)
    { "gruul",     "gruul", "gruul" },
    { "грул",      "gruul", "gruul" },
    -- ... role qualifiers narrow further:
    { "karazhan.*tank",  "kara_tank", "kara_tank" },
    { "kara.*heal",      "kara_heal", "kara_heal" },
    -- etc
}
```

Match logic: **most-specific first** (longest pattern wins). Sorted at load by pattern length descending. Same trick as Russian Translator's `PHRASE_ORDER`.

### Sound mapping with cooldown

```lua
ns.SOUNDS = {
    kara      = { file = "kara.ogg",      cooldownSec = 30 },
    kara_tank = { file = "kara_tank.ogg", cooldownSec = 30 },
    gruul     = { file = "gruul.ogg",     cooldownSec = 60 },
    -- ...
}
```

Per-key cooldown to avoid spam. Default 30s. A bulletin that re-matches the same sound within cooldown is logged-only, not played.

### Event hooking

Subscribe to LFG-relevant chat events:

- `CHAT_MSG_CHANNEL` — the LookingForGroup channel + Global + Trade etc.
- `CHAT_MSG_YELL` — sometimes pugs yell their bulletins
- `CHAT_MSG_GUILD` and `CHAT_MSG_OFFICER` — guild LFG
- `CHAT_MSG_PARTY` and `CHAT_MSG_RAID*` — direct invites

For each event, run the same pipeline:
1. Get translated text (RT or raw Cyrillic).
2. Lower-case it.
3. Match against `PATTERNS` (most-specific first).
4. On match: check cooldown for that sound key. If past cooldown, `PlaySoundFile` + update last-played timestamp.

### Slash command

```
/lfgreader  or  /lfg
  /lfg on   off                enable/disable
  /lfg test <instance>         play a sound by key (e.g. /lfg test kara_tank)
  /lfg cooldown <sec>          set global cooldown override
  /lfg list                    list known patterns + last-fire times
  /lfg log                     recent matched bulletins (last 20)
  /lfg mute <key>              mute a specific sound key
  /lfg unmute <key>
  /lfg vol <0-100>             adjust play volume (if supported on this client; logs note otherwise)
```

### SavedVariables

```lua
LFGR_DB = {
    enabled        = true,
    cooldownGlobal = 30,
    mutedKeys      = { kara_dps = true, ... },
    lastFireTimes  = { kara = 1714521234, ... },
    matchLog       = { { t=..., msg=..., key=... }, ... },  -- ring buffer 100 entries
}
```

## Sound generation workflow

External Python helper `generate_sounds.py` at repo root. Recommended TTS engine: **edge-tts** (Microsoft Neural voices via free Edge TTS API). Best free quality, no API key.

```bash
pip install edge-tts
```

```python
# generate_sounds.py (sketch)
import asyncio, edge_tts, subprocess, pathlib, json

VOICE = "en-US-AriaNeural"          # natural female voice
OUT_DIR = pathlib.Path("LFGReader/sounds")

PHRASES = {
    "kara":       "Karazhan",
    "kara_tank":  "Karazhan, tank needed",
    "kara_heal":  "Karazhan, healer needed",
    "kara_dps":   "Karazhan, DPS needed",
    "gruul":      "Gruul's Lair",
    # ...
}

async def main():
    for key, text in PHRASES.items():
        out = OUT_DIR / f"{key}.ogg"
        # edge-tts outputs MP3; convert via ffmpeg to OGG Vorbis
        tmp = OUT_DIR / f"{key}.mp3"
        await edge_tts.Communicate(text, VOICE).save(str(tmp))
        subprocess.run([
            "ffmpeg", "-y", "-i", str(tmp),
            "-c:a", "libvorbis", "-b:a", "32k", "-ac", "1", "-ar", "22050",
            str(out)
        ], check=True)
        tmp.unlink()
        print(f"  {key}: {out}")

asyncio.run(main())
```

Run once per dictionary expansion. Commit the resulting `.ogg` files to the repo (under `LFGReader/sounds/`). Distribution: clone or download release ZIP; `.ogg` files travel with the addon.

Alternative TTS engines (if user prefers):
- **piper-tts** (offline, fast, MIT) — `pip install piper-tts` + voice model. Good for hundreds of phrases without rate limits.
- **gTTS** (Google Translate TTS, free) — `pip install gtts`. Lower quality, very fast, no key.
- **Azure Cognitive Services Speech** — best quality, paid, requires API key.

Recommend **edge-tts** for v1 (good quality, free, no key, low setup).

## Russian-language LFG patterns to cover

For pattern matching: include both transliterated and Cyrillic forms. Common Russian LFG vocabulary (from sister-project's dictionary):

### Roles
- танк / танка / танку / танком  → tank
- хил / хила / хилка / хилу / хилом  → healer
- дд / двадэ / два дэ / dps  → DPS
- мил / милешник  → melee
- кд / кастер / каст  → caster

### Recruiting verbs
- ищу / ищем / нужен / нужны / нужно / надо  → looking for, need
- набираем / собираем / открыт набор  → recruiting
- инв в пм / го в пм  → invite to whisper

### Common instances (Russian + English)
| Russian | English | Suggested key |
|---------|---------|---------------|
| Каражан / Кара / КА | Karazhan | kara |
| Грулл / Грул | Gruul's Lair | gruul |
| Магтеридон / Магт | Magtheridon | magth |
| Серпентшир / ССК / СШ | Serpentshrine | ssc |
| Крепость Бурь / ТК / Око | Tempest Keep | tk |
| Хиджал / ХС | Hyjal Summit | hyjal |
| Чёрный Храм / БТ | Black Temple | bt |
| Зул'Аман / ЗА | Zul'Aman | za |
| Зул'Гуруб / ЗГ | Zul'Gurub | zg |
| Молтен Кор / МК | Molten Core | mc |
| Логово Крыла Тьмы / БВЛ | Blackwing Lair | bwl |
| Логово Ониксии | Onyxia | onyx |
| Шпиль Чёрной Горы / БРД | Blackrock Depths | brd |
| Стратхольм / Страт | Stratholme | strat |
| Гробница / Узилище | Auchindoun (Mana-Tombs/Sethekk/Arcatraz) | tombs/sethekk/arcatraz |
| Шадоу Лабиринт / ШЛ | Shadow Labyrinth | shadowlab |
| Underbog / Топи Силы | Underbog | underbog |
| Sethekk Halls / Сеттекские Залы | Sethekk Halls | sethekk |
| ... | ... | ... |

A starter dictionary of ~50 base patterns + 30 instance keys × 3 roles ≈ ~150 sound clips for full coverage. v1 ship: ~30 most common keys.

## TOC file (target)

```
## Interface: 20400
## Title: LFG Reader (TTS)
## Notes: Plays audio cue when an LFG bulletin matches a known instance pattern
## Author: Grzegorz Korycki (Poczwarka)
## Version: 0.1.0
## OptionalDeps: RussianTranslator
## SavedVariables: LFGR_DB

Patterns.lua
Sounds.lua
Core.lua
```

`OptionalDeps` ensures RussianTranslator (if installed) loads BEFORE us, so `RussianTranslatorNS` is available when our `PLAYER_LOGIN` fires.

## Build / sync / release workflow

No build step. Iteration:

1. **Edit** Lua/sound files in `I:\GITHUB\WOW_LFG_Reader\LFGReader\`.
2. **`sync.bat`** → `robocopy /MIR` to `C:\Gry\World of WarcraftOLD\Interface\AddOns\LFGReader\`.
   - Cross-volume (I: → C:) means `mklink /J` isn't possible.
3. **`/reload`** in-game picks up Lua + sound changes.
   - TOC changes (new sound file added to TOC list? — they're NOT in TOC, only Lua is) — full client restart only if TOC's file list changes.
   - Adding new `.ogg` files to `sounds/` does NOT require TOC change because Lua references them by path, not TOC declaration. So `/reload` is enough.
4. **`/lfg test <key>`** to verify a specific sound plays.
5. **Errors** via `/console scriptErrors 1` or BugSack/BugGrabber.

### Release ritual (when ready to publish on GitHub)

When the addon is stable enough to publish:

1. Edit `LFGReader/LFGReader.toc` `## Version: X.Y.Z`.
2. Add a `## [X.Y.Z] - YYYY-MM-DD` block to `CHANGELOG.md`.
3. Update version badge in `README.md`.
4. `sync.bat` → WoW (sanity check).
5. `git commit`, `git tag -a vX.Y.Z -m "..."`.
6. `powershell Compress-Archive LFGReader → releases/wow243-lfgreader-vX.Y.Z.zip`.
7. `git push origin main && git push origin vX.Y.Z`.
8. `gh release create vX.Y.Z releases/*.zip --title "..." --notes-file .release_notes_tmp.md`.

### CRITICAL — never use `@<word>` in any GitHub-visible text

NEVER include `@WoW`, `@Poczwarka`, or any `@someword` in commit messages, release titles, release notes, README, CHANGELOG, TOC author field, or the in-game startup message. GitHub parses `@word` as a user mention and pings whoever owns that GitHub username. The sister project once burned a history rewrite because `Poczwarka @WoW` in a commit pinged `github.com/wow`. The rule is enforced via memory: write `(Poczwarka)` with parens, never `@Poczwarka`.

## Code conventions

- Shared-global namespace at top of every Lua file:
  ```lua
  LFGReaderNS = LFGReaderNS or {}
  local ns = LFGReaderNS
  ```
- No `Mixin`, no `Enum.*`, no `C_*` namespace.
- No animation XML. Tweens via `OnUpdate` + `SetAlpha`/`SetPoint`.
- `hooksecurefunc` only for Blizzard globals, never `rawset`.
- Use `Msg(...)` helper for user-facing messages — wrap in pcall, prefix with colour code (e.g., `|cffff8800[LFG]|r`).
- Comments explain **why** (constraints, past bugs, non-obvious choices). NOT **what** (the code shows that).
- Files end with `\n`, no trailing whitespace.

## What to push back on if the user asks

- **Live TTS via HTTP / external process** — impossible on 2.4.3 sandbox; only pre-baked.
- **`C_*` namespace** — doesn't exist on 2.4.3.
- **Streaming sound from URL** — `PlaySoundFile` only takes addon-local paths.
- **Speech recognition / voice input** — no microphone API on any WoW client.
- **Multi-flavour TOC** (`Interface-Classic: 11302`) — Shadowlands+.
- **Modern Lua features** (`goto`, `<const>`, integer division `//`) — Lua 5.1 only.

## Russian Translator integration (technical)

When `RussianTranslator` addon is installed and loaded:

```lua
local function getEnglish(msg)
    if RussianTranslatorNS and type(RussianTranslatorNS.TranslatePublic) == "function" then
        local en = RussianTranslatorNS.TranslatePublic(msg)
        if en then return en end
    end
    return nil  -- fall back to Cyrillic matching
end
```

**Note**: at the time of writing, `RussianTranslatorNS.TranslatePublic` does not yet exist as a public API. The Russian Translator addon translates messages internally via `ChatFrame_AddMessageEventFilter`, which mutates the message before it reaches subsequent filters. Two options:

1. **Register our filter AFTER RT's** — addon load order determines filter order. Set `## OptionalDeps: RussianTranslator` and rely on RT registering first. Then our filter receives the already-translated text. Verify this with `/lfg test` and trace order.
2. **Call RT's public function** — patch RT to expose `TranslatePublic(rawMsg)` in `RussianTranslatorNS`. Then call it explicitly regardless of filter order. More explicit; less load-order risk. Adds ~5 lines to RT.

**Recommended**: prefer option 2 — patch RT to expose `TranslatePublic`. It's a tiny, non-invasive change in RT and gives us a stable contract.

If neither works (RT not installed, function missing), the addon falls back to matching `PATTERNS` against the raw message, which works for Cyrillic LFG ads because pattern entries include both English and common Russian word forms.

## Ongoing workflow when the user returns

1. Pull fresh `C:\Gry\World of WarcraftOLD\Logs\WoWChatLog.txt`.
2. Run an `analyze_lfg.py` script (to be written): identifies chat lines that LOOK like LFG bulletins (heuristics: contains role words `танк/хил/дд/tank/heal/dps`, instance words, recruiting verbs, `+1/+2/+3` markers, `LF/LFM` prefix). Reports which ones matched a sound key vs which ones went unmatched.
3. For each missed bulletin, decide:
   - Is it a known instance with a different surface form? → add new pattern entry, no new sound needed.
   - Is it a new instance/event combo? → add pattern AND generate new sound via `generate_sounds.py`.
4. Sync, `/reload`, test in-game with `/lfg test <key>`.
5. If stable, bump version and release.

## Sister-project hard-earned wisdom (do not relearn)

The Russian Translator project (the user's other addon) burned multi-hour debugging sessions on each of these. Avoid all of them here:

1. **`local x, ns = ...` at file top** — fails silently on 2.4.3. Use shared-global pattern.
2. **Chat filter signature** — `function(msg, ...)`, NO self, NO event. Close over event name at registration.
3. **TOC file-list caching** — `/reload` does NOT re-read TOC. Add/remove/rename a TOC-listed file → user must full-restart client.
4. **Lua table size 262,144 cap** — silent truncation. Not relevant here (sound count is tiny) but know about it.
5. **Phrase substring matching without word boundaries** — the sister project had a bug where the phrase `и то` (4 chars) substring-matched mid-word, eating letters from adjacent words. If we ever do phrase matching against Cyrillic message text, **enforce word boundaries via byte-level letter detection** (UTF-8 multibyte bytes 0x80-0xFF + ASCII letters count as "word").
6. **Multi-gloss dictionary values** — Wiktionary-style "fuck, bang, screw" comma lists rendering as a multi-word soup. We don't have this problem here (one phrase → one sound) but be aware.
7. **`@word` in GitHub text** — pings random GitHub users. Forbidden everywhere.
8. **Add visible BUILD STAMP** when diagnosing reload issues so the user can see code actually changed. E.g., `>>> LFG-BUILD: 2026-05-12 v0.2.3 <<<` in the load message. Removable when stable.
9. **Wrap diagnostic `Msg()` calls in `pcall`** — 2.4.3 silently aborts event handlers on Lua errors.
10. **Sync to local WoW folder FIRST, GitHub only after user verifies in-game.** The user has been burned by broken GitHub releases — they prefer iterative local testing.

## Memory references (carry over from sister project)

These project-wide truths from the sister project apply here too. If you have access to the user's auto-memory at `C:\Users\Admin\.claude\projects\`, you'll see entries like:
- WoW 2.4.3 install path is `C:\Gry\World of WarcraftOLD\`
- User plays Moonwell x5 (ruRU TBC), NOT WoWCircle
- Polish communication, direct/blunt, Windows-only
- Never `@word` in git/GitHub text
- Sync to WoW folder locally first, GitHub only after user confirmation

If you DON'T have those memories (new Claude Code session), the rules above are encoded in this CLAUDE.md — follow them.
