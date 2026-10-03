# Credits and third-party licences

| Asset | Author | Licence | Where |
|---|---|---|---|
| **Godette** placeholder character (VRM) | Original model © SirRichard94 ([low-poly-godette](https://github.com/SirRichard94/low-poly-godette)); VRM adaptation © 2021 Lyuma | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | `game/assets/characters/default/godette.vrm` |
| **VRoid Studio sample characters**: Sendagaya Shino, Sendagaya Shibu, Darkness Shibu, Sakurada Fumiriya, Victoria Rubin, Vita, Vivi, HairSample Male and HairSample Female | pixiv Inc. (VRoid Studio beta sample models, via [madjin/vrm-samples](https://github.com/madjin/vrm-samples)) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/): stated in each file's VRM metadata (checked by `tests/unit/test_wardrobe.gd`) and on [pixiv's VRoid help page](https://vroid.pixiv.help/hc/en-us/articles/4402614652569) | `game/assets/characters/roster/` (textures reduced to 1024 px by `art/characters/prepare_vrm.py`) |
| **Universal Animation Library** (Standard, the free edition: idle, walk, jog, sprint, jumps, punches, spell cast, hit reactions, death, talking idle) | Quaternius ([quaternius.com](https://quaternius.com/packs/universalanimationlibrary.html)), glTF copy via [J-Ponzo/gltf-universal-animation-library](https://github.com/J-Ponzo/gltf-universal-animation-library) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (licence file inside) | `game/assets/animations/ual/`, retargeted by `game/tools/setup_ual.gd` |
| **Sky photographs** (pure-sky HDRIs): Kloofendal 48d Partly Cloudy, Kloppenheim 06, Table Mountain 1 and Kloppenheim 02 (Greg Zaal, Jarod Guest); Overcast Soil and Snow Field (Jarod Guest, Sergej Majboroda) | [Poly Haven](https://polyhaven.com/hdris) | [CC0 1.0](https://polyhaven.com/license) | `game/assets/skies/` (tone-scaled to 8-bit panoramas by `art/polyhaven/fetch.py`; light levels and sun positions in `game/data/skies.json`) |
| **Scanned ground textures**: Forest Ground 01, Coast Sand 01, Snow 02 (Rob Tuytel); Forest Ground 04 (Rob Tuytel, Rico Cilliers); Rock Face 03 (Dario Barresi, Rico Cilliers) | [Poly Haven](https://polyhaven.com/textures) | [CC0 1.0](https://polyhaven.com/license) | `game/assets/textures/ground/` (ambient occlusion folded into the colour, height packed into the normal map, by `art/polyhaven/fetch.py`) |
| **godot-vrm** importer | V-Sekai contributors, VRM Consortium | MIT | `game/addons/vrm` (licence file inside) |
| **Godot-MToon-Shader** | V-Sekai contributors; original MToon © Masataka SUMI | MIT | `game/addons/Godot-MToon-Shader` (licence file inside) |
| **Shojumaru** font | Brian J. Bonislawsky (Astigmatic) | SIL OFL 1.1 (unmodified; Reserved Font Name "Shojumaru") | `game/assets/fonts/Shojumaru-Regular.ttf` |
| **Yuji Syuku** font (subset to the kanji the UI uses) | The Yuji Project Authors | SIL OFL 1.1 | `game/assets/fonts/YujiSyuku-Subset.ttf` |
| **Zen Kaku Gothic New** font (subset to Latin and UI kanji) | The Zen Kaku Gothic Project Authors | SIL OFL 1.1 | `game/assets/fonts/ZenKakuGothicNew-*-Subset.ttf` |
| **FluidR3 GM SoundFont** (instrument samples the music is rendered with; the soundfont itself isn't bundled) | Frank Wen and contributors | MIT | used by `art/audio/make_music.py` |
| **Voice lines** (synthesised with the **Kokoro-82M** text-to-speech model and its voices, run through [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx), with espeak-ng for pronunciation) | [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) by hexgrad; kokoro-onnx by thewh1teagle; [espeak-ng](https://github.com/espeak-ng/espeak-ng) (used as a tool, not shipped) | Kokoro-82M: Apache 2.0; kokoro-onnx: MIT. The recordings were post-processed (level, and an effect for the Nue) | `game/assets/audio/voice/`, made by `art/audio/make_voices.py` |
| **Godot Engine** | Godot contributors | MIT | not bundled |

Full font licence texts are in `game/assets/fonts/OFL-*.txt`. The subsets
are rebuilt by `art/fonts/subset_fonts.py`. Everything else
in this repository (code, shaders, jutsu data, generated environment models,
synthesised sound effects, the music's compositions, the procedurally
generated effect textures and test fixtures) is original to this project.
