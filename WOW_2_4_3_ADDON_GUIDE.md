# WoW 2.4.3 Addon Development — Deep Reference Guide

Target client: **World of Warcraft: The Burning Crusade, patch 2.4.3 (build 8606)**, released July 15, 2008. This is the final TBC patch and is the standard target for private / emulated TBC servers.

This guide compiles what is allowed, what is forbidden, what exists in 2.4.3 and what does NOT (because it arrived in 3.x WotLK, 4.x Cata, 5.x MoP or later). Everything below is specific to 2.4.3 — do not copy snippets from modern Wowpedia pages without verifying against this document.

---

## 1. TOC file — the contract with the client

### 1.1 Folder & file layout

```
World of Warcraft\Interface\AddOns\<AddonName>\
    <AddonName>.toc          ← REQUIRED; filename must equal folder name
    <AddonName>.lua          ← Lua code
    <AddonName>.xml          ← optional, XML UI
    Bindings.xml             ← optional, auto-loaded, do NOT list in .toc
    Localization.lua         ← optional
    libs\...                 ← optional embedded libraries
```

- Do **not** put version numbers in the folder name (breaks `## Dependencies`).
- Folder name is case-insensitive on Windows but case-sensitive on some emu-server packagers; pick one casing and stick with it.

### 1.2 TOC header fields (2.4.3)

Mandatory line that the 2.4.3 client actually checks:

```
## Interface: 20400
```

- The number is `MMmmpp` → 2.4.0 = `20400`. WoW 2.4.3 clients accept `20400`. Declaring anything `< 20000` makes the client refuse to load the addon; declaring a number higher than the client's build marks the addon "Out of Date" unless the user ticks *Load out of date AddOns* at the character-select screen.
- There is **no** `## Interface: 20403` in real use — the client rounds to minor version. Stay at `20400`.

Commonly-used optional headers (all supported in 2.4.3):

```
## Title: Russian Translator
## Notes: Translate quest/npc text on 2.4.3
## Author: you
## Version: 0.1
## X-Category: Chat & Communication
## X-License: MIT
## Dependencies: OtherAddon            ← hard dep; won't load if missing
## OptionalDeps: Ace3                  ← soft dep; load-order hint only
## LoadOnDemand: 0                     ← 1 = addon stays unloaded until LoadAddOn()
## LoadWith: Blizzard_TradeSkillUI     ← LoD only; piggyback on a Blizz addon
## DefaultState: enabled
## SavedVariables: RT_DB               ← account-wide
## SavedVariablesPerCharacter: RT_CHAR ← per-char, separate file
```

Then list files to load, in order, one per line, **after** the `##` block:

```
libs\LibStub\LibStub.lua
Localization.lua
Core.lua
UI.xml
```

### 1.3 What does NOT exist in 2.4.3

- `## Interface: 30000+` — WotLK-era; on a 2.4.3 client the addon is marked out-of-date.
- Multi-line `## Interface: 20400, 30300` — multi-TOC was added late (Shadowlands). 2.4.3 clients do not parse it.
- Separate `<Name>_<Flavor>.toc` files (`_TBC.toc`, `_Vanilla.toc`, `_Classic.toc`) — also a modern CurseForge / WoW 9.x convention; not read by 2.4.3.
- `## X-Part-Of`, `## X-Embeds` — ignored.
- UTF-8 BOM on the TOC file — breaks parsing on 2.4.3. Save TOC as plain UTF-8 **without BOM** (or ANSI if the file is ASCII-only).

---

## 2. The Lua environment

### 2.1 Language & runtime

- WoW 2.0 upgraded to **Lua 5.1** (vanilla 1.12 ran 5.0). 2.4.3 is Lua 5.1.
- Integer / float distinction: all numbers are doubles; no `//` integer division.
- `setfenv`, `getfenv`, `debug.*` exist but are *taint-generating* — see §5.
- Each loaded Lua file runs in a shared global table `_G` **plus** a private local scope; no `require`, no `package`, no `module`.
- **IMPORTANT — do NOT use `local addonName, ns = ...` on 2.4.3.** That idiom (the addon-name + private-namespace varargs at file top level) was **added in patch 3.0.2 (WotLK, October 2008)**. On a 2.4.3 client the top-level `...` is an empty tuple, so the line silently binds `addonName = nil, ns = nil`. Every subsequent `ns.foo = 1` then errors with `attempt to index nil value 'ns'` — and because `/console scriptErrors` defaults to off, the error is completely invisible. The addon appears "loaded" but nothing runs.
- On 2.4.3, share state between files through a shared-namespace global, and hardcode the addon name where needed:

```lua
-- at the top of every Lua file in the addon
RussianTranslatorNS = RussianTranslatorNS or {}
local ns = RussianTranslatorNS
local addonName = "RussianTranslator"

ns.foo = 1  -- visible to every other file in this addon
```

  Pick a globally unique table name (addon folder name + `NS` suffix is a safe convention) so you do not collide with other addons.

### 2.2 Standard library — what's in the sandbox

Available (safe to call):
- `string.*` — `format`, `sub`, `gsub`, `find`, `match`, `gmatch`, `rep`, `lower`, `upper`, `len`, `byte`, `char`, `reverse`.
  - `string.gmatch` **exists** (renamed from `gfind` in 5.1); old addons sometimes still call `gfind`, which is also aliased for backward compat in 2.4.3.
- `table.*` — `insert`, `remove`, `concat`, `sort`, `wipe` (WoW extension).
- `math.*` — all standard, plus random seeded per session.
- `coroutine.*` — full.
- `bit` library — present (Blizzard-provided, LuaBitOp-style: `bit.band`, `bit.bor`, `bit.bxor`, `bit.lshift`, `bit.rshift`, `bit.arshift`, `bit.bnot`).

