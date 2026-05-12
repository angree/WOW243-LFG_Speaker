"""Generate full snippet set + HTML preview for LFGSpeaker.

- Generates every snippet (with multiple phonetic variants for known
  ambiguous instance names) using ElevenLabs Will voice (1x multiplier).
- Builds preview.html that lets the user:
    * pick a preferred variant per ambiguous instance (radio button)
    * play any single clip
    * play 10 example "composed" sentences using current variant choices,
      via plain JS Audio() sequencing (no server required for relative
      paths in same directory)
- If a browser blocks local audio (some Chrome configs), run
  `python -m http.server 8765` in test_output/ and open
  http://localhost:8765/preview.html — or use serve.bat.

Outputs to test_output/ (gitignored).
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import sys
import time
from html import escape as eschtml

try:
    import requests
except ImportError:
    sys.exit("pip install requests")

ROOT = pathlib.Path(__file__).parent
OUT_DIR = ROOT / "test_output"
OUT_DIR.mkdir(exist_ok=True)

VOICE_ID = "bIHbv24MWmeRgasZH58o"          # Will - Relaxed Optimist (1x)
MODEL_ID = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_128"
API_URL = (
    f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    f"?output_format={OUTPUT_FORMAT}"
)


def get_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if key:
        return key.strip()
    secret = ROOT / ".secrets" / "elevenlabs.md"
    if secret.exists():
        m = re.search(r"sk_[A-Za-z0-9_]+", secret.read_text(encoding="utf-8"))
        if m:
            return m.group(0)
    sys.exit("set ELEVENLABS_API_KEY or put key in .secrets/elevenlabs.md")


# -- Instance variants -------------------------------------------------------
# Comma at end of every instance name (user feedback: instance is a
# continuation, not a sentence end).  Multiple variants only where
# default English TTS reading is known to diverge from WoW canonical.

INSTANCE_VARIANTS = {
    # Single-variant entries expanded to 3: comma / period / no-punctuation.
    # Different endings give TTS different prosody — comma = continuation,
    # period = full-stop fall, no-punct = neutral.  User picks the one
    # where Will's ending intonation flows best into next clip.
    "ramp":  ["Hellfire Ramparts,", "Hellfire Ramparts.", "Hellfire Ramparts"],
    "bf":    ["Blood Furnace,", "Blood Furnace.", "Blood Furnace"],
    "shh":   ["Shattered Halls,", "Shattered Halls.", "Shattered Halls"],
    "sp":    ["Slave Pens,", "Slave Pens.", "Slave Pens"],
    "ub":    ["Underbog,", "Underbog.", "Underbog"],
    "sv":    ["Steamvault,", "Steam Vault,"],
    "mt":    ["Mana-Tombs,", "Mana Tombs,", "Mana-Toombs,"],
    "auch":  ["Auchenai Crypts,", "Aukenai Crypts,"],
    "seh":   ["Sethekk Halls,", "Sethek Halls,", "Seh-thek Halls,"],
    "sl":    ["Shadow Labyrinth,", "Shadow Labyrinth.", "Shadow Labyrinth"],
    "bot":   ["The Botanica,", "Botanica,"],
    "mech":  ["The Mechanar,", "Mechanar,"],
    "arc":   ["The Arcatraz,", "Arcatraz,"],
    "oh":    ["Old Hillsbrad Foothills,", "Old Hillsbrad Foothills.", "Old Hillsbrad Foothills"],
    "bm":    ["Black Morass,", "Black Morass.", "Black Morass"],
    "mgt":   ["Magisters' Terrace,", "Magisters Terrace,"],
    "kara":  ["Karazan,", "Kara-zan,", "Karazhan,", "Kara'zan,",
              "Karazan.", "Kara-zan.", "Karazhan.", "Kara'zan."],
    "gruul": ["Gruul's Lair,", "Gruuls Lair,"],
    "magth": ["Magtheridon,", "Mag-theridon,",
              "Mag-the-ri-don,", "Mahg-theridon,",
              "Mag the ridon,", "Magtherydon,",
              "Magtherri-don,"],
    "ssc":   ["Serpentshrine Cavern,", "Serpentshrine Cavern.", "Serpentshrine Cavern"],
    "tk":    ["Tempest Keep,", "The Eye,"],
    "hyjal": ["Hyjal Summit,", "Hi-yal Summit,", "Hy-yal Summit,",
              "Hee-yal Summit,", "Hee-jol Summit,"],
    "bt":    ["Black Temple,", "Black Temple.", "Black Temple"],
    "za":    ["Zul Aman,", "Zul'Aman,", "Zool Aman,"],
    "swp":   ["Sunwell Plateau,", "Sunwell Plateau.", "Sunwell Plateau"],
}

DISPLAY_NAMES = {
    "ramp": "Hellfire Ramparts", "bf": "Blood Furnace", "shh": "Shattered Halls",
    "sp": "Slave Pens", "ub": "Underbog", "sv": "Steamvault",
    "mt": "Mana-Tombs", "auch": "Auchenai Crypts", "seh": "Sethekk Halls",
    "sl": "Shadow Labyrinth", "bot": "The Botanica", "mech": "The Mechanar",
    "arc": "The Arcatraz", "oh": "Old Hillsbrad", "bm": "Black Morass",
    "mgt": "Magisters' Terrace", "kara": "Karazhan", "gruul": "Gruul's Lair",
    "magth": "Magtheridon", "ssc": "Serpentshrine Cavern", "tk": "Tempest Keep",
    "hyjal": "Hyjal Summit", "bt": "Black Temple", "za": "Zul'Aman",
    "swp": "Sunwell Plateau",
}

PREFIX = {"lfg": "LFG."}
DIFFICULTY = {
    "diff_heroic": "heroic.",
    "diff_normal": "normal.",  # expanded via SNIPPET_VARIANTS below
}
ROLES = {
    "role_tank_1":   "one tank,",   "role_tank_2":   "two tanks,",
    "role_heal_1":   "one healer,", "role_heal_2":   "two healers,",
    "role_dps_1":    "one DPS,",    "role_dps_2":    "two DPS,",
    "role_dps_3":    "three DPS,",  "role_dps_4":    "four DPS,",
    "role_dps_5":    "five DPS,",   "role_dps_many": "many DPS,",
    "role_melee_1":  "one melee,",  "role_melee_2":  "two melee,",
    "role_melee_3":  "three melee,",
    "role_ranged_1": "one ranged,", "role_ranged_2": "two ranged,",
    "role_ranged_3": "three ranged,",
}

# ---------------------------------------------------------------------------
# Snippet variants — same idea as INSTANCE_VARIANTS, but for non-instance
# clips.  When a key is here, the script generates variants <key>_v1..<key>_vN
# instead of a single <key>.mp3, and the HTML renders radio buttons.
#
# For "normal." — user reported that the base "normal." was read with a
# Polish accent rather than English.  ElevenLabs has some run-to-run
# variability, so we generate 4 different spellings, all just "Normal."
# essentially — hoping at least one gets the English flavour right.
# ---------------------------------------------------------------------------

SNIPPET_VARIANTS = {
    "diff_normal":     ["normal.", "Normal.", "NORMAL.", " Normal. "],
    "fill_target_25":  ["twenty five.", "twenty five,", "twenty five",
                        "twenty-five."],
    "role_tank_1":     ["one tank,", "one tank.", "one tank", "one tank, "],
    "role_tank_2":     ["two tanks,", "two tanks.", "two tanks", "two tanks, "],
    "role_heal_1":     ["one healer,", "one healer.", "one healer", "one healer, "],
    "role_heal_2":     ["two healers,", "two healers.", "two healers", "two healers, "],
    "role_dps_1":      ["one DPS,", "one DPS.", "one DPS", "one DPS, "],
    "role_dps_2":      ["two DPS,", "two DPS.", "two DPS", "two DPS, "],
    "role_dps_3":      ["three DPS,", "three DPS.", "three DPS", "three DPS, "],
    "role_dps_4":      ["four DPS,", "four DPS.", "four DPS", "four DPS, "],
    "role_dps_5":      ["five DPS,", "five DPS.", "five DPS", "five DPS, "],
    "role_dps_many":   ["many DPS,", "many DPS.", "many DPS", "many DPS, "],
    "role_melee_1":    ["one melee,", "one melee.", "one melee", "one melee, "],
    "role_melee_2":    ["two melee,", "two melee.", "two melee", "two melee, "],
    "role_melee_3":    ["three melee,", "three melee.", "three melee", "three melee, "],
    "role_ranged_1":   ["one ranged,", "one ranged.", "one ranged", "one ranged, "],
    "role_ranged_2":   ["two ranged,", "two ranged.", "two ranged", "two ranged, "],
    "role_ranged_3":   ["three ranged,", "three ranged.", "three ranged", "three ranged, "],
}
CONNECTORS = {
    "conn_and":      "and",
    "conn_needed":   "needed.",
    "gen_all_roles": "all roles needed.",
}
NUMBERS = {
    f"num_{i}": w + "." for i, w in enumerate(
        ["one","two","three","four","five","six","seven","eight","nine","ten",
         "eleven","twelve","thirteen","fourteen","fifteen"], start=1
    )
}
FILL_PARTS = {
    "fill_out_of":     "out of",
    "fill_target_25":  "twenty five.",
    "fill_target_40":  "forty.",
}
MODIFIERS = {
    "mod_class_req": "class requested.",
    "mod_fresh":     "fresh,",
    "mod_daily":     "daily.",
}


# Slots starting with "inst:" resolve at runtime to the selected
# instance variant.  Slots without prefix are fixed-key clips.
EXAMPLES = [
    {
        "bulletin": "LFM tank,heal,dps BM HC",
        "spoken":   "LFG. Black Morass, heroic. All roles needed.",
        "slots":    ["lfg", "inst:bm", "diff_heroic", "gen_all_roles"],
    },
    {
        "bulletin": "LF 2 dps and 1 heal Karazhan 6/10",
        "spoken":   "LFG. Karazhan. One healer, and two DPS, needed. Six out of ten.",
        "slots":    ["lfg", "inst:kara", "role_heal_1", "conn_and", "role_dps_2", "conn_needed", "num_6", "fill_out_of", "num_10"],
    },
    {
        "bulletin": "LFM Fresh Karazhan 7/10",
        "spoken":   "LFG. Karazhan, fresh. Seven out of ten.",
        "slots":    ["lfg", "inst:kara", "mod_fresh", "num_7", "fill_out_of", "num_10"],
    },
    {
        "bulletin": "LFM SHH (normal) tank/dps",
        "spoken":   "LFG. Shattered Halls, normal. One tank, and one DPS, needed.",
        "slots":    ["lfg", "inst:shh", "diff_normal", "role_tank_1", "conn_and", "role_dps_1", "conn_needed"],
    },
    {
        "bulletin": "lf2m ac or mt (h) - heal & range dps",
        "spoken":   "LFG. Mana-Tombs, heroic. One healer, and one ranged, needed.",
        "slots":    ["lfg", "inst:mt", "diff_heroic", "role_heal_1", "conn_and", "role_ranged_1", "conn_needed"],
    },
    {
        "bulletin": "Fresh Kara 1 tank dd spd heal",
        "spoken":   "LFG. Karazhan. All roles needed.",
        "slots":    ["lfg", "inst:kara", "gen_all_roles"],
    },
    {
        "bulletin": "ramp norm tank heal dps +++",
        "spoken":   "LFG. Hellfire Ramparts, normal. All roles needed.",
        "slots":    ["lfg", "inst:ramp", "diff_normal", "gen_all_roles"],
    },
    {
        "bulletin": "LFM SP normal need tank heal",
        "spoken":   "LFG. Slave Pens, normal. One tank, and one healer, needed.",
        "slots":    ["lfg", "inst:sp", "diff_normal", "role_tank_1", "conn_and", "role_heal_1", "conn_needed"],
    },
    {
        "bulletin": "LFM Hyjal 12/25",
        "spoken":   "LFG. Hyjal Summit. Twelve out of twenty five.",
        "slots":    ["lfg", "inst:hyjal", "num_12", "fill_out_of", "fill_target_25"],
    },
    {
        "bulletin": "LFM Sunwell 5/25 class requested",
        "spoken":   "LFG. Sunwell Plateau. Five out of twenty five. Class requested.",
        "slots":    ["lfg", "inst:swp", "num_5", "fill_out_of", "fill_target_25", "mod_class_req"],
    },
]


# Build the flat clip list: key -> text -> filename
def build_clip_list():
    clips = []  # (filename_without_ext, text)
    # Standard clips — if key is in SNIPPET_VARIANTS, generate variants
    # only; otherwise generate the single bare-key file.
    for d in (PREFIX, DIFFICULTY, ROLES, CONNECTORS, NUMBERS, FILL_PARTS, MODIFIERS):
        for k, txt in d.items():
            if k in SNIPPET_VARIANTS:
                for i, v_text in enumerate(SNIPPET_VARIANTS[k], start=1):
                    clips.append((f"{k}_v{i}", v_text))
            else:
                clips.append((k, txt))
    # Instance variants — name as inst_<key>_v<idx+1>
    for inst_key, variants in INSTANCE_VARIANTS.items():
        for i, txt in enumerate(variants, start=1):
            clips.append((f"inst_{inst_key}_v{i}", txt))
    return clips


MANIFEST_FILE = OUT_DIR / "_manifest.json"


def load_manifest():
    if MANIFEST_FILE.exists():
        try:
            return json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
    return {}


def save_manifest(m):
    MANIFEST_FILE.write_text(json.dumps(m, indent=2, ensure_ascii=False), encoding="utf-8")


def synth(api_key, key, text, manifest):
    """Generate clip if not cached OR if cached text differs from current.

    Manifest tracks {filename: text_used} so we auto-regenerate when the
    spelling changes (e.g. Karazan, -> Karazan.).
    """
    out = OUT_DIR / f"{key}.mp3"
    cached_text = manifest.get(key)
    if out.exists() and cached_text == text:
        size_kb = out.stat().st_size / 1024
        print(f"  {key:24}  {size_kb:5.1f} KB  (cached)")
        return True, 0
    headers = {"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"}
    body = {"text": text, "model_id": MODEL_ID}
    r = requests.post(API_URL, headers=headers, json=body, timeout=60)
    if r.status_code != 200:
        print(f"  {key:24}  HTTP {r.status_code}  {r.text[:200]}")
        return False, 0
    out.write_bytes(r.content)
    manifest[key] = text
    save_manifest(manifest)
    size_kb = out.stat().st_size / 1024
    suffix = " (regenerated)" if cached_text and cached_text != text else ""
    print(f"  {key:24}  {size_kb:5.1f} KB  \"{text}\"{suffix}")
    return True, len(text)


HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>LFGSpeaker Voice Test</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 1100px; margin: 24px auto; padding: 0 16px; background:#1a1a1a; color:#ddd; }
  h1 { color: #ff9933; border-bottom: 2px solid #444; padding-bottom: 6px; }
  h2 { color: #66ccff; margin-top: 30px; border-bottom: 1px solid #333; }
  h3 { color: #ffcc66; margin: 16px 0 6px 0; }
  .row { display: flex; align-items: center; gap: 8px; margin: 3px 0; padding: 3px 6px; border-radius: 4px; }
  .row:hover { background:#252525; }
  .label { min-width: 220px; color: #aaa; font-size: 0.9em; }
  .text { color: #ddd; font-family: ui-monospace, monospace; min-width: 250px; }
  button.play { background: #2d6fd1; color: white; border: none; padding: 4px 10px; border-radius: 4px; cursor: pointer; font-size: 0.85em; }
  button.play:hover { background: #3a8aff; }
  button.play-big { background:#2d8d2d; padding: 8px 16px; font-size: 0.95em; }
  button.play-big:hover { background:#3aa83a; }
  .ex { background: #232323; padding: 10px 14px; border-radius: 6px; margin: 8px 0; border-left: 3px solid #66ccff; }
  .ex .bullet { color: #888; font-family: ui-monospace, monospace; }
  .ex .spoken { color: #ddd; margin: 4px 0; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 4px; }
  input[type=radio] { accent-color: #66ccff; }
  .note { color: #888; font-size: 0.85em; margin-top: 4px; }
  .badge { background:#664422; color:#ffcc66; padding: 1px 6px; border-radius: 3px; font-size: 0.75em; }
</style>
</head>
<body>
<h1>LFGSpeaker Voice Preview</h1>
<p class="note">Voice: Will - Relaxed Optimist (1× multiplier). Model: eleven_multilingual_v2. Click [▶] to play a clip, or use the example buttons to hear a composed sentence using your currently-selected instance variants.</p>

<div style="background:#2a2a2a;padding:12px;border-radius:6px;margin:10px 0;border:1px solid #555">
  <button onclick="exportSelections()" style="background:#aa6622;color:white;border:none;padding:8px 16px;border-radius:4px;cursor:pointer;font-size:0.95em">📋 Export selections (copy &amp; paste to chat)</button>
  <textarea id="exportArea" style="width:100%;height:200px;margin-top:8px;background:#111;color:#aaeeaa;font-family:ui-monospace,monospace;font-size:0.85em;padding:8px;border:1px solid #333;display:none"></textarea>
</div>

<h2>Instance variants — pick the one that sounds most WoW-canonical</h2>
__INSTANCE_BLOCKS__

<h2>Standard clips</h2>
<h3>Prefix / Difficulty</h3>
__PREFIX_DIFF__

<h3>Roles (count + role, comma at end)</h3>
__ROLES__

<h3>Connectors / Generic</h3>
__CONNECTORS__

<h3>Numbers 1-15</h3>
__NUMBERS__

<h3>Group fill parts</h3>
__FILL__

<h3>Modifiers</h3>
__MODIFIERS__

<h2>10 composed examples</h2>
<p class="note">Uses your currently-selected instance variants. Click play to hear how a real bulletin would sound through the addon. Gap between clips is 180 ms.</p>
__EXAMPLES__

<script>
const VARIANTS = __VARIANTS_JSON__;   // radio_name -> variant count
const STORAGE_KEY_PREFIX = "lfgspeaker_variant_";

function play(filename) {
  const a = new Audio(filename + ".mp3");
  a.play();
}

// Resolve a slot key to an actual .mp3 filename (without extension).
//   "inst:kara"     -> selected variant value (or first variant default)
//   "role_tank_1"   -> selected variant (or _v1)
//   "lfg"           -> "lfg" (no variants)
function resolveSlot(slot) {
  let radioName, fallbackDefault;
  if (slot.startsWith("inst:")) {
    radioName = slot.substring(5);
    fallbackDefault = `inst_${radioName}_v1`;
  } else {
    radioName = slot;
    fallbackDefault = slot;  // may be `<key>_v1` if variants exist, see below
  }
  const r = document.querySelector(`input[name="${radioName}"]:checked`);
  if (r) return r.value;
  // No checked radio found.  If this key has variants in VARIANTS map,
  // default to v1 with proper prefix.
  if (VARIANTS[radioName] && VARIANTS[radioName] > 1) {
    if (slot.startsWith("inst:")) return `inst_${radioName}_v1`;
    return `${radioName}_v1`;
  }
  return slot;
}

async function playSequence(slots, gapMs) {
  gapMs = gapMs || 180;
  for (const slot of slots) {
    const file = resolveSlot(slot);
    if (!file) continue;
    try {
      const a = new Audio(file + ".mp3");
      await new Promise((resolve) => {
        a.onended = resolve;
        a.onerror = (e) => { console.warn("audio error", file, e); resolve(); };
        a.play().catch(err => { console.warn("play() rejected", file, err); resolve(); });
      });
      await new Promise(r => setTimeout(r, gapMs));
    } catch (err) {
      console.warn("error playing", file, err);
    }
  }
}

// --- Persistence ---
// localStorage key = `lfgspeaker_variant_<radioName>`, value = radio.value.
// Radio name is the bare slot key (e.g., "kara", "role_tank_1", "diff_normal")
// so existing user selections from earlier runs (which already stored by
// stripped key like "kara") keep working without migration.
function persistRadio(r) {
  if (r.checked) {
    localStorage.setItem(STORAGE_KEY_PREFIX + r.name, r.value);
  }
}

function restoreRadios() {
  document.querySelectorAll('input[type=radio]').forEach(r => {
    const saved = localStorage.getItem(STORAGE_KEY_PREFIX + r.name);
    if (saved && r.value === saved) {
      r.checked = true;
    }
  });
}

document.querySelectorAll('input[type=radio]').forEach(r => {
  r.addEventListener('change', () => persistRadio(r));
});

restoreRadios();

// --- Export selections for hand-off ---
function exportSelections() {
  const sel = {};
  document.querySelectorAll('input[type=radio]:checked').forEach(r => {
    sel[r.name] = r.value;
  });
  const area = document.getElementById('exportArea');
  area.style.display = 'block';
  area.value = JSON.stringify(sel, null, 2);
  area.focus();
  area.select();
  try {
    navigator.clipboard.writeText(area.value).then(() => {
      area.style.borderColor = '#5fa55f';
    });
  } catch (e) { /* fallback: user copies manually */ }
}

// Visible confirmation when something is saved
const note = document.createElement('div');
note.style.cssText = 'position:fixed;bottom:10px;right:10px;background:#264022;color:#9fd49f;padding:6px 10px;border-radius:4px;font-size:0.8em;opacity:0;transition:opacity 0.3s;z-index:1000';
note.textContent = 'Selection saved';
document.body.appendChild(note);
document.querySelectorAll('input[type=radio]').forEach(r => {
  r.addEventListener('change', () => {
    note.style.opacity = '1';
    setTimeout(() => { note.style.opacity = '0'; }, 800);
  });
});
</script>

</body>
</html>
"""


