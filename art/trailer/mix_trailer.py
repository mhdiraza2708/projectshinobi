"""Scores the recorded trailer: music, voice lines and the game's own sound.

    python art/trailer/mix_trailer.py --movie TRAILER.avi --audio DIR --out TRAILER.mp4

TRAILER.avi is what Godot's movie writer recorded (see TrailerDirector):
the picture plus the game's sound effects. DIR is what
make_trailer_audio.py wrote (music.wav, vo_<n>.wav, cues.json). The music
dips under each voice line, everything is levelled to -14 LUFS (where
streaming sites play trailers), and the result is an H.264/AAC mp4.

Needs ffmpeg (on PATH, or pip install imageio-ffmpeg).
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path


def ffmpeg() -> str:
	found = shutil.which("ffmpeg")
	if found:
		return found
	import imageio_ffmpeg
	return imageio_ffmpeg.get_ffmpeg_exe()


def main() -> int:
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	p.add_argument("--movie", type=Path, required=True)
	p.add_argument("--audio", type=Path, required=True)
	p.add_argument("--out", type=Path, required=True)
	p.add_argument("--sfx-gain", type=float, default=0.55, help="level of the game's own sound under the music")
	p.add_argument("--fps", type=int, default=30, help="the recording's frame rate (kept in the mp4)")
	p.add_argument("--skip", type=float, default=0.0,
		help="seconds of recording before the trailer starts (TRAILER_START_FRAME / fps from Godot's log)")
	args = p.parse_args()
	cues = json.loads((args.audio / "cues.json").read_text())
	length = float(cues["seconds"])

	inputs = ["-i", str(args.movie), "-i", str(args.audio / "music.wav")]
	for line in cues["lines"]:
		inputs += ["-i", str(args.audio / line["file"])]
	chains = []
	vo_labels = []
	for i, line in enumerate(cues["lines"]):
		ms = int(round(float(line["at"]) * 1000))
		chains.append(f"[{i + 2}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={ms}|{ms},apad[vo{i}]")
		vo_labels.append(f"[vo{i}]")
	n = len(vo_labels)
	chains.append(f"{''.join(vo_labels)}amix=inputs={n}:normalize=0,atrim=0:{length},volume=1.6[vo]")
	chains.append("[vo]asplit=2[vo_mix][vo_key]")
	chains.append(f"[1:a]aresample=48000,aformat=channel_layouts=stereo,atrim=0:{length}[music]")
	# The music steps back while someone speaks.
	chains.append("[music][vo_key]sidechaincompress=threshold=0.03:ratio=6:attack=15:release=350:makeup=1[ducked]")
	skip = args.skip
	chains.append(f"[0:a]aresample=48000,aformat=channel_layouts=stereo,atrim={skip}:{skip + length},asetpts=PTS-STARTPTS,"
		f"volume={args.sfx_gain}[sfx]")
	chains.append("[ducked][sfx][vo_mix]amix=inputs=3:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[aout]")
	chains.append(f"[0:v]trim={skip}:{skip + length},setpts=PTS-STARTPTS,fps={args.fps},format=yuv420p[vout]")
	cmd = [ffmpeg(), "-y", *inputs, "-filter_complex", ";".join(chains), "-map", "[vout]", "-map", "[aout]",
		"-c:v", "libx264", "-preset", "slow", "-crf", "18", "-movflags", "+faststart",
		"-r", str(args.fps), "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-t", str(length), str(args.out)]
	subprocess.run(cmd, check=True)
	print(f"{args.out}  {args.out.stat().st_size / 1e6:.1f} MB")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
