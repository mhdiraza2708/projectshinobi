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
from scipy.signal import butter, lfilter, sosfilt

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


def modal(partials, seconds: float, seed: int = 0, detune: float = 0.0) -> np.ndarray:
    """A struck bell or blade: sines that each ring for their own time
    (`partials`: (hertz, level, seconds to -60 dB)); `detune` jitters them
    per seed so variants don't ring alike."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    out = np.zeros(len(t))
    for f, a, decay in partials:
        f *= 1.0 + rng.uniform(-detune, detune)
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * a * np.exp(-6.9 * t / decay)
    return out


def pluck(freq: float, seconds: float, seed: int, bright: float = 0.5, sustain: float = 0.996) -> np.ndarray:
    """A plucked string (Karplus-Strong): koto and shamisen-like."""
    n = int(seconds * SR)
    period = int(round(SR / freq))
    burst = np.zeros(n)
    burst[:period] = np.random.default_rng(seed).uniform(-1.0, 1.0, period)
    burst = lfilter([bright], [1.0, bright - 1.0], burst)
    a = np.zeros(period + 2)
    a[0] = 1.0
    a[period] = -sustain * 0.5
    a[period + 1] = -sustain * 0.5
    return lfilter([1.0], a, burst)


def rustle(seconds: float, seed: int, lo: float, hi: float, rate: float = 28.0) -> np.ndarray:
    """Paper, cloth or leaves: band-limited noise in random little bursts."""
    n = int(seconds * SR)
    flutter = np.clip(lp(noise(seconds, seed + 500), rate), 0.0, None) ** 1.5
    flutter /= np.max(flutter) + 1e-9
    return bp(noise(seconds, seed), lo, hi) * (0.25 + 0.75 * flutter)[:n]


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
# Loudness (so every sound can be mastered to a level, not just a peak)
# --------------------------------------------------------------------------

def _k_weight(x: np.ndarray) -> np.ndarray:
    """ITU-R BS.1770 K-weighting: a high shelf and a rumble filter."""
    g, q, fc = 3.999843853973347, 0.7071752369554196, 1681.9744509555319
    k = np.tan(np.pi * fc / SR)
    vh = 10 ** (g / 20.0)
    vb = vh ** 0.4996667741545416
    a0 = 1.0 + k / q + k * k
    shelf_b = [(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
    shelf_a = [1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
    q2, fc2 = 0.5003270373238773, 38.13547087613982
    k2 = np.tan(np.pi * fc2 / SR)
    a02 = 1.0 + k2 / q2 + k2 * k2
    return lfilter([1.0, -2.0, 1.0], [1.0, 2.0 * (k2 * k2 - 1.0) / a02, (1.0 - k2 / q2 + k2 * k2) / a02],
                   lfilter(shelf_b, shelf_a, x))


def loudness_db(x: np.ndarray, window: float = 0.1) -> float:
    """Loudness of the loudest `window` seconds (K-weighted mean square, in dB).
    Short sounds are judged on their peak moment, not averaged with silence."""
    w = int(window * SR)
    xk = _k_weight(np.pad(x, (0, max(0, w - len(x)))))
    hop = max(1, w // 10)
    sq = np.cumsum(np.concatenate([[0.0], xk * xk]))
    best = max((sq[i + w] - sq[i]) / w for i in range(0, len(xk) - w + 1, hop))
    return 10.0 * np.log10(best + 1e-12)


def master(x: np.ndarray, lk: float, ceiling_db: float = -1.0) -> np.ndarray:
    """Scales `x` to loudness `lk`, then soft-limits whatever pokes above the
    ceiling (a hit's click is far above its body, so it takes the squash)."""
    x = x * 10 ** ((lk - loudness_db(x)) / 20.0)
    ceiling = 10 ** (ceiling_db / 20.0)
    knee = ceiling * 0.6
    mag = np.abs(x)
    over = mag > knee
    squashed = knee + (ceiling - knee) * np.tanh((mag - knee) / (ceiling - knee))
    return np.where(over, np.sign(x) * squashed, x)


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


def impact(v: int = 0):
    """A jutsu landing: a low thump with a crack on top and a puff of dust."""
    d = 0.3
    n = int(d * SR)
    body = tone(115 * (1.0, 1.09, 0.92)[v], 45, d) * env(n, 0.001, 0.14)
    click = hp(noise(d, 121 + 10 * v), 1500) * env(n, 0.001, 0.012) * 0.7
    dust = lp(noise(d, 122 + 10 * v), 1500) * env(n, 0.002, 0.1) * 0.4
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


def kunai_hit(v: int = 0):
    """A kunai biting into wood: a click, a thunk and a short steel ring."""
    d = 0.4
    n = int(d * SR)
    t = t_axis(d)
    k = (1.0, 1.05, 0.95)[v]
    click = hp(noise(d, 171 + 10 * v), 2000) * env(n, 0.0005, 0.006)
    ring = sum(np.sin(2 * np.pi * f * k * t) * a for f, a in [(2480, 1.0), (3960, 0.6), (5870, 0.35)])
    ring *= env(n, 0.0005, 0.22) * 0.25
    thunk = tone(260 * k, 190 * k, d) * env(n, 0.0005, 0.06) * 0.7
    return mix(click, ring, thunk)


def strike_whoosh(v: int = 0):
    """A fist or blade cutting the air."""
    d = 0.17
    k = (1.0, 1.12, 0.9)[v]
    return svf_sweep(noise(d, 181 + 10 * v), 700 * k, 2300 * k, 1100 * k, q=2.0) * env(int(d * SR), 0.015, 0.1)


def strike_hit(v: int = 0):
    """A fist landing: a dull thud and the slap of skin and cloth."""
    d = 0.2
    n = int(d * SR)
    body = tone(150 * (1.0, 1.1, 0.9)[v], 60, d) * env(n, 0.001, 0.08)
    slap = lp(noise(d, 191 + 10 * v), 2500) * env(n, 0.0005, 0.03) * 0.8
    return mix(body, slap)


def hit_player(v: int = 0):
    """The player taking a blow."""
    d = 0.35
    n = int(d * SR)
    body = tone(95 * (1.0, 1.08)[v], 40, d) * env(n, 0.001, 0.18)
    crunch = bp(noise(d, 201 + 10 * v), 300, 1600) * env(n, 0.001, 0.07)
    return mix(body, crunch * 0.8)


def guard(v: int = 0):
    """A blow caught on the forearm guards: a dry wooden clack."""
    d = 0.22
    n = int(d * SR)
    k = (1.0, 1.07)[v]
    clack = bp(noise(d, 211 + 10 * v), 1500, 3200) * env(n, 0.0005, 0.02)
    wood = mix(tone(720 * k, 700 * k, d) * env(n, 0.0005, 0.05), tone(1080 * k, 1060 * k, d) * env(n, 0.0005, 0.04) * 0.6)
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


def land(v: int = 0):
    """Feet meeting the ground after a fall."""
    d = 0.14
    n = int(d * SR)
    return mix(tone(110 * (1.0, 1.1)[v], 60, d) * env(n, 0.001, 0.06),
               lp(noise(d, 251 + 10 * v), 900) * env(n, 0.001, 0.05) * 0.5)


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


def teleport():
    """Summoning: a rising shimmer of detuned partials over a swelling
    whoosh, ending in a soft low boom."""
    d = 2.2
    n = int(d * SR)
    t = t_axis(d)
    rise = np.zeros(n)
    for k, base in enumerate((392.0, 523.3, 659.3, 784.0, 1046.5)):
        f = base * np.geomspace(0.7, 1.25, n)
        rise += np.sin(2 * np.pi * np.cumsum(f) / SR + k) * (0.6 ** k)
    swell = np.clip(t / 1.3, 0, 1) ** 2 * np.exp(-np.clip(t - 1.35, 0, None) * 5.0)
    shimmer = rise * swell * (0.7 + 0.3 * np.sin(2 * np.pi * 11.0 * t)) * 0.25
    whoosh = svf_sweep(noise(d, 361), 300.0, 3200.0, 900.0, q=2.0) * swell * 0.9
    boom = at(tone(90, 40, 0.9) * env(int(0.9 * SR), 0.004, 0.8) * 0.9, 1.3, d)
    sparkle = at(hp(crackle(0.8, 90, 362), 5000) * env(int(0.8 * SR), 0.01, 0.6) * 0.8, 1.3, d)
    return mix(shimmer, whoosh, boom, sparkle)


def eye_open():
    """A dojutsu opening, timed to the cut-in: a rush swelling for 0.4 s, then
    as the lids part a metallic shing, a sub boom and a breathy flare, and a
    shimmer that rings out."""
    d = 1.7
    n = int(d * SR)
    t = t_axis(d)
    hit = 0.42
    # The rush: noise climbing through a filter toward the cut.
    swell = np.clip(t / hit, 0, 1) ** 2.5 * np.exp(-np.clip(t - hit, 0, None) * 14.0)
    rush = svf_sweep(noise(d, 371), 200.0, 2600.0, 5200.0, q=2.5) * swell * 0.8
    under = lp(brown(d, 372), 180) * swell * 0.9
    # The shing: inharmonic bright partials with a slight downward bend.
    m = int((d - hit) * SR)
    tt = np.arange(m) / SR
    ring = np.zeros(m)
    for k, (f, a, dec) in enumerate(((1318.0, 1.0, 0.9), (1977.0, 0.7, 0.7), (2794.0, 0.5, 0.55),
                                     (3729.0, 0.35, 0.45), (5274.0, 0.2, 0.3))):
        bend = f * (1.0 + 0.03 * np.exp(-tt * 18.0))
        ring += np.sin(2 * np.pi * np.cumsum(bend) / SR + k) * a * np.exp(-tt * 6.9 / dec)
    shing = at(ring * 0.32 + hp(noise(d - hit, 373), 4000)[:m] * np.exp(-tt * 60.0) * 0.5, hit, d)
    boom = at(tone(78, 32, 1.0) * env(int(1.0 * SR), 0.003, 0.9) * 1.0, hit, d)
    # The shimmer after: a soft high cluster trembling as it fades.
    tail = np.zeros(n)
    for k, f in enumerate((2093.0, 2637.0, 3136.0, 4186.0)):
        tail += np.sin(2 * np.pi * f * t + k * 1.3) * (0.5 ** k)
    shimmer = tail * np.clip((t - hit) / 0.05, 0, 1) * np.exp(-np.clip(t - hit, 0, None) * 2.2) \
        * (0.6 + 0.4 * np.sin(2 * np.pi * 13.0 * t)) * 0.2
    return mix(rush, under, shing, boom, shimmer)


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


def _seamless(x: np.ndarray, n: int, fade_s: float = 0.3) -> np.ndarray:
    """Crossfades the tail past n samples into the head so x[:n] loops cleanly."""
    f = int(fade_s * SR)
    out = x[:n].copy()
    ramp = np.linspace(0.0, 1.0, f)
    out[:f] = x[:f] * ramp + x[n : n + f] * (1 - ramp)
    return out


def rain_loop():
    """4 s of steady rain: a hiss bed plus scattered drop ticks, seamless."""
    d = 4.0
    n = int(d * SR)
    bed = bp(noise(d + 0.4, 401), 900, 7000) * 0.35 + lp(brown(d + 0.4, 402), 400) * 0.25
    rng = np.random.default_rng(403)
    drops = np.zeros(n + int(0.4 * SR))
    tick = hp(noise(0.012, 404), 3000) * env(int(0.012 * SR), 0.0003, 0.006)
    for pos in rng.integers(0, n, 260):
        drops[pos : pos + len(tick)] += tick * rng.uniform(0.15, 0.6)
    return _seamless(bed + drops, n)


def wind_loop():
    """4 s of gusting wind, seamless: band-passed noise with a slow swell."""
    d = 4.0
    n = int(d * SR)
    t = np.arange(n + int(0.4 * SR)) / SR
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * 0.25 * t) ** 2
    x = bp(noise(d + 0.4, 411), 250, 1400) * swell
    return _seamless(x, n)


