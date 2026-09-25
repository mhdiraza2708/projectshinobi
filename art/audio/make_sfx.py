"""Synthesises Project Shinobi's sound effects as WAV files.

    python art/audio/make_sfx.py [--out game/assets/audio/sfx] [--only NAME]

Everything here is generated from noise, filters and oscillators with fixed
seeds, so the output is reproducible and entirely original (no licensing).
It's "good game-jam" quality; drop recorded/purchased sounds with the same
file names into game/assets/audio/sfx/ to replace any of them.

Needs numpy and scipy (see art/audio/requirements.txt).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "audio" / "sfx"


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def noise(seconds: float, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).uniform(-1.0, 1.0, int(seconds * SR))


def brown(seconds: float, seed: int) -> np.ndarray:
    b = np.cumsum(noise(seconds, seed))
    b = hp(b, 20.0)
    return b / (np.max(np.abs(b)) + 1e-9)


def env(n: int, attack: float, decay: float, hold: float = 0.0) -> np.ndarray:
    """Linear attack, optional hold, exponential decay (decay = time to ~-60 dB)."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    after = np.clip(t - attack - hold, 0.0, None)
    return a * np.exp(-6.9 * after / max(decay, 1e-4))


def _sos(kind: str, freq, order: int = 2):
    nyq = SR * 0.5
    if isinstance(freq, (tuple, list)):
        wn = [min(max(f / nyq, 1e-4), 0.999) for f in freq]
    else:
        wn = min(max(freq / nyq, 1e-4), 0.999)
    return butter(order, wn, btype=kind, output="sos")


def lp(x, f, order=2):
    return sosfilt(_sos("lowpass", f, order), x)


def hp(x, f, order=2):
    return sosfilt(_sos("highpass", f, order), x)


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("bandpass", (lo, hi), order), x)


def svf_sweep(x: np.ndarray, f_start: float, f_mid: float, f_end: float, q: float = 1.2, mode: str = "bp") -> np.ndarray:
    """State-variable filter whose cutoff glides start -> mid -> end."""
    n = len(x)
    half = n // 2
    f = np.concatenate([np.geomspace(f_start, f_mid, half), np.geomspace(f_mid, f_end, n - half)])
    out = np.zeros(n)
    low = band = 0.0
    damp = 1.0 / q
    for i in range(n):
        c = 2.0 * np.sin(np.pi * min(f[i], SR * 0.2) / SR)
        high = x[i] - low - damp * band
        band += c * high
        low += c * band
        out[i] = {"bp": band, "lp": low, "hp": high}[mode]
    return out


def tone(freq_start: float, freq_end: float, seconds: float, shape: str = "sine") -> np.ndarray:
    n = int(seconds * SR)
    f = np.geomspace(max(freq_start, 1.0), max(freq_end, 1.0), n)
    phase = 2 * np.pi * np.cumsum(f) / SR
    if shape == "saw":
        return 2.0 * ((phase / (2 * np.pi)) % 1.0) - 1.0
    return np.sin(phase)


def pad(x: np.ndarray, seconds: float) -> np.ndarray:
    n = int(seconds * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mix(*parts: np.ndarray) -> np.ndarray:
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x: np.ndarray, seconds: float, total: float) -> np.ndarray:
    """Places `x` starting at `seconds` inside a buffer `total` long."""
    out = np.zeros(int(total * SR))
    start = int(seconds * SR)
    end = min(len(out), start + len(x))
    out[start:end] = x[: end - start]
    return out


