"""Composes and renders Project Shinobi's music as seamless Ogg Vorbis loops.

    python art/audio/make_music.py [--out game/assets/audio/music] [--only NAME]

Every track is written out below as notes. They're rendered through
FluidSynth with the FluidR3 General MIDI SoundFont (MIT licence), which has
sampled koto, shamisen, shakuhachi, taiko, strings, brass and choir. Each
loop is rendered three times and the middle pass is kept, so reverb from the
end carries into the start and the loop has no seam.

The music is original. It uses Japanese scales: miyako-bushi (D Eb G A Bb /
E F A B C), yo (G A C D E), hirajoshi (A B C E F), in (C Db F G Bb), ryo
(D E F# A B, the major pentatonic) and ryukyu (C E F G B). Each island has a
theme of its own, and the open world adds a night piece and a sea piece; a
second battle theme, a tense cue and a sad one serve the story.

Needs mido, numpy and scipy (pip), plus fluidsynth, fluid-soundfont-gm and
vorbis-tools (apt).
"""

from __future__ import annotations

import argparse
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import mido
import numpy as np
from scipy.io import wavfile

SR = 44100
TPB = 480
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "audio" / "music"
SOUNDFONT = Path("/usr/share/sounds/sf2/FluidR3_GM.sf2")

# General MIDI programs (0-based).
KOTO, SHAMISEN, SHAKUHACHI, TAIKO, FLUTE = 107, 106, 77, 116, 73
STRINGS, SLOW_STRINGS, PIZZICATO, VIOLIN, CELLO = 48, 49, 45, 40, 42
CHOIR, BRASS, TIMPANI, WARM_PAD, FINGER_BASS = 52, 61, 47, 89, 33
CELESTA, GLOCKENSPIEL, TUBULAR_BELLS, HARP, TREMOLO_STRINGS, CONTRABASS = 8, 9, 14, 46, 44, 43
OBOE, ENGLISH_HORN, PAN_FLUTE, VOICE_OOH, FRENCH_HORN, ACOUSTIC_BASS = 68, 69, 75, 53, 60, 32
KALIMBA, TINKLE_BELL, BOWED_PAD, ATMOSPHERE, CRYSTAL, REVERSE_CYMBAL = 108, 112, 92, 99, 98, 119
DRUMS = -1  # channel 10
# Drum kit notes.
KICK, SNARE, HAT, OPEN_HAT, CRASH, LOW_TOM, MID_TOM, HIGH_TOM = 36, 38, 42, 46, 49, 45, 47, 50
SIDE_STICK, CLAP, TAMBOURINE, CLAVES, WOODBLOCK = 37, 39, 54, 75, 76

_LETTER = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def n(name: str) -> int:
	"""MIDI note number from a name like "Eb4" or "C#5" (C4 = 60)."""
	pitch = _LETTER[name[0]]
	rest = name[1:]
	while rest and rest[0] in "b#":
		pitch += -1 if rest[0] == "b" else 1
		rest = rest[1:]
	return 12 * (int(rest) + 1) + pitch


def notes(text: str) -> list[int]:
	return [n(x) for x in text.split()]


class Part:
	"""One instrument on one MIDI channel."""

	def __init__(self, program: int, channel: int, volume: int, pan: int, reverb: int, chorus: int, humanize: float):
		self.program = program
		self.channel = channel
		self.volume = volume
		self.pan = pan
		self.reverb = reverb
		self.chorus = chorus
		self.humanize = humanize
		self.events: list[tuple[float, float, int, int]] = []   # beat, length, pitch, velocity
		self.controls: list[tuple[float, str, int, int]] = []    # beat, kind, number, value

	def note(self, beat: float, length: float, pitch: int, vel: int = 90) -> None:
		self.events.append((beat, length, pitch, vel))

	def chord(self, beat: float, length: float, pitches: list[int], vel: int = 80) -> None:
		for p in pitches:
			self.note(beat, length, p, vel)

	def phrase(self, beat: float, line: str, vel: int = 90, slide: bool = False, vibrato: bool = False,
			transpose: int = 0, legato: float = 0.95) -> float:
		"""Plays "A4:2 Bb4:1 r:1 ..." (name:beats, r for a rest) from `beat`.
		Slides bend up into each phrase's first note, as a shakuhachi does;
		vibrato swells on held notes. Returns the beat after the phrase."""
		first = True
		for token in line.split():
			name, length = token.split(":")
			length = float(length)
			if name != "r":
				pitch = n(name) + transpose
				self.note(beat, length * legato, pitch, vel)
				if slide and first:
					self.controls.append((beat - 0.02, "bend", 0, -2400))
					self.controls.append((beat + 0.2, "bend", 0, 0))
				if vibrato and length >= 1.5:
					self.controls.append((beat, "cc", 1, 0))
					self.controls.append((beat + length * 0.45, "cc", 1, 0))
					self.controls.append((beat + length * 0.8, "cc", 1, 55))
					self.controls.append((beat + length, "cc", 1, 0))
				first = False
			else:
				first = True
			beat += length
		return beat


class Song:
	def __init__(self, name: str, bpm: float, bars: int, seed: int, beats_per_bar: int = 4):
		self.name = name
		self.bpm = bpm
		self.bars = bars
		self.bpb = beats_per_bar
		self.parts: list[Part] = []
		self.rng = random.Random(seed)
		self._next_channel = 0

	@property
	def beats(self) -> int:
		return self.bars * self.bpb

	@property
	def seconds(self) -> float:
		return self.beats * 60.0 / self.bpm

	def bar(self, b: int) -> float:
		"""First beat of bar `b` (1-based, like a score)."""
		return (b - 1) * self.bpb

	def part(self, program: int, volume: int = 100, pan: int = 64, reverb: int = 50, chorus: int = 0,
			humanize: float = 0.012) -> Part:
		if program == DRUMS:
			channel = 9
		else:
			channel = self._next_channel
			self._next_channel += 1
			if self._next_channel == 9:
				self._next_channel = 10
		p = Part(program, channel, volume, pan, reverb, chorus, 0.0 if program == DRUMS else humanize)
		self.parts.append(p)
		return p

	def to_midi(self, path: Path, repeats: int) -> None:
		mid = mido.MidiFile(ticks_per_beat=TPB)
		meta = mido.MidiTrack()
		meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(self.bpm), time=0))
		mid.tracks.append(meta)
		for part in self.parts:
			timed: list[tuple[int, int, mido.Message]] = []   # tick, order, message
			ch = part.channel
			setup = [("control_change", dict(control=0, value=0)), ("control_change", dict(control=7, value=part.volume)),
				("control_change", dict(control=10, value=part.pan)), ("control_change", dict(control=91, value=part.reverb)),
				("control_change", dict(control=93, value=part.chorus)),
				# Pitch bend range: 2 semitones.
				("control_change", dict(control=101, value=0)), ("control_change", dict(control=100, value=0)),
				("control_change", dict(control=6, value=2)), ("control_change", dict(control=38, value=0))]
			for kind, args in setup:
				timed.append((0, 0, mido.Message(kind, channel=ch, **args)))
			if part.program != DRUMS:
				timed.append((0, 1, mido.Message("program_change", channel=ch, program=part.program)))
			for rep in range(repeats):
				offset = rep * self.beats
				for beat, length, pitch, vel in part.events:
					jitter = self.rng.uniform(-part.humanize, part.humanize)
					on = max(0, round((offset + beat + jitter) * TPB))
					off = max(on + 1, round((offset + beat + length) * TPB))
					v = max(1, min(127, vel + self.rng.randint(-5, 5)))
					timed.append((on, 3, mido.Message("note_on", channel=ch, note=pitch, velocity=v)))
					timed.append((off, 2, mido.Message("note_off", channel=ch, note=pitch, velocity=0)))
				for beat, kind, number, value in part.controls:
					tick = max(0, round((offset + beat) * TPB))
					if kind == "bend":
						timed.append((tick, 1, mido.Message("pitchwheel", channel=ch, pitch=value)))
					else:
						timed.append((tick, 1, mido.Message("control_change", channel=ch, control=number, value=value)))
			timed.sort(key=lambda t: (t[0], t[1]))
			track = mido.MidiTrack()
			last = 0
			for tick, _, msg in timed:
				track.append(msg.copy(time=tick - last))
				last = tick
			mid.tracks.append(track)
		mid.save(path)


# --------------------------------------------------------------------------
# Shared figures
# --------------------------------------------------------------------------

def arpeggio(part: Part, start: float, bars: int, pool: list[int], pattern: list[int], step: float = 0.5,
		vel: int = 70, accent: int = 10, ring: float = 2.0, bpb: int = 4) -> None:
	"""A plucked figure cycling through `pool` by `pattern` indices; each note rings on."""
	beat = start
	end = start + bars * bpb
	i = 0
	while beat < end - 1e-6:
		idx = pattern[i % len(pattern)]
		v = vel + (accent if abs((beat - start) % bpb) < 1e-6 else 0)
		part.note(beat, ring, pool[idx], v)
		beat += step
		i += 1


def taiko_hits(part: Part, start: float, hits: list[tuple[float, int, int]]) -> None:
	"""(beat offset, pitch, velocity) hits from `start`."""
	for off, pitch, vel in hits:
		part.note(start + off, 1.5, pitch, vel)


def bed(part: Part, song: Song, start: int, end: int, chords: list[list[int]], per: int, vel: int,
		trim: float = 0.1) -> None:
	"""Holds a chord for `per` bars at a time from bar `start` through `end`.
	Chord k plays in bars k*per+1 ... (k+1)*per, and the list repeats."""
	b = start
	while b <= end:
		k = (b - 1) // per
		last = min((k + 1) * per, end)
		part.chord(song.bar(b), (last - b + 1) * song.bpb - trim, chords[k % len(chords)], vel)
		b = last + 1