Forbidden / not exposed in 2.4.3:
- `io.*` — **not present**. No file I/O from addons, ever.
- `os.*` — only `os.time`, `os.date`, `os.clock`, `os.difftime` exist; no `os.execute`, no `os.getenv`, no `os.remove`.
- `package`, `require`, `dofile`, `loadfile`, `load` with string source — all removed from the sandbox.
- `debug.*` — mostly present but using it taints your execution path.
- `print` — exists but outputs to the DEFAULT chat frame in 2.4.3 (not to a log); use `DEFAULT_CHAT_FRAME:AddMessage` for reliability.

### 2.3 WoW-specific Lua globals you can rely on in 2.4.3

Strings / formatting: `format`, `strsplit`, `strjoin`, `strtrim`, `strlower`, `strupper`, `strsub`, `strlen`, `strmatch`, `strfind`, `gsub`, `tostring`, `tonumber`.

Tables: `table.wipe(t)` and global `wipe(t)` (same); no `table.pack`/`table.unpack` — use `{ ... }` and `unpack`.

Time: `GetTime()` returns seconds since client start (float, monotonic, ~millisecond resolution). `time()` returns Unix-like epoch seconds. `date("%H:%M:%S")` works.

Debug: `geterrorhandler()`, `seterrorhandler()`, `error`, `assert`, `pcall`, `xpcall`.

### 2.4 String handling for Cyrillic / Russian text

- WoW 2.4.3 stores all strings as **UTF-8 bytes**. The client renders them using whatever font is active.
- `string.len`, `string.sub`, `#s` operate on **bytes**, not code points. A Russian character is 2 bytes → `#"Привет"` returns 12, not 6. For character-wise work write a UTF-8 iterator or use a known lib.
- Save every `.lua` file containing Cyrillic as **UTF-8 without BOM**.
- The default Western fonts (`Fonts\FRIZQT__.TTF`) do **not** render Cyrillic. To display Russian text you must either (a) ship a Cyrillic-capable TTF in your addon and call `FontString:SetFont("Interface\\AddOns\\<YourAddon>\\fonts\\<file>.ttf", 12)`, or (b) rely on a ruRU client whose Blizzard fonts already include Cyrillic glyphs. This is the main reason "translator" addons on enUS 2.4.3 clients often ship their own font.
- `GetLocale()` returns one of `enUS`, `enGB`, `deDE`, `frFR`, `esES`, `koKR`, `zhCN`, `zhTW`, `ruRU`. Note: **ruRU was NOT officially supported by Blizzard until WotLK 3.0**. A 2.4.3 client reporting `ruRU` is typically a private-server localised build; do not assume Blizzard-translated global strings exist on it.

---

## 3. Events — the addon programming model

### 3.1 The event loop

Every addon talks to the game by:
1. Creating a frame with `CreateFrame("Frame")`.
2. Registering events on it with `frame:RegisterEvent("EVENT_NAME")`.
3. Installing an `OnEvent` script with `frame:SetScript("OnEvent", fn)`.

In 2.4.3 the handler signature is:

```lua
frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, ...)
    -- 'self' was added in 2.0; pre-2.0 the first arg was the event.
end)
```

`this`, `event`, `arg1`..`arg9` still exist as implicit globals during event dispatch (backward-compat with vanilla-style code) but relying on them is discouraged because they taint. Always use the `(self, event, ...)` signature.

### 3.2 Load lifecycle (exact order in 2.4.3)

1. TOC parsed, files loaded in order, each file's top-level code runs.
2. `ADDON_LOADED` fires once per addon, with `arg1 = addonName`. SavedVariables for that addon are readable from this point.
3. After all non-LoD addons finish, `VARIABLES_LOADED` fires once globally. (In 2.4.3 it is fired *before* `PLAYER_LOGIN`, unlike what some modern guides say.)
4. `PLAYER_LOGIN` fires once when the world starts streaming. All UI frames and talent data are valid.
5. `PLAYER_ENTERING_WORLD` fires on login AND after every zone load / instance transition / UI reload.

Golden rule: register for `ADDON_LOADED`, check `arg1 == myAddonName`, initialise SavedVariables, then `UnregisterEvent("ADDON_LOADED")`.

### 3.3 Events that exist in 2.4.3 (non-exhaustive, most used)