def crackle(seconds: float, rate: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    out = np.zeros(n)
    hits = rng.random(n) < rate / SR
    out[hits] = rng.uniform(-1, 1, hits.sum())
    return hp(out, 1800.0)


def finish(x: np.ndarray, peak_db: float = -1.0, fade_ms: float = 3.0) -> np.ndarray:
    x = x - np.mean(x)
    f = int(fade_ms / 1000 * SR)
    if f and len(x) > 2 * f:
        ramp = np.linspace(0.0, 1.0, f)
        x[:f] *= ramp
        x[-f:] *= ramp[::-1]
    peak = np.max(np.abs(x)) + 1e-9
    return x * (10 ** (peak_db / 20.0) / peak)


# --------------------------------------------------------------------------
# Sounds
# --------------------------------------------------------------------------

def seal(bank: int) -> np.ndarray:
    """A crisp hand clap; each seal bank sits a little higher."""
    d = 0.1
    k = 2 ** (bank * 2 / 12)
    clap = bp(noise(d, 10 + bank), 1100 * k, 4600 * k) * env(int(d * SR), 0.001, 0.02)
    clap2 = at(bp(noise(d, 20 + bank), 1300 * k, 5000 * k) * env(int(d * SR), 0.001, 0.015), 0.007, d) * 0.6
    body = tone(230 * k, 180 * k, d) * env(int(d * SR), 0.001, 0.045) * 0.5
    return mix(clap, clap2, body)


def weave_start():
    d = 0.5
    n = int(d * SR)
    t = t_axis(d)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 6 * t)
    chord = sum(np.sin(2 * np.pi * f * vib * t * (1 + 0.05 * t)) / (i + 1) for i, f in enumerate([220, 330, 440]))
    breath = bp(noise(d, 31), 2000, 6500) * 0.12
    return (chord * 0.5 + breath) * env(n, 0.08, 0.35, 0.05)


def seal_break():
    d = 0.5
    n = int(d * SR)
    fizz = svf_sweep(noise(d, 41), 3200, 1200, 180, q=0.9, mode="lp") * env(n, 0.004, 0.35)
    fall = tone(620, 140, d) * env(n, 0.005, 0.3) * 0.3
    return mix(fizz, fall)


def misfire():
    d = 0.4
    n = int(d * SR)
    puff = lp(noise(d, 51), 900) * env(n, 0.003, 0.25)
    thud = tone(95, 48, d) * env(n, 0.002, 0.18) * 0.8
    return mix(puff, thud)


def cast_fire():
    d = 1.0
    n = int(d * SR)
    roar = svf_sweep(brown(d, 61) * 0.6 + noise(d, 62) * 0.4, 350, 2600, 800, q=0.8, mode="lp")
    roar *= env(n, 0.06, 0.55, 0.15)
    snap = crackle(d, 70, 63) * env(n, 0.01, 0.8) * 0.6
    whump = tone(90, 55, d) * env(n, 0.01, 0.3) * 0.6
    return mix(roar, snap, whump)


def cast_wind():
    d = 0.8
    n = int(d * SR)
    gust = svf_sweep(noise(d, 71), 450, 3800, 900, q=2.2) * env(n, 0.08, 0.45, 0.1)
    edge = svf_sweep(noise(d, 72), 2500, 7000, 3000, q=4.0) * env(n, 0.12, 0.3) * 0.35
    return mix(gust, edge)


def cast_lightning():
    d = 0.7
    n = int(d * SR)
    t = t_axis(d)
    carrier = np.geomspace(2400, 280, n)
    mod = np.sin(2 * np.pi * np.cumsum(carrier * 1.37) / SR) * 4.0
    zap = np.sin(2 * np.pi * np.cumsum(carrier) / SR + mod) * env(n, 0.001, 0.18)
    rng = np.random.default_rng(81)
    gate = (np.sin(2 * np.pi * rng.uniform(35, 75) * t + rng.uniform(0, 6)) > 0.2).astype(float)
    arcs = hp(noise(d, 82), 2500) * gate * env(n, 0.002, 0.55) * 0.55
    buzz = tone(120, 118, d, "saw") * env(n, 0.005, 0.4) * 0.18
    return mix(zap * 0.8, arcs, crackle(d, 140, 83) * env(n, 0.001, 0.6) * 0.8, buzz)


def cast_earth():
    d = 1.1
    n = int(d * SR)
    rumble = lp(brown(d, 91), 170, 4) * env(n, 0.03, 0.85)
    thud = tone(72, 34, d) * env(n, 0.002, 0.4)
    gravel = bp(crackle(d, 90, 92) + noise(d, 93) * 0.05, 500, 2600) * env(n, 0.02, 0.6) * 1.5
    return mix(rumble * 0.9, thud, gravel)