def thunder():
    d = 3.2
    n = int(d * SR)
    crack = hp(noise(d, 421), 1200) * env(n, 0.002, 0.18) * 0.6
    rumble = lp(brown(d, 422), 160) * env(n, 0.05, 2.4) * 1.4
    roll = lp(noise(d, 423), 500) * env(n, 0.3, 1.8) * 0.5
    return mix(crack, rumble, roll)


# --------------------------------------------------------------------------
# Swords
# --------------------------------------------------------------------------

def _saya_click(seed: int) -> np.ndarray:
    """The guard meeting the scabbard's mouth: a wooden knock, a steel tick
    and the faintest ring. 0.2 s."""
    d = 0.2
    n = int(d * SR)
    knock = tone(640, 470, d) * env(n, 0.0004, 0.03) * 0.7
    tick = hp(noise(d, seed), 1800) * env(n, 0.0003, 0.007) * 0.8
    ring = modal([(2310, 1.0, 0.12), (3470, 0.5, 0.09)], d) * env(n, 0.0004, 0.12) * 0.18
    return mix(knock, tick, ring)


def sword_draw():
    """The blade leaves the scabbard: steel rasping up the mouth of the saya
    (a band of grit sweeping higher), a click as it frees, then a bright
    ringing shing. Timed to the moment the sword changes hands."""
    d = 0.6
    slide = 0.24
    m = int(slide * SR)
    rise = np.linspace(0.25, 1.0, m) ** 1.4
    grit = svf_sweep(noise(slide, 501), 1700, 4800, 8200, q=5.0) * rise * np.minimum(1.0, np.linspace(0, 1, m) * 40)
    rasp = 0.65 + 0.35 * np.clip(lp(noise(slide, 502), 90), -1, 1)
    free = at(hp(noise(0.03, 503), 2500) * env(int(0.03 * SR), 0.0003, 0.008), slide - 0.01, d) * 0.9
    shing = at(modal([(2640, 1.0, 0.5), (3980, 0.75, 0.38), (5710, 0.5, 0.3), (7460, 0.32, 0.22)], d - slide + 0.01, 504)
               * 0.55, slide - 0.01, d)
    air = at(svf_sweep(noise(0.3, 505), 500, 1800, 900, q=1.3) * env(int(0.3 * SR), 0.05, 0.16) * 0.25, slide - 0.05, d)
    return mix(at(grit * rasp, 0.0, d) * 0.8, free, shing, air)


