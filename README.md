# Project Shinobi

A third-person shinobi action game built around **weaving hand seals to cast
jutsu**. It is fully playable on **keyboard + mouse and controller**, and all
controls can be remapped.

> **Scope and IP, honestly:** this is an *original* shinobi setting inspired
> by the genre, not a Naruto game. Naruto's names, characters and techniques
> are licensed IP, and fan games using them get taken down. It targets
> polished indie/AA quality, not "AAA" (a budget no small team has). See
> [docs/DESIGN.md](docs/DESIGN.md) for the reasoning.

## Status

**M0 Foundation is done:**

- Input layer with keyboard/mouse and gamepad bindings for every action,
  physical-key bindings, remapping with conflict swapping, saved settings,
  device detection for button prompts (Xbox, PlayStation and Nintendo), and
  gamepad-navigable menus.
- A 12-seal weaving system with an adjustable (or disabled) timing window.
- Data-driven jutsu: 16 original techniques across 5 elements plus neutral,
  in 5 forms (projectile, area, wall, buff, heal), with strict validation.
- Headless test suite.

**M1 Training ground is in progress:** the playable slice (see the roadmap in
the design doc).

## Docs
- [docs/DESIGN.md](docs/DESIGN.md): scope, IP, pillars, systems, roadmap
- [docs/CONTROLS.md](docs/CONTROLS.md): full control scheme, seal chart, accessibility options

## Requirements
- [Godot 4.7](https://godotengine.org/download) (standard build, not .NET)
- Optional, to regenerate models: Blender 4.5 LTS, or `pip install bpy==4.5.14` on Python 3.11

## Running

```sh
# open in the editor
godot --path game -e

# run the test suite headless (exit code 1 on failure)
godot --headless --path game --import
godot --headless --path game res://tests/test_runner.tscn
```

## Layout

```
game/                 Godot project
  autoload/           Settings, InputDevice, JutsuRegistry singletons
  data/jutsu/         Jutsu definitions (JSON, one file per element)
  scripts/input/      Bindings table + binding (de)serialisation
  scripts/jutsu/      Seals, elements, weaver, definitions
  tests/              Headless test runner + unit tests
docs/                 Design + controls
```
