"""Assemble final addon sound set from test_output/ and user's chosen
variants.  Converts MP3 (ElevenLabs output) → OGG Vorbis mono 22050 32k
(addon format).  Renames variant files to bare snippet keys.  Writes
sounds_data.lua with the SNIPPETS table including per-clip durations
(needed for OnUpdate scheduling — PlaySoundFile has no completion
callback on 2.4.3).
"""
from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys


# User's selected variants — pasted from preview.html export button.
SELECTIONS = {
    "ramp":  "inst_ramp_v1",
    "bf":    "inst_bf_v2",
    "shh":   "inst_shh_v1",
    "sp":    "inst_sp_v1",
    "ub":    "inst_ub_v1",
    "sv":    "inst_sv_v2",
    "mt":    "inst_mt_v3",
    "auch":  "inst_auch_v1",
    "seh":   "inst_seh_v1",
    "sl":    "inst_sl_v1",
    "bot":   "inst_bot_v1",
    "mech":  "inst_mech_v1",
    "arc":   "inst_arc_v1",
    "oh":    "inst_oh_v3",
    "bm":    "inst_bm_v2",
    "mgt":   "inst_mgt_v1",
    "kara":  "inst_kara_v2",
    "gruul": "inst_gruul_v1",
    "magth": "inst_magth_v6",
    "ssc":   "inst_ssc_v2",
    "tk":    "inst_tk_v1",
    "hyjal": "inst_hyjal_v2",
    "bt":    "inst_bt_v3",
    "za":    "inst_za_v3",
    "swp":   "inst_swp_v1",
    "diff_normal":     "diff_normal_v2",
    "role_tank_1":     "role_tank_1_v2",
    "role_tank_2":     "role_tank_2_v2",
    "role_heal_1":     "role_heal_1_v2",
    "role_heal_2":     "role_heal_2_v1",
    "role_dps_1":      "role_dps_1_v1",
    "role_dps_2":      "role_dps_2_v4",
    "role_dps_3":      "role_dps_3_v2",
    "role_dps_4":      "role_dps_4_v4",
    "role_dps_5":      "role_dps_5_v4",
    "role_dps_many":   "role_dps_many_v1",
    "role_melee_1":    "role_melee_1_v4",
    "role_melee_2":    "role_melee_2_v2",
    "role_melee_3":    "role_melee_3_v1",
    "role_ranged_1":   "role_ranged_1_v1",
    "role_ranged_2":   "role_ranged_2_v4",
    "role_ranged_3":   "role_ranged_3_v2",
    "fill_target_25":  "fill_target_25_v2",
}

# Clips that don't have variants — copy as-is (just convert MP3->OGG).
NON_VARIANT = [
    "lfg",
    "diff_heroic",
    "conn_and", "conn_needed", "gen_all_roles",
    "fill_out_of", "fill_target_40",
    "mod_class_req", "mod_fresh", "mod_daily",
] + [f"num_{i}" for i in range(1, 16)]


ROOT = pathlib.Path(__file__).parent
TEST_OUT = ROOT / "test_output"
ADDON_SOUNDS = ROOT / "LFGSpeaker" / "sounds"
SOUNDS_DATA_LUA = ROOT / "LFGSpeaker" / "Snippets.lua"

ADDON_SOUNDS.mkdir(parents=True, exist_ok=True)

if shutil.which("ffmpeg") is None:
    sys.exit("ffmpeg not on PATH")
if shutil.which("ffprobe") is None:
    sys.exit("ffprobe not on PATH")

# loudnorm filter brings each clip up to -14 LUFS integrated loudness
# (broadcast-loud, audible even through WoW's master+sound attenuation)
# with true-peak -1 dB to avoid clipping.  Without this the raw
# ElevenLabs MP3 lands at mean -22 dB which is barely audible at
# typical WoW volume slider settings.
import re as _re

# Output format params (no normalization here — see convert() below).
FFMPEG_OUT_FLAGS = [
    "-c:a", "libvorbis",
    "-b:a", "64k",
    "-ac", "1",
    "-ar", "22050",
]

# Light compression to flatten voice dynamics + bring up quieter parts,
# then volume boost calculated per-file so peak ends up at TARGET_PEAK_DB.
# Result: every clip sits at the same peak ceiling, perceived loudness
# is consistent and as loud as possible without clipping.
TARGET_PEAK_DB = -1.0


