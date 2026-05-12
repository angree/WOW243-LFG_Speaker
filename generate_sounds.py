"""Generate pre-baked TTS sound clips for LFG Reader using ElevenLabs.

WoW 2.4.3 Lua sandbox has no network and no live TTS option, so all
audio cues must be pre-rendered to disk and bundled with the addon.

Workflow:
  1. pip install requests
     (optional: pip install python-dotenv  -- for .env support)
  2. Have ffmpeg on PATH.
  3. Set the API key as an environment variable:
       PowerShell:    $env:ELEVENLABS_API_KEY = "sk_..."
       cmd.exe:       set ELEVENLABS_API_KEY=sk_...
     OR put it in .secrets/elevenlabs.md (this script falls back to
     reading the first sk_... line from that file).
  4. python generate_sounds.py
  5. .ogg files appear in LFGReader/sounds/.

Phrases are read from phrases.txt at the repo root.  Format per line:
    <sound_key>|<english phrase>

The script SKIPS keys whose .ogg already exists — so re-runs cost
zero ElevenLabs credits.  Use --force to regenerate.

Voice: Callum (voice ID N2lVS1w4EtoT3dr4eOWO).  Model: eleven_multilingual_v2
(NOT v3 — user confirmed v3 produces inferior voice fidelity).

Cyrillic in filenames does NOT work on 2.4.3.  Keep keys ASCII.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

try:
    import requests
except ImportError:
    print("requests not installed.  Run: pip install requests")
    sys.exit(1)

if shutil.which("ffmpeg") is None:
    print("ffmpeg not found on PATH.  Install ffmpeg first.")
    sys.exit(1)

ROOT = pathlib.Path(__file__).parent
PHRASES_FILE = ROOT / "phrases.txt"
OUT_DIR = ROOT / "LFGSpeaker" / "sounds"
OUT_DIR.mkdir(parents=True, exist_ok=True)

VOICE_ID = "N2lVS1w4EtoT3dr4eOWO"          # Callum, premade
MODEL_ID = "eleven_multilingual_v2"        # NOT v3
OUTPUT_FORMAT = "mp3_44100_128"            # transcoded to OGG Vorbis below

# Mono, 22050 Hz, 32 kbps Vorbis.  ~30-60 KB per 2-3s clip.
FFMPEG_FLAGS = [
    "-c:a", "libvorbis",
    "-b:a", "32k",
    "-ac", "1",
    "-ar", "22050",
]

API_URL = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format={OUTPUT_FORMAT}"

REQUEST_DELAY_SEC = 0.4  # gentle rate-limit


def get_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if key:
        return key.strip()
    # Fallback: scrape from .secrets/elevenlabs.md  (gitignored).
    secret_file = ROOT / ".secrets" / "elevenlabs.md"
    if secret_file.exists():
        m = re.search(r"sk_[A-Za-z0-9_]+", secret_file.read_text(encoding="utf-8"))
        if m:
            return m.group(0)
    print("ELEVENLABS_API_KEY not set and not found in .secrets/elevenlabs.md")
    print("Set it with:  $env:ELEVENLABS_API_KEY = 'sk_...'  (PowerShell)")
    sys.exit(1)


def load_phrases() -> list[tuple[str, str]]:
    if not PHRASES_FILE.exists():
        print(f"phrases.txt not found at {PHRASES_FILE}")
        sys.exit(1)
    out: list[tuple[str, str]] = []
    for lineno, raw in enumerate(PHRASES_FILE.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "|" not in line:
            print(f"phrases.txt line {lineno}: missing '|' -> {line!r}")
            continue
        key, phrase = line.split("|", 1)
        key, phrase = key.strip(), phrase.strip()
        if not key or not phrase:
            continue
        if not re.fullmatch(r"[a-z0-9_]+", key):
            print(f"phrases.txt line {lineno}: non-ASCII key {key!r} — skipping")
            continue
        out.append((key, phrase))
    return out


def synth_one(api_key: str, key: str, text: str, force: bool) -> tuple[str, int]:
    """Return (status, char_count).  status: 'created'|'skipped'|'error'."""
    out_ogg = OUT_DIR / f"{key}.ogg"
    if out_ogg.exists() and not force:
        return "skipped", 0

    tmp_mp3 = OUT_DIR / f"{key}.mp3"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }
    body = {"text": text, "model_id": MODEL_ID}

    resp = requests.post(API_URL, headers=headers, json=body, timeout=60)
    if resp.status_code != 200:
        print(f"  {key:14}  HTTP {resp.status_code}  {resp.text[:200]}")
        return "error", 0

    tmp_mp3.write_bytes(resp.content)
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-i", str(tmp_mp3), *FFMPEG_FLAGS, str(out_ogg)],
        check=True,
    )
    tmp_mp3.unlink(missing_ok=True)

    size_kb = out_ogg.stat().st_size / 1024
    print(f"  {key:14}  {size_kb:5.1f} KB  \"{text}\"")
    return "created", len(text)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate TTS sounds via ElevenLabs.")
    parser.add_argument("--force", action="store_true",
                        help="Regenerate even if .ogg already exists.")
    parser.add_argument("--only", metavar="KEY",
                        help="Render only this one key (and skip cache).")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be done; make no API calls.")
    args = parser.parse_args()

    api_key = get_api_key() if not args.dry_run else "(dry-run)"
    phrases = load_phrases()
    if args.only:
        phrases = [(k, p) for k, p in phrases if k == args.only]
        if not phrases:
            print(f"key not in phrases.txt: {args.only}")
            return 1

    print(f"voice:   Callum ({VOICE_ID})")
    print(f"model:   {MODEL_ID}")
    print(f"out:     {OUT_DIR}")
    print(f"phrases: {len(phrases)}")
    print()

    created = skipped = errors = total_chars = 0
    for key, text in phrases:
        if args.dry_run:
            exists = (OUT_DIR / f"{key}.ogg").exists() and not args.force
            print(f"  {key:14}  {'(cached)' if exists else f'WOULD render: {text!r} ({len(text)} chars)'}")
            if not exists:
                total_chars += len(text)
            continue

        status, chars = synth_one(api_key, key, text, args.force or bool(args.only))
        if status == "created":
            created += 1
            total_chars += chars
            time.sleep(REQUEST_DELAY_SEC)
        elif status == "skipped":
            skipped += 1
        else:
            errors += 1

    print()
    if args.dry_run:
        print(f"dry-run: would render ~{total_chars} chars total")
    else:
        print(f"created={created} skipped={skipped} errors={errors}  ({total_chars} chars sent)")
        print("run sync.bat to push to WoW AddOns folder.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