def sword_sheathe():
    """The blade slides home into the scabbard: a quiet scrape that sinks as
    it goes in. It lasts as long as the animation's slide (0.24 s); the knock
    that ends it is sword_snap, played when the hand lets go."""
    d = 0.26
    slide = 0.235
    m = int(slide * SR)
    fall = np.linspace(1.0, 0.45, m) * np.minimum(1.0, np.linspace(0, 1, m) * 25)
    grit = svf_sweep(noise(slide, 511), 5200, 3000, 1500, q=4.0) * fall
    clink = at(modal([(3050, 1.0, 0.1)], 0.1) * env(int(0.1 * SR), 0.0004, 0.1) * 0.12, 0.02, d)
    return mix(at(grit * 0.45, 0.0, d), clink)


def sword_snap():
    """The sword home: the guard knocking against the scabbard's mouth. Ends
    every sheathing, and is all there is to a sword put away at once (to
    weave seals)."""
    return _saya_click(521)


def blade_hit(v: int = 0):
    """A cut landing with the sword: a fast sweeping 'shk' of steel through
    cloth and flesh, a dull body, and a faint steel ring."""
    d = 0.34
    n = int(d * SR)
    k = (1.0, 1.08, 0.93)[v]
    slice_ = svf_sweep(noise(d, 531 + 10 * v), 7000 * k, 2800 * k, 900 * k, q=1.7) * env(n, 0.0008, 0.07)
    edge = hp(noise(d, 532 + 10 * v), 4500) * env(n, 0.0004, 0.02) * 0.5
    body = tone(190 * k, 70, d) * env(n, 0.001, 0.07) * 0.65
    flesh = lp(noise(d, 533 + 10 * v), 700) * env(n, 0.002, 0.05) * 0.5
    ring = modal([(3100 * k, 1.0, 0.16), (4720 * k, 0.5, 0.1)], d) * env(n, 0.0006, 0.16) * 0.12
    return mix(slice_ * 0.9, edge, body, flesh, ring)


