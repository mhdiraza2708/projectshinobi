"""Composes the teaser trailer's music cue and records its voice lines.

    python art/trailer/make_trailer_audio.py --kokoro DIR --out OUT_DIR

The cue is 60 seconds at 120 BPM (30 bars of two seconds), written to the
trailer's cut list (TrailerDirector) with the same FluidSynth pipeline and
Japanese scale (D miyako-bushi) as the game's score, so every cut lands on
a bar line. The voice lines are new, spoken by the story cast's Kokoro
voices (game/data/story/characters.json), a little slower than in the game
and cleaned up for clarity (every line transcribes word for word with
Whisper). Writes music.wav, vo_<n>.wav and
cues.json (when each line starts) to OUT_DIR; art/trailer/mix_trailer.py
puts them under the rendered video.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "audio"))
import make_music as mm  # noqa: E402

BPM = 120.0
BARS = 30
SECONDS = BARS * 2.0
CAST = HERE.parents[1] / "game" / "data" / "story" / "characters.json"

# (seconds into the trailer, who, line, speed). Every line is original. The
# speeds are slower than the game's, for clarity.
LINES = [
	(1.0, "hisame", "Every shinobi begins with a single seal.", 0.9),
	(22.4, "asahi", "Try to keep up!", 1.0),
	(30.3, "kagerou", "Five natures. One scroll. All of it, mine.", 0.9),
	(34.3, "hisame", "Open your eyes.", 0.85),
	(46.4, "nue", "You will kneel before the flame.", 0.8),
	(54.5, "hisame", "This is the way of the shinobi.", 0.88),
]
# How much of the spirit effect goes on a spirit's voice (the rest dry, so
# the words stay clear).
SPIRIT_MIX = 0.4


def compose() -> mm.Song:
	s = mm.Song("trailer", bpm=BPM, bars=BARS + 2, seed=71)
	n, notes = mm.n, mm.notes
	pad = s.part(mm.WARM_PAD, volume=84, reverb=100)
	koto = s.part(mm.KOTO, volume=96, pan=44, reverb=80)
	flute = s.part(mm.SHAKUHACHI, volume=112, pan=58, reverb=90)
	drums = s.part(mm.DRUMS, volume=104, reverb=40)
	taiko = s.part(mm.TAIKO, volume=120, reverb=60, humanize=0.0)
	timp = s.part(mm.TIMPANI, volume=110, reverb=70, humanize=0.0)
	low = s.part(mm.STRINGS, volume=100, pan=44, reverb=50, humanize=0.004)
	choir = s.part(mm.CHOIR, volume=92, reverb=100)
	brass = s.part(mm.BRASS, volume=104, pan=76, reverb=60)
	violin = s.part(mm.STRINGS, volume=84, pan=84, reverb=80)

	roots = [n("D2"), n("Bb1"), n("G1"), n("A1")]
	chords = [notes("D3 A3 D4 F4"), notes("Bb2 F3 Bb3 D4"), notes("G2 D3 G3 Bb3"), notes("A2 E3 A3 C#4")]
	figure = [0, 0, 12, 0, 13, 0, 7, 12]
	bar = s.bar

	# Bars 1-4: a drone, a breathy flute and, from bar 3, the koto.
	pad.chord(bar(1), 16, notes("D2 A2 D3"), 70)
	flute.phrase(bar(1) + 1, "A4:3 Bb4:1 A4:2 G4:2 D4:4 r:2 Eb4:1 D4:1", vel=92, slide=True, vibrato=True)
	mm.arpeggio(koto, bar(3), 2, notes("D3 A3 Bb3 D4 Eb4 G4 A4"), [0, 2, 4, 3, 5, 4, 6, 4], step=0.5, vel=66)
	# Bar 5: the build. A timpani roll, taiko closing in, the choir swelling.
	for k in range(16):
		timp.note(bar(5) + k * 0.25, 0.25, n("D3"), 50 + k * 4)
	for k, off in enumerate([0, 1, 2, 2.5, 3, 3.25, 3.5, 3.75]):
		taiko.note(bar(5) + off, 1.0, n("C2"), 70 + k * 6)
	choir.chord(bar(5), 4, notes("D3 A3 D4"), 60)
	# Bars 6-17: the drive (Dm Bb Gm A, two bars each).
	for b in range(6, 18):
		t = bar(b)
		ci = ((b - 6) // 2) % 4
		root = roots[ci] + 12
		for k, off in enumerate(figure):
			low.note(t + k * 0.5, 0.32, root + off, 92 if k in (0, 3, 6) else 72)
		hard = b >= 12
		hits = [(0, n("C2"), 118), (0.5, n("G2"), 72), (1, n("C2"), 92), (1.75, n("G2"), 78),
			(2, n("C2"), 106), (2.75, n("G2"), 82), (3, n("C2"), 98), (3.5, n("G2"), 86)] if hard \
			else [(0, n("C2"), 114), (1.5, n("C2"), 90), (2, n("G2"), 80), (3, n("C2"), 100)]
		mm.taiko_hits(taiko, t, hits)
		drums.note(t, 0.2, mm.KICK, 110)
		drums.note(t + 1, 0.2, mm.LOW_TOM, 92)
		drums.note(t + 2, 0.2, mm.KICK, 106)
		drums.note(t + 3, 0.2, mm.LOW_TOM, 96)
		drums.note(t + 3.5, 0.2, mm.MID_TOM, 88)
		if (b - 6) % 2 == 0:
			brass.chord(t, 0.5, chords[ci][:3], 98)
			brass.chord(t + 0.75, 0.5, chords[ci][:3], 90)
			choir.chord(t, 7.6, chords[ci], 72 if not hard else 86)
			timp.note(t, 1.0, roots[ci] + 12, 100)
	# The drop at 10 s (the katana): everyone at once.
	drums.note(bar(6), 2, mm.CRASH, 124)
	taiko.chord(bar(6), 2, [n("C2"), n("G2")], 127)
	timp.note(bar(6), 2, n("D2"), 122)
	brass.chord(bar(6), 1.5, notes("D3 A3 D4 F4"), 110)
	drums.note(bar(12), 1, mm.CRASH, 110)
	lead = "D5:1 Eb5:1 D5:0.5 A4:0.5 Bb4:1 A4:2 G4:1 A4:1 Bb4:1 D5:1 Eb5:1.5 D5:0.5 D5:3 r:1 " \
		"G5:2 Eb5:1 D5:1 Bb4:1 A4:1 G4:2 A4:1 Bb4:1 A4:1 G4:1 D4:1 Eb4:1 A4:2"
	flute.phrase(bar(8), lead, vel=104, slide=True, vibrato=True, legato=0.92)
	violin.phrase(bar(8), lead, vel=72, legato=0.92)
	# Bar 18 (34 s): everything stops but a heartbeat and one high string
	# ("Open your eyes").
	timp.note(bar(18), 0.6, n("D2"), 70)
	timp.note(bar(18) + 0.6, 0.6, n("D2"), 56)
	timp.note(bar(18) + 2, 0.6, n("D2"), 74)
	timp.note(bar(18) + 2.6, 0.6, n("D2"), 60)
	violin.note(bar(18), 4, n("A5"), 64)
	# Bar 19 (36 s): the eyes snap open on the hit, then the climax to bar 27.
	drums.note(bar(19), 2, mm.CRASH, 124)
	taiko.chord(bar(19), 2, [n("C2"), n("G2")], 127)
	timp.note(bar(19), 2, n("D2"), 124)
	for b in range(19, 28):
		t = bar(b)
		ci = ((b - 19) // 2) % 4
		root = roots[ci] + 12
		for k, off in enumerate(figure):
			low.note(t + k * 0.5, 0.32, root + off, 98 if k in (0, 3, 6) else 78)
		mm.taiko_hits(taiko, t, [(0, n("C2"), 122), (0.5, n("G2"), 80), (1, n("C2"), 98), (1.5, n("G2"), 84),
			(2, n("C2"), 112), (2.5, n("G2"), 88), (3, n("C2"), 104), (3.25, n("C2"), 92), (3.5, n("G2"), 96), (3.75, n("C2"), 100)])
		drums.note(t, 0.2, mm.KICK, 116)
		drums.note(t + 2, 0.2, mm.KICK, 112)
		if (b - 19) % 2 == 0:
			choir.chord(t, 7.8, chords[ci], 98)
			brass.chord(t, 7.6, chords[ci][:3], 92)
			timp.note(t, 1.0, roots[ci] + 12, 110)
			drums.note(t, 1, mm.CRASH, 108)
	hero = "D4:2 A3:2 Bb3:1.5 A3:0.5 G3:2 Bb3:2 D4:2 Eb4:3 D4:1 D4:2 Bb3:1 G3:1 A3:2 Bb3:2 A3:4"
	brass.phrase(bar(19), hero, vel=110, legato=0.95, transpose=12)
	violin.phrase(bar(19), hero, vel=90, transpose=24, legato=0.95)
	flute.phrase(bar(21), lead, vel=116, slide=True, vibrato=True, transpose=12, legato=0.92)
	# The meteor lands (about 42.5 s): an extra blow.
	drums.note(bar(22) + 1.0, 2, mm.CRASH, 124)
	taiko.chord(bar(22) + 1.0, 2, [n("C2"), n("G2")], 127)
	# Bar 24 (46 s): the Nue. A dark, heavy blow.
	drums.note(bar(24), 2, mm.CRASH, 120)
	taiko.chord(bar(24), 2, [n("C2"), n("G2")], 127)
	timp.note(bar(24), 2, n("D2"), 127)
	brass.chord(bar(24), 3, notes("D2 A2 D3 F3"), 112)
	# Bars 26-27: the montage, quickening to the title.
	for k in range(8):
		timp.note(bar(27) + 2 + k * 0.25, 0.25, n("A2"), 64 + k * 7)
	# Bar 28 (54 s): the title. One last hit, then it rings out.
	drums.note(bar(28), 3, mm.CRASH, 127)
	taiko.chord(bar(28), 3, [n("C2"), n("G2")], 127)
	timp.note(bar(28), 4, n("D2"), 127)
	choir.chord(bar(28), 10, notes("D3 A3 D4 F4 A4"), 104)
	brass.chord(bar(28), 8, notes("D3 A3 D4"), 104)
	pad.chord(bar(28), 12, notes("D2 A2 D3"), 80)
	mm.arpeggio(koto, bar(28) + 1, 1, notes("D4 Eb4 G4 A4 Bb4 D5 Eb5 G5"), [0, 1, 2, 3, 4, 5, 6, 7], step=0.25, vel=76, ring=4.0)
	return s


def render_music(out: Path, work: Path) -> Path:
	song = compose()
	mid = work / "trailer.mid"
	raw = work / "trailer_raw.wav"
	song.to_midi(mid, repeats=1)
	subprocess.run(["fluidsynth", "-ni", "-q", "-g", "0.5", "-r", str(mm.SR), "-R", "1", "-C", "1",
		"-o", "synth.reverb.room-size=0.8", "-o", "synth.reverb.width=0.9", "-o", "synth.reverb.level=0.85",
		"-F", str(raw), str(mm.SOUNDFONT), str(mid)], check=True, stdout=subprocess.DEVNULL)
	rate, data = wavfile.read(raw)
	x = data.astype(np.float64) / 32768.0
	x = x[: round(SECONDS * rate)]
	if len(x) < round(SECONDS * rate):
		x = np.pad(x, ((0, round(SECONDS * rate) - len(x)), (0, 0)))
	# The last second fades out under the title.
	fade = int(rate * 1.2)
	x[-fade:] *= np.linspace(1.0, 0.0, fade)[:, None]
	x *= 0.89 / (np.max(np.abs(x)) + 1e-9)
	dest = out / "music.wav"
	wavfile.write(dest, rate, (x * 32767).astype(np.int16))
	return dest


def clarify(x: np.ndarray, sr: int) -> np.ndarray:
	"""Speech that cuts through music: rumble off, a presence lift at
	2-5.5 kHz (where consonants live), gentle compression so quiet syllables
	keep up with loud ones, then levelled."""
	from scipy.signal import butter, sosfilt

	x = sosfilt(butter(2, 80 / (sr / 2), "highpass", output="sos"), x)
	x = x + 0.45 * sosfilt(butter(2, [2200 / (sr / 2), 5500 / (sr / 2)], "bandpass", output="sos"), x)
	env = np.sqrt(np.convolve(x * x, np.ones(sr // 50) / (sr // 50), mode="same")) + 1e-6
	x = x * np.minimum(1.0, (0.12 / env) ** 0.35)
	return x * (0.85 / (np.max(np.abs(x)) + 1e-9))


def record_lines(kokoro: Path, out: Path) -> list[dict]:
	import make_voices as mv

	cast = json.loads(CAST.read_text())
	speaker = mv.Speaker(kokoro)
	cues = []
	for i, (at, who, text, speed) in enumerate(LINES):
		voice = dict(cast[who]["voice"])
		voice["speed"] = speed

		class Line:
			spoken = text
			mood = "neutral"

		x = speaker.say(Line, voice)
		if voice.get("effect") == "spirit":
			wet = mv.spirit(x, mv.SAMPLE_RATE)
			x = (1.0 - SPIRIT_MIX) * np.pad(x, (0, len(wet) - len(x))) + SPIRIT_MIX * wet
		x = clarify(x, mv.SAMPLE_RATE)
		dest = out / f"vo_{i}.wav"
		wavfile.write(dest, mv.SAMPLE_RATE, (x * 32767).astype(np.int16))
		cues.append({"file": dest.name, "at": at, "who": who, "text": text,
			"seconds": round(len(x) / mv.SAMPLE_RATE, 2)})
		print(f"{at:5.1f}s  {who:8s} {len(x) / mv.SAMPLE_RATE:4.1f}s  {text}")
	return cues


def main() -> int:
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	p.add_argument("--kokoro", type=Path, required=True, help="folder with kokoro-v1.0.onnx and voices-v1.0.bin")
	p.add_argument("--out", type=Path, required=True)
	args = p.parse_args()
	args.out.mkdir(parents=True, exist_ok=True)
	with tempfile.TemporaryDirectory() as tmp:
		music = render_music(args.out, Path(tmp))
	print(f"{music.name}: {SECONDS:.0f}s")
	cues = record_lines(args.kokoro, args.out)
	(args.out / "cues.json").write_text(json.dumps({"seconds": SECONDS, "lines": cues}, indent="\t"))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
