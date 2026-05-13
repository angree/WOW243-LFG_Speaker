# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.4.6] - 2026-05-13 — false-positive fixes

- **Instance disambiguation:** parser now picks the LONGEST matching alias across all instances in a message.  Fixes `"LFM 4 RDPS (Lock, SP, Mage) Gruul"` triggering Slave Pens (sp = Shadow Priest class abbrev here) — now correctly picks Gruul.
- **Guild ad detection:** added `progress XX N/M` (no colon) pattern, `with N static` phrase, and bare word `guild` as anti-LFG markers.  Catches guild ads like `"in PvE guild need players ( progress BT 9/9 ... Hyjal 5/5)"`.  Trade-off: rare "my guild needs X" LFG bulletins get filtered too.

## [0.4.5] - 2026-05-13 — config UI polish

- N/H column letters moved to a dedicated row between group header and the first instance row (no more overlap with header text).
- Slider value labels (`Cooldown: 30s`, `Gap: 70 ms`, `Sender cooldown: 150s`) shifted to 75% of the slider bar — out of the way of the thumb.
- Config panel height tightened (770 → 700) to remove dead space below the instance list.

## [0.4.4] - 2026-05-13 — first public release

Initial public release. Working end-to-end snippet-based TTS announcer.

### Detection
- Parser for 25 TBC instances (16 5-mans + 9 raids).
- Difficulty detection (`heroic`, `normal`, including bracketed short forms `(h)` / `(n)`).
- Role counts: tank, healer, DPS, melee DPS, ranged DPS with explicit number capture (`2 mili dps`, `1 heal`, etc.).
- Group fill detection (`6/10`, `5/25`, etc., restricted to valid raid sizes).
- Class-requested flag (`Enx/Elem/Lock/Fury` etc. raises a boolean — no class is decoded).
- LFG markers: `LFM`, `LFG`, `LF<N>M`, `looking for`, `need`.
- Anti-LFG markers: trade (`WTS`/`WTB`), guild recruitment (`recruiting`, `DKP`, `raid time`, `Progress:`), solo offers (`<role> lf`, `I'll go`, `im going`), bug reports (`bug`, `is broken`, `doesn't work`).

### Playback
- 68 pre-rendered voice clips (ElevenLabs Will voice, eleven_multilingual_v2 model).
- Peak-normalized to -1 dB; OGG Vorbis mono 22050 Hz 64 kbps.
- Runtime sentence composition via `OnUpdate` scheduler.
- Configurable inter-clip gap (default 180 ms, range 0-500 ms).
- Sentence template: `LFG → instance → difficulty → roles+needed → group fill → class-requested`.
- "All roles needed" shortcut when tank + heal + DPS are all listed.

### Filters
- Per-instance N (normal) and H (heroic) independent toggles for 5-mans; single toggle for raids.
- "My role" filter (Any / Tank / Healer / DPS / DPS-Melee / DPS-Ranged).
- Channel groups: Channels, Guild, Group, Local — each toggleable.
- Per-instance cooldown (sentence-level; default 30 s).
- Per-sender cooldown (default 120 s; mutes sound but still logs).

### UI
- Programmatic Config window (700×720) with sliders and grouped checkboxes.
- Draggable minimap button (left = config, right = enable toggle).
- Slash commands: `/lfgspeaker`, `/lfgspeak`, `/lfgs` with `say` / `test` / `parse` / `list` / `log` / `mute` / `unmute` / `cooldown` / `minimap` / `debug` subcommands.
- Optional debug live-feedback prints (off by default).

### Russian support
- Soft dependency on [RussianTranslator](https://github.com/angree/wow243-russiantranslator) via TOC `OptionalDeps`. RT translates Cyrillic chat to English before LFGSpeaker's filter sees it.
- No internal Cyrillic patterns — RT does the translation.

## [0.1.0] - 2026-05-12 — initial scaffold

- Repo bootstrap: `CLAUDE.md`, `WOW_2_4_3_ADDON_GUIDE.md`, `LICENSE`, `README.md`, `.gitignore`, `sync.bat`.
- Addon folder skeleton, no code yet.