- Player / world: `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_LEAVING_WORLD`, `PLAYER_LOGOUT`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE`, `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `UPDATE_FACTION`.
- Combat log (2.4.3 flavour — **NOT** the unified `COMBAT_LOG_EVENT_UNFILTERED`, that one arrived in 3.0 WotLK): `UNIT_COMBAT`, `CHAT_MSG_COMBAT_*` family, `CHAT_MSG_SPELL_*` family. If you need structured combat data on 2.4.3 you must parse the chat-message events.
- Chat: `CHAT_MSG_SAY`, `CHAT_MSG_YELL`, `CHAT_MSG_PARTY`, `CHAT_MSG_RAID`, `CHAT_MSG_RAID_LEADER`, `CHAT_MSG_RAID_WARNING`, `CHAT_MSG_GUILD`, `CHAT_MSG_OFFICER`, `CHAT_MSG_WHISPER`, `CHAT_MSG_WHISPER_INFORM`, `CHAT_MSG_CHANNEL`, `CHAT_MSG_CHANNEL_JOIN`, `CHAT_MSG_CHANNEL_LEAVE`, `CHAT_MSG_CHANNEL_NOTICE`, `CHAT_MSG_EMOTE`, `CHAT_MSG_TEXT_EMOTE`, `CHAT_MSG_MONSTER_SAY`, `CHAT_MSG_MONSTER_YELL`, `CHAT_MSG_MONSTER_WHISPER`, `CHAT_MSG_MONSTER_EMOTE`, `CHAT_MSG_SYSTEM`, `CHAT_MSG_ADDON`.
- Quest: `QUEST_DETAIL`, `QUEST_PROGRESS`, `QUEST_COMPLETE`, `QUEST_FINISHED`, `QUEST_ACCEPTED`, `QUEST_LOG_UPDATE`, `QUEST_GREETING`, `QUEST_WATCH_UPDATE`, `QUEST_ITEM_UPDATE`, `UI_INFO_MESSAGE`, `UI_ERROR_MESSAGE`.
- Gossip / vendor / mail: `GOSSIP_SHOW`, `GOSSIP_CLOSED`, `MERCHANT_SHOW`, `MERCHANT_CLOSED`, `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `TAXIMAP_OPENED`, `TRAINER_SHOW`.
- Group / raid: `PARTY_MEMBERS_CHANGED`, `RAID_ROSTER_UPDATE`, `PARTY_LEADER_CHANGED`, `PARTY_LOOT_METHOD_CHANGED`.
- Inventory / bags: `BAG_UPDATE`, `BAG_UPDATE_COOLDOWN`, `UNIT_INVENTORY_CHANGED`, `ITEM_LOCK_CHANGED`.
- Spellbook / actions: `SPELLS_CHANGED`, `LEARNED_SPELL_IN_TAB`, `UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_STOP`, `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_INTERRUPTED`, `UNIT_SPELLCAST_FAILED`, `UNIT_SPELLCAST_DELAYED`, `UNIT_SPELLCAST_CHANNEL_START`, `UNIT_SPELLCAST_CHANNEL_STOP`.
- Violations: `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`, `MACRO_ACTION_BLOCKED`, `MACRO_ACTION_FORBIDDEN`.

### 3.4 Events that do NOT exist in 2.4.3

Common mistakes when copying modern code:

- `COMBAT_LOG_EVENT_UNFILTERED` / `COMBAT_LOG_EVENT` — arrived in 3.0 (WotLK). Use the per-line `CHAT_MSG_*` events on 2.4.3.
- `NAME_PLATE_UNIT_ADDED` / `NAME_PLATE_UNIT_REMOVED` — added in 6.0 (WoD). For nameplates in 2.4.3 you must hook `WorldFrame` children and look for `NamePlateXYZ`-named or unnamed frames with a specific child-widget layout.
- `ENCOUNTER_START` / `ENCOUNTER_END` — added in 5.x.
- `GROUP_ROSTER_UPDATE` — added in 5.0; use `PARTY_MEMBERS_CHANGED` + `RAID_ROSTER_UPDATE`.
- `PLAYER_SPECIALIZATION_CHANGED`, `TALENT_GROUP_CHANGED` — talent specs are Cataclysm+. 2.4.3 has a single linear talent tree per char.
- `CHAT_MSG_BN_*` (Battle.net Whisper) — 3.3+.
- `UPDATE_MOUSEOVER_UNIT` **does** exist in 2.4.3, good for hover-detection.
- Most `LFG_*` events — 3.3+; 2.4.3 has the old meeting-stone LFG API only.

---

## 4. Frames, widgets, XML — the UI layer

### 4.1 Frame types available in 2.4.3 via `CreateFrame(frameType, name, parent, template)`

`Frame`, `Button`, `CheckButton`, `EditBox`, `GameTooltip`, `MessageFrame`, `Minimap`, `Model`, `PlayerModel`, `DressUpModel`, `TabardModel`, `MovieFrame`, `ScrollFrame`, `ScrollingMessageFrame`, `SimpleHTML`, `Slider`, `StatusBar`, `ColorSelect`, `WorldFrame` (single instance, do not create).

LayoutFrame-only (cannot be `CreateFrame`'d; only exist inside XML or via a parent-frame method): `Texture`, `FontString`, `Line` (does not exist; Line widget was added ~8.x — use rotated/stretched textures on 2.4.3), `MaskTexture` (added later).

### 4.2 Frame type additions that are NOT in 2.4.3

- `Cooldown` — **does exist** in 2.4.3 (used by action buttons).
- `Browser` — added in 8.x; unavailable.
- `OffScreenFrame` — Dragonflight; unavailable.
- `ModelScene` / `ModelSceneActor` — Legion+; unavailable. Use the simple `Model` / `PlayerModel` instead.
- `Line` — unavailable.
- `AnimationGroup` / `Animation` — **arrived in 3.0.2 (WotLK)**, NOT in 2.4.3. You cannot declare `<Animations>` in XML on 2.4.3. Implement tween / fade with `OnUpdate` driving `SetAlpha`.

### 4.3 Template system

`inherits="Name1,Name2"` (comma-separated multiple inheritance) was added in 2.0 so it's fine in 2.4.3. Useful Blizzard templates that exist in 2.4.3:

- `UIPanelButtonTemplate`, `UIPanelButtonGrayTemplate`, `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `InputBoxTemplate`.
- `GameTooltipTemplate`.
- Secure: `SecureActionButtonTemplate`, `SecureUnitButtonTemplate`, `SecurePartyHeaderTemplate`, `SecureRaidGroupHeaderTemplate`, `SecureHandlerClickTemplate` (added 2.0 with later refinement), `SecureHandlerBaseTemplate`.

Templates that do NOT exist on 2.4.3:
- `BackdropTemplate` — added in 9.0.1. In 2.4.3 every `Frame` **natively** supports `SetBackdrop`, `SetBackdropColor`, `SetBackdropBorderColor`. Do NOT `Mixin(frame, BackdropTemplateMixin)` — it will error.
- `NamePlateFullBorderTemplate`, `UIDropDownMenuTemplate` is available, but `UIDropDownMenuTemplate2` and later variants are retail.

