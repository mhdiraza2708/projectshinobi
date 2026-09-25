"""Rebuilds the trimmed UI fonts in game/assets/fonts/ from the full fonts.

    python art/fonts/subset_fonts.py [--src DIR]

The Japanese fonts are ~8 MB each, but the UI only draws a few dozen kanji,
so the game ships subsets. This scans every script and data file for the
characters the game actually draws and keeps exactly those (plus Latin and
anything the current subsets already had). Re-run it whenever you add new
kanji or symbols; tests/unit/test_ui.gd fails if a character is missing.

--src is a folder with the full fonts. Without it they are downloaded from
the google/fonts repository (all SIL OFL 1.1).
Needs fonttools (pip install fonttools).
"""

from __future__ import annotations

import argparse
import tempfile
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

REPO_ROOT = Path(__file__).resolve().parents[2]
GAME = REPO_ROOT / "game"
OUT = GAME / "assets" / "fonts"
GOOGLE_FONTS = "https://raw.githubusercontent.com/google/fonts/main/ofl/"

# (full font file, where to get it, subset written, keep non-CJK symbols?)
FONTS = [
    ("YujiSyuku-Regular.ttf", "yujisyuku/", "YujiSyuku-Subset.ttf", False),
    ("ZenKakuGothicNew-Medium.ttf", "zenkakugothicnew/", "ZenKakuGothicNew-Medium-Subset.ttf", True),
    ("ZenKakuGothicNew-Bold.ttf", "zenkakugothicnew/", "ZenKakuGothicNew-Bold-Subset.ttf", True),
]
SCANNED = ["**/*.gd", "data/**/*.json"]


def is_cjk(cp: int) -> bool:
    return 0x3000 <= cp <= 0x9FFF or 0xF900 <= cp <= 0xFAFF or 0xFF00 <= cp <= 0xFFEF


def used_codepoints() -> set[int]:
    found: set[int] = set()
    for pattern in SCANNED:
        for path in GAME.glob(pattern):
            if "addons" in path.parts or ".godot" in path.parts:
                continue
            found.update(ord(c) for c in path.read_text(encoding="utf-8") if ord(c) > 0x7E)
    return found


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, help="folder holding the full fonts")
    args = ap.parse_args()

    used = used_codepoints()
    basic = set(range(0x20, 0x7F))
    src = args.src or Path(tempfile.mkdtemp(prefix="fonts-"))
    for full_name, remote_dir, subset_name, symbols in FONTS:
        full = src / full_name
        if not full.exists():
            print(f"downloading {full_name}")
            urllib.request.urlretrieve(GOOGLE_FONTS + remote_dir + full_name, full)
        wanted = basic | {cp for cp in used if symbols or is_cjk(cp)}
        if symbols:
            wanted |= set(range(0xA0, 0x100))  # Latin-1: accented names
        target = OUT / subset_name
        if target.exists():
            wanted |= set(TTFont(target).getBestCmap())
        available = set(TTFont(full).getBestCmap())
        missing = sorted(cp for cp in wanted - available if cp > 0x7E)
        if missing and not symbols:
            print(f"  {full_name} lacks: {''.join(map(chr, missing))}")

        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        font = subset.load_font(str(full), opts)
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=sorted(wanted & available))
        sub.subset(font)
        subset.save_font(font, str(target), opts)
        print(f"{subset_name}: {len(wanted & available)} characters, {target.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