def measure_peak_db(src: pathlib.Path) -> float:
    r = subprocess.run(
        ["ffmpeg", "-i", str(src),
         "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    m = _re.search(r"max_volume:\s*(-?[\d.]+)\s*dB", r.stderr)
    return float(m.group(1)) if m else -100.0


def convert(src: pathlib.Path, dst: pathlib.Path) -> None:
    # Pure peak normalization: measure source peak, calculate boost so
    # output peak hits TARGET_PEAK_DB exactly.  No compression — voice
    # dynamics are preserved.  Per-file boost (different for each clip
    # depending on how quietly ElevenLabs rendered it).
    peak = measure_peak_db(src)
    boost = TARGET_PEAK_DB - peak
    boost = max(0.0, min(boost, 30.0))
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-i", str(src),
         "-af", f"volume={boost:.2f}dB",
         *FFMPEG_OUT_FLAGS, str(dst)],
        check=True,
    )


def duration_sec(file: pathlib.Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error",
         "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1",
         str(file)],
        capture_output=True, text=True, check=True,
    )
    return float(r.stdout.strip())


def addon_filename_for(slot_key: str, variant_file: str) -> str:
    """Return bare addon filename (without .ogg) for a slot key + chosen
    variant file.

    Examples:
      ("kara",        "inst_kara_v2")     -> "inst_kara"
      ("role_tank_1", "role_tank_1_v2")   -> "role_tank_1"
      ("diff_normal", "diff_normal_v2")   -> "diff_normal"
      ("fill_target_25", "fill_target_25_v2") -> "fill_target_25"
    """
    if variant_file.startswith("inst_"):
        # Instance variant — strip "_v<n>" suffix
        # variant_file is "inst_<key>_v<n>", target is "inst_<key>"
        parts = variant_file.rsplit("_v", 1)
        return parts[0]
    # Snippet variant — slot_key IS the bare name
    return slot_key


def main() -> int:
    snippets: dict[str, tuple[str, float]] = {}  # key -> (filename, duration)
    missing: list[str] = []

    print("Converting non-variant clips:")
    for key in NON_VARIANT:
        src = TEST_OUT / f"{key}.mp3"
        if not src.exists():
            missing.append(str(src))
            continue
        dst = ADDON_SOUNDS / f"{key}.ogg"
        convert(src, dst)
        dur = duration_sec(dst)
        snippets[key] = (f"{key}.ogg", dur)
        print(f"  {key:20}  {dur:5.2f}s")

    print("\nConverting selected variants:")
    for slot_key, variant_file in SELECTIONS.items():
        src = TEST_OUT / f"{variant_file}.mp3"
        if not src.exists():
            missing.append(str(src))
            continue
        addon_key = addon_filename_for(slot_key, variant_file)
        dst = ADDON_SOUNDS / f"{addon_key}.ogg"
        convert(src, dst)
        dur = duration_sec(dst)
        snippets[addon_key] = (f"{addon_key}.ogg", dur)
        print(f"  {addon_key:20}  {dur:5.2f}s   <-  {variant_file}.mp3")

    if missing:
        print("\nMISSING source files:")
        for m in missing:
            print(f"  {m}")

    # Write Snippets.lua
    lines = [
        "-- AUTO-GENERATED by assemble_addon_sounds.py — do not edit.",
        "-- Re-run the script after changing user's variant selections.",
        "",
        "LFGSpeakerNS = LFGSpeakerNS or {}",
        "local ns = LFGSpeakerNS",
        "",
        "-- Per-clip duration (seconds) used by Core.lua's OnUpdate",
        "-- scheduler to chain snippets — PlaySoundFile has no completion",
        "-- callback on 2.4.3 so we time-out manually.",
        "ns.SNIPPETS = {",
    ]
    for key in sorted(snippets.keys()):
        fname, dur = snippets[key]
        # Lua identifier needs to be valid — all keys here are ASCII safe.
        lines.append(f'    {key:20} = {{ f = "{fname}", d = {dur:.2f} }},')
    lines.append("}")
    lines.append("")
    SOUNDS_DATA_LUA.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nWrote {SOUNDS_DATA_LUA}  ({len(snippets)} snippets)")

    # Also dump JSON for reference / debug
    debug_json = ROOT / "test_output" / "_assembled_snippets.json"
    debug_json.write_text(
        json.dumps({k: {"file": f, "dur": d}
                    for k, (f, d) in sorted(snippets.items())},
                   indent=2),
        encoding="utf-8",
    )

    print(f"\nTotal snippets: {len(snippets)}")
    print(f"Output dir:     {ADDON_SOUNDS}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