def render_html(clips):
    # variants_json: radio_name -> count (used by JS for default lookups)
    variants_json = {}

    # Build instance blocks — radio name = bare instance key, value =
    # inst_<key>_v<n>.  Bare radio name keeps localStorage compatible
    # with previous saves (key = "kara", not "inst_kara").
    inst_html = []
    for inst_key, variants in INSTANCE_VARIANTS.items():
        variants_json[inst_key] = len(variants)
        if len(variants) == 1:
            txt = variants[0]
            inst_html.append(
                f'<div class="row"><span class="label">{eschtml(DISPLAY_NAMES[inst_key])}</span>'
                f'<span class="text">{eschtml(txt)}</span>'
                f'<button class="play" onclick="play(\'inst_{inst_key}_v1\')">▶</button>'
                f'</div>'
            )
        else:
            inst_html.append(f'<h3>{eschtml(DISPLAY_NAMES[inst_key])} <span class="badge">{len(variants)} variants</span></h3>')
            for i, txt in enumerate(variants, start=1):
                checked = "checked" if i == 1 else ""
                inst_html.append(
                    f'<div class="row">'
                    f'<input type="radio" name="{inst_key}" value="inst_{inst_key}_v{i}" id="r_{inst_key}_{i}" {checked}>'
                    f'<label for="r_{inst_key}_{i}" class="label">variant {i}</label>'
                    f'<span class="text">{eschtml(txt)}</span>'
                    f'<button class="play" onclick="play(\'inst_{inst_key}_v{i}\')">▶</button>'
                    f'</div>'
                )

    def section_with_variants(d, header_label_map=None):
        """Render section.  If key is in SNIPPET_VARIANTS, render with
        radio buttons; else single row."""
        rows = []
        for k, txt in d.items():
            if k in SNIPPET_VARIANTS:
                variants = SNIPPET_VARIANTS[k]
                variants_json[k] = len(variants)
                display = header_label_map.get(k, k) if header_label_map else k
                rows.append(f'<h4>{eschtml(display)} <span class="badge">{len(variants)} variants</span></h4>')
                for i, v_text in enumerate(variants, start=1):
                    checked = "checked" if i == 1 else ""
                    rows.append(
                        f'<div class="row">'
                        f'<input type="radio" name="{k}" value="{k}_v{i}" id="r_{k}_{i}" {checked}>'
                        f'<label for="r_{k}_{i}" class="label">variant {i}</label>'
                        f'<span class="text">{eschtml(v_text)}</span>'
                        f'<button class="play" onclick="play(\'{k}_v{i}\')">▶</button>'
                        f'</div>'
                    )
            else:
                rows.append(
                    f'<div class="row"><span class="label">{eschtml(k)}</span>'
                    f'<span class="text">{eschtml(txt)}</span>'
                    f'<button class="play" onclick="play(\'{k}\')">▶</button></div>'
                )
        return "\n".join(rows)

    prefix_diff = section_with_variants({**PREFIX, **DIFFICULTY})
    roles_html = section_with_variants(ROLES)
    conn_html = section_with_variants(CONNECTORS)
    numbers_html = section_with_variants(NUMBERS)
    fill_html = section_with_variants(FILL_PARTS)
    mods_html = section_with_variants(MODIFIERS)

    example_blocks = []
    for ex in EXAMPLES:
        slots_json = json.dumps(ex["slots"])
        example_blocks.append(
            f'<div class="ex">'
            f'<div class="bullet">Bulletin: {eschtml(ex["bulletin"])}</div>'
            f'<div class="spoken">→ {eschtml(ex["spoken"])}</div>'
            f'<button class="play play-big" onclick=\'playSequence({slots_json})\'>▶ Play composed</button>'
            f'</div>'
        )

    html = HTML_TEMPLATE
    html = html.replace("__INSTANCE_BLOCKS__", "\n".join(inst_html))
    html = html.replace("__PREFIX_DIFF__", prefix_diff)
    html = html.replace("__ROLES__", roles_html)
    html = html.replace("__CONNECTORS__", conn_html)
    html = html.replace("__NUMBERS__", numbers_html)
    html = html.replace("__FILL__", fill_html)
    html = html.replace("__MODIFIERS__", mods_html)
    html = html.replace("__EXAMPLES__", "\n".join(example_blocks))
    html = html.replace("__VARIANTS_JSON__", json.dumps(variants_json))

    (OUT_DIR / "preview.html").write_text(html, encoding="utf-8")
    print(f"  preview.html written")


def write_serve_bat():
    (OUT_DIR / "serve.bat").write_text(
        "@echo off\r\n"
        "cd /d %~dp0\r\n"
        "echo Serving http://localhost:8765/preview.html\r\n"
        "python -m http.server 8765\r\n",
        encoding="ascii",
    )


def main():
    api_key = get_api_key()
    print(f"voice:   Will - Relaxed Optimist ({VOICE_ID})")
    print(f"model:   {MODEL_ID}")
    print(f"out:     {OUT_DIR}\n")

    clips = build_clip_list()
    manifest = load_manifest()
    print(f"Generating {len(clips)} clips...")
    total_chars = 0
    errors = 0
    for key, text in clips:
        ok, chars = synth(api_key, key, text, manifest)
        if ok:
            total_chars += chars
            if chars > 0:  # actually generated, not cached
                time.sleep(0.25)
        else:
            errors += 1
    print()
    print("Building preview.html...")
    render_html(clips)
    write_serve_bat()
    print()
    print(f"Total characters sent: {total_chars}")
    print(f"Errors: {errors}")
    print(f"\nOpen in browser: file:///{OUT_DIR.resolve().as_posix()}/preview.html")
    print(f"Or run: {OUT_DIR / 'serve.bat'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