def roll(part: Part, song: Song, start: int, end: int, pools: list[list[int]], per: int,
		patterns: list[list[int]], vel: int, step: float = 0.5, accent: int = 8, ring: float = 2.5) -> None:
	"""A plucked figure bar by bar: the pool changes every `per` bars, the pattern every bar."""
	for b in range(start, end + 1):
		pool = pools[((b - 1) // per) % len(pools)]
		arpeggio(part, song.bar(b), 1, pool, patterns[(b - 1) % len(patterns)], step=step, vel=vel,
			accent=accent, ring=ring, bpb=song.bpb)


# --------------------------------------------------------------------------
# Title: "Ink and Ember". D miyako-bushi, slow, koto and shakuhachi.
# --------------------------------------------------------------------------

def title() -> Song:
	s = Song("title", bpm=72, bars=32, seed=11)
	koto = s.part(KOTO, volume=104, pan=50, reverb=70)
	pad = s.part(SLOW_STRINGS, volume=70, pan=64, reverb=80)
	cello = s.part(CELLO, volume=76, pan=76, reverb=70)
	shaku = s.part(SHAKUHACHI, volume=108, pan=60, reverb=85)
	flute = s.part(FLUTE, volume=58, pan=80, reverb=90)
	taiko = s.part(TAIKO, volume=96, pan=64, reverb=60, humanize=0.0)
	violins = s.part(STRINGS, volume=64, pan=40, reverb=80)

	# 8-bar cycle, two bars per chord except the last two.
	cycle = [
		("D", notes("D3 A3 D4 Eb4 A4"), notes("D3 A3 D4"), n("D2"), 2),
		("Bb", notes("Bb2 D3 A3 Bb3 D4"), notes("Bb2 F3 D4"), n("Bb1"), 2),
		("Gm", notes("G2 D3 G3 Bb3 D4"), notes("G2 D3 Bb3"), n("G1"), 2),
		("Eb", notes("Eb3 Bb3 D4 Eb4 G4"), notes("Eb3 Bb3 G4"), n("Eb2"), 1),
		("A", notes("A2 D3 A3 Bb3 D4"), notes("A2 D3 A3"), n("A1"), 1),
	]
	up_down = [0, 1, 2, 3, 4, 3, 2, 1]
	turn = [0, 2, 1, 3, 2, 4, 3, 2]
	bar = 1
	while bar <= s.bars:
		for _, pool, voicing, root, length in cycle:
			for k in range(length):
				b = bar + k
				if b > s.bars:
					break
				soft = b >= 31
				arpeggio(koto, s.bar(b), 1, pool, up_down if k == 0 else turn, vel=58 if soft else 66)
			if bar >= 5 and bar < 31:
				pad.chord(s.bar(bar), length * 4 - 0.1, voicing, 56 if bar < 17 else 66)
				cello.note(s.bar(bar), length * 4 - 0.1, root + 12, 62)
			if bar >= 25 and bar < 31:
				violins.chord(s.bar(bar), length * 4 - 0.1, [p + 12 for p in voicing[1:]], 52)
			bar += length

	a = "A4:2 Bb4:1 A4:1 G4:1.5 A4:0.5 D4:2 D4:1 Eb4:1 G4:1 A4:1 Bb4:3 r:1 " \
		"D5:2 Bb4:1 A4:1 G4:1 A4:0.5 G4:0.5 D4:2 Eb4:1 G4:1 Bb4:1.5 A4:0.5 A4:4"
	b = "D5:1 Eb5:1 D5:1 A4:1 Bb4:1.5 A4:0.5 G4:1 A4:1 D5:2 Eb5:1 D5:1 Bb4:3 r:1 " \
		"G5:2 Eb5:1 D5:1 Bb4:1.5 A4:0.5 G4:2 G4:1 Bb4:1 Eb5:1 D5:1 A4:2 G4:1 A4:1"
	a_end = a.rsplit(" ", 1)[0] + " D4:4"
	shaku.phrase(s.bar(9), a, vel=84, slide=True, vibrato=True)
	shaku.phrase(s.bar(17), b, vel=94, slide=True, vibrato=True)
	flute.phrase(s.bar(17), b, vel=60, transpose=12)
	shaku.phrase(s.bar(25), a_end, vel=88, slide=True, vibrato=True)

	# Taiko: a heartbeat under the melody, fuller in the second half.
	for b in range(9, 31, 2):
		taiko_hits(taiko, s.bar(b), [(0, n("D2"), 88), (2.5, n("A2"), 52)] if b < 17 else
			[(0, n("D2"), 98), (1.5, n("A2"), 58), (2, n("D2"), 76), (3.5, n("A2"), 50)])
	taiko_hits(taiko, s.bar(24), [(3, n("A2"), 60), (3.25, n("A2"), 68), (3.5, n("A2"), 76), (3.75, n("A2"), 86)])
	return s


# --------------------------------------------------------------------------
# Calm: "Emberwood Morning". G yo scale, koto, flute, pizzicato.
# --------------------------------------------------------------------------

def calm() -> Song:
	s = Song("calm", bpm=80, bars=24, seed=23)
	koto = s.part(KOTO, volume=96, pan=44, reverb=70)
	pizz = s.part(PIZZICATO, volume=78, pan=80, reverb=60)
	pad = s.part(WARM_PAD, volume=58, pan=64, reverb=80, chorus=30)
	flute = s.part(FLUTE, volume=96, pan=60, reverb=80)
	shaku = s.part(SHAKUHACHI, volume=98, pan=70, reverb=85)

	cycle = [
		(notes("G2 D3 G3 A3 D4"), notes("G3 D4 A4"), n("G2")),
		(notes("C3 G3 C4 D4 E4"), notes("C4 G4 E4"), n("C3")),
		(notes("A2 E3 A3 C4 E4"), notes("A3 E4 C5"), n("A2")),
		(notes("D3 A3 D4 E4 A4"), notes("D4 A4 E4"), n("D3")),
	]
	pattern = [0, 2, 1, 3, 2, 4, 3, 1]
	for b in range(1, s.bars + 1):
		pool, voicing, root = cycle[(b - 1) % 4]
		arpeggio(koto, s.bar(b), 1, pool, pattern, vel=58 if b <= 4 or b > 20 else 62, ring=2.5)
		pad.chord(s.bar(b), 3.9, voicing, 44)
		if 5 <= b <= 20:
			for beat, p in [(0, root), (1.5, root + 7), (2, root + 12), (3, root + 7)]:
				pizz.note(s.bar(b) + beat, 0.4, p, 64)

	a = "D5:1 E5:1 G5:1.5 E5:0.5 D5:2 C5:1 A4:1 C5:1 D5:1 E5:2 D5:3 r:1 " \
		"G5:1 A5:1 G5:1 E5:1 D5:1.5 E5:0.5 C5:2 A4:1 C5:1 D5:1 E5:1 D5:4"
	b = "G4:2 A4:1 C5:1 D5:2 E5:2 E5:1 D5:1 C5:1 A4:1 A4:3 r:1 " \
		"D5:1.5 E5:0.5 D5:1 C5:1 A4:1 G4:1 A4:2 C5:1 A4:1 G4:1 E4:1 D4:4"
	flute.phrase(s.bar(5), a, vel=74, vibrato=True)
	shaku.phrase(s.bar(13), b, vel=80, slide=True, vibrato=True)
	flute.phrase(s.bar(17), " ".join(a.split()[12:]), vel=52, transpose=-12)
	return s


# --------------------------------------------------------------------------
# Battle: "Steel in the Rain". E miyako-bushi, 140 BPM.
# --------------------------------------------------------------------------

def battle() -> Song:
	s = Song("battle", bpm=140, bars=44, seed=37)
	drums = s.part(DRUMS, volume=104, reverb=30)
	taiko = s.part(TAIKO, volume=112, pan=64, reverb=50, humanize=0.0)
	bass = s.part(FINGER_BASS, volume=100, pan=64, reverb=20, humanize=0.005)
	ost = s.part(STRINGS, volume=92, pan=40, reverb=45, humanize=0.005)
	sham = s.part(SHAMISEN, volume=100, pan=88, reverb=40, humanize=0.006)
	lead = s.part(SHAKUHACHI, volume=112, pan=58, reverb=60)
	violin = s.part(VIOLIN, volume=84, pan=70, reverb=60)
	brass = s.part(BRASS, volume=96, pan=52, reverb=55)

	roots = [n("E2"), n("C2"), n("A1"), n("F1")]
	triads = [notes("E3 B3 E4 G4"), notes("C3 G3 C4 E4"), notes("A2 E3 A3 C4"), notes("F2 C3 F3 A3")]
	riff = notes("E4 E4 B4 E4 C5 B4 A4 E4 F4 E4 B4 E4 A4 B4 C5 B4")

	def section(b: int) -> str:
		if b <= 4:
			return "intro"
		if b <= 12:
			return "A"
		if b <= 20:
			return "B"
		if b <= 28:
			return "C"
		if b <= 32:
			return "break"
		if b <= 40:
			return "B2"
		return "turn"

	for b in range(1, s.bars + 1):
		sec = section(b)
		chord = ((b - 1) // 2) % 4
		root = roots[chord]
		t = s.bar(b)
		# String ostinato: root, octave and fifth in driving eighths.
		o = root + 12
		for k, p in enumerate([o, o, o + 12, o, o + 7, o, o + 12, o + 7]):
			vel = 70 + (14 if k in (0, 3, 6) else 0) + (8 if sec in ("C", "B2") else 0)
			if sec == "intro":
				vel -= 20 - 4 * b
			ost.note(t + k * 0.5, 0.3, p, vel)
		if sec not in ("intro", "break"):
			for k in range(8):
				bass.note(t + k * 0.5, 0.42, root + (12 if k in (3, 7) else 0), 92 if k in (0, 3, 5) else 74)
		elif sec == "break":
			bass.note(t, 3.8, root, 90)
		if sec in ("A", "C", "turn") or (sec == "B" and b % 2 == 0):
			for k, p in enumerate(riff):
				sham.note(t + k * 0.25, 0.22, p, 84 if k % 4 == 0 else 66)
		# Drum kit.
		if sec in ("A", "B", "C", "B2", "turn"):
			for k in range(8):
				drums.note(t + k * 0.5, 0.2, OPEN_HAT if k == 7 else HAT, 70 if k % 2 == 0 else 54)
			for beat in (0, 1.5, 2.5):
				drums.note(t + beat, 0.2, KICK, 104)
			for beat in (1, 3):
				drums.note(t + beat, 0.2, SNARE, 100)
			if b in (5, 13, 21, 25, 33, 37):
				drums.note(t, 1, CRASH, 100)
		elif sec == "break":
			drums.note(t, 0.2, KICK, 100)
			drums.note(t + 2, 0.2, KICK, 96)
			if b == 32:
				for k in range(16):
					drums.note(t + k * 0.25, 0.2, SNARE, 50 + k * 4)
		# Taiko: carries the intro and break, punctuates the rest.
		if sec in ("intro", "break"):
			taiko_hits(taiko, t, [(0, n("C2"), 112), (0.75, n("G2"), 70), (1.5, n("C2"), 96), (2, n("G2"), 80),
				(3, n("C2"), 104), (3.5, n("G2"), 76)])
		elif b % 2 == 1:
			taiko_hits(taiko, t, [(0, n("C2"), 108), (2.5, n("G2"), 82)])
		# Brass stabs on each chord change in C and B2.
		if sec in ("C", "B2") and b % 2 == 1:
			brass.chord(t, 0.45, triads[chord], 96)
			brass.chord(t + 1.5, 0.45, triads[chord], 88)
			brass.chord(t + 3, 0.9, triads[chord], 92)

	# Fills into the loop point and the break.
	for bar_no in (28, 44):
		t = s.bar(bar_no) + 2
		for k, p in enumerate([HIGH_TOM, HIGH_TOM, MID_TOM, MID_TOM, LOW_TOM, LOW_TOM, LOW_TOM, CRASH]):
			drums.note(t + k * 0.25, 0.2, p, 90 + k * 3)

	m1 = "E5:1.5 F5:0.5 E5:1 B4:1 C5:1 B4:1 A4:2 C5:1.5 B4:0.5 A4:1 E4:1 F4:2 E4:2 " \
		"A4:1 B4:1 C5:1 E5:1 F5:2 E5:1 C5:1 B4:1.5 C5:0.5 B4:1 A4:1 B4:4"
	m2 = "B5:2 A5:1 B5:1 C6:1 B5:1 A5:1 F5:1 E5:2 F5:1 A5:1 C6:3 B5:1 " \
		"A5:1.5 F5:0.5 E5:1 C5:1 E5:1 F5:1 A5:2 F5:1 E5:1 C5:1 B4:1 E5:4"
	lead.phrase(s.bar(13), m1, vel=100, slide=True, vibrato=True, legato=0.9)
	violin.phrase(s.bar(13), m1, vel=70, transpose=-12, legato=0.9)
	violin.phrase(s.bar(21), m2, vel=92, legato=0.9)
	lead.phrase(s.bar(21), m2, vel=86, slide=True, vibrato=True, transpose=-12, legato=0.9)
	lead.phrase(s.bar(33), m1, vel=108, slide=True, vibrato=True, transpose=12, legato=0.9)
	violin.phrase(s.bar(33), m1, vel=84, legato=0.9)
	return s


# --------------------------------------------------------------------------
# Boss: "Nue". D miyako-bushi, 150 BPM, choir, brass and timpani.
# --------------------------------------------------------------------------

def boss() -> Song:
	s = Song("boss", bpm=150, bars=40, seed=53)
	drums = s.part(DRUMS, volume=100, reverb=40)
	taiko = s.part(TAIKO, volume=116, pan=64, reverb=60, humanize=0.0)
	timp = s.part(TIMPANI, volume=104, pan=64, reverb=60, humanize=0.0)
	low = s.part(STRINGS, volume=100, pan=44, reverb=50, humanize=0.004)
	choir = s.part(CHOIR, volume=86, pan=64, reverb=90)
	brass = s.part(BRASS, volume=100, pan=76, reverb=60)
	lead = s.part(SHAKUHACHI, volume=116, pan=56, reverb=70)
	violin = s.part(STRINGS, volume=80, pan=84, reverb=70)

	# Two bars per chord: Dm, Bb, Gm, A.
	roots = [n("D2"), n("Bb1"), n("G1"), n("A1")]
	chords = [notes("D3 A3 D4 F4"), notes("Bb2 F3 Bb3 D4"), notes("G2 D3 G3 Bb3"), notes("A2 E3 A3 C#4")]
	# Low-string figure: root, octave, and a half-step lean (Eb over D) for menace.
	figures = [
		[0, 0, 12, 0, 13, 0, 7, 12],
		[0, 0, 12, 0, 11, 0, 7, 12],
		[0, 0, 12, 0, 8, 0, 7, 12],
		[0, 0, 12, 0, 6, 0, 7, 12],
	]

	def section(b: int) -> str:
		if b <= 4:
			return "intro"
		if b <= 12:
			return "A"
		if b <= 20:
			return "B"
		if b <= 28:
			return "C"
		if b <= 32:
			return "break"
		return "B2"

	for b in range(1, s.bars + 1):
		sec = section(b)
		ci = ((b - 1) // 2) % 4
		root = roots[ci] + 12
		t = s.bar(b)
		for k, off in enumerate(figures[ci]):
			low.note(t + k * 0.5, 0.32, root + off, 88 if k in (0, 3, 6) else 70)
		if b % 2 == 1 and b >= 3:
			choir.chord(t, 7.8, chords[ci], 70 if sec in ("intro", "break") else 84)
		# Timpani on the downbeats, rolls into sections.
		if sec in ("intro", "break"):
			timp.note(t, 1.0, roots[ci] + 12, 100)
			timp.note(t + 2.5, 0.5, roots[ci] + 12, 78)
		elif b % 2 == 1:
			timp.note(t, 1.0, roots[ci] + 12, 96)
		if b in (4, 12, 20, 28, 32, 40):
			for k in range(8):
				timp.note(t + 2 + k * 0.25, 0.25, n("D3") if b != 40 else n("A2"), 60 + k * 6)
		if sec != "intro":
			pattern = [(0, n("C2"), 116), (0.5, n("G2"), 70), (1, n("C2"), 90), (1.75, n("G2"), 76),
				(2, n("C2"), 104), (2.75, n("G2"), 80), (3, n("C2"), 96), (3.5, n("G2"), 84)] \
				if sec in ("C", "B2") else [(0, n("C2"), 112), (1.5, n("C2"), 90), (2, n("G2"), 78), (3, n("C2"), 100)]
			taiko_hits(taiko, t, pattern)
		if sec in ("A", "B", "C", "B2"):
			drums.note(t, 0.2, KICK, 108)
			drums.note(t + 1, 0.2, LOW_TOM, 90)
			drums.note(t + 2, 0.2, KICK, 104)
			drums.note(t + 3, 0.2, LOW_TOM, 94)
			drums.note(t + 3.5, 0.2, MID_TOM, 86)
			if b in (5, 13, 21, 33):
				drums.note(t, 1, CRASH, 108)
		# Brass holds the harmony in A, stabs in B.
		if sec == "A" and b % 2 == 1:
			brass.chord(t, 7.6, [p for p in chords[ci][:3]], 78)
		elif sec in ("B", "B2") and b % 2 == 1:
			brass.chord(t, 0.5, chords[ci][:3], 96)
			brass.chord(t + 0.75, 0.5, chords[ci][:3], 88)

	m = "D5:1 Eb5:1 D5:0.5 A4:0.5 Bb4:1 A4:2 G4:1 A4:1 Bb4:1 D5:1 Eb5:1.5 D5:0.5 D5:3 r:1 " \
		"G5:2 Eb5:1 D5:1 Bb4:1 A4:1 G4:2 A4:1 Bb4:1 A4:1 G4:1 D4:1 Eb4:1 A4:2"
	hero = "D4:2 A3:2 Bb3:1.5 A3:0.5 G3:2 Bb3:2 D4:2 Eb4:3 D4:1 " \
		"D4:2 Bb3:1 G3:1 A3:2 Bb3:2 A3:4 A3:2 D4:2"
	lead.phrase(s.bar(13), m, vel=100, slide=True, vibrato=True, legato=0.92)
	violin.phrase(s.bar(13), m, vel=74, legato=0.92)
	brass.phrase(s.bar(21), hero, vel=104, legato=0.95)
	brass.phrase(s.bar(21), hero, vel=90, transpose=12, legato=0.95)
	violin.phrase(s.bar(21), hero, vel=84, transpose=24, legato=0.95)
	lead.phrase(s.bar(33), m, vel=112, slide=True, vibrato=True, transpose=12, legato=0.92)
	violin.phrase(s.bar(33), m, vel=88, legato=0.92)
	return s


# --------------------------------------------------------------------------
# Autumn Wood: "Maple Weather". A hirajoshi, 3/4, harp, koto, falling kalimba.
# --------------------------------------------------------------------------

def autumn_wood() -> Song:
	s = Song("autumn_wood", bpm=84, bars=32, seed=61, beats_per_bar=3)
	harp = s.part(HARP, volume=92, pan=46, reverb=75)
	cello = s.part(CELLO, volume=78, pan=80, reverb=70)
	pad = s.part(SLOW_STRINGS, volume=62, pan=64, reverb=85)
	kalimba = s.part(KALIMBA, volume=76, pan=88, reverb=85)
	koto = s.part(KOTO, volume=100, pan=56, reverb=75)
	shaku = s.part(SHAKUHACHI, volume=100, pan=70, reverb=85)

	# An eight-bar cycle: Am, Am, F, F, C, C, E (with its flat ninth), Am.
	am, f, c, e = notes("A2 E3 A3 C4 E4 A4"), notes("F2 C3 F3 A3 C4 E4"), notes("C3 E3 B3 C4 E4 B4"), notes("E2 B2 E3 B3 E4 F4")
	pools = [am, am, f, f, c, c, e, am]
	voicings = [notes("A3 C4 E4")] * 2 + [notes("F3 A3 C4 E4")] * 2 + [notes("C4 E4 B4")] * 2 + [notes("E3 B3 E4"), notes("A3 C4 E4")]
	for b in range(1, s.bars + 1):
		soft = b <= 4 or b >= 31
		roll(harp, s, b, b, pools, 1, [[0, 2, 3, 5, 3, 2], [1, 3, 4, 5, 4, 2]], vel=46 if soft else 58, ring=2.5)
	bed(pad, s, 5, 30, voicings, 1, 48)
	roots = [n("A2"), n("A2"), n("F2"), n("F2"), n("C3"), n("C3"), n("E2"), n("A2")]
	for b in range(1, s.bars + 1):
		i = (b - 1) % 8
		if i in (0, 2, 4, 6, 7):
			cello.note(s.bar(b), (2 if i in (0, 2, 4) else 1) * 3 - 0.1, roots[i], 60)

	# Leaves coming down, one by one: (bar in the block, beat, note).
	leaves = [(2, 1, "E6"), (2, 2, "C6"), (4, 0, "F6"), (4, 1.5, "E6"), (4, 2.5, "C6"), (6, 1, "B5"), (6, 2, "A5"),
		(8, 0, "E6"), (8, 1, "C6"), (8, 2, "A5")]
	for block in (1, 9, 17, 25):
		fewer = block == 17   # the shakuhachi has the stage
		for bar_in, beat, name in leaves[:5] if fewer else leaves:
			kalimba.note(s.bar(block + bar_in - 1) + beat, 2, n(name), 50)

	a = "E5:2 C5:1 A4:1.5 B4:0.5 C5:1 E5:2 F5:1 E5:3 C5:1 B4:1 A4:1 B4:2 C5:1 A4:3 r:3"
	b = "A5:2 F5:1 E5:1.5 F5:0.5 E5:1 C5:2 B4:1 C5:3 E5:1 F5:1 A5:1 F5:2 E5:1 C5:2 B4:1 A4:3"
	koto.phrase(s.bar(9), a, vel=82)
	shaku.phrase(s.bar(17), b, vel=90, slide=True, vibrato=True)
	for bar_no in range(17, 25, 2):
		koto.chord(s.bar(bar_no), 4, voicings[(bar_no - 1) % 8][:3], 54)
	koto.phrase(s.bar(25), a, vel=66)
	shaku.phrase(s.bar(25), "A4:6 C5:6 A4:6 F4:6", vel=70, slide=True, vibrato=True)
	return s


# --------------------------------------------------------------------------
# Ashen Pass: "Cinders". C in scale (C Db F G Bb), very slow, a bowed drone.
# --------------------------------------------------------------------------

def ashen_pass() -> Song:
	s = Song("ashen_pass", bpm=52, bars=16, seed=71)
	bass = s.part(CONTRABASS, volume=90, pan=60, reverb=70)
	pad = s.part(BOWED_PAD, volume=68, pan=64, reverb=90)
	bells = s.part(TUBULAR_BELLS, volume=70, pan=86, reverb=100)
	shaku = s.part(SHAKUHACHI, volume=106, pan=58, reverb=90)
	koto = s.part(KOTO, volume=84, pan=40, reverb=85)
	taiko = s.part(TAIKO, volume=86, pan=64, reverb=80, humanize=0.0)

	# Two bars to a chord, over a drone on C that never quite agrees with them.
	home, soft, low, dark = notes("C3 G3 C4 Db4 F4"), notes("Db3 F3 Bb3 Db4"), notes("Bb2 F3 Bb3 Db4 F4"), notes("G2 Db3 G3 Bb3 Db4")
	bed(pad, s, 1, 16, [home, soft, home, low, dark, soft, low, home], 2, 54)
	for k, root in enumerate([n("C2"), n("Db2"), n("C2"), n("Bb1"), n("G1"), n("Db2"), n("Bb1"), n("C2")]):
		bass.note(s.bar(1 + 2 * k), 7.8, root, 64)
	for bar_no, beat, name in [(3, 0, "G4"), (7, 2, "Db5"), (11, 0, "C5"), (13, 2, "F4"), (15, 0, "C4")]:
		bells.note(s.bar(bar_no) + beat, 4, n(name), 48)
	for bar_no, chord in {1: "C3 G3 Db4", 5: "Db3 F3 Bb3", 9: "G2 Db3 Bb3", 13: "Bb2 F3 Db4"}.items():
		for i, p in enumerate(notes(chord)):
			koto.note(s.bar(bar_no) + i * 0.2, 5, p, 52)
	# A heartbeat a long way off, nearer at the end.
	for bar_no in range(5, 17, 2):
		taiko_hits(taiko, s.bar(bar_no), [(0, n("C2"), 62), (0.75, n("C2"), 44)])
	for bar_no in (14, 16):
		taiko_hits(taiko, s.bar(bar_no), [(0, n("C2"), 66), (0.75, n("C2"), 48)])

	shaku.phrase(s.bar(3), "G4:3 Bb4:1 Db5:2 C5:1 Bb4:1 G4:4 r:4", vel=78, slide=True, vibrato=True)
	shaku.phrase(s.bar(9), "F4:2 G4:2 Bb4:3 G4:1 Db5:4 C5:2 G4:2", vel=84, slide=True, vibrato=True)
	shaku.phrase(s.bar(13), "G4:4 F4:2 Db4:2 C4:4 r:4", vel=70, slide=True, vibrato=True)
	return s


# --------------------------------------------------------------------------
# Old Dam: "Spillway". Bb yo, 6/8, harp water over a slow stone pulse.
# --------------------------------------------------------------------------

def old_dam() -> Song:
	# A bar is six eighth-note beats, so `bpm` counts eighths (dotted quarter = 56).
	s = Song("old_dam", bpm=168, bars=32, seed=83, beats_per_bar=6)
	harp = s.part(HARP, volume=94, pan=46, reverb=70)
	bass = s.part(ACOUSTIC_BASS, volume=92, pan=60, reverb=40)
	timp = s.part(TIMPANI, volume=96, pan=64, reverb=65, humanize=0.0)
	choir = s.part(VOICE_OOH, volume=70, pan=64, reverb=90)
	horn = s.part(ENGLISH_HORN, volume=104, pan=62, reverb=75)
	flute = s.part(FLUTE, volume=84, pan=82, reverb=80)
	koto = s.part(KOTO, volume=96, pan=36, reverb=70)

	# Two bars to a chord: Bb, Eb, Gm, Cm, Bb, Eb, Cm, F, and round again.
	pools = [notes("Bb2 F3 Bb3 C4 F4 Bb4"), notes("Eb3 Bb3 Eb4 F4 Bb4 C5"), notes("G3 Bb3 C4 F4 G4 Bb4"),
		notes("C3 G3 C4 Eb4 G4 C5"), notes("Bb2 F3 Bb3 C4 F4 Bb4"), notes("Eb3 Bb3 Eb4 F4 Bb4 C5"),
		notes("C3 G3 C4 Eb4 G4 C5"), notes("F3 C4 Eb4 F4 G4 C5")]
	roots = [n("Bb1"), n("Eb2"), n("G1"), n("C2"), n("Bb1"), n("Eb2"), n("C2"), n("F1")]
	choir_v = [notes("Bb3 F4 Bb4"), notes("Bb3 Eb4 G4"), notes("G3 Bb3 F4"), notes("C4 Eb4 G4"),
		notes("Bb3 F4 Bb4"), notes("Bb3 Eb4 G4"), notes("C4 Eb4 G4"), notes("C4 Eb4 F4")]
	water = [[0, 2, 3, 4, 3, 2], [1, 3, 4, 5, 4, 3]]
	for b in range(1, s.bars + 1):
		brk = 17 <= b <= 20
		roll(harp, s, b, b, pools, 2, water, vel=50 if b <= 4 else 56, step=1.0, accent=10, ring=3.0)
		root = roots[((b - 1) // 2) % 8]
		t = s.bar(b)
		bass.note(t, 2.6, root, 86)
		bass.note(t + 3, 2.6, root if b % 2 else root + 7, 68)
		if b >= 3:
			timp.note(t, 2.0, root + 12, 66 if brk else 84)
			if b % 2 == 0 and not brk:
				timp.note(t + 3, 1.0, root + 12, 56)
	for bar_no in (16, 32):
		for k in range(4):
			timp.note(s.bar(bar_no) + 3 + k * 0.75, 0.7, n("Bb2"), 60 + k * 10)
	bed(choir, s, 9, 16, choir_v, 2, 50)
	bed(choir, s, 21, 32, choir_v, 2, 56)
	for bar_no in (17, 19):
		arpeggio(koto, s.bar(bar_no), 2, notes("Bb3 C4 Eb4 F4 G4 Bb4 C5"), [0, 2, 4, 6, 4, 2], step=1.0, vel=60, ring=4, bpb=6)

	m = "G4:3 F4:1 G4:1 Bb4:1 C5:3 Bb4:2 G4:1 Eb4:3 F4:1 G4:2 Bb4:6 " \
		"F4:3 G4:1 Bb4:2 C5:3 Eb5:3 Bb4:3 G4:1 F4:2 G4:6 " \
		"Eb5:3 C5:1 Bb4:2 G4:3 Bb4:1 C5:2 F4:3 Eb4:1 F4:2 G4:6"
	horn.phrase(s.bar(5), m, vel=84, vibrato=True)
	horn.phrase(s.bar(21), m, vel=96, vibrato=True)
	flute.phrase(s.bar(21), m, vel=58, transpose=12)
	return s


# --------------------------------------------------------------------------
# Frozen Road: "Lantern Snow". C ryukyu (C E F G B), bells, choir, a pan flute.
# --------------------------------------------------------------------------

def frozen_road() -> Song:
	s = Song("frozen_road", bpm=60, bars=16, seed=97)
	celesta = s.part(CELESTA, volume=90, pan=50, reverb=95)
	glock = s.part(GLOCKENSPIEL, volume=62, pan=82, reverb=100)
	strings = s.part(SLOW_STRINGS, volume=72, pan=64, reverb=90)
	choir = s.part(VOICE_OOH, volume=66, pan=64, reverb=100)
	flute = s.part(PAN_FLUTE, volume=104, pan=58, reverb=95)
	lanterns = s.part(TINKLE_BELL, volume=54, pan=26, reverb=100)
	timp = s.part(TIMPANI, volume=64, pan=64, reverb=90, humanize=0.0)

	# Two bars to a chord: Cmaj7, Em, Fmaj9 (no third), Cmaj7, Em, F, G sus, C.
	pools = [notes("C4 E4 G4 B4 E5 G5"), notes("E4 G4 B4 E5 G5 B5"), notes("F4 C5 E5 G5 C6 E6"), notes("C4 E4 G4 B4 E5 G5"),
		notes("E4 G4 B4 E5 G5 B5"), notes("F4 C5 E5 G5 C6 E6"), notes("G4 C5 F5 G5 B5 C6"), notes("C4 E4 G4 B4 E5 G5")]
	low = [notes("C3 G3 B3 E4"), notes("E3 B3 G4"), notes("F3 C4 E4 G4"), notes("C3 G3 B3 E4"),
		notes("E3 B3 G4"), notes("F3 C4 E4 G4"), notes("G3 C4 G4"), notes("C3 G3 B3 E4")]
	roll(celesta, s, 1, 16, pools, 2, [[0, 3, 2, 4], [1, 4, 3, 5]], vel=64, step=1.0, accent=8, ring=3.5)
	bed(strings, s, 1, 16, low, 2, 50)
	bed(choir, s, 9, 16, low, 2, 44)
	for bar_no in range(4, 17, 2):
		glock.note(s.bar(bar_no) + 2.5, 3, pools[((bar_no - 1) // 2) % 8][5], 38)
	for bar_no, beat, name in [(2, 3, "G6"), (6, 3, "G6"), (10, 3, "E6"), (14, 3, "G6"), (4, 1.5, "E6"), (12, 1.5, "B6")]:
		lanterns.note(s.bar(bar_no) + beat, 2, n(name), 34)
	timp.note(s.bar(1), 3, n("C2"), 50)
	timp.note(s.bar(9), 3, n("C2"), 54)

	flute.phrase(s.bar(5), "C5:3 E5:1 G5:2 F5:1 E5:1 E5:3 G5:1 B5:4", vel=70, vibrato=True)
	flute.phrase(s.bar(9), "G5:2 B5:2 E6:4 C6:2 B5:1 G5:1 F5:3 E5:1", vel=76, vibrato=True)
	flute.phrase(s.bar(13), "G5:4 F5:2 E5:2 E5:2 C5:2 C5:4", vel=66, vibrato=True)
	return s


# --------------------------------------------------------------------------
# Five Winds: "Five Pillars". C yo (C D F G A), 5/4, horns and a rising koto.
# --------------------------------------------------------------------------

def five_winds() -> Song:
	s = Song("five_winds", bpm=92, bars=20, seed=107, beats_per_bar=5)
	timp = s.part(TIMPANI, volume=100, pan=64, reverb=65, humanize=0.0)
	taiko = s.part(TAIKO, volume=104, pan=64, reverb=70, humanize=0.0)
	bells = s.part(TUBULAR_BELLS, volume=72, pan=70, reverb=100)
	horns = s.part(FRENCH_HORN, volume=86, pan=50, reverb=75)
	choir = s.part(CHOIR, volume=74, pan=64, reverb=90)
	strings = s.part(STRINGS, volume=82, pan=36, reverb=75)
	koto = s.part(KOTO, volume=98, pan=44, reverb=75)
	lead = s.part(SHAKUHACHI, volume=108, pan=62, reverb=80)
	flute = s.part(FLUTE, volume=78, pan=84, reverb=85)

	# Four chords, a bar each, round and round; the third time Dm stands in for Am.
	c, am, dm, f, g = notes("C3 G3 D4"), notes("A3 C4 G4"), notes("D3 A3 F4"), notes("F3 C4 G4"), notes("G3 C4 D4")
	cycle = [c, am, f, g]
	chords = cycle * 2 + [c, dm, f, g] + cycle * 2
	for b in range(1, 6):
		strings.chord(s.bar(b), 4.9, chords[b - 1], 52 + 4 * b)
	bed(strings, s, 6, 20, chords, 1, 72)
	bed(horns, s, 4, 20, chords, 1, 62)
	bed(choir, s, 11, 20, chords, 1, 58)
	run = notes("C4 D4 F4 G4 A4 C5 D5 F5 G5 A5")
	for b in range(1, 21):
		arpeggio(koto, s.bar(b), 1, run, list(range(10)), step=0.5, vel=70 if b <= 5 or b >= 16 else 48, accent=10, ring=1.6, bpb=5)
	# The five pillars wake one by one: a bell for each note of the scale.
	for i, name in enumerate(["C5", "D5", "F5", "G5", "A5"]):
		bells.note(s.bar(1 + i), 4.5, n(name), 62)
	roots = [n("C2"), n("A1"), n("F1"), n("G1")]
	for b in range(1, 21):
		root = n("D2") if 9 <= b <= 12 and b % 4 == 2 else roots[(b - 1) % 4]
		timp.note(s.bar(b), 1.5, root + 12, 94)
		timp.note(s.bar(b) + 3, 1.0, root + 12, 66)
		if b >= 6:
			taiko_hits(taiko, s.bar(b), [(0, n("C2"), 92), (3, n("G2"), 74)] + ([(4.5, n("G2"), 66)] if b % 2 == 0 else []))
	for bar_no in (5, 10, 15, 20):
		for k in range(8):
			timp.note(s.bar(bar_no) + 3 + k * 0.25, 0.3, n("D3"), 54 + k * 6)

	p1 = "G4:3 A4:2 C5:3 D5:2 F5:3 G5:2 A5:5 G5:2 F5:1 D5:2"
	p2 = "A5:3 G5:2 F5:2 G5:1 F5:1 D5:1 C5:3 D5:2 F5:3 D5:2 C5:5"
	lead.phrase(s.bar(6), p1, vel=96, slide=True, vibrato=True)
	horns.phrase(s.bar(6), p1, vel=60, transpose=-12)
	lead.phrase(s.bar(11), p2, vel=100, slide=True, vibrato=True)
	horns.phrase(s.bar(11), p2, vel=84, transpose=-12)
	lead.phrase(s.bar(16), p1, vel=104, slide=True, vibrato=True)
	flute.phrase(s.bar(16), p1, vel=66, transpose=12)
	horns.phrase(s.bar(16), p1, vel=88, transpose=-12)
	return s

# --------------------------------------------------------------------------
# Night: "Quiet Hour". D hirajoshi (D E F A Bb), very sparse, kalimba and koto.
# --------------------------------------------------------------------------

def night() -> Song:
	s = Song("night", bpm=50, bars=16, seed=113)
	pad = s.part(WARM_PAD, volume=38, pan=64, reverb=95, chorus=40)
	kalimba = s.part(KALIMBA, volume=100, pan=40, reverb=90)
	koto = s.part(KOTO, volume=92, pan=68, reverb=90)
	shaku = s.part(SHAKUHACHI, volume=64, pan=76, reverb=100)
	crickets = s.part(TINKLE_BELL, volume=34, pan=18, reverb=90)

	# Two bars to a chord: Dm(add9), Bb, Dm, F, Bb, Dm, a sus on E, Dm.
	pools = [notes("D3 A3 D4 E4 F4 A4"), notes("Bb2 F3 Bb3 D4 F4 Bb4"), notes("D3 A3 D4 F4 A4 D5"), notes("F3 A3 D4 F4 A4 D5"),
		notes("Bb2 F3 Bb3 D4 F4 Bb4"), notes("D3 A3 D4 F4 A4 D5"), notes("E3 A3 D4 E4 A4 D5"), notes("D3 A3 D4 E4 F4 A4")]
	bed(pad, s, 1, 16, [p[:5] for p in pools], 2, 40)
	roll(kalimba, s, 1, 16, pools, 2, [[0, 3], [2, 4], [1, 3], [2, 5]], vel=44, step=2.0, accent=6, ring=6)
	koto.note(s.bar(1), 8, n("D3"), 50)
	koto.note(s.bar(3), 8, n("A3"), 44)
	koto.phrase(s.bar(5), "A4:2 F4:1 E4:1 D4:4 A4:3 F4:1 E4:2 r:2", vel=58)
	koto.phrase(s.bar(9), "D5:2 Bb4:1 A4:1 F4:4 A4:2 D5:1 E5:1 D5:4", vel=60)
	koto.phrase(s.bar(13), "E5:3 D5:1 A4:4 F4:2 E4:2 D4:4", vel=56)
	shaku.phrase(s.bar(9), "F4:8 D4:8", vel=52, slide=True, vibrato=True)
	shaku.phrase(s.bar(13), "A4:8 D4:8", vel=48, slide=True, vibrato=True)
	for bar_no, beat, name in [(2, 1.5, "D7"), (2, 2, "D7"), (6, 0.5, "A6"), (6, 1, "A6"), (6, 1.5, "A6"),
			(10, 3, "F7"), (10, 3.5, "F7"), (14, 2, "D7"), (14, 2.5, "D7"), (14, 3, "D7")]:
		crickets.note(s.bar(bar_no) + beat, 0.4, n(name), 30)
	return s


# --------------------------------------------------------------------------
# Sea: "Open Water". D ryo (D E F# A B), 112 BPM, light percussion.
# --------------------------------------------------------------------------

def sea() -> Song:
	s = Song("sea", bpm=112, bars=32, seed=127)
	drums = s.part(DRUMS, volume=80, reverb=30)
	bass = s.part(PIZZICATO, volume=92, pan=64, reverb=40)
	koto = s.part(KOTO, volume=92, pan=40, reverb=60)
	sham = s.part(SHAMISEN, volume=88, pan=88, reverb=45)
	flute = s.part(FLUTE, volume=100, pan=60, reverb=70)
	violin = s.part(VIOLIN, volume=72, pan=72, reverb=70)
	harp = s.part(HARP, volume=64, pan=30, reverb=80)
	pad = s.part(WARM_PAD, volume=48, pan=64, reverb=80, chorus=30)

	# Two bars to a chord: D, A sus2, Bm7, E sus; four times round.
	pools = [notes("D3 A3 D4 F#4 A4"), notes("A2 E3 A3 B3 E4"), notes("B2 F#3 B3 D4 F#4"), notes("E3 A3 B3 E4 A4")]
	comp = [notes("D4 F#4 A4"), notes("A3 E4 B4"), notes("B3 D4 F#4"), notes("E4 A4 B4")]
	roots = [n("D2"), n("A1"), n("B1"), n("E2")]
	roll(koto, s, 1, 32, pools, 2, [[0, 1, 2, 3, 4, 3, 2, 1]], vel=50, accent=8, ring=2.0)
	bed(pad, s, 9, 32, comp, 2, 36)
	for b in range(1, s.bars + 1):
		t = s.bar(b)
		k = ((b - 1) // 2) % 4
		r = roots[k]
		for beat, pitch, vel in [(0, r, 86), (0.75, r, 58), (2, r, 78), (2.75, r + 7, 62), (3.5, r + 12, 66)]:
			bass.note(t + beat, 0.4, pitch, vel)
		for i in range(8):
			drums.note(t + i * 0.5, 0.2, HAT, 44 if i % 2 == 0 else 32)
		if b >= 3:
			drums.note(t + 1, 0.2, SIDE_STICK, 56)
			drums.note(t + 3, 0.2, SIDE_STICK, 56)
			drums.note(t, 0.2, KICK, 66)
			drums.note(t + 2.5, 0.2, KICK, 58)
		if b >= 17:
			for i in range(4):
				drums.note(t + i + 0.5, 0.2, TAMBOURINE, 40)
		if b >= 5 and not 17 <= b <= 24:
			for beat in (1.5, 3.5):
				sham.chord(t + beat, 0.3, comp[k], 62)
	# A wave of harp at the head of each cycle.
	for bar_no in (1, 9, 17, 25):
		for i, p in enumerate(notes("D4 E4 F#4 A4 B4 D5 E5 F#5 A5 B5 D6")):
			harp.note(s.bar(bar_no) + i * 0.1, 2.5, p, 44 + i * 2)

	m1 = "F#5:1 A5:1 B5:2 A5:1 F#5:1 E5:2 E5:1 A5:1 B5:1 A5:1 E5:4 " \
		"B4:1 D5:1 F#5:2 A5:2 F#5:1 D5:1 E5:1.5 D5:0.5 B4:1 A4:1 E5:4"
	m2 = "D6:2 B5:1 A5:1 F#5:2 E5:2 A5:1 B5:1 D6:2 B5:4 " \
		"A5:1.5 F#5:0.5 E5:1 D5:1 F#5:2 A5:2 B5:1 A5:1 F#5:1 E5:1 D5:4"
	flute.phrase(s.bar(9), m1, vel=84, vibrato=True)
	sham.phrase(s.bar(17), m2, vel=90)
	flute.phrase(s.bar(17), m2, vel=52)
	flute.phrase(s.bar(25), m1, vel=90, vibrato=True)
	violin.phrase(s.bar(25), m1, vel=64)
	return s


# --------------------------------------------------------------------------
# Battle 2: "Storm Drums". G miyako-bushi (G Ab C D Eb), 6/8 gallop, no drum kit.
# --------------------------------------------------------------------------

def battle2() -> Song:
	# A bar is six eighth-note beats, so `bpm` counts eighths (dotted quarter = 100).
	s = Song("battle2", bpm=300, bars=56, seed=139, beats_per_bar=6)
	drums = s.part(DRUMS, volume=96, reverb=30)
	taiko = s.part(TAIKO, volume=100, pan=64, reverb=55, humanize=0.0)
	timp = s.part(TIMPANI, volume=88, pan=64, reverb=60, humanize=0.0)
	ostinato = s.part(PIZZICATO, volume=104, pan=42, reverb=40, humanize=0.004)
	tremolo = s.part(TREMOLO_STRINGS, volume=84, pan=50, reverb=60)
	sham = s.part(SHAMISEN, volume=100, pan=88, reverb=40, humanize=0.006)
	violin = s.part(VIOLIN, volume=92, pan=64, reverb=55)
	flute = s.part(FLUTE, volume=76, pan=76, reverb=60)
	brass = s.part(BRASS, volume=98, pan=54, reverb=55)
	choir = s.part(CHOIR, volume=80, pan=64, reverb=80)

	# Chords two bars at a time. Cycle X: G, Ab, Cm, Ab. Cycle Y: G, Ab, Eb, G.
	X = ["G", "Ab", "Cm", "Ab"]
	Y = ["G", "Ab", "Eb", "G"]
	root_of = {"G": n("G2"), "Ab": n("Ab2"), "Cm": n("C3"), "Eb": n("Eb3")}
	fifth = {"G": 7, "Ab": 7, "Cm": 7, "Eb": 4}
	triad = {"G": notes("G3 D4 G4"), "Ab": notes("Ab3 C4 Eb4"), "Cm": notes("C4 Eb4 G4"), "Eb": notes("Eb4 G4 D5")}
	riff = {"G": notes("G4 G4 D5 G4 Eb5 D5 G4 G4 Ab4 G4 D5 Eb5"), "Ab": notes("Ab4 Ab4 Eb5 Ab4 C5 Eb5 Ab4 Ab4 C5 Ab4 Eb5 C5"),
		"Cm": notes("C5 C5 G5 C5 Eb5 G5 C5 C5 D5 C5 G4 Eb5"), "Eb": notes("Eb5 Eb5 G5 Eb5 D5 G5 Eb5 Eb5 C5 Eb5 G5 D5")}

	def chord(b: int) -> str:
		if b <= 4:
			return "G"
		if b <= 28:
			return (X if b <= 20 else Y)[((b - 5) // 2) % 4]
		if b <= 32:
			return ["Ab", "G"][(b - 29) // 2]
		return (Y if b <= 40 else X if b <= 48 else Y)[((b - 33) // 2) % 4]

	def section(b: int) -> str:
		for last, name in [(4, "intro"), (12, "A"), (20, "B"), (28, "B2"), (32, "break"), (40, "C"), (48, "C2")]:
			if b <= last:
				return name
		return "D"

	for b in range(1, s.bars + 1):
		sec = section(b)
		ch = chord(b)
		root = root_of[ch]
		t = s.bar(b)
		even = (b % 2 == 0)
		# Taiko: the gallop, six even eighths with a push on 1 and 4.
		if sec == "intro":
			hits = [(0, n("C2"), 70 + 8 * b)] if b == 1 else [(0, n("C2"), 80 + 6 * b), (3, n("C2"), 74 + 6 * b)]
			if b == 3:
				hits += [(i, n("G2"), 60) for i in (1, 2, 4, 5)]
			if b == 4:
				hits = [(i * 0.5, n("C2") if i % 3 == 0 else n("G2"), 70 + i * 4) for i in range(12)]
			taiko_hits(taiko, t, hits)
		elif sec == "break":
			taiko_hits(taiko, t, [(0, n("C2"), 108), (3, n("C2"), 90)])
		else:
			hits = [(0, n("C2"), 110), (1, n("G2"), 58), (2, n("G2"), 66), (3, n("C2"), 100), (4, n("G2"), 58), (5, n("G2"), 70)]
			if even and b != 56:
				hits[4:] = [(4, n("C2"), 90), (4.5, n("G2"), 74), (5, n("C2"), 100)]
			taiko_hits(taiko, t, hits)
		# Low pizzicato ostinato and the shamisen riff.
		if sec not in ("intro", "break"):
			for i, off in enumerate([0, 0, 12, 0, fifth[ch], 12]):
				ostinato.note(t + i, 0.4, root + 12 + off, 96 if i in (0, 3) else 74)
			if b != 56:
				for i, p in enumerate(riff[ch]):
					sham.note(t + i * 0.5, 0.4, p, 86 if i in (0, 6) else 72 if i % 3 == 0 else 58)
		# Strings tremble under the lead from B on; the break holds them alone.
		if sec in ("B", "B2", "C", "C2", "D") and not even:
			tremolo.chord(t, 11.8, triad[ch] + [root + 12], 66 if sec in ("B", "B2") else 78)
		if b == 29:
			tremolo.chord(t, 23.8, notes("Ab3 Eb4 G4"), 76)
		# Weight: timpani and brass stabs on the big sections.
		if sec in ("C", "C2", "D"):
			timp.note(t, 2.0, root + 12, 100)
			timp.note(t + 3, 2.0, root + 12, 84)
			for beat, length in [(0, 1.5), (3, 1.5)] + ([(4.5, 0.5)] if b % 2 == 1 else []):
				brass.chord(t + beat, length, triad[ch], 98 if beat == 0 else 88)
			if not even:
				choir.chord(t, 3.0, triad[ch], 78)
		if sec in ("B", "B2", "C", "C2", "D") and b != 56:
			drums.note(t + 3, 0.2, CLAP, 62)
		if b in (5, 13, 21, 33, 41, 49):
			drums.note(t, 1.0, CRASH, 104)
	# Fills into the break, the last section and the loop.
	for bar_no in (28, 32, 56):
		t = s.bar(bar_no) + 3
		for k, p in enumerate([HIGH_TOM, HIGH_TOM, MID_TOM, MID_TOM, LOW_TOM, LOW_TOM]):
			drums.note(t + k * 0.5, 0.2, p, 84 + k * 4)
		drums.note(s.bar(bar_no) + 5.5, 0.5, CRASH if bar_no != 32 else LOW_TOM, 100)
	for k in range(12):
		timp.note(s.bar(32) + k * 0.5, 0.5, n("G3"), 56 + k * 4)

	m1 = "D5:3 Eb5:1 D5:1 G4:1 Ab4:2 C5:1 Eb5:3 C5:3 Eb5:1 C5:1 Ab4:1 G4:2 Ab4:1 C5:3 " \
		"Eb5:3 D5:1 C5:1 G4:1 G4:1 C5:2 D5:3 Eb5:2 D5:1 C5:1 Ab4:2 G4:6"
	m2 = "G5:3 D5:1 Eb5:1 D5:1 C5:2 D5:1 Eb5:3 Ab5:2 G5:1 Eb5:3 C5:3 Ab4:1 C5:1 Eb5:1 " \
		"G5:3 Eb5:1 D5:1 C5:1 Eb5:2 D5:1 C5:1 G4:2 D5:3 Eb5:1 D5:1 G4:1 G4:6"
	violin.phrase(s.bar(13), m1, vel=96, legato=0.9)
	violin.phrase(s.bar(21), m2, vel=98, legato=0.9)
	flute.phrase(s.bar(21), m2, vel=60, legato=0.9, transpose=12)
	violin.phrase(s.bar(33), m2, vel=104, legato=0.9, transpose=12)
	brass.phrase(s.bar(41), m1, vel=84, legato=0.9)
	violin.phrase(s.bar(41), m1, vel=100, legato=0.9, transpose=12)
	flute.phrase(s.bar(41), m1, vel=64, legato=0.9, transpose=12)
	violin.phrase(s.bar(49), m2, vel=108, legato=0.9, transpose=12)
	flute.phrase(s.bar(49), m2, vel=70, legato=0.9, transpose=12)
	return s


# --------------------------------------------------------------------------
# Tension: "Held Breath". F# miyako-bushi (F# G B C# D) with a stray C.
# --------------------------------------------------------------------------

def tension() -> Song:
	s = Song("tension", bpm=60, bars=16, seed=151)
	drone = s.part(CONTRABASS, volume=86, pan=60, reverb=60)
	strings = s.part(TREMOLO_STRINGS, volume=64, pan=40, reverb=80)
	air = s.part(ATMOSPHERE, volume=50, pan=64, reverb=95)
	shaku = s.part(SHAKUHACHI, volume=84, pan=72, reverb=90)
	koto = s.part(KOTO, volume=70, pan=34, reverb=80)
	crystal = s.part(CRYSTAL, volume=40, pan=90, reverb=100)
	timp = s.part(TIMPANI, volume=78, pan=64, reverb=70, humanize=0.0)
	drums = s.part(DRUMS, volume=44, reverb=50)

	# A drone on F# with a half step above it, then a tritone, then another key
	# standing on top of it, and back.
	drone.note(s.bar(1), 63.8, n("F#1"), 58)
	for bar_no in (5, 13):
		drone.note(s.bar(bar_no), 7.8, n("G1"), 44)
	clusters = [notes("F#3 G3 C#4"), notes("F#3 C4 D4"), notes("G3 D4 F#4"), notes("F#3 C#4 G4 C5")]
	bed(strings, s, 1, 16, clusters, 4, 54)
	bed(air, s, 5, 16, [notes("F#2 C#3 G3"), notes("G2 D3 F#3 C4")], 4, 40)
	for bar_no in range(1, 17, 2):
		koto.note(s.bar(bar_no), 4, n("F#3") if bar_no % 4 == 1 else n("G3"), 52)
	# A pulse that creeps closer.
	for bar_no in range(5, 17):
		vel = 40 if bar_no < 9 else 50 if bar_no < 13 else 62
		taiko_hits(timp, s.bar(bar_no), [(0, n("F#2"), vel), (0.6, n("F#2"), vel - 12)])
	for k in range(12):
		timp.note(s.bar(8) + 2 + k * 0.25, 0.3, n("F#2"), 38 + k * 3)
	for bar_no in range(9, 17):
		for beat in (1, 3):
			drums.note(s.bar(bar_no) + beat, 0.1, SIDE_STICK, 36)
	for bar_no, beat, name in [(4, 2, "F#6"), (8, 1, "G6"), (12, 3, "C6"), (15, 0, "G6")]:
		crystal.note(s.bar(bar_no) + beat, 4, n(name), 44)

	shaku.phrase(s.bar(3), "C#5:3 D5:1 C#5:4", vel=62, slide=True, vibrato=True)
	shaku.phrase(s.bar(7), "G4:2 F#4:2 C5:4", vel=66, slide=True, vibrato=True)
	shaku.phrase(s.bar(11), "D5:3 C#5:1 B4:2 G4:2", vel=70, slide=True, vibrato=True)
	shaku.phrase(s.bar(14), "F#5:6 G5:2", vel=64, slide=True, vibrato=True)
	return s


# --------------------------------------------------------------------------
# Sorrow: "After the Fire". B hirajoshi (B C# D F# G), a cello with strings.
# --------------------------------------------------------------------------

def sorrow() -> Song:
	s = Song("sorrow", bpm=56, bars=16, seed=163)
	cello = s.part(CELLO, volume=104, pan=64, reverb=75)
	violin = s.part(VIOLIN, volume=70, pan=76, reverb=80)
	pad = s.part(SLOW_STRINGS, volume=64, pan=64, reverb=85)
	koto = s.part(KOTO, volume=76, pan=40, reverb=85)
	shaku = s.part(SHAKUHACHI, volume=70, pan=70, reverb=95)
	voices = s.part(VOICE_OOH, volume=52, pan=64, reverb=100)
	timp = s.part(TIMPANI, volume=60, pan=64, reverb=80, humanize=0.0)

	# Two bars to a chord: Bm, G, Bm(add9), F#, G, Bm, F#, Bm.
	pools = [notes("B2 F#3 B3 D4 F#4"), notes("G2 D3 G3 B3 D4 F#4"), notes("B2 F#3 C#4 D4 F#4"), notes("F#2 C#3 F#3 B3 D4"),
		notes("G2 D3 G3 B3 D4 F#4"), notes("B2 F#3 B3 D4 F#4"), notes("F#2 C#3 F#3 B3 D4"), notes("B2 F#3 B3 D4 F#4")]
	bed(pad, s, 1, 16, [p[1:] for p in pools], 2, 44)
	roll(koto, s, 1, 16, pools, 2, [[0, 2, 4, 3], [1, 3, 4, 2]], vel=42, step=1.0, accent=6, ring=3.5)
	bed(voices, s, 13, 16, [p[2:] for p in pools], 2, 40)
	for bar_no in (1, 5, 9, 13):
		timp.note(s.bar(bar_no), 3, n("B1"), 48)

	line = "F#4:3 D4:1 B3:2 C#4:2 D4:2 G4:3 F#4:3 D5:3 C#5:1 B4:2 F#4:2 C#5:4 B4:2 F#4:2 " \
		"G4:3 B4:1 D5:4 F#5:4 D5:2 C#5:2 B4:3 C#5:1 B4:2 F#4:2 D4:2 B3:6"
	cello.phrase(s.bar(1), line, vel=78, vibrato=True)
	violin.phrase(s.bar(9), " ".join(line.split()[14:]), vel=58, transpose=12, vibrato=True)
	shaku.phrase(s.bar(13), "F#5:6 D5:2 B4:8", vel=62, slide=True, vibrato=True)
	return s


# --------------------------------------------------------------------------
# The open world's own pieces. Each place and hour has its music: the regions'
# themes at night (below), the wilds, a village, a shrine, a camp, a duel,
# a third battle theme, a finale and the Hollow Court.
# --------------------------------------------------------------------------

def bars_of(*bars: str) -> str:
	"""A melody written a bar at a time ("A4:1 C5:1 D5:2" ...), joined up. A
	bar that does not add up to the song's bar length is a typo."""
	return " ".join(bars)


# Road: "The Long Road". C ryo (C D E G A), 96 BPM: travelling music for the wilds.
def road() -> Song:
	s = Song("road", bpm=96, bars=32, seed=211)
	taiko = s.part(TAIKO, volume=72, pan=64, reverb=60, humanize=0.0)
	bass = s.part(PIZZICATO, volume=92, pan=64, reverb=40)
	koto = s.part(KOTO, volume=90, pan=42, reverb=65)
	sham = s.part(SHAMISEN, volume=78, pan=88, reverb=45)
	flute = s.part(FLUTE, volume=98, pan=60, reverb=75)
	shaku = s.part(SHAKUHACHI, volume=84, pan=72, reverb=85)
	pad = s.part(SLOW_STRINGS, volume=52, pan=64, reverb=80)
	harp = s.part(HARP, volume=60, pan=30, reverb=80)

	# Two bars to a chord: C, Am, G sus, D sus.
	pools = [notes("C3 G3 C4 D4 E4 G4"), notes("A2 E3 A3 C4 D4 E4"), notes("G2 D3 G3 A3 D4 E4"), notes("D3 A3 D4 E4 G4 A4")]
	comp = [notes("C4 E4 G4"), notes("A3 C4 E4"), notes("G3 A3 D4"), notes("D4 E4 A4")]
	roots = [n("C2"), n("A1"), n("G1"), n("D2")]
	roll(koto, s, 1, 32, pools, 2, [[0, 1, 2, 3, 4, 3, 2, 1]], vel=50, accent=8, ring=2.0)
	bed(pad, s, 5, 32, comp, 2, 38)
	for b in range(1, s.bars + 1):
		t = s.bar(b)
		r = roots[((b - 1) // 2) % 4]
		for beat, pitch, vel in [(0, r, 84), (1.5, r + 7, 60), (2, r + 12, 70), (3, r + 7, 58)]:
			bass.note(t + beat, 0.4, pitch, vel)
		if b >= 9 and b % 2 == 1:
			taiko_hits(taiko, t, [(0, n("C2"), 80), (2.5, n("G2"), 52)])
		if b >= 9 and b not in range(17, 25):
			for beat in (1.5, 3.5):
				sham.chord(t + beat, 0.3, comp[((b - 1) // 2) % 4], 56)
	for bar_no in (1, 9, 17, 25):
		for i, p in enumerate(notes("C4 D4 E4 G4 A4 C5 D5 E5 G5 A5 C6")):
			harp.note(s.bar(bar_no) + i * 0.1, 2.5, p, 42 + i * 2)
	m1 = bars_of("E5:1 G5:1 A5:2", "G5:1 E5:1 D5:2", "C5:1 D5:1 E5:2", "G5:3 r:1",
		"A5:1 G5:1 E5:2", "D5:1 E5:1 G5:2", "E5:1 D5:1 C5:2", "D5:2 C5:2")
	m2 = bars_of("A5:2 G5:1 E5:1", "G5:2 A5:2", "C6:2 A5:1 G5:1", "E5:3 r:1",
		"D5:1 E5:1 G5:1 A5:1", "C6:1 A5:1 G5:2", "E5:1 G5:1 E5:1 D5:1", "C5:4")
	flute.phrase(s.bar(9), m1, vel=84, vibrato=True)
	shaku.phrase(s.bar(17), m2, vel=80, slide=True, vibrato=True)
	flute.phrase(s.bar(17), m1, vel=50, transpose=-12)
	flute.phrase(s.bar(25), m2, vel=88, vibrato=True)
	shaku.phrase(s.bar(25), m1, vel=64, transpose=-12, slide=True)
	return s


# Village: "Market Day". A minor pentatonic (A C D E G), 112 BPM: a shamisen, a flute, woodblocks.
def village() -> Song:
	s = Song("village", bpm=112, bars=24, seed=223)
	perc = s.part(DRUMS, volume=70, reverb=25)
	bass = s.part(PIZZICATO, volume=92, pan=64, reverb=35)
	sham = s.part(SHAMISEN, volume=96, pan=84, reverb=40)
	koto = s.part(KOTO, volume=76, pan=40, reverb=60)
	flute = s.part(FLUTE, volume=100, pan=58, reverb=70)
	violin = s.part(VIOLIN, volume=70, pan=72, reverb=70)
	pad = s.part(WARM_PAD, volume=44, pan=64, reverb=75, chorus=30)

	# A bar to a chord: Am, G, C, D sus.
	pools = [notes("A2 E3 A3 C4 E4"), notes("G2 D3 G3 A3 D4"), notes("C3 G3 C4 D4 E4"), notes("D3 A3 D4 E4 G4")]
	roots = [n("A1"), n("G1"), n("C2"), n("D2")]
	roll(koto, s, 1, 24, pools, 1, [[0, 2, 1, 3, 2, 4, 3, 1]], vel=46, accent=8, ring=1.6)
	bed(pad, s, 5, 24, [p[1:4] for p in pools], 1, 34)
	for b in range(1, s.bars + 1):
		t = s.bar(b)
		k = (b - 1) % 4
		r = roots[k]
		for beat, pitch, vel in [(0, r, 86), (1, r + 7, 60), (2, r, 76), (3, r + 7, 62)]:
			bass.note(t + beat, 0.35, pitch, vel)
		for beat in (1, 3):
			perc.note(t + beat, 0.15, CLAVES, 66)
		for i in range(8):
			perc.note(t + i * 0.5, 0.15, TAMBOURINE if i % 2 == 1 else WOODBLOCK, 40 if i % 2 == 1 else 30)
		if b >= 5:
			chord = pools[k][1:4]
			for beat in (0.5, 1.5, 2.5, 3.5):
				sham.chord(t + beat, 0.28, chord, 70 if beat in (0.5, 2.5) else 54)
	a = bars_of("A4:1 C5:1 D5:1 E5:1", "G5:2 E5:2", "D5:1 C5:1 D5:1 E5:1", "C5:4",
		"A4:1 C5:1 D5:1 E5:1", "G5:1 A5:1 G5:2", "E5:1 D5:1 C5:1 D5:1", "A4:4")
	b_ = bars_of("E5:1 E5:1 G5:2", "A5:2 G5:2", "E5:1 D5:1 C5:2", "D5:2 E5:2",
		"G5:1 A5:1 C6:2", "A5:2 G5:2", "E5:1 G5:1 E5:1 D5:1", "C5:1 A4:3")
	flute.phrase(s.bar(5), a, vel=82, vibrato=True)
	sham.phrase(s.bar(13), b_, vel=92)
	flute.phrase(s.bar(13), b_, vel=70)
	violin.phrase(s.bar(13), b_, vel=56, transpose=-12)
	flute.phrase(s.bar(21), bars_of("A4:1 C5:1 D5:1 E5:1", "G5:1 A5:1 G5:2"), vel=84, vibrato=True)
	return s


# Shrine: "Wayside Bell". A hirajoshi (A B C E F), 58 BPM: bells, a choir's breath, long shakuhachi.
def shrine() -> Song:
	s = Song("shrine", bpm=58, bars=20, seed=233)
	bells = s.part(TUBULAR_BELLS, volume=78, pan=66, reverb=100)
	choir = s.part(VOICE_OOH, volume=62, pan=64, reverb=95)
	pad = s.part(SLOW_STRINGS, volume=44, pan=50, reverb=90)
	koto = s.part(KOTO, volume=86, pan=40, reverb=90)
	shaku = s.part(SHAKUHACHI, volume=100, pan=70, reverb=95)
	crystal = s.part(CRYSTAL, volume=34, pan=92, reverb=100)

	# Four bars to a chord: Am(add b6), F, Em sus, Am.
	pools = [notes("A2 E3 A3 C4 E4 F4"), notes("F2 C3 F3 A3 C4 E4"), notes("E2 B2 E3 A3 B3 E4"), notes("A2 E3 A3 B3 C4 E4")]
	bed(pad, s, 1, 20, [notes("A3 C4 E4"), notes("F3 A3 C4"), notes("E3 A3 B3"), notes("A3 C4 E4")], 4, 44)
	bed(choir, s, 5, 20, [notes("A3 E4"), notes("F3 C4"), notes("E3 B3"), notes("A3 E4")], 4, 40)
	roll(koto, s, 1, 20, pools, 4, [[0, 3, 5, 2, 4, 1, 3, 0]], vel=48, step=1.0, accent=6, ring=4.0)
	for bar_no, name in [(1, "A4"), (5, "E5"), (9, "C5"), (13, "A4"), (17, "E5")]:
		bells.note(s.bar(bar_no), 8.0, n(name), 56)
	for bar_no, name in [(3, "A5"), (11, "F6"), (19, "E6")]:
		crystal.note(s.bar(bar_no), 4.0, n(name), 38)
	shaku.phrase(s.bar(5), "E5:3 F5:1 E5:2 C5:2 B4:4 A4:4", vel=66, slide=True, vibrato=True)
	shaku.phrase(s.bar(9), "A5:4 F5:2 E5:2 C5:3 B4:1 A4:4", vel=72, slide=True, vibrato=True)
	shaku.phrase(s.bar(15), "E5:4 F5:2 E5:2 C5:4 A4:4", vel=64, slide=True, vibrato=True)
	return s


# Camp: "Campfire Knives". D in (D Eb G A Bb), 126 BPM: rough, close, not epic.
def camp() -> Song:
	s = Song("camp", bpm=126, bars=32, seed=241)
	drums = s.part(DRUMS, volume=92, reverb=30)
	taiko = s.part(TAIKO, volume=104, pan=64, reverb=55, humanize=0.0)
	bass = s.part(CONTRABASS, volume=100, pan=64, reverb=30)
	sham = s.part(SHAMISEN, volume=104, pan=86, reverb=35)
	strings = s.part(TREMOLO_STRINGS, volume=64, pan=40, reverb=60)
	shaku = s.part(SHAKUHACHI, volume=100, pan=64, reverb=65)
	violin = s.part(VIOLIN, volume=74, pan=76, reverb=55)

	roots = [n("D2"), n("Bb1"), n("G1"), n("A1")]
	pools = [notes("D3 A3 D4 Eb4 G4"), notes("Bb2 F3 Bb3 D4 G4"), notes("G2 D3 G3 Bb3 D4"), notes("A2 Eb3 A3 D4 Eb4")]
	riff = notes("D4 D4 A4 D4 Bb4 A4 G4 D4 Eb4 D4 A4 D4 G4 A4 Bb4 A4")
	for b in range(1, s.bars + 1):
		t = s.bar(b)
		ci = ((b - 1) // 2) % 4
		root = roots[ci]
		if b <= 4 or b >= 29:
			taiko_hits(taiko, t, [(0, n("D2"), 106), (0.75, n("A2"), 66), (2, n("D2"), 92), (3, n("A2"), 70)])
		else:
			for beat, vel in [(0, 100), (1.5, 74), (2, 90), (3.5, 70)]:
				bass.note(t + beat, 0.45, root + (12 if beat == 1.5 else 0), vel)
			for k in range(8):
				drums.note(t + k * 0.5, 0.2, HAT, 60 if k % 2 == 0 else 44)
			for beat in (0, 2.5):
				drums.note(t + beat, 0.2, KICK, 98)
			for beat in (1, 3):
				drums.note(t + beat, 0.2, SNARE if b >= 13 else SIDE_STICK, 90 if b >= 13 else 72)
			if b % 2 == 1:
				taiko_hits(taiko, t, [(0, n("D2"), 100)])
		if b >= 5 and b <= 28 and (b % 2 == 0 or b >= 13):
			for k, p in enumerate(riff):
				sham.note(t + k * 0.25, 0.22, p + (root - n("D2") if ci in (1, 2, 3) else 0) - (12 if ci == 3 else 0) * 0, 82 if k % 4 == 0 else 62)
		if b >= 13 and b <= 28:
			strings.chord(t, 3.9, pools[ci][1:4], 54)
		if b in (12, 28):
			for k in range(8):
				drums.note(t + 2 + k * 0.25, 0.2, [HIGH_TOM, HIGH_TOM, MID_TOM, MID_TOM, LOW_TOM, LOW_TOM, LOW_TOM, CRASH][k], 84 + k * 3)
	call = bars_of("D5:1 Eb5:1 D5:1 A4:1", "Bb4:2 A4:1 G4:1", "A4:1 Bb4:1 D5:2", "Eb5:1 D5:1 A4:2", "G4:2 A4:2", "D5:4")
	shaku.phrase(s.bar(13), call, vel=96, slide=True, vibrato=True)
	violin.phrase(s.bar(21), call, vel=82)
	shaku.phrase(s.bar(21), call, vel=70, transpose=12, slide=True)
	return s


# Duel: "Two Blades". A in (A Bb D E F), 132 BPM: mostly space and a pulse.
def duel() -> Song:
	s = Song("duel", bpm=132, bars=32, seed=251)
	drums = s.part(DRUMS, volume=84, reverb=40)
	taiko = s.part(TAIKO, volume=108, pan=64, reverb=65, humanize=0.0)
	timp = s.part(TIMPANI, volume=86, pan=64, reverb=70, humanize=0.0)
	sham = s.part(SHAMISEN, volume=104, pan=84, reverb=45)
	strings = s.part(TREMOLO_STRINGS, volume=60, pan=44, reverb=75)
	bass = s.part(CONTRABASS, volume=92, pan=64, reverb=40)
	shaku = s.part(SHAKUHACHI, volume=104, pan=60, reverb=80)
	violin = s.part(VIOLIN, volume=76, pan=74, reverb=65)

	roots = [n("A1"), n("A1"), n("Bb1"), n("E2")]
	clusters = [notes("A3 E4 F4"), notes("A3 D4 E4"), notes("Bb3 D4 F4"), notes("E3 A3 Bb3")]
	for b in range(1, s.bars + 1):
		t = s.bar(b)
		ci = ((b - 1) // 2) % 4
		# The pulse: two hits and a breath.
		taiko_hits(taiko, t, [(0, n("A2"), 104), (0.75, n("A2"), 70)] + ([(2.5, n("E2"), 84)] if b % 2 == 0 else []))
		if b >= 5:
			strings.chord(t, 3.9, clusters[ci], 46 + (8 if b >= 17 else 0))
		if b >= 9:
			bass.note(t, 1.0, roots[ci], 92)
			bass.note(t + 2, 0.5, roots[ci] + 12, 70)
		if b >= 17:
			for k in range(8):
				drums.note(t + k * 0.5, 0.15, HAT, 56 if k % 2 == 0 else 40)
			drums.note(t, 0.2, KICK, 100)
			drums.note(t + 2, 0.2, SNARE, 92)
			drums.note(t + 3.5, 0.2, KICK, 80)
		elif b >= 9:
			drums.note(t + 1, 0.15, SIDE_STICK, 60)
			drums.note(t + 3, 0.15, SIDE_STICK, 60)
		if b in (8, 16, 24):
			for k in range(8):
				timp.note(t + 2 + k * 0.25, 0.3, n("A2"), 56 + k * 5)
	# The shamisen's motif: a flick, a held note, a flick back.
	motif = [bars_of("A4:0.5 r:0.5 A4:0.5 Bb4:0.5 A4:1 E4:1"), bars_of("D5:0.5 r:0.5 D5:0.5 E5:0.5 D5:1 A4:1"),
		bars_of("F5:0.5 E5:0.5 D5:1 Bb4:1 A4:1"), bars_of("E5:0.5 r:0.5 E5:0.5 F5:0.5 E5:2")]
	for b in range(9, 17):
		sham.phrase(s.bar(b), motif[(b - 9) % 4], vel=88)
	for b in range(17, 25):
		sham.phrase(s.bar(b), motif[(b - 17) % 4], vel=96, transpose=0)
	cry = bars_of("E5:4", "F5:2 E5:2", "D5:3 E5:1", "A4:4", "Bb4:2 A4:2", "E5:4", "F5:2 E5:1 D5:1", "A4:4")
	shaku.phrase(s.bar(5), cry, vel=70, slide=True, vibrato=True)
	violin.phrase(s.bar(17), cry, vel=84)
	shaku.phrase(s.bar(25), cry[:len("E5:4 F5:2 E5:2 D5:3 E5:1 A4:4")], vel=92, slide=True, vibrato=True, transpose=12)
	return s


# Battle 3: "Iron Rain". C in (C Db F G Bb), 152 BPM.
def battle3() -> Song:
	s = Song("battle3", bpm=152, bars=40, seed=263)
	drums = s.part(DRUMS, volume=104, reverb=30)
	taiko = s.part(TAIKO, volume=110, pan=64, reverb=50, humanize=0.0)
	bass = s.part(FINGER_BASS, volume=100, pan=64, reverb=20, humanize=0.005)
	ost = s.part(STRINGS, volume=90, pan=40, reverb=45, humanize=0.005)
	sham = s.part(SHAMISEN, volume=96, pan=88, reverb=40, humanize=0.006)
	lead = s.part(FLUTE, volume=108, pan=60, reverb=60)
	violin = s.part(VIOLIN, volume=86, pan=72, reverb=60)
	brass = s.part(BRASS, volume=96, pan=52, reverb=55)
	choir = s.part(CHOIR, volume=70, pan=64, reverb=85)

	roots = [n("C2"), n("Db2"), n("Bb1"), n("G1")]
	triads = [notes("C3 G3 C4 F4"), notes("Db3 F3 Db4 G4"), notes("Bb2 F3 Bb3 Db4"), notes("G2 Db3 G3 Bb3")]
	riff = notes("C4 C4 G4 C4 Db4 C4 F4 G4 Bb4 G4 F4 Db4 C4 Db4 F4 G4")

	def section(b: int) -> str:
		if b <= 4:
			return "intro"
		if b <= 12:
			return "A"
		if b <= 20:
			return "B"
		if b <= 28:
			return "C"
		if b <= 32:
			return "break"
		return "B2"

	for b in range(1, s.bars + 1):
		sec = section(b)
		chord = ((b - 1) // 2) % 4
		root = roots[chord]
		t = s.bar(b)
		o = root + 12
		for k, p in enumerate([o, o + 7, o + 12, o + 7, o, o + 7, o + 12, o + 5]):
			vel = 68 + (14 if k in (0, 4) else 0) + (8 if sec in ("C", "B2") else 0)
			if sec == "intro":
				vel -= 24 - 5 * b
			ost.note(t + k * 0.5, 0.3, p, vel)
		if sec not in ("intro", "break"):
			for k in range(8):
				bass.note(t + k * 0.5, 0.42, root + (12 if k in (2, 6) else 0), 94 if k in (0, 3, 5) else 72)
		elif sec == "break":
			bass.note(t, 3.8, root, 90)
		if sec in ("A", "C", "B2") or (sec == "B" and b % 2 == 0):
			for k, p in enumerate(riff):
				sham.note(t + k * 0.25, 0.22, p, 84 if k % 4 == 0 else 64)
		if sec in ("A", "B", "C", "B2"):
			for k in range(8):
				drums.note(t + k * 0.5, 0.2, OPEN_HAT if k == 7 else HAT, 72 if k % 2 == 0 else 54)
			for beat in (0, 0.75, 2, 2.5):
				drums.note(t + beat, 0.2, KICK, 102)
			for beat in (1, 3):
				drums.note(t + beat, 0.2, SNARE, 100)
			if b in (5, 13, 21, 25, 33):
				drums.note(t, 1, CRASH, 100)
		elif sec == "break":
			drums.note(t, 0.2, KICK, 100)
			drums.note(t + 2, 0.2, KICK, 96)
			if b == 32:
				for k in range(16):
					drums.note(t + k * 0.25, 0.2, SNARE, 50 + k * 4)
		if sec in ("intro", "break"):
			taiko_hits(taiko, t, [(0, n("C2"), 112), (0.75, n("G2"), 72), (1.5, n("C2"), 96), (2, n("G2"), 82), (3, n("C2"), 104)])
		elif b % 2 == 1:
			taiko_hits(taiko, t, [(0, n("C2"), 108), (2.5, n("G2"), 80)])
		if sec in ("C", "B2") and b % 2 == 1:
			brass.chord(t, 0.45, triads[chord], 94)
			brass.chord(t + 1.5, 0.45, triads[chord], 86)
			brass.chord(t + 3, 0.9, triads[chord], 92)
		if sec in ("C", "B2") and b % 4 == 1:
			choir.chord(t, 7.8, triads[chord][:3], 66)
	for bar_no in (28, 40):
		t = s.bar(bar_no) + 2
		for k, p in enumerate([HIGH_TOM, HIGH_TOM, MID_TOM, MID_TOM, LOW_TOM, LOW_TOM, LOW_TOM, CRASH]):
			drums.note(t + k * 0.25, 0.2, p, 90 + k * 3)
	m1 = bars_of("G5:2 F5:1 G5:1", "Bb5:2 G5:2", "F5:1 Db5:1 C5:2", "Db5:1 F5:1 G5:2",
		"C6:2 Bb5:1 G5:1", "F5:2 G5:2", "Db5:1 F5:1 G5:1 F5:1", "C5:4")
	m2 = bars_of("C6:1 Bb5:1 G5:1 F5:1", "G5:2 Bb5:2", "C6:2 Db6:2", "C6:1 Bb5:1 G5:2",
		"F5:1 G5:1 Bb5:1 C6:1", "Db6:2 C6:2", "Bb5:1 G5:1 F5:1 Db5:1", "C5:4")
	lead.phrase(s.bar(13), m1, vel=100, vibrato=True, legato=0.9)
	violin.phrase(s.bar(13), m1, vel=70, transpose=-12, legato=0.9)
	violin.phrase(s.bar(21), m2, vel=92, legato=0.9)
	lead.phrase(s.bar(21), m2, vel=86, transpose=-12, legato=0.9)
	lead.phrase(s.bar(33), m1, vel=108, vibrato=True, transpose=12, legato=0.9)
	violin.phrase(s.bar(33), m2, vel=84, legato=0.9)
	return s


# Finale: "The Last Name". D in-less miyako-bushi (D Eb G A Bb), 144 BPM: choir, brass, timpani, taiko.
def finale() -> Song:
	s = Song("finale", bpm=144, bars=48, seed=277)
	drums = s.part(DRUMS, volume=100, reverb=40)
	taiko = s.part(TAIKO, volume=116, pan=64, reverb=60, humanize=0.0)
	timp = s.part(TIMPANI, volume=106, pan=64, reverb=65, humanize=0.0)
	low = s.part(CELLO, volume=104, pan=44, reverb=50, humanize=0.004)
	strings = s.part(STRINGS, volume=84, pan=36, reverb=70)
	choir = s.part(CHOIR, volume=92, pan=64, reverb=92)
	brass = s.part(BRASS, volume=100, pan=76, reverb=60)
	horns = s.part(FRENCH_HORN, volume=84, pan=52, reverb=70)
	lead = s.part(SHAKUHACHI, volume=112, pan=58, reverb=70)
	violin = s.part(VIOLIN, volume=84, pan=84, reverb=70)
	bells = s.part(TUBULAR_BELLS, volume=60, pan=70, reverb=100)

	# Two bars to a chord: Dm, Gm, Bb, A.
	roots = [n("D2"), n("G1"), n("Bb1"), n("A1")]
	chords = [notes("D3 A3 D4 F4"), notes("G2 D3 G3 Bb3"), notes("Bb2 F3 Bb3 D4"), notes("A2 E3 A3 C#4")]

	def section(b: int) -> str:
		if b <= 4:
			return "intro"
		if b <= 12:
			return "A"
		if b <= 20:
			return "B"
		if b <= 28:
			return "slow"
		if b <= 36:
			return "C"
		return "turn"

	for b in range(1, s.bars + 1):
		sec = section(b)
		ci = ((b - 1) // 2) % 4
		root = roots[ci] + 12
		t = s.bar(b)
		for k, off in enumerate([0, 0, 12, 0, 7, 0, 12, 7]):
			low.note(t + k * 0.5, 0.32, root + off, 86 if k in (0, 3, 6) else 68)
		if b % 2 == 1:
			choir.chord(t, 7.8, chords[ci], 72 if sec in ("intro", "slow") else 88)
			if sec not in ("intro",):
				strings.chord(t, 7.8, [p + 12 for p in chords[ci][1:]], 60 if sec == "slow" else 74)
		if sec in ("intro", "slow"):
			timp.note(t, 1.0, roots[ci] + 12, 100)
			timp.note(t + 2.5, 0.5, roots[ci] + 12, 76)
		else:
			if b % 2 == 1:
				timp.note(t, 1.0, roots[ci] + 12, 98)
			taiko_hits(taiko, t, [(0, n("C2"), 114), (1.5, n("C2"), 90), (2, n("G2"), 80), (3, n("C2"), 100)]
				if sec in ("A", "B") else [(0, n("C2"), 116), (0.5, n("G2"), 74), (1, n("C2"), 92), (1.75, n("G2"), 78),
					(2, n("C2"), 106), (2.75, n("G2"), 82), (3, n("C2"), 98), (3.5, n("G2"), 86)])
			drums.note(t, 0.2, KICK, 108)
			drums.note(t + 1, 0.2, SNARE, 100)
			drums.note(t + 2.5, 0.2, KICK, 98)
			drums.note(t + 3, 0.2, SNARE, 100)
			for k in range(8):
				drums.note(t + k * 0.5, 0.2, HAT, 64 if k % 2 == 0 else 48)
		if sec in ("C", "turn") and b % 2 == 1:
			brass.chord(t, 0.5, chords[ci], 98)
			brass.chord(t + 1.5, 0.5, chords[ci], 90)
			brass.chord(t + 3, 1.2, chords[ci], 96)
		if b in (4, 12, 20, 28, 36, 48):
			for k in range(8):
				timp.note(t + 2 + k * 0.25, 0.25, n("D3") if b != 48 else n("A2"), 60 + k * 6)
	for bar_no in (1, 13, 29, 41):
		for i, name in enumerate(["D5", "F5", "A5", "D6"]):
			bells.note(s.bar(bar_no) + i * 1.0, 6.0, n(name), 58)
	p1 = bars_of("A4:2 Bb4:1 A4:1", "G4:2 A4:2", "D5:3 Eb5:1", "D5:2 A4:2", "Bb4:2 A4:2", "G4:2 A4:2", "D5:1 Eb5:1 D5:2", "A4:4")
	p2 = bars_of("D5:1 Eb5:1 G5:2", "A5:2 G5:2", "Eb5:1 D5:1 A4:2", "Bb4:4", "G5:2 A5:2", "Bb5:3 A5:1", "G5:2 Eb5:2", "D5:4")
	lead.phrase(s.bar(5), p1, vel=88, slide=True, vibrato=True)
	violin.phrase(s.bar(13), p2, vel=84)
	lead.phrase(s.bar(13), p2, vel=94, slide=True, vibrato=True, transpose=-12)
	violin.phrase(s.bar(21), p1, vel=62, transpose=12)
	horns.phrase(s.bar(21), p1, vel=64, transpose=-12)
	lead.phrase(s.bar(29), p2, vel=108, slide=True, vibrato=True, transpose=12)
	horns.phrase(s.bar(29), p2, vel=90, transpose=-12)
	brass.phrase(s.bar(37), p1, vel=96, legato=0.9)
	lead.phrase(s.bar(37), p2, vel=104, slide=True, vibrato=True, transpose=12)
	violin.phrase(s.bar(37), p2, vel=86, legato=0.9)
	return s


# Hollow: "Ledger of Names". D whole-tone-ish (D E F# G# Bb C), 66 BPM: bowed glass, bells, low strings.
def hollow() -> Song:
	s = Song("hollow", bpm=66, bars=32, seed=283)
	drone = s.part(CONTRABASS, volume=82, pan=60, reverb=70)
	bowed = s.part(BOWED_PAD, volume=64, pan=44, reverb=95)
	air = s.part(ATMOSPHERE, volume=44, pan=64, reverb=100)
	celesta = s.part(CELESTA, volume=70, pan=84, reverb=95)
	crystal = s.part(CRYSTAL, volume=38, pan=24, reverb=100)
	cello = s.part(CELLO, volume=84, pan=70, reverb=85)
	choir = s.part(VOICE_OOH, volume=52, pan=64, reverb=100)
	timp = s.part(TIMPANI, volume=64, pan=64, reverb=80, humanize=0.0)

	drone.note(s.bar(1), 64.0, n("D1"), 54)
	drone.note(s.bar(17), 56.0, n("Bb0") + 12, 46)
	beds = [notes("D3 F#3 G#3 C4"), notes("E3 G#3 Bb3 D4"), notes("Bb2 D3 F#3 G#3"), notes("C3 E3 G#3 Bb3")]
	bed(bowed, s, 1, 32, beds, 4, 50)
	bed(air, s, 5, 32, [notes("D2 A2 C#3"), notes("Bb1 F2 G#2")], 8, 36)
	bed(choir, s, 13, 28, [notes("D4 F#4 C5"), notes("Bb3 D4 G#4"), notes("E4 G#4 D5"), notes("C4 E4 Bb4")], 4, 40)
	# A slow figure on the celesta that never settles on a key.
	figure = [notes("F#5 D5 G#4 C5"), notes("G#5 E5 Bb4 D5"), notes("D5 Bb4 F#4 G#4"), notes("E5 C5 G#4 Bb4")]
	for b in range(3, 31):
		pool = figure[((b - 1) // 4) % 4]
		for i, p in enumerate(pool):
			celesta.note(s.bar(b) + i * 1.0, 3.0, p, 44 + (6 if i == 0 else 0))
	cello.phrase(s.bar(5), "D3:6 F#3:2 G#3:8", vel=70, vibrato=True)
	cello.phrase(s.bar(13), "Bb3:6 G#3:2 F#3:4 D3:4", vel=76, vibrato=True)
	cello.phrase(s.bar(21), "E3:6 G#3:2 Bb3:4 D4:4", vel=80, vibrato=True)
	cello.phrase(s.bar(27), "D4:4 C4:2 Bb3:2 G#3:8", vel=72, vibrato=True)
	for bar_no, name in [(4, "G#6"), (10, "D7"), (16, "F#6"), (22, "C7"), (28, "G#6")]:
		crystal.note(s.bar(bar_no) + 2, 6.0, n(name), 42)
	for bar_no in range(9, 33):
		if bar_no % 2 == 1:
			timp.note(s.bar(bar_no), 1.0, n("D2"), 44 + (bar_no - 9))
	return s


# --------------------------------------------------------------------------
# Night versions of the regions' themes: the same melodies, slower and softer,
# the percussion gone, the plucked and bowed instruments swapped for gentler
# ones. Made by changing a finished song, so a region's night sounds like its
# own place.
# --------------------------------------------------------------------------

NIGHT_PROGRAMS = {KOTO: HARP, SHAMISEN: KOTO, BRASS: FRENCH_HORN, STRINGS: SLOW_STRINGS, VIOLIN: SLOW_STRINGS,
	PIZZICATO: KALIMBA, FLUTE: SHAKUHACHI, CHOIR: VOICE_OOH, TREMOLO_STRINGS: SLOW_STRINGS}


def nightfall(make, name: str, bpm_scale: float = 0.78) -> Song:
	s = make()
	s.name = name
	s.bpm = s.bpm * bpm_scale
	kept = []
	for part in s.parts:
		if part.program in (DRUMS, TAIKO, TIMPANI):
			continue
		part.program = NIGHT_PROGRAMS.get(part.program, part.program)
		part.volume = int(part.volume * 0.78)
		part.reverb = min(127, part.reverb + 25)
		part.events = [(beat, length * 1.1, pitch, max(1, int(vel * 0.76))) for beat, length, pitch, vel in part.events]
		kept.append(part)
	s.parts = kept
	return s


TRACKS = {
	"title": (title, -19.0), "calm": (calm, -21.0), "battle": (battle, -17.0), "boss": (boss, -17.0),
	"autumn_wood": (autumn_wood, -21.0), "ashen_pass": (ashen_pass, -22.0), "old_dam": (old_dam, -20.0),
	"frozen_road": (frozen_road, -22.0), "five_winds": (five_winds, -19.0), "night": (night, -26.5),
	"sea": (sea, -20.0), "battle2": (battle2, -17.0), "tension": (tension, -23.0), "sorrow": (sorrow, -22.0),
	# The open world's own.
	"road": (road, -21.0), "village": (village, -21.0), "shrine": (shrine, -24.0), "camp": (camp, -18.0),
	"duel": (duel, -19.0), "battle3": (battle3, -17.0), "finale": (finale, -17.0), "hollow": (hollow, -24.0),
	# Night versions.
	"calm_night": (lambda: nightfall(calm, "calm_night"), -27.0),
	"autumn_wood_night": (lambda: nightfall(autumn_wood, "autumn_wood_night"), -27.0),
	"ashen_pass_night": (lambda: nightfall(ashen_pass, "ashen_pass_night"), -28.0),
	"old_dam_night": (lambda: nightfall(old_dam, "old_dam_night"), -27.0),
	"frozen_road_night": (lambda: nightfall(frozen_road, "frozen_road_night"), -28.0),
	"five_winds_night": (lambda: nightfall(five_winds, "five_winds_night", 0.82), -26.0),
	"road_night": (lambda: nightfall(road, "road_night"), -27.0),
}


def render(song: Song, target_rms_db: float, out: Path, work: Path) -> None:
	mid = work / f"{song.name}.mid"
	wav = work / f"{song.name}_raw.wav"
	song.to_midi(mid, repeats=3)
	subprocess.run(["fluidsynth", "-ni", "-q", "-g", "0.5", "-r", str(SR), "-R", "1", "-C", "1",
		"-o", "synth.reverb.room-size=0.72", "-o", "synth.reverb.width=0.9", "-o", "synth.reverb.level=0.8",
		"-F", str(wav), str(SOUNDFONT), str(mid)], check=True, stdout=subprocess.DEVNULL)
	rate, data = wavfile.read(wav)
	x = data.astype(np.float64) / 32768.0
	length = round(song.seconds * rate)
	loop = x[length:2 * length].copy()
	# What really follows the loop's last sample is the third pass's start;
	# fade from that into the loop's own start so the wrap has no click.
	fade = int(0.05 * rate)
	ramp = np.linspace(0.0, 1.0, fade)[:, None]
	loop[:fade] = loop[:fade] * ramp + x[2 * length:2 * length + fade] * (1.0 - ramp)
	rms = np.sqrt(np.mean(loop ** 2)) + 1e-12
	gain = 10 ** (target_rms_db / 20.0) / rms
	loop = loop * gain
	peak = np.max(np.abs(loop))
	if peak > 0.89:
		# Soft-knee limiter above -1 dB: rare peaks only.
		loop = np.where(np.abs(loop) > 0.8, np.sign(loop) * (0.8 + 0.19 * np.tanh((np.abs(loop) - 0.8) / 0.19)), loop)
	pcm = work / f"{song.name}.wav"
	wavfile.write(pcm, rate, (np.clip(loop, -1, 1) * 32767).astype(np.int16))
	dest = out / f"{song.name}.ogg"
	subprocess.run(["oggenc", "-Q", "-q", "3", "-o", str(dest), str(pcm)], check=True)
	print(f"{dest.name}  {song.seconds:.1f}s  gain {20 * np.log10(gain):+.1f} dB  peak {20 * np.log10(peak + 1e-12):+.1f} dB"
		f"  {dest.stat().st_size / 1024:.0f} KiB")


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
	parser.add_argument("--only", action="append", choices=sorted(TRACKS))
	parser.add_argument("--keep", type=Path, help="keep the MIDI and WAV files in this folder")
	args = parser.parse_args()
	for tool in ("fluidsynth", "oggenc"):
		if shutil.which(tool) is None:
			sys.exit(f"{tool} not found: apt install fluidsynth fluid-soundfont-gm vorbis-tools")
	if not SOUNDFONT.exists():
		sys.exit(f"{SOUNDFONT} not found: apt install fluid-soundfont-gm")
	args.out.mkdir(parents=True, exist_ok=True)
	with tempfile.TemporaryDirectory() as tmp:
		work = args.keep or Path(tmp)
		work.mkdir(parents=True, exist_ok=True)
		for name in args.only or TRACKS:
			make, level = TRACKS[name]
			render(make(), level, args.out, work)
	if args.out == DEFAULT_OUT:
		subprocess.run([sys.executable, str(Path(__file__).with_name("sync_audio_pack.py"))], check=True)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