def cast_water():
    d = 0.9
    n = int(d * SR)
    rng = np.random.default_rng(101)
    splash = bp(noise(d, 102), 700, 5200) * env(n, 0.006, 0.4)
    swell = lp(noise(d, 103), 600) * env(n, 0.04, 0.5) * 0.6
    bubbles = np.zeros(n)
    for _ in range(14):
        start = rng.uniform(0.02, d * 0.7)
        f0 = rng.uniform(350, 900)
        blip = tone(f0, f0 * 2.1, 0.03) * env(int(0.03 * SR), 0.002, 0.03)
        bubbles += at(blip, start, d) * rng.uniform(0.15, 0.35)
    return mix(splash, swell, bubbles)


def cast_none():
    d = 0.55
    n = int(d * SR)
    t = t_axis(d)
    notes = [523.25, 659.25, 783.99]
    chord = sum(at(np.sin(2 * np.pi * f * t[: int((d - i * 0.04) * SR)]), i * 0.04, d) for i, f in enumerate(notes))
    shimmer = bp(noise(d, 111), 4000, 9000) * 0.12
    return (chord * 0.35 + shimmer) * env(n, 0.01, 0.4)


def impact():
    d = 0.3
    n = int(d * SR)
    body = tone(115, 45, d) * env(n, 0.001, 0.14)
    click = hp(noise(d, 121), 1500) * env(n, 0.001, 0.012) * 0.7
    dust = lp(noise(d, 122), 1500) * env(n, 0.002, 0.1) * 0.4
    return mix(body, click, dust)


def explosion():
    d = 1.3
    n = int(d * SR)
    blast = svf_sweep(noise(d, 131), 5000, 1400, 250, q=0.8, mode="lp") * env(n, 0.002, 0.9)
    sub = tone(58, 28, d) * env(n, 0.002, 0.55)
    debris = crackle(d, 50, 132) * env(n, 0.05, 0.9) * 0.4
    return mix(blast, sub * 0.9, debris)


def wall_rise():
    d = 0.8
    n = int(d * SR)
    t = t_axis(d)
    grind = svf_sweep(brown(d, 141), 150, 500, 950, q=1.0, mode="lp")
    grind *= (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t)) * env(n, 0.05, 0.45, 0.25)
    thud = at(tone(80, 40, 0.3) * env(int(0.3 * SR), 0.002, 0.2), 0.3, d)
    return mix(grind, thud * 0.8)


def heal():
    d = 1.2
    t = t_axis(d)
    parts = []
    for i, f in enumerate([880.0, 1318.5, 1760.0]):
        seg = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 1.003 * t)
        parts.append(at(seg * env(len(seg), 0.02, 0.9), i * 0.07, d) * (0.5 - i * 0.1))
    return mix(*parts)


def buff():
    d = 0.8
    n = int(d * SR)
    rise = tone(300, 950, d) * env(n, 0.03, 0.55, 0.1)
    fifth = tone(450, 1425, d) * env(n, 0.05, 0.5, 0.1) * 0.5
    sparkle = hp(noise(d, 151), 5000) * env(n, 0.2, 0.4) * 0.2
    return mix(rise * 0.6, fifth * 0.6, sparkle)


def kunai_throw():
    d = 0.22
    n = int(d * SR)
    return svf_sweep(noise(d, 161), 1500, 5200, 2600, q=3.0) * env(n, 0.012, 0.14)


def kunai_hit():
    d = 0.4
    n = int(d * SR)
    t = t_axis(d)
    click = hp(noise(d, 171), 2000) * env(n, 0.0005, 0.006)
    ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(2480, 1.0), (3960, 0.6), (5870, 0.35)])
    ring *= env(n, 0.0005, 0.22) * 0.25
    thunk = tone(260, 190, d) * env(n, 0.0005, 0.06) * 0.7
    return mix(click, ring, thunk)