### 4.4 Anchoring

Fully supported: `SetPoint("TOPLEFT", parent, "BOTTOMLEFT", x, y)` with points `TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT, BOTTOMLEFT, BOTTOM, BOTTOMRIGHT`. `ClearAllPoints`, `GetPoint`, `GetNumPoints` all work. `SetAllPoints([frame])` works.

`SetSize(w, h)` is a modern single-call convenience; on 2.4.3 use `SetWidth(w); SetHeight(h)` (though `SetSize` was also added in 2.0, test if unsure).

### 4.5 Scripts (widget script handlers)

Available in 2.4.3: `OnLoad`, `OnShow`, `OnHide`, `OnUpdate(self, elapsed)`, `OnEvent`, `OnEnter`, `OnLeave`, `OnMouseDown`, `OnMouseUp`, `OnMouseWheel(self, delta)`, `OnClick`, `OnDoubleClick`, `OnKeyDown`, `OnKeyUp` (only when `EnableKeyboard(true)`), `OnChar`, `OnDragStart`, `OnDragStop`, `OnReceiveDrag`, `OnEnterPressed`, `OnEscapePressed`, `OnTabPressed`, `OnTextChanged`, `OnEditFocusGained`, `OnEditFocusLost`, `OnValueChanged` (Slider), `OnColorSelect`, `OnAnimFinished` — wait, no, animation handlers don't exist (see §4.2).

Use `hooksecurefunc("FunctionName", myCallback)` to post-hook Blizzard API without breaking secure propagation (added 2.0.1).

### 4.6 Textures and fonts

- `frame:CreateTexture([name, layer, inheritsFrom, subLevel])` — works.
- Texture:`SetTexture(path)` accepts BLP files (native) and TGA/PNG with limits. In 2.4.3 the client accepts only BLP1 and BLP2 textures; **PNG files are ignored**. Convert art to BLP.
- `SetVertexColor(r,g,b[,a])`, `SetTexCoord(l,r,t,b)`, `SetBlendMode("BLEND"|"ADD"|"ALPHAKEY"|"DISABLE"|"MOD")` all available.
- `FontString:SetFont(path, size, flags)` flags: `"OUTLINE"`, `"THICKOUTLINE"`, `"MONOCHROME"` (combine space-separated).
- TTFs must be placed inside your addon folder and referenced with `Interface\\AddOns\\<Addon>\\fonts\\<x>.ttf` (the client accepts double-backslash Windows-style paths; forward slashes also work on 2.4.3).
- The 2.4.3 client **cannot** load OTF fonts. Stick with TTF.

### 4.7 XML UI — quick shape

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">

    <Script file="Core.lua"/>

    <Frame name="RT_MainFrame" parent="UIParent" toplevel="true" movable="true" enableMouse="true" hidden="true">
        <Size x="400" y="300"/>
        <Anchors><Anchor point="CENTER"/></Anchors>
        <Backdrop bgFile="Interface\DialogFrame\UI-DialogBox-Background"
                  edgeFile="Interface\DialogFrame\UI-DialogBox-Border" tile="true">
            <BackgroundInsets><AbsInset left="11" right="12" top="12" bottom="11"/></BackgroundInsets>
            <TileSize><AbsValue val="32"/></TileSize>
            <EdgeSize><AbsValue val="32"/></EdgeSize>
        </Backdrop>
        <Scripts>
            <OnLoad>RT_MainFrame_OnLoad(self)</OnLoad>
            <OnDragStart>self:StartMoving()</OnDragStart>
            <OnDragStop>self:StopMovingOrSizing()</OnDragStop>
        </Scripts>
    </Frame>
</Ui>
```

`$parent` inside `name=""` attributes substitutes the parent's name — useful inside templates.

---

## 5. Secure execution, taint, combat lockdown

This is the subject that trips up every new TBC addon author.

### 5.1 Why the system exists

Blizzard introduced the protection model in 1.10 and massively expanded it in 2.0 (the start of TBC). Goal: prevent addons from reproducing automated bot-like behaviour — auto-casting, auto-moving, auto-targeting, rotating raid frames in combat, etc.

### 5.2 Terminology

- **Secure code**: code that came from Blizzard-shipped FrameXML / `Blizzard_*` addons.
- **Insecure / tainted code**: anything any addon loads, plus the execution path after any value derived from insecure code is used by secure code.
- **Protected function**: a WoW API function that may only be called by secure code.
- **Protected frame**: a frame whose critical attributes (visibility, size, anchors, SecureActionButton `type`/`unit`/`spell` attributes) may only be modified by secure code while the player is in **combat lockdown**.
- **Combat lockdown**: the interval between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`. `InCombatLockdown()` returns true during it.

### 5.3 What addons CAN do, always

- Create frames, anchor, size, show, hide — **outside combat**.
- Register events, read state (unit HP, buffs, inventory, quests, channels).
- Filter / print chat messages.
- Modify FontStrings, Textures.
- Write SavedVariables.
- Open trade, open mail *(only after user interaction)*.
- React to the user clicking a SecureActionButton you set up before combat.

### 5.4 What addons CANNOT do, ever (always-forbidden)