def blade_clash(v: int = 0):
    """Steel on steel: a hard click and clang, inharmonic partials ringing
    on in slightly detuned pairs, and a short scrape as the blades slide."""
    d = 0.9
    n = int(d * SR)
    base = [(1230, 1.0, 0.75), (1860, 0.85, 0.6), (2740, 0.9, 0.5), (3520, 0.6, 0.4), (4890, 0.5, 0.3), (6330, 0.35, 0.22)]
    ring = modal(base, d, 541 + v, 0.02) + modal([(f * 1.004, a * 0.6, dec) for f, a, dec in base], d, 551 + v, 0.02)
    click = hp(noise(d, 561 + 10 * v), 1500) * env(n, 0.0003, 0.009)
    scrape = svf_sweep(noise(0.12, 562 + v), 3000, 6200, 3600, q=3.0) * env(int(0.12 * SR), 0.003, 0.07) * 0.5
    thunk = tone(260, 130, d) * env(n, 0.001, 0.04) * 0.5
    return mix(ring * 0.28, click, at(scrape, 0.01, d), thunk)


def guard_break():
    """A guard smashed aside: a hard crack, splintering debris, a low body
    blow and a falling metallic ring."""
    d = 0.8
    n = int(d * SR)
    crack = hp(noise(d, 571), 1000) * env(n, 0.0004, 0.05)
    splinter = crackle(d, 220, 572) * env(n, 0.002, 0.3) * 1.4
    body = tone(140, 38, d) * env(n, 0.002, 0.3)
    thump = lp(noise(d, 573), 420) * env(n, 0.003, 0.18) * 0.9
    ring = modal([(1500, 0.6, 0.5), (2330, 0.5, 0.4), (3410, 0.35, 0.3)], d, 574, 0.01) * env(n, 0.001, 0.5) * 0.25
    return mix(crack * 0.9, splinter, body, thump, ring)


# --------------------------------------------------------------------------
# Footsteps (three of each, so a run doesn't machine-gun one sample)
# --------------------------------------------------------------------------

def step_dirt(v: int = 0):
    """A foot on packed earth: heel thud, a scuff of grit, the toe after."""
    d = 0.2
    n = int(d * SR)
    s = 600 + 10 * v
    heel = tone(105 * (1.0, 1.12, 0.9)[v], 55, d) * env(n, 0.002, 0.05)
    body = lp(noise(d, s), 700) * env(n, 0.002, 0.055) * 0.9
    grit = bp(noise(d, s + 1), 1400, 5000) * env(n, 0.004, 0.04) * 0.3
    toe = at(lp(noise(0.1, s + 2), 520) * env(int(0.1 * SR), 0.002, 0.035), 0.075, d) * 0.35
    return mix(heel * 0.8, body, grit, toe)


