"""Records the story's voice lines with a neural text-to-speech voice.

    python art/audio/make_voices.py --piper PATH/piper --model PATH/en-us-libritts-high.onnx

Every line a story character speaks (dialogue, boss taunts, boss phase
shouts, an ally's retreat) is spoken with Piper and the LibriTTS "high"
voice model, which has 904 speakers. Each character's `voice` in
game/data/story/characters.json picks the speaker, speed and pitch, plus an
optional effect ("spirit": a doubled, hollow voice for the Nue). The line's
mood changes the delivery a little.

The player's lines stay silent: you choose their name and look, so no single
voice fits. Lines that say the player's name are spoken without it ("You're
late, {name}." becomes "You're late."); lines with {nature} are recorded
once per nature.

Files go to game/assets/audio/voice/<who>/<key>.ogg, where key is the first
12 hex digits of md5("<who>|<text as written>[|<nature>]"). Voice.gd computes
the same key, so editing a line's text simply leaves it unvoiced until this
is run again (the tests list what's missing).

Get Piper and the voice model from https://github.com/rhasspy/piper/releases:
piper_linux_x86_64.tar.gz (2023.11.14-2) and voice-en-us-libritts-high.tar.gz
(v0.0.2). Also needs numpy and scipy, and oggenc (vorbis-tools).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, resample_poly, sosfilt

REPO_ROOT = Path(__file__).resolve().parents[2]
STORY_DIR = REPO_ROOT / "game" / "data" / "story"
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "audio" / "voice"
NATURES = ["fire", "wind", "lightning", "earth", "water"]
PLAYER = "player"
# Must match StoryDirector.ALLY_RETREAT_LINE.
ALLY_RETREAT_LINE = "I'm hurt... Finish it without me!"
# Delivery by mood: (speed multiplier, piper noise_scale).
MOODS = {
	"neutral": (1.0, 0.6),
	"relaxed": (1.05, 0.55),
	"happy": (0.95, 0.75),
	"angry": (0.95, 0.8),
	"sad": (1.12, 0.55),
}
TARGET_RMS_DB = -19.0


@dataclass
class Line:
	who: str
	raw: str
	mood: str
	nature: str = ""

	@property
	def key(self) -> str:
		text = f"{self.who}|{self.raw}" + (f"|{self.nature}" if self.nature else "")
		return hashlib.md5(text.encode("utf-8")).hexdigest()[:12]

	@property
	def spoken(self) -> str:
		return spoken_text(self.raw, self.nature)


def spoken_text(raw: str, nature: str = "") -> str:
	"""The line as said aloud: without the player's name, with their nature,
	and with button prompts read as words."""
	t = raw.replace("{nature}", nature)
	t = re.sub(r",\s*\{name\},", ",", t)                       # "But tonight, {name}, you" -> "But tonight, you"
	t = re.sub(r",\s*\{name\}([.?!:])", r"\1", t)              # "Not bad, {name}." -> "Not bad."
	t = re.sub(r"(^|[.?!:]\s+)\{name\}[,.:]\s*(\w)",           # "{name}, take" -> "Take"
		lambda m: m.group(1) + m.group(2).upper(), t)
	t = re.sub(r"\s*\{name\}", "", t)
	t = re.sub(r"\{(\w+)\}", lambda m: "the " + m.group(1).replace("_", " ") + " button", t)
	return t.strip()


def collect() -> tuple[dict, list[Line]]:
	cast = json.loads((STORY_DIR / "characters.json").read_text())
	lines: list[Line] = []
	allies: set[str] = set()

	def add(who: str, raw: str, mood: str) -> None:
		if who == PLAYER or who not in cast or not raw:
			return
		if "{nature}" in raw:
			lines.extend(Line(who, raw, mood, n) for n in NATURES)
		else:
			lines.append(Line(who, raw, mood))

	for path in sorted(STORY_DIR.glob("*.json")):
		if path.name == "characters.json":
			continue
		for beat in json.loads(path.read_text()).get("beats", []):
			kind = beat.get("do")
			if kind == "say":
				for entry in beat["lines"]:
					add(entry[0], entry[1], entry[2] if len(entry) > 2 else "neutral")
			elif kind == "boss":
				add(beat["who"], beat.get("taunt", ""), "angry")
				for phase in beat.get("phases", []):
					add(beat["who"], phase.get("say", ""), "angry")
			elif kind == "ally":
				allies.add(beat["who"])
	for who in sorted(allies):
		add(who, ALLY_RETREAT_LINE, "sad")
	unique = {(l.who, l.key): l for l in lines}
	return cast, list(unique.values())


def synthesize(piper: Path, model: Path, cast: dict, lines: list[Line], work: Path) -> None:
	"""One Piper run per (speaker, speed, noise) so the model loads rarely."""
	groups: dict[tuple, list[Line]] = {}
	for line in lines:
		voice = cast[line.who]["voice"]
		pitch = float(voice.get("pitch", 0.0))
		speed_mood, noise = MOODS.get(line.mood, MOODS["neutral"])
		# Pitch is shifted afterwards by resampling, which also changes the
		# length: pre-compensate so the final pace is what was asked for.
		length = float(voice.get("speed", 1.0)) * speed_mood * 2 ** (pitch / 12.0)
		groups.setdefault((int(voice["speaker"]), round(length, 3), noise), []).append(line)
	for (speaker, length, noise), group in groups.items():
		jsonl = "\n".join(json.dumps({"text": l.spoken, "speaker_id": speaker,
			"output_file": str(work / f"{l.who}_{l.key}.wav")}) for l in group) + "\n"
		subprocess.run([str(piper), "--model", str(model), "--json-input", "--length_scale", str(length),
			"--noise_scale", str(noise), "--noise_w", "0.8", "--sentence_silence", "0.3"],
			input=jsonl.encode(), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _sos(kind: str, freq, sr: int):
	return butter(2, np.array(freq) / (sr / 2), btype=kind, output="sos")


def shift_pitch(x: np.ndarray, semitones: float) -> np.ndarray:
	"""Resamples (tape-style: pitch and formants together)."""
	if abs(semitones) < 0.05:
		return x
	ratio = 2 ** (semitones / 12.0)
	# Playing back `ratio` times faster = fewer samples.
	up, down = 1000, int(round(1000 * ratio))
	return resample_poly(x, up, down)


def spirit(x: np.ndarray, sr: int) -> np.ndarray:
	"""A hollow, doubled voice: an octave-down shadow, a slow ring, and a
	short dark reverb."""
	low = shift_pitch(x, -12.0)[: len(x)]
	low = np.pad(low, (0, len(x) - len(low)))
	t = np.arange(len(x)) / sr
	ring = x * (0.75 + 0.25 * np.sin(2 * np.pi * 34.0 * t))
	mix = 0.8 * ring + 0.55 * sosfilt(_sos("lowpass", 1400.0, sr), low)
	rng = np.random.default_rng(7)
	ir_len = int(0.9 * sr)
	ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (0.22 * sr))
	ir = sosfilt(_sos("lowpass", 2500.0, sr), ir)
	ir /= np.sqrt(np.sum(ir ** 2))
	wet = np.convolve(mix, ir)[: len(mix) + ir_len // 2]
	out = np.pad(mix, (0, len(wet) - len(mix))) + 0.35 * wet
	return out


def finish(src: Path, dest: Path, voice: dict) -> float:
	sr, data = wavfile.read(src)
	x = data.astype(np.float64) / 32768.0
	x = shift_pitch(x, float(voice.get("pitch", 0.0)))
	x = sosfilt(_sos("highpass", 75.0, sr), x)
	if voice.get("effect") == "spirit":
		x = spirit(x, sr)
	# Trim silence at both ends (keep a breath), then level the speech.
	env = np.convolve(np.abs(x), np.ones(256) / 256, mode="same")
	loud = np.nonzero(env > 0.02 * env.max())[0]
	if loud.size:
		x = x[max(0, loud[0] - int(0.04 * sr)): loud[-1] + int(0.12 * sr)]
		env = np.convolve(np.abs(x), np.ones(256) / 256, mode="same")
	active = x[env > 0.05 * env.max()] if loud.size else x
	rms = np.sqrt(np.mean(active ** 2)) + 1e-9
	x *= 10 ** (TARGET_RMS_DB / 20.0) / rms
	peak = np.max(np.abs(x))
	if peak > 0.95:
		x *= 0.95 / peak
	fade = int(0.008 * sr)
	x[:fade] *= np.linspace(0, 1, fade)
	x[-fade:] *= np.linspace(1, 0, fade)
	pcm = src.with_suffix(".final.wav")
	wavfile.write(pcm, sr, (x * 32767).astype(np.int16))
	dest.parent.mkdir(parents=True, exist_ok=True)
	subprocess.run(["oggenc", "-Q", "-q", "2", "-o", str(dest), str(pcm)], check=True)
	return len(x) / sr


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--piper", type=Path, required=True)
	parser.add_argument("--model", type=Path, required=True)
	parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
	parser.add_argument("--only", help="just this character")
	parser.add_argument("--list", action="store_true", help="print the lines as they'll be spoken and stop")
	args = parser.parse_args()
	if shutil.which("oggenc") is None:
		sys.exit("oggenc not found: apt install vorbis-tools")
	cast, lines = collect()
	missing = sorted({l.who for l in lines if "voice" not in cast[l.who]})
	if missing:
		sys.exit(f"no 'voice' in characters.json for: {', '.join(missing)}")
	if args.only:
		lines = [l for l in lines if l.who == args.only]
	if args.list:
		for l in lines:
			print(f"{l.who:8s} {l.key}  {l.spoken}")
		return 0

	with tempfile.TemporaryDirectory() as tmp:
		work = Path(tmp)
		synthesize(args.piper, args.model, cast, lines, work)
		total = 0.0
		for l in lines:
			total += finish(work / f"{l.who}_{l.key}.wav", args.out / l.who / f"{l.key}.ogg", cast[l.who]["voice"])
	# Drop recordings of lines that no longer exist.
	keep = {(args.out / l.who / f"{l.key}.ogg") for l in lines}
	for f in args.out.rglob("*.ogg"):
		if f not in keep and (not args.only or f.parent.name == args.only):
			f.unlink()
			f.with_suffix(".ogg.import").unlink(missing_ok=True)
	print(f"{len(lines)} lines, {total / 60:.1f} minutes")
	if args.out == DEFAULT_OUT:
		subprocess.run([sys.executable, str(Path(__file__).with_name("sync_audio_pack.py"))], check=True)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
