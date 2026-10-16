"""Download one character's ElevenLabs takes from a saved creative_get_flow_run_status result.

Usage: fetch_elevenlabs.py <who> <voice_id> <status.json> [out_dir]
Matches each take to its game line by voice id and by the line text with the audio tags
stripped. Skips keys already on disk, so move stale takes aside first. Then master with
import_elevenlabs.py <who> <out_dir>/<who>."""
import json, pathlib, re, sys, urllib.request, urllib.error
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import make_voices as mv

who, voice_id, src = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
out = pathlib.Path(sys.argv[4] if len(sys.argv) > 4 else "voices_mp3") / who
out.mkdir(parents=True, exist_ok=True)
_, lines = mv.collect()
by_text = {l.spoken: l.key for l in lines if l.who == who}
data = json.loads(src.read_text())
got = 0
for m in data.get("media", []):
    if m.get("voice", {}).get("voice_id") != voice_id:
        continue
    key = by_text.get(re.sub(r"\[[^\]]*\]\s*", "", m["prompt"]).strip())
    if key is None or (out / f"{key}.mp3").exists():
        continue
    try:
        with urllib.request.urlopen(m["master_url"], timeout=60) as r:
            (out / f"{key}.mp3").write_bytes(r.read())
        got += 1
    except urllib.error.URLError as e:
        print("FAIL", key, e)
print("downloaded", got, "| on disk for", who, ":", len(list(out.glob("*.mp3"))), "of", len(by_text))