- Move the character (`MoveForwardStart`, `TurnLeftStart`, `JumpOrAscendStart` — all blocked).
- Call `TargetUnit("name")` from Lua outside a secure click.
- Call `CastSpellByName`, `UseAction`, `PickupSpell`, `PickupAction` from plain Lua.
- Set `FocusUnit` arbitrarily.
- Reload the UI without user confirmation via a non-interactive path (ReloadUI() itself works, but other addons' popups may interfere).

Violation → `ADDON_ACTION_FORBIDDEN` fires, player sees the red "Interface Action Blocked" popup with your addon name.

### 5.5 What addons CANNOT do IN COMBAT

- Show / hide a protected frame (action bars, unit frames, secure buttons).
- Change a SecureActionButton's `type`, `unit`, `spell`, `macrotext`, `action`, `target-unit` attributes.
- Move a protected frame (`SetPoint`, `ClearAllPoints`).
- Call `SetBinding*` family, modify key bindings.
- Call `SetMacroBody`, create or delete macros.
- Set CVars that are tagged sensitive.

Violation → `ADDON_ACTION_BLOCKED` fires; nothing happens for that call, game keeps running.

### 5.6 The taint rules, in plain words

1. Every value has a *taint level*: secure or insecure.
2. Reading a value from a tainted table taints the reader.
3. Calling a function with any tainted argument taints the function's execution.
4. Once the call stack is tainted, any *protected* action invoked on it is refused.
5. Writing to a table member with tainted code taints that member (and sometimes propagates to the whole table for secure-path reads).
6. **`hooksecurefunc`** lets you run your code AFTER Blizzard's without tainting theirs — it's the only allowed way to observe protected functions. You cannot replace / pre-hook them without tainting.

Practical pitfalls that cause taint in 2.4.3:
- Overwriting a Blizzard global with your own function: `ChatFrame_OnEvent = myFn` → **do not**. Use `ChatFrame_AddMessageEventFilter` or `hooksecurefunc`.
- Using `setfenv` on a Blizzard function.
- Iterating `_G` and calling methods on every frame.
- Reading `C_...` tables (they don't exist in 2.4.3 anyway).
- Modifying entries of `SecureActionButtonTemplate`-derived frames' attribute tables during combat.

### 5.7 Secure action buttons — the allowed bridge

To let a user cast, target, or use an item via your UI:

```lua
local btn = CreateFrame("Button", "RT_CastBtn", UIParent, "SecureActionButtonTemplate")
btn:SetSize(80, 22)
btn:SetPoint("CENTER")
btn:SetAttribute("type", "spell")          -- or "macro", "item", "target"
btn:SetAttribute("spell", "Fireball")
btn:RegisterForClicks("AnyUp")
```

Set attributes **before combat**; in combat the attribute setter is blocked. Use `SecureHandlerStateTemplate` + `RegisterStateDriver` (exists in 2.4.3) if attributes must change based on combat/stance — state is driven by secure snippets (Restricted Environment Lua, small dialect) that Blizzard evaluates.

---

## 6. SavedVariables

- Files: `WTF\Account\<ACCOUNT>\SavedVariables\<Addon>.lua` (account) and `WTF\Account\<ACCOUNT>\<server>\<character>\SavedVariables\<Addon>.lua` (per-char).
- Variables listed in `## SavedVariables` and `## SavedVariablesPerCharacter` are **global Lua names**. They are written out on clean logout / reloadui / /console exit. A client crash loses anything not yet written.
- 2.4.3 serialises Lua tables naively; non-table non-string non-number keys are dropped silently.
- **Don't** store functions or frames — they won't serialise.
- Init pattern (run inside `ADDON_LOADED` for your addon name):

```lua
RT_DB = RT_DB or {}
RT_DB.version = RT_DB.version or 1
RT_DB.enabled = (RT_DB.enabled ~= false)  -- default true
```

- Migrations: bump a `version` field and transform old data during init.

---

## 7. Slash commands

2.4.3 pattern (unchanged since vanilla):

```lua
SLASH_RT1 = "/rt"
SLASH_RT2 = "/translator"
SlashCmdList["RT"] = function(msg, editBox)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "toggle" then RT.Toggle()
    elseif cmd == "config" then RT.OpenConfig()
    else print("|cff55ddff[RT]|r /rt toggle|config") end
end
```

The key is any unique uppercase string; `SLASH_<KEY><N>` sets command aliases, `SlashCmdList[<KEY>]` sets the handler.

---

## 8. Chat handling — the translator's bread and butter

Incoming chat messages arrive as `CHAT_MSG_*` events. Their arguments in 2.4.3:

```
arg1: text (UTF-8)
arg2: senderName
arg3: languageName  -- "Common", "Orcish", "Русский" on ruRU...
arg4: channelName
arg5: targetName
arg6: flags         -- "GM", "DEV", ...
arg7: zoneChannelID
arg8: channelIndex
arg9: channelBaseName
arg10: (unused / lineID, added later)
arg11: guidLike     -- not a proper GUID on 2.4.3; may be empty
```

### 8.1 Filtering / rewriting chat

`ChatFrame_AddMessageEventFilter` was added in **2.4**, so it exists in 2.4.3. Filter functions can mutate or suppress messages before they reach the chat windows.

**CRITICAL — filter signature on 2.4.3 is different from modern.** On 2.4.3 the callback receives ONLY the chat-event args: `function(msg, sender, language, channelName, target, flags, zoneChannelID, channelIndex, channelBaseName)`. There is **no `self`** and **no `event` name** passed. Modern retail signature `(self, event, msg, sender, ...)` was added in WotLK/Cata — using it on 2.4.3 shifts every positional arg by two, so `msg` gets the sender, `sender` gets the language, and events like `CHAT_MSG_SYSTEM` that have no sender cause a nil-arg crash inside your code (often visible as "bad argument #N to format").

Confirmed by reading a working TBC addon (`Timed/Modules/Chat.lua`):

```lua
function Timed.ChatFilter(msg)
    if Timed.filter then return true end
    return false, msg
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", Timed.ChatFilter)
```

Because the event name is not passed to the callback, close over it at registration time:

```lua
local function FilterImpl(eventName, msg, ...)
    local newMsg = RT.Translate(msg)
    if not newMsg then return false end          -- pass through
    return false, newMsg, ...                    -- replace msg, keep the rest
end

for _, ev in ipairs({"CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_CHANNEL",--[[...]]}) do
    local eventName = ev                          -- capture in closure
    ChatFrame_AddMessageEventFilter(ev, function(msg, ...)
        return FilterImpl(eventName, msg, ...)
    end)
end
```

Return contract (same across versions):
- `return true` → drop message entirely.
- `return` (nothing) or `return false` → pass through unchanged.
- `return false, msg, ...` → replace the args (you must return every arg you want to keep).

Wrap filter bodies in `pcall` — one error inside a filter taints the chat frame until `/reload`.

### 8.2 Sending addon-to-addon data

`SendAddonMessage(prefix, text, channel [, target])` exists in 2.4.3. Channels: `"PARTY"`, `"RAID"`, `"GUILD"`, `"BATTLEGROUND"`, `"WHISPER"` (+ target). Limits: prefix ≤ 16 chars, message ≤ 255 chars (combined). **There is no `RegisterAddonMessagePrefix` in 2.4.3** — it was added in MoP (5.1). On 2.4.3, you just listen for `CHAT_MSG_ADDON` and filter by prefix yourself; all prefixes are delivered.

### 8.3 Rendering rewritten text

When you rewrite chat to include Cyrillic on a non-ruRU client, you must ensure a Cyrillic-capable font is applied to the chat FontStrings. Hook `ChatFrame1`..`ChatFrame7`:

```lua
for i = 1, NUM_CHAT_WINDOWS do
    local f = _G["ChatFrame"..i]
    f:SetFont("Interface\\AddOns\\RT\\fonts\\PTSans.ttf", select(2, f:GetFont()), select(3, f:GetFont()))
end
```

Redo on `UPDATE_CHAT_WINDOWS` and `CVAR_UPDATE`.

---

## 9. Hooking Blizzard UI safely

Three tools, from safest to most invasive:

1. **`hooksecurefunc("FuncName", callback)`** — your callback runs after the original, return value ignored, secure chain preserved. Good for: observing state changes (e.g. `QuestFrame_OnShow`).
2. **Frame script post-hooks** — `frame:HookScript("OnShow", myFn)` runs your fn after any existing script. Does NOT taint.
3. **`frame:SetScript("OnShow", myFn)`** — replaces the script. Breaks Blizzard behaviour. Avoid on frames you didn't create.

Never do `_G.OriginalBlizzardFunction = myFunc` — classic vanilla "pre-hook" pattern breaks security in TBC.

---

## 10. Libraries available in 2.4.3

### 10.1 LibStub + Ace3

- **LibStub** is a tiny (~20 lines) version-stub loader, published before 2.0; runs fine on 2.4.3. It's the entry point for all modern libraries.
- **Ace3** (AceAddon-3.0, AceEvent-3.0, AceDB-3.0, AceConsole-3.0, AceGUI-3.0, AceConfig-3.0, AceLocale-3.0, AceTimer-3.0, AceHook-3.0, AceComm-3.0, AceSerializer-3.0) — Ace3 was designed through 2007-2008 and was fully TBC-compatible. Embed it under `libs\` or as an external dependency. Almost every TBC-era community addon uses it.
- **Ace2** still exists but is deprecated even in TBC; new code should use Ace3.
- **CallbackHandler-1.0** — required by most Ace3 libs; ship alongside.

### 10.2 LibBabble-* family

`LibBabble-Zone-3.0`, `LibBabble-Class-3.0`, `LibBabble-Race-3.0`, `LibBabble-Faction-3.0`, `LibBabble-SubZone-3.0` — all available for 2.4.3 era. They provide client-locale ↔ English mapping for zone / class / race names and include a `ruRU` table. Useful for a translator to look up canonical names.

### 10.3 Libraries you may want for a translator

- **LibStub** + **CallbackHandler-1.0** — foundation.
- **AceAddon-3.0** — addon object lifecycle.
- **AceEvent-3.0** — clean `:RegisterEvent` / `:UnregisterEvent` on self.
- **AceDB-3.0** — profiled SavedVariables with defaults.
- **AceLocale-3.0** — localisation tables.
- **AceConfig-3.0** + **AceGUI-3.0** — options panel.
- **LibDeformat-3.0** — reverse-engineer `GlobalStrings.lua` format strings, invaluable for pulling structured data out of localised server messages.

### 10.4 Libraries that will NOT work on 2.4.3

- Anything referencing `C_Timer` (`C_Timer.After`, `C_Timer.NewTicker`) — added in 5.4. Use `AceTimer-3.0` or an `OnUpdate` accumulator.
- Anything referencing `C_ChatInfo.*`, `C_Container.*`, `C_Item.*`, `C_QuestLog.*` — post-Legion.
- `LibSharedMedia-3.0` works, but its modern bundled files may use features you don't need; any version ≥ r80 tagged WotLK-compatible is fine.

---

## 11. Version-compat cheat sheet — "does this exist in 2.4.3?"

| Feature / API                                   | 2.4.3? | Notes                                                                 |
|-------------------------------------------------|:------:|------------------------------------------------------------------------|
| Lua 5.1                                         |   ✔    | Since 2.0.                                                            |
| `hooksecurefunc`                                |   ✔    | Since 2.0.1.                                                          |
| `InCombatLockdown`                              |   ✔    | Core TBC.                                                             |
| `ChatFrame_AddMessageEventFilter`               |   ✔    | Added in 2.4.                                                         |
| Secure templates (SecureActionButton, etc.)     |   ✔    | Since 2.0.                                                            |
| `SetCVar`                                       |   ✔    | 3rd arg `scriptCVar` for `CVAR_UPDATE` exists in 2.4.3.               |
| `RegisterStateDriver` / SecureHandlerXxxTemplate|   ✔    | Added in 2.x; refinements in 3.x, but core exists.                    |
| `AnimationGroup` / `<Animations>` XML           |   ✘    | Added 3.0.2. Use `OnUpdate` + `SetAlpha`/`SetPoint`.                  |
| `COMBAT_LOG_EVENT_UNFILTERED`                   |   ✘    | 3.0. Parse `CHAT_MSG_*` combat events.                                |
| `CombatLogGetCurrentEventInfo`                  |   ✘    | 7.x.                                                                  |
| `C_Timer.After` / `NewTicker`                   |   ✘    | 5.4. Use `AceTimer-3.0`.                                              |
| `C_ChatInfo.SendAddonMessage`                   |   ✘    | 8.0. Use global `SendAddonMessage`.                                   |
| `RegisterAddonMessagePrefix`                    |   ✘    | 5.1. Not needed on 2.4.3 — all prefixes delivered.                    |
| `NAME_PLATE_UNIT_ADDED` event                   |   ✘    | 6.0.                                                                  |
| `GetSpellInfo(id)` by numeric id                |   ✔    | Since 2.0; returns `(name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange)`. |
| `GetItemInfo`                                   |   ✔    | Returns 10 values in 2.4.3 (no `expansionID`, `setID`, `isCraftingReagent`). |
| `UnitAura` / `UnitBuff` / `UnitDebuff`          |   ✔    | Return tuple is shorter than modern; no `spellId` field on 2.4.3 — you get name/rank/icon/count/debuffType/duration/expirationTime only. |
| `GetTalentInfo`                                 |   ✔    | Single active spec.                                                   |
| Dual spec / `GetActiveTalentGroup`              |   ✘    | 3.1.                                                                  |
| Achievements API                                |   ✘    | 3.0.                                                                  |
| Mounts journal, companion journal               |   ✘    | Mounts/pets are plain spells/items in 2.4.3.                          |
| LFG tool (the modern one)                       |   ✘    | 3.3. 2.4.3 has meeting-stone LFG only.                                |
| Glyphs / runeforging                            |   ✘    | 3.0 / 3.1.                                                            |
| Transmog                                        |   ✘    | 4.3.                                                                  |
| `BackdropTemplate` mixin                        |   ✘    | 9.0. `SetBackdrop` is native on every Frame in 2.4.3.                 |
| `Mixin()` helper                                |   ✘    | Added 7.0. Write manual copy-loops.                                   |
| `Enum.*` constants                              |   ✘    | Post-Legion.                                                          |
| `PNG` / `OTF` assets                            |   ✘    | BLP + TTF only.                                                       |
| Multi-TOC (`Interface: 20400, 30300`)           |   ✘    | Shadowlands+.                                                         |
| LibStub / Ace3                                  |   ✔    | Standard.                                                             |
| Multiple inherits in XML (comma-sep)            |   ✔    | Since 2.0.                                                            |
| `CreateFrame("Cooldown", ...)`                  |   ✔    | Native.                                                               |
| `CreateFrame("Line", ...)`                      |   ✘    | Added much later.                                                     |

---

## 12. Practical recipe: a minimal 2.4.3 addon skeleton

**RussianTranslator.toc**

```
## Interface: 20400
## Title: Russian Translator
## Notes: Translates incoming chat to Russian on a 2.4.3 client
## Author: (you)
## Version: 0.1.0
## SavedVariables: RT_DB
## SavedVariablesPerCharacter: RT_CHAR

libs\LibStub\LibStub.lua
libs\AceAddon-3.0\AceAddon-3.0.lua
libs\AceEvent-3.0\AceEvent-3.0.lua
Localization.lua
Core.lua
UI.xml
```

**Core.lua**

```lua
local addonName, ns = ...
local RT = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0")
ns.RT = RT

local defaults = { enabled = true, fontPath = "Interface\\AddOns\\"..addonName.."\\fonts\\PTSans.ttf" }

function RT:OnInitialize()
    RT_DB = RT_DB or {}
    for k,v in pairs(defaults) do if RT_DB[k] == nil then RT_DB[k] = v end end
    SLASH_RT1 = "/rt"
    SlashCmdList["RT"] = function(msg) self:OnSlash(msg) end
end

function RT:OnEnable()
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY",     function(...) return self:Filter(...) end)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL",    function(...) return self:Filter(...) end)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(...) return self:Filter(...) end)
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyFonts")
    self:ApplyFonts()
