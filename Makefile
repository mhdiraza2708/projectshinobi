# Common tasks. Override tool paths, e.g. `make test GODOT=~/bin/godot`.
GODOT ?= godot
# Any Python with `bpy` installed (pip install -r art/blender/requirements.txt, Python 3.11),
# or use: make assets BLENDER_RUN="blender --background --python"
BLENDER_RUN ?= python
SHOTS ?= screenshots

# Any Python with numpy and scipy (pip install -r art/audio/requirements.txt).
PYTHON ?= python3

.PHONY: run editor import test assets animations sfx screenshots

run:
	$(GODOT) --path game

editor:
	$(GODOT) --path game -e

import:
	$(GODOT) --headless --path game --import

test: import
	$(GODOT) --headless --path game res://tests/test_runner.tscn

assets:
	$(BLENDER_RUN) art/blender/build_assets.py
	$(MAKE) import

# Configure Mixamo FBX clips in game/assets/animations/mixamo/ for humanoid
# retargeting (see docs/CHARACTERS.md), then re-import them.
animations: import
	$(GODOT) --headless --path game --script res://tools/setup_mixamo.gd
	$(MAKE) import

# Regenerate the synthesised sound effects in game/assets/audio/sfx/.
sfx:
	$(PYTHON) art/audio/make_sfx.py
	$(MAKE) import

# Needs Xvfb when there is no display.
screenshots: import
	mkdir -p $(SHOTS)
	for demo in overview weave cast menu; do \
		xvfb-run -a -s "-screen 0 1280x720x24" $(GODOT) --path game \
			--rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy \
			-- --screenshot=$(abspath $(SHOTS))/$$demo.png --demo=$$demo; \
	done