def step_grass(v: int = 0):
    """A foot in grass: a soft swish of blades over a muffled thud."""
    d = 0.26
    n = int(d * SR)
    s = 620 + 10 * v
    swish = bp(noise(d, s), 2300, 7200) * env(n, 0.012, 0.08) * 0.8
    thud = lp(noise(d, s + 1), 380) * env(n, 0.003, 0.05)
    heel = tone(85 * (1.0, 1.1, 0.92)[v], 50, d) * env(n, 0.003, 0.05) * 0.6
    tail = rustle(d, s + 2, 3000, 8500) * env(n, 0.03, 0.14) * 0.3
    return mix(swish, thud, heel, tail)


def step_stone(v: int = 0):
    """A foot on rock or boards: a crisp tap with a hollow knock."""
    d = 0.16
    n = int(d * SR)
    s = 640 + 10 * v
    k = (1.0, 1.08, 0.94)[v]
    tap = hp(noise(d, s), 1800) * env(n, 0.0004, 0.014)
    knock = tone(215 * k, 150 * k, d) * env(n, 0.001, 0.035) * 0.8
    scuff = bp(noise(d, s + 1), 700, 2400) * env(n, 0.001, 0.03) * 0.55
    toe = at(hp(noise(0.05, s + 2), 1600) * env(int(0.05 * SR), 0.0004, 0.01), 0.06, d) * 0.4
    return mix(tap * 0.7, knock, scuff, toe)


def step_sand(v: int = 0):
    """A foot in sand: a soft scrunch of grains and a very low thud."""
    d = 0.25
    n = int(d * SR)
    s = 660 + 10 * v
    scrunch = bp(noise(d, s), 1100, 4600) * env(n, 0.008, 0.09) * 0.8
    grains = crackle(d, 900, s + 1) * env(n, 0.004, 0.09) * 1.6
    thud = lp(noise(d, s + 2), 260) * env(n, 0.003, 0.05)
    return mix(scrunch, grains, thud * 0.9)


def step_snow(v: int = 0):
    """A foot in snow: a squeaky crunch of crystals over a muffled step."""
    d = 0.28
    n = int(d * SR)
    s = 680 + 10 * v
    crunch = crackle(d, 1300, s) * env(n, 0.004, 0.11) * 1.8
    squeak = bp(noise(d, s + 1), 2400, 6500) * env(n, 0.015, 0.07) * 0.45
    thud = lp(noise(d, s + 2), 300) * env(n, 0.004, 0.06) * 0.8
    return mix(crunch, squeak, thud)


def step_water(v: int = 0):
    """A foot splashing in shallow water: a slap, a spray, a bubble or two."""
    d = 0.38
    n = int(d * SR)
    s = 700 + 10 * v
    rng = np.random.default_rng(s)
    slap = bp(noise(d, s), 500, 4800) * env(n, 0.003, 0.13)
    plap = tone(300 * (1.0, 1.1, 0.9)[v], 140, d) * env(n, 0.002, 0.05) * 0.6
    spray = hp(noise(d, s + 1), 3500) * env(n, 0.01, 0.12) * 0.3
    drops = np.zeros(n)
    for _ in range(3):
        f0 = rng.uniform(500, 1100)
        blip = tone(f0, f0 * 1.9, 0.035) * env(int(0.035 * SR), 0.002, 0.03)
        drops += at(blip, rng.uniform(0.05, 0.25), d) * rng.uniform(0.15, 0.3)
    return mix(slap, plap, spray, drops)


# --------------------------------------------------------------------------
# Movement and combat cues
# --------------------------------------------------------------------------

def charge_start():
    """Chakra catching: a swell of air climbing through a filter over a
    rising hum, and a bright flare as it takes hold."""
    d = 0.6
    t = t_axis(d)
    ramp = np.clip(t / 0.45, 0, 1) ** 1.6 * np.exp(-np.clip(t - 0.45, 0, None) * 12.0)
    air = svf_sweep(noise(d, 601), 250, 1400, 3400, q=2.5) * ramp
    rise = (tone(110, 330, d) + 0.5 * tone(220, 660, d)) * ramp * 0.35
    flare = at(bp(noise(0.2, 602), 3000, 8500) * env(int(0.2 * SR), 0.01, 0.12) * 0.4, 0.42, d)
    return mix(air, rise, flare)


def charge_end():
    """Chakra released: the glow sinks back, a breath of air going out."""
    d = 0.4
    n = int(d * SR)
    sink = svf_sweep(noise(d, 611), 3200, 1100, 280, q=1.8) * env(n, 0.01, 0.22)
    fall = (tone(330, 110, d) + 0.4 * tone(660, 220, d)) * env(n, 0.01, 0.2) * 0.3
    return mix(sink, fall)


