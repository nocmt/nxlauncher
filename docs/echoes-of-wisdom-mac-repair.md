# Echoes of Wisdom Mac repair

Date: 2026-10-23

The startup faults and observed heart-HUD compositing error are fixed in a separate Mac export:

`game/塞尔达传说-智慧的再现/画面修复导出-最终/The Legend of Zelda Echoes of Wisdom.app`

The exports under `验证导出`, `修复导出` and `画面修复导出` are retained. The new app uses the same `Echoes of Wisdom` Application Support name for normal saves. Automated runs use fresh home, save, temp, cache and working directories and do not write the user's normal saves. Path isolation is not an operating-system security sandbox.

## Changes

- Shared fonts: upstream PR [#55](https://github.com/seedds/nxnative/pull/55), source commit `951d6ff`, forwards only exact host-owned BFTTF allocation bases as TTF payloads at `LoadFont`. The original SDK parses the font and returns its status; other pointers and all arguments retain their meaning.
- Mip ranges: bound a sampled texture view's count to the levels remaining after its base. The failing descriptor was texture 292, serial 36, a 64x64 six-layer array with seven mip levels, requesting base 1/count 7. Both NVN and Metal had seven levels; six remain after the base. Invalid bases produce a diagnostic and an empty binding. The invalid-base branch was not observed in this game path.
- Sampled texture channels: compose the NVN format's channel mapping with the texture builder or view's component selection. Guest selectors address NVN logical components, while Metal samples its storage components. ZERO/ONE remain constants, explicit view channels override builder channels, and a supported view format determines the format mapping. Unsupported view formats preserve the base format's mapping, matching the existing pixel-format fallback. The effective channels remain part of the view-cache key.
- Mac exports now copy the existing `cb_extent.tsv` alongside the other shader tables. No shader translation code, generated MSL, shader metadata or metallib was changed.

The user confirmed normal Mac packaging and gameplay on 2026-10-23. The currently retained playable app is `game/塞尔达传说-智慧的再现/The Legend of Zelda Echoes of Wisdom.app`; earlier export-directory paths below are historical build records.

The font fix from PR #55 was landed by the maintainer as `1765d53`. Graphics repairs 0009 and 0010 are submitted together in [PR #66](https://github.com/seedds/nxnative/pull/66), commit `e31597e92ed742c3ee983b7b65c0dd74f4597a1e`, rebased onto upstream `8a4b1dc82073f9d8635bd51d634af681f5d71ee1`. The PR contains four source/test files only (127 additions, five deletions), with no launcher patches or game content. Both Metal regressions pass on this final baseline (34 and 156 checks), and the Echoes host builds. The final PR host also completed a 110-second isolated input run (`echoes-run-20261023-094806-236618`); frame 6000 confirms normal hearts, scene and prompts after movement. The timeout intentionally ended the run. The local launcher's pinned baseline and packaged artifacts were not upgraded as part of publishing this PR. Repair sources remain at `nxnative-echoes-fix-20261022`; the clean contribution worktree is `nxnative-echoes-pr-20261023`.

## Heart-HUD cause

The earlier interpretation of diagnostic format `40` as RGBA8 sRGB was incorrect: the dump reports decimal Metal pixel-format values. The heart mask uses NVN RGB565 mapped to Metal `B5G6R5Unorm` (40); the other sampled textures use ASTC 4x4 sRGB (186) and RG8Unorm (30).

Twenty six-index heart draws use vertex key `e9c270089a0e0b9a_b` and fragment key `72832d3b4c25cdf6_b`. In the observed branch the shader's coverage depends on the mask's red and green channels. The mask contains `0xf800` around the heart and `0x001f` in its center. The format table already specifies an R/B exchange for RGB565, but sampled view creation previously discarded that mapping. The reversed mask produced the red rectangular surroundings and dark heart centers. Standard source-alpha blending was present; forcing alpha to one did not address the active shader branch.

The correction is general texture-format handling, with no game-specific shader override. Independent implementation references support the packed-channel interpretation:

- [deko3d packed format traits](https://github.com/devkitPro/deko3d/blob/master/source/maxwell/format_traits.inc#L51)
- [Mesa format definitions](https://github.com/chaotic-cx/mesa-mirror/blob/main/src/util/format/u_format.yaml#L281)
- [ANGLE Metal format table](https://github.com/google/angle/blob/main/src/libANGLE/renderer/metal/mtl_format_table_autogen.mm#L242)

These are implementation evidence, not an authoritative NVN specification. The mip-count correction is independently consistent with [deko3d's descriptor maximum clipping](https://github.com/devkitPro/deko3d/blob/master/source/maxwell/tic_generate.cpp#L160).

## Verification

- Actual Metal sampling through production `tex_by_id`: 156 checks, zero failures with `MTL_DEBUG_LAYER=1`. Coverage includes RGB565/BGR565, composition, constants, builder/view precedence, RGBX alpha, format overrides in both directions, RG8/RGBA8 preservation, and unsupported-view-format fallback. Initial packed-format tests reproduced 12 failures before composition; fallback tests separately reproduced six failures before the fallback correction.
- Production mip-range regression: 34 checks, zero failures after the final swizzle correction, including invalid bases, last mip, default count, array layers and cache reuse.
- Complete nine-patch preparation check passes against upstream `677345b0933f`, with the real dependency index unchanged. All 57 launcher Python tests pass, including 12 preparation tests.
- A 110-second input run after channel composition shows twenty correctly rendered red hearts without rectangular backgrounds at frames 3000 and 6000. Movement to the stair obstacle, sword interaction, scene rendering and action prompts were observed. Run: `echoes-run-20261023-001602-358096`.
- The first graphics export passed deep strict ad-hoc signature verification and a 70-second native-window run using its own resources: `echoes-run-20261023-002051-981463`.
- The final export includes the unsupported-format fallback correction and passes deep strict local ad-hoc signature verification. Its actual `BotW` launcher, invoked without arguments in a fresh HOME, remained alive for 110 seconds (`echoes-launcher-final-20261023-082919`). No original font error was found. Window display-link stalls limited this run to about frame 1200, so it did not reach the scheduled HUD captures and is not a smooth-performance claim.
- A second 110-second input run uses the final export's own host and resources without a native window: `echoes-run-20261023-083141-768345`. Local inspection of frames 3000 and 6000 confirms twenty red hearts without rectangular backgrounds, intact scene/action prompts, and movement to the stair obstacle. It deliberately ends at the external timeout. This validates final-binary rendering separately from window presentation performance.
- The rebuilt launcher archive was checked byte-for-byte against the current font source, renderer, both Metal tests, graphics test Makefile and Mac export script. The release Swift build and deep strict local signature verification pass.

External timeouts deliberately terminate bounded runs with SIGKILL; exit code -9 with `timed_out: true` is not classified as a game crash. Historical startup/font/mip runs from 2026-10-22 remain under the game's diagnostics directory; those results do not independently validate the later graphics binary.

## Delivered artifacts

The default launcher is `dist/NxLauncher.app`; its previous build is retained as `dist/NxLauncher-before-graphics-20261023.app`. The standalone `dist/nxlauncher-home.tgz` matches the embedded archive. SHA-256 after local signing:

| Artifact | SHA-256 |
|---|---|
| Final game `Contents/MacOS/dmhost` | `6ddd8bf6400f0281302d64e721288bf84ceed234f3d6cb59d17b41a418b91972` |
| Final game `Contents/MacOS/BotW` | `1e300bb8de4e2bc3c1a860c7320fcfc5bc10bdb6c02ae1b087d5fb610f054338` |
| Launcher embedded tools archive | `4dab07340c005506e1713cb8b2bc8796e6f5cedba84f5eeacc26d39f3b9dcb07` |

## Remaining limitations

No whole-game completion or long-term stability claim is made. Later scenes, transitions, save round-trips and other games have not been exhaustively tested. Existing mappings for other packed formats such as RGB5/RGB5A1 are now used by the sampled-view path but are not covered by the RGB565-specific evidence. Existing renderer/compiler warnings remain. No iOS device execution, signing or installation was performed for this graphics delivery. Game assets, keys, fonts and raw diagnostic data remain local and are excluded from the source patch.