end

function RT:ApplyFonts()
    for i = 1, NUM_CHAT_WINDOWS do
        local f = _G["ChatFrame"..i]
        local _, size, flags = f:GetFont()
        f:SetFont(RT_DB.fontPath, size, flags)
    end
end

function RT:Filter(chatFrame, event, msg, sender, ...)
    if not RT_DB.enabled or not msg or msg == "" then return false end
    local translated = self:Translate(msg)
    if not translated or translated == msg then return false end
    return false, translated, sender, ...
end

function RT:Translate(msg)
    -- TODO: plug in dictionary / remote service result
    return msg
end

function RT:OnSlash(msg)
    if msg == "toggle" then
        RT_DB.enabled = not RT_DB.enabled
        DEFAULT_CHAT_FRAME:AddMessage("|cff55ddff[RT]|r "..(RT_DB.enabled and "ON" or "OFF"))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff55ddff[RT]|r /rt toggle")
    end
end
```

---

## 13. Debugging on 2.4.3

- `/console scriptErrors 1` — show the red error popup.
- `/dump expr` and `/run code` — arrive later. 2.4.3 has only `/script <code>` and `/run` (added late vanilla). No `/dump`. Use `DEFAULT_CHAT_FRAME:AddMessage(tostring(val))` or ship a tiny dump helper.
- **BugSack / BugGrabber** — TBC-compatible versions exist; highly recommended.
- **Swatter** (Norganna) — alternative error catcher, still has 2.4.3-era releases.
- `geterrorhandler()` lets you capture errors from your own `pcall`s.
- There is no Blizzard `/api` command or in-game API browser in 2.4.3. Keep Wowpedia archive tabs open.
- **Crucial**: `/reload` (a.k.a. `ReloadUI()`) is cheap in 2.4.3; use it liberally while iterating. SavedVariables are flushed on reload.

---

## 14. Shipping & distribution notes

- Private-server users install by copying `<Addon>` folder into `Interface\AddOns\`. No Curse / CurseForge client uptake on 2.4.3 realms.
- Zip the folder at the correct level — the ZIP should expand to `<Addon>\<Addon>.toc`, not to a wrapper directory.
- Line endings: 2.4.3 Lua loader accepts both LF and CRLF. BOM on Lua files is OK (the loader tolerates it) but BOM on the `.toc` is **not**.
- No code-signing, no manifest, no checksums.

---

## 15. Gotchas specific to a Russian-translator addon on 2.4.3

1. **Font**: ship a Cyrillic-capable TTF; apply to all `NUM_CHAT_WINDOWS` chat frames and re-apply after `PLAYER_LOGIN`, `UPDATE_CHAT_WINDOWS`, `CVAR_UPDATE`.
2. **Byte vs char length**: never use `#msg` or `string.sub(msg, 1, N)` to truncate — you will split a UTF-8 sequence and produce mojibake. Write a UTF-8-safe `sub`.
3. **Outgoing messages**: if you *send* translated text back to the server (e.g. with `SendChatMessage`), 2.4.3 servers cap chat length to 255 bytes. Cyrillic is 2 bytes/char, so budget ~127 chars. Split on word boundaries.
4. **Language channel detection**: `arg3` of `CHAT_MSG_SAY/YELL` gives the in-game language ("Common", "Orcish"). The server will have already enforced language obfuscation on the text itself — you can only translate what you can read.
5. **Quest text**: `GetQuestText`, `GetObjectiveText`, `GetQuestDescription`, `GetGossipText` all return plain strings at the moment their respective frames open. Hook `QUEST_DETAIL`, `QUEST_PROGRESS`, `QUEST_COMPLETE`, `GOSSIP_SHOW` events, read those globals, overwrite `QuestFrame`'s FontStrings before the user sees them.
6. **Tooltip text**: `GameTooltip` exposes `GameTooltipTextLeft1` .. `GameTooltipTextLeftN` (and similar Right). Walk them on `OnTooltipSetUnit`/`OnTooltipSetItem`/`OnTooltipSetSpell` and rewrite — but never on *every* `OnUpdate`, or you will tank frame rate.
7. **Network translation**: the 2.4.3 client has **no HTTP API**. You cannot call Google Translate from Lua. Options:
   - Ship a bundled dictionary / phrase-book.
   - Use an out-of-process helper (separate desktop app) that writes a translation file the addon reads via SavedVariables on `/reload` — awkward but occasionally done.
   - Accept that translation is static/offline on 2.4.3.
