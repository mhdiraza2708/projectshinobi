# Controls

Every action is playable on **keyboard + mouse** and on **controller**, and
every binding can be changed in-game (Pause → Controls). A unit test
(`game/tests/unit/test_bindings.gd`) fails the build if any action ships
without both a keyboard/mouse and a gamepad binding.

Controller names below are Xbox. The game detects PlayStation and Nintendo
pads and shows their labels (Cross/Circle/Square/Triangle, L1/R1/L2/R2, and so on)
automatically. Prompts switch the moment you touch the other device.

## In the field

| Action | Keyboard + Mouse | Controller |
|---|---|---|
| Move | W A S D | Left stick |
| Camera | Mouse (or arrow keys) | Right stick |
| Jump / chakra jump (in air) | Space | A |
| Dash (tap) / Sprint (hold) | Shift | B |
| Strike | Left mouse (or K) | X |
| Throw kunai | Q | RT |
| Guard (hold) | E | RB |
| Charge chakra (hold) | R | Y |
| Lock on | Tab or middle mouse | R3 |
| **Weave seals** | **Right mouse (or F)** | **LT** |
| Quick-cast slots 1–4 | 1 2 3 4 | D-pad ↑ → ↓ ← |
| Pause / settings | Esc | Start |

## Weaving hand seals

Hold **Weave** (right mouse / LT), enter seals, release to cast. You stand
still while weaving, so the movement and face buttons are free to become
seal inputs.

A seal is a **direction** plus an optional **bank** modifier:

| | Bottom | Right | Left | Top |
|---|---|---|---|---|
| **Bank I** (no modifier) | Rat | Ox | Tiger | Hare |
| **Bank II** (hold Shift / LB) | Dragon | Snake | Horse | Ram |
| **Bank III** (hold Space / RB) | Monkey | Bird | Dog | Boar |

| Direction | Keyboard | Controller |
|---|---|---|
| Bottom | S | A or D-pad ↓ |
| Right | D | B or D-pad → |
| Left | A | X or D-pad ← |
| Top | W | Y or D-pad ↑ |

The keyboard directions are laid out like the controller's face-button
diamond, so a sequence you learn on one device is the same shape on the
other. Example: **Ember Volley** is Tiger → Ox, which is *left, right* on both
devices.

The D-pad copies the face buttons, so a controller player can do the whole
weave with the left hand (LT + D-pad + LB).

If more than about a second passes between seals, the sequence breaks. You
keep weaving and can start the sequence again without letting go.

## Accessibility options (Pause → Accessibility)

| Option | What it does |
|---|---|
| Weave mode: Hold / Toggle | Toggle mode: press Weave once to start and again to cast. Nothing needs to be held. |
| Seal timing window | Widens the allowed gap between seals, or turns the time limit off. |
| Seal hints | While weaving, shows which jutsu your sequence can still become and the next input for each. |
| Quick-cast slots | Cast any slotted jutsu with one button. The character weaves the seals automatically, a bit slower than a fast manual weave. |
| Quick-cast weave speed | How fast the automatic weave runs. |
| Mouse / stick sensitivity, invert Y, stick deadzone | Camera and stick tuning. |
| Vibration | Controller rumble on/off. |
| Screen shake | 0–100%. |
| UI scale | Makes every menu and HUD element bigger or smaller. |
| Remapping | Rebind any action on either device. If a key is already in use, the two actions swap, so nothing is left bound twice by accident. |

Elements are never shown by colour alone. The HUD always prints the nature
name (Fire, Water, and so on).
