"""Lists every music and voice file in the "Audio" export preset.

    python art/audio/sync_audio_pack.py

Music and voices ship as audio_1.pck beside the game (like the character
packs), which keeps the executable small enough to send as one file. Godot
presets name their files one by one, so run this after adding or removing
tracks or voice lines. make_music.py and make_voices.py run it for you, and
the tests fail if the preset is out of date.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GAME = REPO_ROOT / "game"
PRESETS = GAME / "export_presets.cfg"
AUDIO_DIRS = ["assets/audio/music", "assets/audio/voice"]
PRESET_NAME = "Audio"


def audio_files() -> list[str]:
	out = []
	for d in AUDIO_DIRS:
		root = GAME / d
		if root.exists():
			out += [f"res://{p.relative_to(GAME).as_posix()}" for p in root.rglob("*.ogg")]
	return sorted(out)


def preset_block(index: int, files: list[str]) -> str:
	listed = ", ".join(f'"{f}"' for f in files)
	return f"""[preset.{index}]

name="{PRESET_NAME}"
platform="Windows Desktop"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="resources"
export_files=PackedStringArray({listed})
include_filter=""
exclude_filter=""
export_path="../build/packs/audio_1.pck"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.{index}.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
application/icon=""
application/file_version=""
application/product_version=""
application/company_name=""
application/product_name="Project Shinobi"
application/file_description="Project Shinobi"
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
application/d3d12_agility_sdk_multiarch=true
"""


def main() -> int:
	text = PRESETS.read_text()
	files = audio_files()
	# Split into [preset.N] + [preset.N.options] blocks.
	blocks = re.split(r"(?m)^(?=\[preset\.\d+\]$)", text)
	head, blocks = blocks[0], blocks[1:]
	index = None
	for i, block in enumerate(blocks):
		if re.search(rf'(?m)^name="{PRESET_NAME}"$', block):
			index = int(re.match(r"\[preset\.(\d+)\]", block).group(1))
			blocks[i] = preset_block(index, files) + ("\n" if i < len(blocks) - 1 else "")
	if index is None:
		index = len(blocks)
		if not blocks[-1].endswith("\n\n"):
			blocks[-1] = blocks[-1].rstrip("\n") + "\n\n"
		blocks.append(preset_block(index, files))
	PRESETS.write_text(head + "".join(blocks))
	print(f"{PRESET_NAME} preset: {len(files)} files")
	return 0


if __name__ == "__main__":
	sys.exit(main())