8. **Secure concerns**: translating chat is entirely insecure territory; you will not touch protected frames. You're safe as long as you don't taint FrameXML globals.

---

## 16. One-line summary

You are writing Lua 5.1 for a sandboxed, no-I/O, no-HTTP client. You get a Blizzard-defined event bus and a Blizzard-defined widget tree. You may observe everything and rewrite chat; you may build any UI you like out of cold frames and textures; you may not move the character, cast spells, or change secure frames in combat. Build the UI out-of-combat, use `SecureActionButtonTemplate` for anything the user must *click* to cast, keep Cyrillic text on a Cyrillic-capable font, and never copy-paste modern retail snippets without checking §11 first.

---

## Sources

Research for this document was compiled from:

- Wowpedia / Warcraft Wiki — Patch 2.0.1 API changes, Secure Execution and Tainting, InCombatLockdown, CreateFrame, ChatFrame_AddMessageEventFilter, hooksecurefunc, Saving variables between game sessions, Creating a slash command, AddOn loading process, Localizing an addon, Getting the current interface number, Widget API.
- WoWWiki Archive (Fandom) — UI XML tutorial, UIOBJECT Frame, GameTooltip, Widget API.
- AddOn Studio — WoW:Creating a WoW AddOn, WoW:UI XML tutorial, WoW:XML templates, WoW:TOC format, WoW:Slash commands, WoW:API CreateFrame, WoW:API hooksecurefunc, WoW:API SetCVar, WoW:Events A-Z, WoW:World of Warcraft API.
- WowAce — Ace3 Getting Started, AceLocale-3.0 API docs, LibBabble-* project pages.
- Wowhead — Patch 2.4.0 and 2.4.3 patch notes.
- GitHub — ElvUI-TBC/ElvUI (!Compatibility/api/wowAPI.lua), RichSteini/NotPlater, nullfoxh/PlateBuffer, tomtko/tbc-addons, MetaIsNull/EntropyDrums.
- Community threads on WoWInterface, Tukui, MMO-Champion, OwnedCore regarding TBC addon quirks, taint, and chat filtering.
