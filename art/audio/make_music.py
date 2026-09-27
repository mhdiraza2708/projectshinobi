"""Composes and renders Project Shinobi's music as seamless Ogg Vorbis loops.

    python art/audio/make_music.py [--out game/assets/audio/music] [--only NAME]

Every track is written out below as notes. They're rendered through
FluidSynth with the FluidR3 General MIDI SoundFont (MIT licence), which has
sampled koto, shamisen, shakuhachi, taiko, strings, brass and choir. Each
loop is rendered three times and the middle pass is kept, so reverb from the
end carries into the start and the loop has no seam.

The music is original. It uses Japanese scales: miyako-bushi (D Eb G A Bb /
E F A B C) and yo (G A C D E).

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
DRUMS = -1  # channel 10
# Drum kit notes.
KICK, SNARE, HAT, OPEN_HAT, CRASH, LOW_TOM, MID_TOM, HIGH_TOM = 36, 38, 42, 46, 49, 45, 47, 50

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


TRACKS = {"title": (title, -19.0), "calm": (calm, -21.0), "battle": (battle, -17.0), "boss": (boss, -17.0)}


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
