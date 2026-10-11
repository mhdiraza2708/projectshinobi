"""Masters a character's lines recorded with ElevenLabs into the game's voice files.

    python art/audio/import_elevenlabs.py asahi DIR

DIR holds one MP3 per line, named by the line's key (see make_voices.py):
DIR/927032b15bda.mp3. Lines without a file keep whatever recording they had.
Each clip goes through the same mastering as the Kokoro recordings (filter,
trim, level, OGG), so the two sets sit together in the game. The character's
effect in characters.json (Nue's spirit) is applied; its Kokoro speaker and
speed are not, since an ElevenLabs voice is picked in the ElevenLabs workspace.
Characters recorded this way go in make_voices.RECORDED_ELSEWHERE so the
Kokoro script leaves them alone.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

import make_voices as mv


def decode(path: Path, rate: int) -> np.ndarray:
	"""The clip as mono float samples at `rate`."""
	x, sr = sf.read(path, dtype="float32", always_2d=True)
	x = x.mean(axis=1)
	if sr != rate:
		x = resample_poly(x, rate, sr).astype(np.float32)
	return x


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("who", help="the character, as in characters.json (asahi, hisame...)")
	parser.add_argument("dir", type=Path, help="folder of MP3s named by line key")
	parser.add_argument("--out", type=Path, default=mv.DEFAULT_OUT)
	args = parser.parse_args()
	if shutil.which("oggenc") is None:
		sys.exit("oggenc not found: apt install vorbis-tools")

	cast, lines = mv.collect()
	mine = [l for l in lines if l.who == args.who]
	if not mine:
		sys.exit(f"no lines for '{args.who}' in the story")
	# The character's effect (Nue's spirit) is applied as it is for Kokoro.
	voice = cast[args.who]["voice"]
	found = [l for l in mine if (args.dir / f"{l.key}.mp3").exists()]
	missing = [l for l in mine if l not in found]
	total = 0.0
	with tempfile.TemporaryDirectory() as tmp:
		for l in found:
			x = decode(args.dir / f"{l.key}.mp3", mv.SAMPLE_RATE)
			total += mv.finish(x, mv.SAMPLE_RATE, args.out / l.who / f"{l.key}.ogg", voice, Path(tmp))
	print(f"{args.who}: {len(found)}/{len(mine)} lines, {total / 60:.1f} minutes")
	for l in missing:
		print(f"  missing {l.key}  {l.spoken}")
	return 0 if not missing else 1


if __name__ == "__main__":
	raise SystemExit(main())
