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
| Dash (tap) / Sprint (hold) | Shift | L3 (click left stick) |
| Strike | Left mouse (or K) | X |
| Throw kunai | Q | RT |
| Guard (hold) | E | RB |
| Charge chakra (hold) | R | Y |
| Lock on | Tab or middle mouse | R3 |
| **Weave seals** | **Right mouse (or F)** | **LT** |
| Quick-cast slots 1–4 | 1 2 3 4 | D-pad ↑ → ↓ ← |
| Pause / settings / customize | Esc | Start |

## Menus

The game opens on the title screen: **Trial of the Five Natures**,
**Training Ground**, **Customize** and **Quit**. Move with the stick, D-pad,
arrow keys or mouse. Confirm with A or Enter; B or Esc backs out. From the
pause menu, **Title screen** leaves the current mode.

## Story dialogue

Confirm (**A**, **Enter**, **Space** or **left click**) finishes the line
being typed, then moves to the next. Hold it to fast-forward. The pause
menu still works during dialogue.

## Fighting enemies

- Health regenerates slowly (3 per second) once you've gone about 4 seconds
  without taking a hit. Chakra regenerates all the time, and much faster
  while you hold Charge.

- Enemies show their nature (kanji and name) and a health bar overhead.
  Hit them with the nature that beats theirs for 1.5× damage (**WEAK!**).
- **Seals above an enemy's head mean a jutsu is coming.** Hit it before the
  last seal to interrupt. A kunai is enough for a genin, a chunin needs a
  harder hit, and a jonin needs a jutsu or a strike combo.
- A red **!** means a strike is winding up. Guard (E / RB) or dash away.
- If your health hits zero the trial ends. Retry from the results screen.

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
| Master / Effects / Menu sounds volume | 0–100% each. 0 mutes that group. |
| Remapping | Rebind any action on either device. If a key is already in use, the two actions swap, so nothing is left bound twice by accident. |

Elements are never shown by colour alone. The HUD always prints the nature
name (Fire, Water, and so on).

## Customize screen

| Action | Keyboard + Mouse | Controller |
|---|---|---|
| Move between options | Arrow keys / Tab | D-pad or left stick |
| Choose | Enter / Space / click | A |
| Switch tab | click the tab | LB / RB |
| Rotate character | drag with the mouse | Right stick |
| Done | Esc | B or Start |
