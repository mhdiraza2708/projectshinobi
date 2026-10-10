"""Measures the sound effects: peak, RMS and loudness of every WAV.

    python art/audio/measure_sfx.py [folder-or-files...]

Prints, per file, its length, sample peak (dBFS), RMS over the whole file, RMS
of its loudest 50 ms, and LK: the K-weighted loudness of its loudest 100 ms,
which is the number make_sfx.py's LEVELS table sets. Files with clipped
samples or a DC offset are flagged. With no arguments it measures the game's
sfx folder.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sfx  # noqa: E402


def db(v: float) -> float:
    return 20.0 * np.log10(max(float(v), 1e-9))


def measure(path: Path) -> dict:
    rate, raw = wavfile.read(path)
    x = raw.astype(np.float64) / 32768.0
    if x.ndim > 1:
        x = x.mean(axis=1)
    if rate != make_sfx.SR:
        raise ValueError(f"{path.name}: {rate} Hz, expected {make_sfx.SR}")
    w = int(0.05 * rate)
    blocks = len(x) // w
    loud50 = np.sqrt(np.mean(x[: blocks * w].reshape(blocks, w) ** 2, axis=1)).max() if blocks else 0.0
    return {
        "seconds": len(x) / rate,
        "peak": db(np.max(np.abs(x))),
        "rms": db(np.sqrt(np.mean(x ** 2))),
        "loud50": db(loud50),
        "lk": make_sfx.loudness_db(x),
        "clipped": int(np.sum(np.abs(raw) >= 32767)),
        "dc": abs(float(np.mean(x))),
    }


def collect(args: list[str]) -> list[Path]:
    if not args:
        args = [str(make_sfx.DEFAULT_OUT)]
    out: list[Path] = []
    for a in args:
        p = Path(a)
        out.extend(sorted(p.glob("*.wav")) if p.is_dir() else [p])
    return out


def main() -> int:
    print(f"{'sound':20s} {'secs':>5s} {'peak':>6s} {'rms':>6s} {'loud50':>7s} {'LK':>6s}")
    bad = 0
    for path in collect(sys.argv[1:]):
        m = measure(path)
        flag = ""
        if m["clipped"]:
            flag += " CLIPPED"
        if m["dc"] > 0.01 and "loop" not in path.stem:
            flag += " DC"
        bad += bool(flag)
        print(f"{path.stem:20s} {m['seconds']:5.2f} {m['peak']:6.1f} {m['rms']:6.1f} {m['loud50']:7.1f} {m['lk']:6.1f}{flag}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