def strike_whoosh():
    d = 0.17
    return svf_sweep(noise(d, 181), 700, 2300, 1100, q=2.0) * env(int(d * SR), 0.015, 0.1)


def strike_hit():
    d = 0.2
    n = int(d * SR)
    body = tone(150, 60, d) * env(n, 0.001, 0.08)
    slap = lp(noise(d, 191), 2500) * env(n, 0.0005, 0.03) * 0.8
    return mix(body, slap)


def hit_player():
    d = 0.35
    n = int(d * SR)
    body = tone(95, 40, d) * env(n, 0.001, 0.18)
    crunch = bp(noise(d, 201), 300, 1600) * env(n, 0.001, 0.07)
    return mix(body, crunch * 0.8)


def guard():
    d = 0.22
    n = int(d * SR)
    clack = bp(noise(d, 211), 1500, 3200) * env(n, 0.0005, 0.02)
    wood = mix(tone(720, 700, d) * env(n, 0.0005, 0.05), tone(1080, 1060, d) * env(n, 0.0005, 0.04) * 0.6)
    return mix(clack, wood * 0.5)


def dash():
    d = 0.3
    return svf_sweep(noise(d, 221), 2600, 1600, 650, q=2.5) * env(int(d * SR), 0.01, 0.2)


def jump():
    d = 0.2
    return svf_sweep(noise(d, 231), 600, 1300, 1700, q=1.8) * env(int(d * SR), 0.01, 0.12) * 0.6


def chakra_jump():
    d = 0.4
    n = int(d * SR)
    whoosh = svf_sweep(noise(d, 241), 700, 1800, 2400, q=2.0) * env(n, 0.01, 0.2)
    shimmer = tone(880, 1320, d) * env(n, 0.01, 0.3) * 0.25
    return mix(whoosh, shimmer)


def land():
    d = 0.14
    n = int(d * SR)
    return mix(tone(110, 60, d) * env(n, 0.001, 0.06), lp(noise(d, 251), 900) * env(n, 0.001, 0.05) * 0.5)


def charge_loop():
    """A seamless 2 s chakra hum: every component completes whole cycles."""
    d = 2.0
    t = t_axis(d)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 1.5 * t)
    hum = sum(np.sin(2 * np.pi * f * t) / (i + 1) for i, f in enumerate([110.0, 220.0, 330.0, 440.0]))
    n = len(t)
    air = bp(noise(d + 0.2, 261), 800, 3000)
    x = int(0.2 * SR)
    loop_air = air[:n].copy()
    fade = np.linspace(0.0, 1.0, x)
    loop_air[:x] = air[:x] * fade + air[n : n + x] * (1 - fade)
    return (hum * 0.5 + loop_air * 0.25 * (0.7 + 0.3 * np.sin(2 * np.pi * 0.5 * t))) * trem


def ui_move():
    d = 0.06
    n = int(d * SR)
    return mix(tone(1900, 1800, d) * env(n, 0.0005, 0.014), bp(noise(d, 271), 3000, 6000) * env(n, 0.0005, 0.004) * 0.5)


def ui_select():
    d = 0.16
    n = int(d * SR)
    return mix(tone(220, 150, d) * env(n, 0.001, 0.09), hp(noise(d, 281), 1500) * env(n, 0.0005, 0.01) * 0.5)


def ui_back():
    d = 0.12
    return tone(900, 650, d) * env(int(d * SR), 0.001, 0.035)


def ui_open():
    d = 0.35
    return svf_sweep(noise(d, 291), 1100, 2600, 3600, q=1.5) * env(int(d * SR), 0.04, 0.2)


def ui_close():
    d = 0.3
    return svf_sweep(noise(d, 301), 3600, 2400, 1100, q=1.5) * env(int(d * SR), 0.02, 0.18)


