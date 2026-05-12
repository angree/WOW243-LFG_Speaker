"""Test voice generation for LFGSpeaker — Will voice, snippet system.

Generates 6 individual snippets and 3 composed sentences as MP3 files
for human listening.  Does NOT touch the addon's sounds/ folder.

Output: test_output/  (gitignored)

Required:
  - ELEVENLABS_API_KEY env var (or .secrets/elevenlabs.md fallback)
  - pip install requests
  - ffmpeg on PATH
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys
import time

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


CLIPS = [
    ("lfg",         "LFG."),
    ("kara",        "Karazhan."),
    ("diff_heroic", "heroic."),
    ("role_heal_1", "one healer."),
    ("conn_needed", "needed."),
    ("fill_5_10",   "five out of ten."),
]

SENTENCES = [
    ("sample_full",
     ["lfg", "kara", "diff_heroic", "role_heal_1", "conn_needed", "fill_5_10"]),
    ("sample_minimal",
     ["lfg", "kara"]),
    ("sample_no_role",
     ["lfg", "kara", "fill_5_10"]),
]


def synth(api_key: str, key: str, text: str) -> bool:
    out = OUT_DIR / f"{key}.mp3"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }
    body = {"text": text, "model_id": MODEL_ID}
    r = requests.post(API_URL, headers=headers, json=body, timeout=60)
    if r.status_code != 200:
        print(f"  {key:14}  HTTP {r.status_code}  {r.text[:200]}")
        return False
    out.write_bytes(r.content)
    size_kb = out.stat().st_size / 1024
    print(f"  {key:14}  {size_kb:5.1f} KB  \"{text}\"")
    return True


def make_silence() -> pathlib.Path:
    out = OUT_DIR / "_silence_200ms.mp3"
    if out.exists():
        return out
    subprocess.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
        "-t", "0.2",
        "-c:a", "libmp3lame", "-b:a", "128k",
        str(out),
    ], check=True)
    return out


def compose(name: str, clip_keys: list[str]) -> pathlib.Path:
    """Concat clips with 200ms silence between via ffmpeg concat demuxer.
    Re-encode at the end to a uniform format so mismatched sample rates
    or channel layouts between ElevenLabs output and our silence don't
    glitch."""
    silence = make_silence()
    list_file = OUT_DIR / f"_concat_{name}.txt"

    lines: list[str] = []
    for i, k in enumerate(clip_keys):
        clip_path = (OUT_DIR / f"{k}.mp3").resolve().as_posix()
        lines.append(f"file '{clip_path}'")
        if i < len(clip_keys) - 1:
            lines.append(f"file '{silence.resolve().as_posix()}'")
    list_file.write_text("\n".join(lines), encoding="utf-8")

    out = OUT_DIR / f"{name}.mp3"
    subprocess.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(list_file),
        "-c:a", "libmp3lame", "-b:a", "128k", "-ar", "44100", "-ac", "1",
        str(out),
    ], check=True)
    list_file.unlink(missing_ok=True)
    size_kb = out.stat().st_size / 1024
    print(f"  {name:18}  {size_kb:5.1f} KB  [{' + '.join(clip_keys)}]")
    return out


def main() -> int:
    api_key = get_api_key()
    print(f"voice:   Will - Relaxed Optimist ({VOICE_ID})")
    print(f"model:   {MODEL_ID}")
    print(f"out:     {OUT_DIR}")
    print()

    print("Generating clips:")
    total_chars = 0
    ok_count = 0
    for key, text in CLIPS:
        if synth(api_key, key, text):
            total_chars += len(text)
            ok_count += 1
            time.sleep(0.3)
    if ok_count != len(CLIPS):
        print(f"\nERROR: only {ok_count}/{len(CLIPS)} clips generated")
        return 1

    print()
    print("Composing sentences:")
    for name, clip_keys in SENTENCES:
        compose(name, clip_keys)

    print()
    print(f"Total characters sent to API: {total_chars}")
    print(f"Files in: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