def dodge():
    """A quick sidestep: a cloth swish and a soft landing."""
    d = 0.26
    n = int(d * SR)
    m = int(0.1 * SR)
    swish = svf_sweep(noise(d, 621), 4500, 3000, 1400, q=1.5) * env(n, 0.006, 0.09)
    foot = (lp(noise(0.1, 622), 600) + tone(120, 70, 0.1) * 0.6) * env(m, 0.002, 0.04)
    return mix(swish, at(foot, 0.09, d) * 0.5)


def perfect_dodge():
    """Slipping a blow at the last moment (the world slows): a thump like a
    heartbeat, a long sinking glassy tone and air drawn backwards."""
    d = 1.0
    n = int(d * SR)
    t = t_axis(d)
    beat = tone(75, 45, d) * env(n, 0.002, 0.12) * 0.9
    sink = tone(1760, 440, d) * env(n, 0.01, 0.55) * 0.3 * (0.8 + 0.2 * np.sin(2 * np.pi * 7 * t))
    glass = modal([(1320, 1.0, 0.85), (1980, 0.6, 0.65), (2640, 0.4, 0.5)], d) * env(n, 0.004, 0.9) * 0.18
    breath = svf_sweep(noise(d, 631), 2600, 900, 300, q=1.6) * env(n, 0.05, 0.5) * 0.5
    return mix(beat, sink, glass, breath)


def windup():
    """An enemy drawing breath to strike: air hissing in, climbing, and cut
    off by a tick, so the blow can be heard coming."""
    d = 0.4
    t = t_axis(d)
    ramp = np.clip(t / 0.3, 0, 1) ** 1.3 * np.exp(-np.clip(t - 0.3, 0, None) * 30.0)
    inhale = svf_sweep(noise(d, 641), 700, 2200, 3600, q=2.2) * ramp
    strain = tone(300, 620, d) * ramp * 0.12
    tick = at(hp(noise(0.03, 642), 2500) * env(int(0.03 * SR), 0.0004, 0.01) * 0.5, 0.31, d)
    return mix(inhale, strain, tick)


def lock_on():
    """A target caught: a crisp tick with a high ping."""
    d = 0.16
    n = int(d * SR)
    ping = tone(1500, 2100, d) * env(n, 0.001, 0.035) * 0.7
    tick = bp(noise(d, 651), 3000, 6500) * env(n, 0.0005, 0.008)
    ring = tone(3150, 3150, d) * env(n, 0.001, 0.09) * 0.2
    return mix(ping, tick, ring)


def lock_off():
    """A target let go: a duller, falling tick."""
    d = 0.12
    n = int(d * SR)
    return mix(tone(1300, 800, d) * env(n, 0.001, 0.03) * 0.7, bp(noise(d, 661), 2000, 4500) * env(n, 0.0005, 0.007) * 0.6)


def ult_ready():
    """The ultimate gauge full: two low heartbeats and a rising shimmer of
    fifths that blooms open."""
    d = 1.1
    n = int(d * SR)
    t = t_axis(d)
    thump = tone(80, 45, 0.3) * env(int(0.3 * SR), 0.002, 0.14)
    beat = mix(at(thump, 0.0, d), at(thump, 0.17, d) * 0.8) * 1.8
    rise = np.zeros(n)
    for k, base in enumerate((440.0, 659.3, 880.0, 1318.5)):
        rise += np.sin(2 * np.pi * np.cumsum(base * np.geomspace(0.8, 1.0, n)) / SR + k) * (0.65 ** k)
    swell = np.clip(t / 0.5, 0, 1) ** 2 * np.exp(-np.clip(t - 0.5, 0, None) * 3.2)
    air = svf_sweep(noise(d, 671), 800, 3000, 6000, q=2.0) * swell * 0.3
    return mix(beat * 0.9, rise * swell * 0.3, air)


# --------------------------------------------------------------------------
# Interface and progress
# --------------------------------------------------------------------------

def ui_tab():
    """Switching tabs: a small wooden block."""
    d = 0.09
    n = int(d * SR)
    return mix(tone(780, 700, d) * env(n, 0.0005, 0.02), tone(1560, 1400, d) * env(n, 0.0005, 0.014) * 0.4,
               bp(noise(d, 681), 1000, 3200) * env(n, 0.0004, 0.004) * 0.5)


def map_open():
    """A map scroll unrolled: a wooden rod knocking down, paper rustling
    open, the rod settling."""
    d = 0.9
    knock = tone(520, 380, 0.1) * env(int(0.1 * SR), 0.0005, 0.03) + hp(noise(0.1, 691), 1500) * env(int(0.1 * SR), 0.0003, 0.008) * 0.5
    paper = rustle(0.62, 692, 1700, 8000, 24.0) * env(int(0.62 * SR), 0.04, 0.3, 0.3)
    settle = tone(430, 330, 0.1) * env(int(0.1 * SR), 0.0005, 0.03) * 0.8
    return mix(at(knock, 0.0, d) * 0.8, at(paper, 0.04, d) * 0.9, at(settle, 0.66, d))


