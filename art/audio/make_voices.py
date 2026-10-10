"""Records the story's voice lines with the Kokoro neural text-to-speech model.

    python art/audio/make_voices.py --kokoro DIR

DIR holds kokoro-v1.0.onnx and voices-v1.0.bin from
https://github.com/thewh1teagle/kokoro-onnx/releases (model-files-v1.0).
Needs: pip install kokoro-onnx scipy (kokoro-onnx brings onnxruntime,
phonemizer and a bundled espeak-ng), and oggenc (vorbis-tools).

Every line a story character speaks (dialogue, cutscene lines, boss taunts
and phase shouts, an ally's retreat) is spoken by Kokoro-82M, an 82M
parameter model whose voices are far closer to a person reading than the
older Piper/LibriTTS ones. Each character's `voice` in
game/data/story/characters.json picks a Kokoro voice (or a blend of two,
"af_sarah*0.6+af_nicole*0.4"), a speed (1 = normal, higher = faster) and an
optional effect ("spirit": a doubled, hollow voice for the Nue). The line's
mood nudges the pace. Nothing is pitch-shifted: resampling a voice is what
made the old recordings sound synthetic.

Pronunciation: text goes through espeak-ng and is mapped to the phoneme set
Kokoro was trained on (its diphthongs and flap). The cast's Japanese names
are not English words, so espeak guesses them badly ("Kagerou" as
"cage-row"); NAMES below spells them out phonetically instead.

The player's lines stay silent: you choose their name and look, so no single
voice fits. Lines that say the player's name are spoken without it ("You're
late, {name}." becomes "You're late."); lines with {nature} are recorded
once per nature.

Files go to game/assets/audio/voice/<who>/<key>.ogg, where key is the first
12 hex digits of md5("<who>|<text as written>[|<nature>]"). Voice.gd computes
the same key, so editing a line's text simply leaves it unvoiced until this
is run again (the tests list what's missing).
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
from scipy.signal import butter, sosfilt

REPO_ROOT = Path(__file__).resolve().parents[2]
STORY_DIR = REPO_ROOT / "game" / "data" / "story"
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "audio" / "voice"
NATURES = ["fire", "wind", "lightning", "earth", "water"]
PLAYER = "player"
# Must match StoryDirector.ALLY_RETREAT_LINE.
ALLY_RETREAT_LINE = "I'm hurt... Finish it without me!"
# Pace by mood (multiplies the character's speed). Kokoro has no emotion
# control; the words and the pace carry it.
MOODS = {
	"neutral": 1.0,
	"relaxed": 0.96,
	"happy": 1.05,
	"angry": 1.07,
	"sad": 0.9,
}
# Silence after a full stop / a comma inside a line, in seconds.
SENTENCE_PAUSE = 0.32
CLAUSE_PAUSE = 0.12
TARGET_RMS_DB = -19.0
SAMPLE_RATE = 24000

# Names espeak can't read, in Kokoro's phonemes (stress mark before the
# stressed vowel; A = the "ay" in "say", O = the "oh" in "go").
NAMES = {
	"Hisame": "hisˈɑmɛ",
	"Asahi": "ɑsˈɑhi",
	"Kagerou": "kɑɡˈɛɹO",
	"Iwao": "iwˈɑO",
	"Tsumugi": "ʦumˈuɡi",
	"Nue": "nˈuɛ",
	"Tobi": "tˈObi",
	"Chiyo": "ʧˈijO",
	"Renji": "ɹˈɛnʤi",
	"Kurogane": "kuɹOɡˈɑnɛ",
	"Mikage": "mikˈɑɡɛ",
	"Sumi": "sˈumi",
	"Shirou": "ʃˈiɹO",
	"Sensei": "sˈɛnsA",
	"sensei": "sˈɛnsA",
}
# The shinobi words, which espeak reads as English: "shinobi" as
# shin-OH-bye, "jutsu" as JUT-soo, "genin" with a soft g.
TERMS = {
	"shinobi": "ʃinˈObi",
	"jutsu": "ʤˈuʦu",
	"dojutsu": "dˈOʤuʦu",
	"kenjutsu": "kˈɛnʤuʦu",
	"ninjutsu": "nˈinʤuʦu",
	"kunai": "kˈunI",
	"genin": "ɡˈɛnin",
	"chunin": "ʧˈunin",
	"jonin": "ʤˈOnin",
	"chakra": "ʧˈɑkɹə",
	"ninjato": "ninʤˈɑtO",
	"hachigane": "hɑʧiɡˈɑnɛ",
	"torii": "tˈOɹii",
}
for _term, _ps in TERMS.items():
	NAMES.setdefault(_term, _ps)
	NAMES.setdefault(_term.capitalize(), _ps)
# A name, and its possessive ("Kagerou's" is one word, not "Kagerou ess").
NAME_RE = re.compile(r"\b(" + "|".join(sorted(NAMES, key=len, reverse=True)) + r")('s)?\b")

# espeak-ng's American English phonemes -> the set Kokoro was trained on
# (after the misaki G2P's espeak fallback). "^" ties diphthongs together.
E2M = sorted({
	"ʔˌn\u0329": "tᵊn", "ʔn\u0329": "tᵊn", "ʔn": "tᵊn", "ʔ": "t",
	"a^ɪ": "I", "a^ʊ": "W", "d^ʒ": "ʤ", "e": "A", "e^ɪ": "A", "r": "ɹ",
	"t^ʃ": "ʧ", "x": "k", "ç": "k", "ɐ": "ə", "ɔ^ɪ": "Y", "ə^l": "ᵊl",
	"ɚ": "əɹ", "ɬ": "l", "ʲ": "",
}.items(), key=lambda kv: -len(kv[0]))


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
			elif kind == "scene":
				# Cutscenes talk too: {"say": [[who, text, mood], ...]} steps.
				for step in beat.get("steps", []):
					for entry in step.get("say", []):
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


class Speaker:
	"""Kokoro plus the espeak front end, loaded once."""

	def __init__(self, model_dir: Path):
		import espeakng_loader
		from kokoro_onnx import Kokoro
		from phonemizer.backend import EspeakBackend
		from phonemizer.backend.espeak.wrapper import EspeakWrapper

		self.kokoro = Kokoro(str(model_dir / "kokoro-v1.0.onnx"), str(model_dir / "voices-v1.0.bin"))
		EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
		EspeakWrapper.set_library(espeakng_loader.get_library_path())
		self.espeak = EspeakBackend("en-us", preserve_punctuation=True, with_stress=True, tie="^",
			language_switch="remove-flags")
		self.vocab = set(self.kokoro.tokenizer.vocab)

	def _g2p(self, text: str) -> str:
		if not text.strip():
			return ""
		ps = self.espeak.phonemize([text], strip=True)[0]
		for old, new in E2M:
			ps = ps.replace(old, new)
		ps = re.sub(r"(\S)\u0329", r"ᵊ\1", ps).replace("\u0329", "")
		ps = ps.replace("o^ʊ", "O").replace("ɜːɹ", "ɜɹ").replace("ɜː", "ɜɹ").replace("ɪə", "iə").replace("ː", "")
		# The American flap ("butter") is T in Kokoro's set.
		ps = ps.replace("o", "ɔ").replace("^", "").replace("ɾ", "T")
		return "".join(c for c in ps if c in self.vocab)

	def phonemes(self, text: str) -> str:
		"""The line in Kokoro's phonemes, with the cast's names spelled out."""
		out = []
		pos = 0
		for m in NAME_RE.finditer(text):
			out.append(self._g2p_before_word(text[pos:m.start()]))
			out.append(NAMES[m.group(1)] + ("z" if m.group(2) else ""))
			pos = m.end()
		out.append(self._g2p(text[pos:]))
		ps = " ".join(p for p in out if p)
		# Splicing can leave a space before punctuation ("hisˈɑmɛ ,") or two
		# spaces in a row.
		ps = re.sub(r"\s+([,.!?;:…])", r"\1", ps)
		return re.sub(r"\s{2,}", " ", ps)

	def _g2p_before_word(self, text: str) -> str:
		"""A stretch of the line that a name follows. espeak reads it with a
		stand-in word after it, then that word is cut off: alone, a closing
		"a" is read as the letter ("AY jonin" for "a jonin")."""
		if not text.strip() or not re.search(r"\w\s*$", text):
			return self._g2p(text)
		if not hasattr(self, "_stand_in"):
			self._stand_in = self._g2p("cat")
		ps = self._g2p(text.rstrip() + " cat")
		if ps.endswith(self._stand_in):
			return ps[: -len(self._stand_in)].rstrip()
		return self._g2p(text)

	def style(self, voice: dict) -> np.ndarray:
		"""A voice name, or a blend "a*0.6+b*0.4"."""
		total = None
		for part in str(voice["speaker"]).split("+"):
			name, _, weight = part.partition("*")
			s = self.kokoro.get_voice_style(name.strip()) * float(weight or 1.0)
			total = s if total is None else total + s
		return total

	def say(self, line: "Line", voice: dict) -> np.ndarray:
		speed = float(voice.get("speed", 1.0)) * MOODS.get(line.mood, 1.0)
		audio, sr = self.kokoro.create(self.phonemes(line.spoken), self.style(voice), speed=min(max(speed, 0.5), 2.0),
			is_phonemes=True, sentence_pause=SENTENCE_PAUSE, clause_pause=CLAUSE_PAUSE)
		assert sr == SAMPLE_RATE
		return audio.astype(np.float64)


def _sos(kind: str, freq, sr: int):
	return butter(2, np.array(freq) / (sr / 2), btype=kind, output="sos")


def spirit(x: np.ndarray, sr: int) -> np.ndarray:
	"""A hollow, doubled voice that stays intelligible: two drifting copies a
	few hundredths of a second behind (a chorus of the same mouth), a darker
	body, a slow ring and a short dark reverb. (Pitching a copy down by
	resampling also slows it, smearing each word over the next.)"""
	n = np.arange(len(x))
	t = n / sr
	out = x.copy()
	for base, depth, rate, gain in [(0.021, 0.004, 0.7, 0.55), (0.034, 0.006, 0.43, 0.4)]:
		delay = (base + depth * np.sin(2 * np.pi * rate * t)) * sr
		out += gain * np.interp(n - delay, n, x, left=0.0, right=0.0)
	out = 0.7 * out + 0.6 * sosfilt(_sos("lowpass", 900.0, sr), out)
	out *= 0.85 + 0.15 * np.sin(2 * np.pi * 34.0 * t)
	rng = np.random.default_rng(7)
	ir_len = int(0.7 * sr)
	ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (0.16 * sr))
	ir = sosfilt(_sos("lowpass", 2500.0, sr), ir)
	ir /= np.sqrt(np.sum(ir ** 2))
	wet = np.convolve(out, ir)[: len(out) + ir_len // 2]
	return np.pad(out, (0, len(wet) - len(out))) + 0.22 * wet


def finish(x: np.ndarray, sr: int, dest: Path, voice: dict, work: Path) -> float:
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
	x = x * 10 ** (TARGET_RMS_DB / 20.0) / rms
	peak = np.max(np.abs(x))
	if peak > 0.95:
		x *= 0.95 / peak
	fade = int(0.008 * sr)
	x[:fade] *= np.linspace(0, 1, fade)
	x[-fade:] *= np.linspace(1, 0, fade)
	pcm = work / (dest.stem + ".wav")
	wavfile.write(pcm, sr, (x * 32767).astype(np.int16))
	dest.parent.mkdir(parents=True, exist_ok=True)
	subprocess.run(["oggenc", "-Q", "-q", "3", "-o", str(dest), str(pcm)], check=True)
	return len(x) / sr


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--kokoro", type=Path, help="folder with kokoro-v1.0.onnx and voices-v1.0.bin")
	parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
	parser.add_argument("--only", help="just this character")
	parser.add_argument("--missing", action="store_true", help="only lines that have no recording yet")
	parser.add_argument("--list", action="store_true", help="print the lines as they'll be spoken and stop")
	parser.add_argument("--phonemes", action="store_true", help="with --list: print the phonemes too")
	args = parser.parse_args()
	cast, lines = collect()
	missing = sorted({l.who for l in lines if "voice" not in cast[l.who]})
	if missing:
		sys.exit(f"no 'voice' in characters.json for: {', '.join(missing)}")
	if args.only:
		lines = [l for l in lines if l.who == args.only]
	if args.list and not args.phonemes:
		for l in lines:
			print(f"{l.who:8s} {l.key}  {l.spoken}")
		return 0
	if args.kokoro is None:
		sys.exit("--kokoro DIR is required (see the top of this file)")
	speaker = Speaker(args.kokoro)
	if args.list:
		for l in lines:
			print(f"{l.who:8s} {l.key}  {l.spoken}\n{'':22s}{speaker.phonemes(l.spoken)}")
		return 0
	if shutil.which("oggenc") is None:
		sys.exit("oggenc not found: apt install vorbis-tools")

	total = 0.0
	todo = [l for l in lines if not (args.missing and (args.out / l.who / f"{l.key}.ogg").exists())]
	with tempfile.TemporaryDirectory() as tmp:
		for i, l in enumerate(todo):
			voice = cast[l.who]["voice"]
			total += finish(speaker.say(l, voice), SAMPLE_RATE, args.out / l.who / f"{l.key}.ogg", voice, Path(tmp))
			print(f"\r{i + 1}/{len(todo)}", end="", flush=True)
	print()
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
