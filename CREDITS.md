# Credits and third-party licences

| Asset | Author | Licence | Where |
|---|---|---|---|
| **Godette** placeholder character (VRM) | Original model © SirRichard94 ([low-poly-godette](https://github.com/SirRichard94/low-poly-godette)); VRM adaptation © 2021 Lyuma | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | `game/assets/characters/default/godette.vrm` |
| **VRoid Studio sample characters**: Sendagaya Shino, Sendagaya Shibu, Darkness Shibu, Sakurada Fumiriya, Victoria Rubin, Vita, Vivi, HairSample Male and HairSample Female | pixiv Inc. (VRoid Studio beta sample models, via [madjin/vrm-samples](https://github.com/madjin/vrm-samples)) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/): stated in each file's VRM metadata (checked by `tests/unit/test_wardrobe.gd`) and on [pixiv's VRoid help page](https://vroid.pixiv.help/hc/en-us/articles/4402614652569) | `game/assets/characters/roster/` (textures reduced to 1024 px by `art/characters/prepare_vrm.py`) |
| **godot-vrm** importer | V-Sekai contributors, VRM Consortium | MIT | `game/addons/vrm` (licence file inside) |
| **Godot-MToon-Shader** | V-Sekai contributors; original MToon © Masataka SUMI | MIT | `game/addons/Godot-MToon-Shader` (licence file inside) |
| **Shojumaru** font | Brian J. Bonislawsky (Astigmatic) | SIL OFL 1.1 (unmodified; Reserved Font Name "Shojumaru") | `game/assets/fonts/Shojumaru-Regular.ttf` |
| **Yuji Syuku** font (subset to the kanji the UI uses) | The Yuji Project Authors | SIL OFL 1.1 | `game/assets/fonts/YujiSyuku-Subset.ttf` |
| **Zen Kaku Gothic New** font (subset to Latin and UI kanji) | The Zen Kaku Gothic Project Authors | SIL OFL 1.1 | `game/assets/fonts/ZenKakuGothicNew-*-Subset.ttf` |
| **Godot Engine** | Godot contributors | MIT | not bundled |

Full font licence texts are in `game/assets/fonts/OFL-*.txt`. The subsets
are rebuilt by `art/fonts/subset_fonts.py`. Everything else
in this repository (code, shaders, jutsu data, generated environment models,
synthesised sound effects and test fixtures) is original to this project.
