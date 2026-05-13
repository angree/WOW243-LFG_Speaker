# LFGSpeaker

Audio announcer for LFG (Looking-For-Group) bulletins on **World of Warcraft 2.4.3** (The Burning Crusade, build 8606). Listens to chat channels for recruitment messages and reads them out loud — *"LFG. Karazhan. One healer needed. Five out of ten."* — so you can hear what's scrolling past Global without watching every line.

> **Target client:** WoW 2.4.3 only.

![version](https://img.shields.io/badge/version-0.4.7-blue)
![interface](https://img.shields.io/badge/interface-20400-orange)
![license](https://img.shields.io/badge/license-MIT-green)

## What it does

When chat receives a message that looks like an LFG bulletin, the addon:

1. Parses the message into structured fields — instance, difficulty (normal / heroic), role counts (tank / healer / DPS / melee DPS / ranged DPS), group fill (e.g. `6/10`), class-requested flag.
2. Filters by your settings — instance enabled, difficulty enabled, role-you-play matches, channel-group enabled, sender not in cooldown.
3. Composes a spoken sentence out of short pre-rendered voice clips and plays them sequentially through the WoW sound engine.

Example bulletin → spoken output:

| Chat message | Spoken |
|---|---|
| `LFM tank,heal,dps BM HC` | LFG. Black Morass, heroic. All roles needed. |
| `LF 2 dps and 1 heal Karazhan 6/10` | LFG. Kara-zan. One healer, and two DPS, needed. Six out of ten. |
| `LFM Hyjal 12/25` | LFG. Hi-yal Summit. Twelve out of twenty five. |
| `LFM SHH (normal) tank/dps` | LFG. Shattered Halls, normal. One tank, and one DPS, needed. |
| `LFM Sunwell 5/25 class requested` | LFG. Sunwell Plateau. Five out of twenty five. Class requested. |

## Companion to RussianTranslator

Russian chat is handled by the sister addon [RussianTranslator](https://github.com/angree/wow243-russiantranslator). When RT is loaded (TOC declares it as `OptionalDeps`), it rewrites Russian messages with an English prefix before our filter sees them — so a bulletin like *"Рампы об нид танк"* arrives at LFGSpeaker as *"Ramparts, need tank"* and matches normally.

Without RT installed, raw Russian messages are not matched. RT is effectively required for Russian-speaking realms.

## Supported instances (25)

5-mans: Hellfire Ramparts, Blood Furnace, Shattered Halls, Slave Pens, Underbog, Steamvault, Mana-Tombs, Auchenai Crypts, Sethekk Halls, Shadow Labyrinth, The Botanica, The Mechanar, The Arcatraz, Old Hillsbrad Foothills, Black Morass, Magisters' Terrace.

Raids: Karazhan, Gruul's Lair, Magtheridon, Serpentshrine Cavern, Tempest Keep, Hyjal Summit, Black Temple, Zul'Aman, Sunwell Plateau.

Each 5-man has independent Normal / Heroic toggles. Raids have a single toggle (no difficulty distinction in TBC).

## Voice

Pre-rendered using **ElevenLabs** with the **Will - Relaxed Optimist** voice (no character multiplier) and `eleven_multilingual_v2` model. Clips are peak-normalized to -1 dB and encoded as OGG Vorbis (mono, 22050 Hz, 64 kbps). 68 short clips total (~1 MB).

Snippet inventory:

- Prefix: `LFG.`
- 25 instance names (each with comma at end for sentence flow)
- Difficulty: `heroic.` / `normal.`
- Roles + counts: tank 1-2, healer 1-2, DPS 1-5 (plus "many DPS" for 5+), melee 1-3, ranged 1-3
- Connectors: `and`, `needed.`, `all roles needed.`
- Numbers 1-15 (for group fill `X out of Y`)
- Targets: `twenty five.`, `forty.`, `out of`
- Modifiers: `class requested.`, `fresh,`, `daily.`

## Slash commands

All three aliases work identically: `/lfgspeaker`, `/lfgspeak`, `/lfgs`.

| Command | Effect |
|---|---|
| `/lfgs` | Open the config window |
| `/lfgs on` / `off` | Master enable / disable |
| `/lfgs say <text>` | Parse + compose + play the sentence (testing tool) |
| `/lfgs test <snippet>` | Play a single snippet by key (e.g. `/lfgs test inst_kara`) |
| `/lfgs parse <text>` | Dry-run the parser, show what would be composed (no sound) |
| `/lfgs list` | List all 68 snippets with durations |
| `/lfgs log [N]` | Last N matched bulletins (default 10), with reason for play / skip |
| `/lfgs mute <instance>` | Mute one instance key (e.g. `/lfgs mute bm`) |
| `/lfgs unmute <instance>` | |
| `/lfgs cooldown <sec>` | Set the global per-sound cooldown |
| `/lfgs minimap` | Toggle the minimap button |
| `/lfgs debug on` / `off` | Verbose error reporting |

## Config window

Open with `/lfgs` or left-click the minimap button.

- **Enable LFGSpeaker** — master switch.
- **Debug: print matches to chat** — when on, every parsed bulletin is echoed to chat with its detection result. Off by default; turn on while tuning.
- **Per-sound cooldown** (5-300 s) — minimum time between the same instance/difficulty sentence playing again.
- **Snippet gap** (0-500 ms) — silence between voice clips when composing a sentence. Lower = snappier, higher = more spoken-word pace.
- **Per-sender sound cooldown** (0-600 s) — same player's bulletins are silenced (sound only) for this long after their last play. Default 120 s catches typical 30-second re-spam.
- **My role** (Any / Tank / Healer / DPS / DPS-Melee / DPS-Ranged) — when set to anything other than Any, only bulletins requesting that role (or with no specific role) trigger a sound.
- **Listen on** — toggle entire channel groups: Channels (public channels like Global, Trade), Guild + Officer, Group (Party / Raid / BG), Local (Say / Yell).
- **Instances** — three columns, each 5-man has two ticks `[N] [H]` (normal / heroic, independent). Raids have a single tick.

## Minimap button

A draggable button appears at the edge of the minimap.

- **Left-click:** toggle config window.
- **Right-click:** toggle the addon enabled / disabled.
- **Drag:** move it around the minimap edge. Position persists.

## Anti-spam filters

The parser deliberately *does not* match:

- Trade chat: `WTS`, `WTB`, `WTT`.
- Solo offers: `tank lf`, `dps lf`, `healer lf`, `I'll go`, `im going`, `ima go`. These are individual players looking for a group, not recruiters.
- Guild recruitment ads: `guild is recruiting`, `recruiting players`, `recruiting active`, `join our guild`, `DKP system`, `raid time Mo/Wed`, `Progress: …`.
- Bug-report chatter: anything containing `bug`, `is broken`, `doesn't work`, `not working`, `anyone know`, `report a bug`.

If a message hits any of these markers, it's silently dropped even if it otherwise looks like a valid bulletin.

## Installation

1. Download the latest `wow243-lfgspeaker-vX.Y.Z.zip` from [Releases](https://github.com/angree/WOW243-LFG_Speaker/releases) and extract so that you get an `LFGSpeaker` folder inside `World of Warcraft\Interface\AddOns\`.
2. (Optional but recommended for ruRU realms) Install [RussianTranslator](https://github.com/angree/wow243-russiantranslator) alongside.
3. Launch WoW, ensure the addon is enabled in the character-select AddOns list, log in.
4. On first login you should see:
   ```
   [LFGS] LFGSpeaker v0.4.7 — made by Grzegorz Korycki (Poczwarka)
   [LFGS] build 2026-05-13
   [LFGS] type /lfgs help, /lfgs to open config, /lfgs say <text> to test composition
   ```
5. Type `/lfgs say LFM Kara 1 healer` to verify the audio chain.

If you hear nothing, check that WoW's **Sound Effects** channel is enabled and the **Sound** volume slider is up — `PlaySoundFile` on 2.4.3 routes through that channel and has no per-addon volume control.

## Sister project

[wow243-russiantranslator](https://github.com/angree/wow243-russiantranslator) by the same author — the Russian → English chat translator that this addon relies on for Russian-speaking realms.

## License

[MIT](LICENSE) © 2026 Grzegorz Korycki.