def hanko(seed: int) -> np.ndarray:
    """An ink stamp pressed down: a soft low thud and a paper pat."""
    d = 0.14
    n = int(d * SR)
    return mix(tone(135, 80, d) * env(n, 0.002, 0.06), lp(noise(d, seed), 900) * env(n, 0.001, 0.035) * 0.6)


def _notes(freqs, gap: float, d: float, seed: int, seconds: float, bright: float = 0.5, sustain: float = 0.996) -> np.ndarray:
    out = np.zeros(int(d * SR))
    for i, f in enumerate(freqs):
        out += at(pluck(f, seconds, seed + i, bright, sustain), i * gap, d) * (1.0 - 0.06 * i)
    return out


def quest_accept():
    """A request taken on: a stamp pressed, then a koto's two rising notes."""
    d = 1.1
    notes = _notes([440.0, 659.3], 0.13, d, 701, 0.9) * 0.9
    return mix(at(hanko(700), 0.0, d), at(notes, 0.05, d))


def quest_done():
    """A quest finished: a stamp, a koto flourish up an open chord and a
    soft gong settling beneath."""
    d = 2.0
    notes = _notes([587.3, 740.0, 880.0, 1174.7], 0.1, d, 711, 1.4, 0.45, 0.997)
    return mix(at(hanko(710), 0.0, d), at(notes, 0.05, d) * 0.9, at(gong(293.7, 1.8, 712) * 0.2, 0.3, d))


def level_up():
    """A level gained: a quick run up a pentatonic scale on the koto over a
    breath of rising air, ending in a glassy bell."""
    d = 1.6
    t = t_axis(d)
    run = _notes([587.3, 659.3, 784.0, 880.0, 1174.7], 0.075, d, 721, 1.2, 0.5, 0.997)
    bell = at(modal([(2349, 1.0, 1.1), (3520, 0.6, 0.9), (4700, 0.35, 0.6)], 1.2) * env(int(1.2 * SR), 0.003, 1.1) * 0.18, 0.3, d)
    swell = np.clip(t / 0.4, 0, 1) ** 2 * np.exp(-np.clip(t - 0.4, 0, None) * 4.0)
    air = svf_sweep(noise(d, 722), 900, 3500, 7000, q=2.0) * swell * 0.22
    return mix(run * 0.9, bell, air)


def skill_learn():
    """A skill learned: a brush stroke swept across paper and a bright ting
    on a struck string."""
    d = 0.7
    stroke = svf_sweep(noise(0.22, 731), 1800, 3800, 5600, q=1.8) * env(int(0.22 * SR), 0.03, 0.12) * 0.5
    ting = at(pluck(1318.5, 0.6, 732, 0.6, 0.996), 0.1, d) * 0.8
    glint = at(modal([(3520, 1.0, 0.5), (5280, 0.5, 0.35)], 0.5) * env(int(0.5 * SR), 0.002, 0.5) * 0.12, 0.1, d)
    return mix(at(stroke, 0.0, d), ting, glint)


def pickup():
    """Something gathered: a rustle and two small bright tinkles."""
    d = 0.4
    rustle_ = rustle(0.1, 741, 2000, 6500, 40.0) * env(int(0.1 * SR), 0.004, 0.06) * 0.6
    tink = at(modal([(2093, 1.0, 0.18), (3140, 0.4, 0.12)], 0.25) * env(int(0.25 * SR), 0.001, 0.2) * 0.4, 0.04, d)
    tink2 = at(modal([(2794, 1.0, 0.2), (4190, 0.4, 0.14)], 0.3) * env(int(0.3 * SR), 0.001, 0.22) * 0.4, 0.11, d)
    return mix(at(rustle_, 0.0, d), tink, tink2)


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
    "enemy_down": enemy_down, "weak_hit": weak_hit, "smoke": smoke, "teleport": teleport,
    "rain_loop": rain_loop, "wind_loop": wind_loop, "thunder": thunder, "eye_open": eye_open,
    # Swords
    "sword_draw": sword_draw, "sword_sheathe": sword_sheathe, "sword_snap": sword_snap,
    "blade_hit": blade_hit, "blade_clash": blade_clash, "guard_break": guard_break,
    # Footsteps
    "step_dirt": step_dirt, "step_grass": step_grass, "step_stone": step_stone,
    "step_sand": step_sand, "step_snow": step_snow, "step_water": step_water,
    # Movement and combat cues
    "charge_start": charge_start, "charge_end": charge_end, "dodge": dodge,
    "perfect_dodge": perfect_dodge, "windup": windup, "lock_on": lock_on, "lock_off": lock_off,
    "ult_ready": ult_ready,
    # Interface and progress
    "ui_tab": ui_tab, "map_open": map_open, "quest_accept": quest_accept, "quest_done": quest_done,
    "level_up": level_up, "skill_learn": skill_learn, "pickup": pickup,
}
# Loops must not be faded or DC-shifted at the seam.
LOOPS = {"charge_loop", "rain_loop", "wind_loop"}