def taiko(seconds: float, seed: int) -> np.ndarray:
    n = int(seconds * SR)
    head = tone(78, 54, seconds) * env(n, 0.002, 0.8)
    skin = bp(noise(seconds, seed), 900, 3000) * env(n, 0.0005, 0.02) * 0.5
    thump = lp(noise(seconds, seed + 1), 350) * env(n, 0.002, 0.12) * 0.8
    return mix(head, skin, thump)


def wave_start():
    d = 1.8
    return mix(at(taiko(1.2, 311), 0.0, d), at(taiko(1.2, 313) * 0.7, 0.22, d))


def gong(base: float, seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = t_axis(seconds)
    out = np.zeros(n)
    for ratio, amp, decay in [(1.0, 1.0, 3.0), (1.51, 0.6, 2.4), (2.08, 0.5, 1.9), (2.74, 0.35, 1.5),
                              (3.54, 0.25, 1.1), (4.5, 0.15, 0.8)]:
        f = base * ratio * rng.uniform(0.995, 1.005)
        bend = 1 + 0.01 * np.exp(-t * 3)
        out += np.sin(2 * np.pi * f * bend * t) * amp * env(n, 0.004, decay)
    mallet = lp(noise(seconds, seed + 1), 800) * env(n, 0.001, 0.05)
    return mix(out, mallet)


def victory():
    return gong(196.0, 3.5, 321)


def defeat():
    d = 2.8
    return mix(gong(98.0, d, 331), at(tone(220, 110, 1.4) * env(int(1.4 * SR), 0.2, 1.0) * 0.2, 0.3, d))


def enemy_down():
    d = 0.6
    n = int(d * SR)
    poof = lp(noise(d, 341), 1300) * env(n, 0.01, 0.4)
    thump = tone(100, 50, d) * env(n, 0.002, 0.15) * 0.6
    return mix(poof, thump)


def weak_hit():
    d = 0.35
    n = int(d * SR)
    t = t_axis(d)
    ping = (np.sin(2 * np.pi * 1568 * t) + 0.6 * np.sin(2 * np.pi * 2093 * t)) * env(n, 0.001, 0.2)
    return mix(ping * 0.5, hp(noise(d, 351), 6000) * env(n, 0.001, 0.05) * 0.3)


def smoke():
    d = 0.5
    n = int(d * SR)
    return mix(lp(noise(d, 361), 1800) * env(n, 0.005, 0.3), svf_sweep(noise(d, 362), 3000, 1200, 500, q=1.0) * env(n, 0.005, 0.3) * 0.5)


SOUNDS = {
    "seal_1": lambda: seal(0), "seal_2": lambda: seal(1), "seal_3": lambda: seal(2),
    "weave_start": weave_start, "seal_break": seal_break, "misfire": misfire,
    "cast_fire": cast_fire, "cast_wind": cast_wind, "cast_lightning": cast_lightning,
    "cast_earth": cast_earth, "cast_water": cast_water, "cast_none": cast_none,
    "impact": impact, "explosion": explosion, "wall_rise": wall_rise, "heal": heal, "buff": buff,
    "kunai_throw": kunai_throw, "kunai_hit": kunai_hit, "strike_whoosh": strike_whoosh,
    "strike_hit": strike_hit, "hit_player": hit_player, "guard": guard, "dash": dash,
    "jump": jump, "chakra_jump": chakra_jump, "land": land, "charge_loop": charge_loop,
    "ui_move": ui_move, "ui_select": ui_select, "ui_back": ui_back, "ui_open": ui_open,
    "ui_close": ui_close, "wave_start": wave_start, "victory": victory, "defeat": defeat,
    "enemy_down": enemy_down, "weak_hit": weak_hit, "smoke": smoke,
}
# Loops must not be faded or DC-shifted at the seam.
LOOPS = {"charge_loop"}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--only", choices=sorted(SOUNDS))
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for name in [args.only] if args.only else SOUNDS:
        x = SOUNDS[name]()
        if name in LOOPS:
            x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (-3 / 20)
        else:
            x = finish(x)
        wavfile.write(args.out / f"{name}.wav", SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
        print(f"{name}.wav  {len(x) / SR:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