# Sounds that come in several takes (the generator is called with the take's
# number): written as <name>_v1.wav ... and played by <name>, the game picking
# one at random each time.
VARIANTS = {
    "strike_hit": 3, "strike_whoosh": 3, "impact": 3, "kunai_hit": 3, "land": 2, "hit_player": 2,
    "guard": 2, "blade_hit": 3, "blade_clash": 3,
    "step_dirt": 3, "step_grass": 3, "step_stone": 3, "step_sand": 3, "step_snow": 3, "step_water": 3,
}

# How loud each sound is when played at 0 dB: the K-weighted loudness (dB) of
# its loudest 100 ms (see art/audio/measure_sfx.py). The mix, loudest first:
# explosions and thunder, then blows landing and spells, then movement and
# cues, then footsteps and the interface. Game code only ever turns sounds
# down (negative volume_db), so nothing is boosted into clipping.
LEVELS = {
    # Blasts and weather
    "explosion": -7.0, "thunder": -9.0, "eye_open": -10.0,
    # Blows landing
    "guard_break": -9.0, "impact": -10.0, "hit_player": -10.0, "blade_clash": -11.0, "blade_hit": -12.0,
    "strike_hit": -13.0, "weak_hit": -14.0, "guard": -14.0, "kunai_hit": -15.0, "enemy_down": -15.0,
    # Spells
    "cast_fire": -11.0, "cast_earth": -11.0, "cast_lightning": -11.0, "cast_water": -12.0, "cast_wind": -12.0,
    "cast_none": -13.0, "wall_rise": -12.0, "buff": -15.0, "heal": -15.0, "teleport": -12.0,
    "seal_break": -14.0, "misfire": -15.0, "weave_start": -18.0, "seal_1": -20.0, "seal_2": -20.0,
    "seal_3": -20.0, "smoke": -17.0,
    # Stingers
    "wave_start": -11.0, "victory": -12.0, "defeat": -12.0, "level_up": -12.0, "quest_done": -13.0,
    "ult_ready": -13.0, "perfect_dodge": -14.0, "quest_accept": -16.0,
    # Movement and combat cues
    "sword_draw": -16.0, "strike_whoosh": -20.0, "dash": -19.0, "chakra_jump": -19.0, "kunai_throw": -19.0,
    "land": -20.0, "windup": -20.0, "charge_start": -18.0, "charge_end": -22.0, "dodge": -22.0,
    "jump": -22.0, "sword_sheathe": -23.0, "sword_snap": -21.0, "pickup": -22.0, "skill_learn": -21.0,
    # Footsteps
    "step_dirt": -25.0, "step_grass": -27.0, "step_stone": -24.0, "step_sand": -27.0, "step_snow": -25.0,
    "step_water": -22.0,
    # Interface
    "ui_open": -23.0, "map_open": -23.0, "ui_select": -24.0, "ui_close": -25.0, "lock_on": -25.0,
    "ui_move": -26.0, "ui_back": -26.0, "ui_tab": -27.0, "lock_off": -28.0,
    # Loops
    "charge_loop": -20.0, "rain_loop": -24.0, "wind_loop": -21.0,
}


def file_names(name: str) -> list[str]:
    n = VARIANTS.get(name, 1)
    return [f"{name}.wav"] if n == 1 else [f"{name}_v{i + 1}.wav" for i in range(n)]


def render(name: str, take: int = 0) -> np.ndarray:
    """One finished sound (or one take of it), mastered to its level."""
    x = SOUNDS[name](take) if name in VARIANTS else SOUNDS[name]()
    if name in LOOPS:
        return master(x, LEVELS[name])
    return master(finish(x), LEVELS[name])


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--only", choices=sorted(SOUNDS))
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    missing = set(SOUNDS) - set(LEVELS)
    if missing:
        raise SystemExit(f"no level for {sorted(missing)}")
    for name in [args.only] if args.only else SOUNDS:
        for take, file in enumerate(file_names(name)):
            x = render(name, take)
            wavfile.write(args.out / file, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
            peak = 20 * np.log10(np.max(np.abs(x)) + 1e-9)
            print(f"{file:22s} {len(x) / SR:5.2f}s  LK {loudness_db(x):6.1f}  peak {peak:5.1f} dBFS")
        if VARIANTS.get(name):
            # A sound that gained takes no longer has a single file.
            (args.out / f"{name}.wav").unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
