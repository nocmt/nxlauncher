# NxLauncher patch inventory

## Upgrade review (2026-10-28)

Official default branch `seedds/nxnative:main` was queried online and fetched on 2026-10-28. The reviewed SHA is **`201dfd1280684e9d3ceac8b644236fdac11b6cc2`** (`Host tests regenerate the game profile header instead of keeping a stale one`). `base-commit` and actual submodule HEAD name it. The parent gitlink is staged separately by the coordinating owner; this review did not stage or commit the parent. The complete patched tree is **`a3814a41de5781b208525f25b6facabcf8cd423f`**.

`series` lists five patches in order:

| Patch | Retained behavior |
|---|---|
| 0001 Mac input/window/controller options | Mouse look/as-A, window size/corners, FPS/input diagnostics, shared Mac/iOS controller glyph mapping. Keeps upstream focus ownership and resume behavior. |
| 0002 Checked memory overrides | Strict `DM_MEM_RESERVE`, `DM_MEM_POOL`, `DM_MEM_ALIAS` and checked layout; preserves upstream once-init, heap locking, mapping ownership and failure semantics. `DM_ALIAS_SIZE` remains a checked diagnostic expansion; combining it with `DM_MEM_ALIAS` is rejected. |
| 0003 Language/touch diagnostics | Explicit `DM_LANG` wins; supported Mac tags preserve Simplified/Traditional script and regional variants. Touch polling remains synchronized. |
| 0004 Font source/iOS policy | Compatible `make_ext_font.py OUT.ttf SOURCE.ttf`, plus `--base-font PATH --no-system-font`. iOS uses the launcher's redistributable font helper. |
| 0005 Static build boundary/Mac fonts | `--no-runtime-capture` sets `NX_NO_RUNTIME_CAPTURE=1`; shared boot, Oodle/LZ5 worker and host preload boundaries reject guest execution with `NX_RUNTIME_CAPTURE_REQUIRED`. Complete cached runtime inputs can be reused. Mac font preparation uses the same helper. |

Both native Mac and iOS builds accept an absolute `NXLAUNCHER_FONT_HELPER`, otherwise use the parent launcher's `Scripts/font-policy.py`. CLI: `python3 HELPER --repo NXNATIVE --out FONT_DIRECTORY`; JSON must name actual `standard.ttf`, `nintendo_ext.ttf` and `redistributable: true`. Standalone builds must supply this helper. Legacy generator system-font fallback remains for direct upstream callers without `--no-system-font`; launcher exports use verified open fonts.

Upstream already has `--platform ios|mac|mac-app`, separate GL/Vulkan translators, Mac packaging in `dm/mac/pack_app.py`, and iOS script `dm/ios/tools/build_ipa.sh`. Its only existing skip option, `--no-heap-check`, did not cover region checks, captures or guest decoder execution. The new static option covers these paths. Offline PSO compilation returns from the host's tool-only entry before guest loading and remains allowed. Missing runtime data reports `NX_RUNTIME_CAPTURE_REQUIRED` and requires explicit user authorization for a later guest run.

### Dropped upstream duplicates

Heap PR [#127](https://github.com/seedds/nxnative/pull/127) was incorporated as `9ba44da`, including the maintainer's corrected fatal-path regression. Focus PR [#128](https://github.com/seedds/nxnative/pull/128) was incorporated as `787523f`: it releases only frontend-owned input, preserves scripted holds and resumes when the window becomes key. Local duplicate heap handling, blanket focus reset and `NSApp.isActive` gate are dropped. Added mouse-look/button state joins upstream release handling. Shared-font payload repair `1765d53`, Metal mip/channel fixes `a08bbdd` (PR #66), mouse routing, menus, fullscreen/backing scale, controller bridge and JSON progress remain upstream implementations.

Old `6034fca` monolithic patch: `archive/6034fca-before-20261028/`. Older archived series are historical and never applied.

### Verification and limits

All 12 dirty/untracked source files were archived and reread byte-for-byte in local `patches/.pre-upgrade-source-20261028.tgz`, plus `.pre-upgrade-diff`, before replacement. Full external snapshot: a timestamped sibling source-snapshot directory outside this repository. Hidden backups are local preservation material, not release inputs. No game build folder or ignored generated artifact was cleaned or replaced.

A fresh temporary Git index loaded the exact official SHA and replayed all five patches with `--whitespace=error-all`. The tree matched the isolated tested tree and actual final source bytes. The submodule index remains official. Actual `Tools/prepare-nxnative.py --check` verified five patches and the full tree.

Commands (NX is the isolated patched root):

```bash
python3.14 Tools/prepare-nxnative.py --check
make -C "$NX/dm/host/tests" GAME=01007EF00011E000 run
make -C "$NX/dm/host" GAME=01007EF00011E000 -j8
python3.14 -m unittest discover -s "$NX/dm/tools/tests" -p 'test_nsp*.py'
python3.14 -m unittest discover -s "$NX/dm/tools/tests" -p test_no_runtime_capture.py
make -C "$NX/dm/gfx/tests" GAME=01007EF00011E000 -j6 t_view_levels t_view_swizzle t_vk_desc t_tex_layout t_pace t_present_crop t_timestamp t_fstep t_hmap t_cover
```

- Full host component run passed, including upstream heap/memory/notification scheduler and local mapping/memory/language regressions. Final script-priority language refinement was rerun and passed.
- Mac host compilation passed with 51 existing warnings, primarily Metal encoder interfaces.
- 144 upstream NSP Python tests passed under Python 3.14, including after Mac font helper integration. Seven added execution-boundary tests passed with mocked process launches. System Python 3.9 failed four assertions and one setup due to upstream's >=3.12 requirement; it is unsupported.
- All ten listed standalone graphics binaries executed with `MTL_DEBUG_LAYER=1` and passed, including mip ranges (34 checks), sampled channels (156), Vulkan descriptors, texture layout, pacing, crop, timestamp, frame step, hash map and coverage. Full graphics run was not executed.
- iOS `DmGamepad.m` passed arm64-apple-ios18.0 syntax with ARC, `-Wall -Werror`; iOS shell passed `bash -n`. No full iOS app/device build.
- Real font helper generated both TTF files from OFL Noto and returned `redistributable: true`, using existing NxLauncher `py-libs` for fontTools (plain interpreters lacked it).
- No guest boot/probe, runtime shader capture, guest decoder, physical-controller test or game/device validation was executed.

## Prior release 0.1.1 (2026-10-26; historical)

The prior checkout was `6034fcad89814786aa6dccacca371d975a54db40`, with monolithic patch target tree `214b5ab5eabcf9981f57ba5d586ff3d05a3d41a3`. The following describes that older release, not the current patch order.

The patch preserves all current intended local source changes, including the five untracked headers/tests: Mac window/mouse options and focus reset; shared Mac/iOS controller glyph mapping; strict guest-memory overrides; touch/operation-mode diagnostics; Mac preferred-language fallback and matching region selection; and their build rules and regressions. It changes exactly these 12 files:

- `dm/host/Makefile`, `dm/host/front_mac.m`, `dm/host/hle_hid.c`, `dm/host/hle_oe.c`, `dm/host/hle_svc.c`
- `dm/host/dm_mem_config.h`, `dm/host/dm_padmap.h`
- `dm/host/tests/Makefile`, `dm/host/tests/t_language.c`, `dm/host/tests/t_mem_config.c`, `dm/host/tests/t_padmap.c`
- `dm/ios/Sources/DmGamepad.m`

The old font repair is already upstream as `1765d53`; the mip-range/channel-composition repairs are upstream as `a08bbdd` (PR #66), including the view regressions. They must not be reapplied from the older series. The complete former nine-patch series, its baseline, order and inventory are preserved byte-for-byte in `archive/677345b-series-before-0.1.1/`. That directory is historical and is never applied.

Preparation still requires the exact upstream HEAD, unchanged upstream index and exact complete patched source bytes. It never accepts a partially patched or otherwise edited dependency. To check without modifying local source:

```bash
python3 Tools/prepare-nxnative.py --check
```

The archive builder always regenerates its payload. It uses `--check --export <new-directory>` to export the **verified Git tree**, checks the exported bytes/modes, and removes the known generated paths only in staging. Unlike recursively copying the dirty checkout, this excludes ignored host/test binaries, `.dSYM` bundles, Xcode projects, Python bytecode and generated per-game tables. The working checkout and all its local/generated files remain untouched. Missing generated profile/tables must be produced by the upstream build flow, not shipped from a developer's old build.

Both packaging scripts fail closed and stage on the output filesystem. Archive publication uses atomic file replacement. App publication uses macOS `renamex_np(RENAME_SWAP)` when replacing a nonempty existing app, after archive, plist and ad-hoc signing/verification succeed. An adjacent build lock prevents simultaneous writers; after an uncatchable termination, inspect and remove a stale `.build-lock` directory before retrying.

Final app/archive packaging for 0.1.1 is intentionally deferred until the export/tool changes finish. The historical runtime/build results below are not new release validation claims.

## Historical inventory (677345b baseline)

The dependency is pinned to upstream [`677345b0933f5f8754aeec3125d14df32683ca97`](https://github.com/seedds/nxnative/commit/677345b0933f5f8754aeec3125d14df32683ca97), fetched on 2026-10-22. `base-commit` is authoritative; `series` lists nine patches in application order: the six launcher patches plus temporary font, Metal mip-range and sampled-channel repairs. The submodule points to upstream, while the applied changes remain in its working tree.

## Why these patches remain local

| Patch | Purpose | Upstream treatment |
|---|---|---|
| 0002 Mac window/mouse options | Mouse look, mouse-as-A, window size, rounded corners, FPS and diagnostics | Local product behavior; preserves upstream menu, Command shortcuts/key-up handling, fullscreen, display scale and centered 16:9 touch mapping |
| 0003 Controller mapping | Preserve existing Nintendo/Xbox glyph mapping and optional `DM_PADMAP` override on Mac/iOS | Local preference; upstream intentionally maps by position. Uses upstream bridge, not a duplicate |
| 0004 Memory overrides | Preserve `DM_MEM_RESERVE`, `DM_MEM_POOL`, `DM_MEM_ALIAS` for existing launcher options, with parser/layout checks | Local pending broader evidence and profile discussion; defaults unchanged |
| 0005 Touch diagnostics | Restore polling/operation-mode logs used to diagnose mouse/touch behavior | Local diagnostics; retains upstream touch points and mode filtering |
| 0006 Mac language fallback | Follow Mac preferred language when `DM_LANG` is absent, retaining legacy Chinese/English fallback | Local because only two fallback outcomes are supported; iOS keeps upstream `DMLanguage` semantics |
| 0007 Touch diagnostic synchronization | Keep polling diagnostics race-free under concurrent guest reads | Local correction to 0005 |
| 0008 Shared-font payload | Forward only exact host-owned BFTTF allocation bases as TTF payloads to the SDK's `LoadFont`; preserve arguments and errors | Temporary carry of `951d6ff918dfd68dbdcb76dac6e2eaf0a191eb45`; [PR #55](https://github.com/seedds/nxnative/pull/55) was landed separately by the maintainer as `1765d53`. Still needed on this older pinned baseline |
| 0009 Metal mip ranges | Reject an out-of-range base mip and clip the requested count to the remaining levels; include the production Metal regression | Temporary local repair; submitted with 0010 in [PR #66](https://github.com/seedds/nxnative/pull/66) against upstream `8a4b1dc` |
| 0010 Sampled texture channels | Compose format and descriptor mappings, preserving view precedence, constants and unsupported-format fallback; verify actual GPU reads | General renderer correction; submitted with 0009 in [PR #66](https://github.com/seedds/nxnative/pull/66), commit `e31597e`; retained locally until a future baseline includes it |

Patch 0008 carries only the font implementation and regression from the source commit, rebasing its test Makefile additions onto the six existing patches. Patch 0009 carries exactly `dm/gfx/nvn/nvn_mtl.m`, `dm/gfx/tests/Makefile`, and `dm/gfx/tests/t_view_levels.m` from the verified repair source. Patch 0010 changes the sampled-channel composition in `nvn_mtl.m`, adds `t_view_swizzle.m`, and registers it in the graphics test Makefile. These patches include no game profiles, game files, fonts, generated assets or test binaries.

The former 0001 Mac mouse-routing patch was dropped because upstream adaptation [`b302d4008351c73bde47113423500633fe7dd401`](https://github.com/seedds/nxnative/commit/b302d4008351c73bde47113423500633fe7dd401) supplies content-view mouse routing, the main menu, Command shortcuts and key-up handling, and centered/clamped 16:9 touch normalization. Rebased 0002 retains launcher-specific mouse look, options and diagnostics. The former 0008 JSON progress patch was dropped because upstream adaptation [`f1c4a6bd67133c58b7a5a3e3d6f413f06b51f12c`](https://github.com/seedds/nxnative/commit/f1c4a6bd67133c58b7a5a3e3d6f413f06b51f12c) includes JSON progress output and a ticker that flushes throttled held counts without another `set()`.

Upstream now supplies the Mac physical-controller bridge (`0adbe8c`), fullscreen and backing-scale updates (`7803945`), and display FIFO improvements (`6400306`). These are not reimplemented by this series. The removed standalone `front_gamepad_mac.m` and obsolete `dm_i18n` UI are not restored.

## Preparation

```bash
python3 Tools/prepare-nxnative.py
python3 Tools/prepare-nxnative.py --check
```

Preparation validates the entire series against the exact upstream baseline, refuses incompatible or partial user edits, and keeps the real index unchanged. The archive builder checks preparation before copying the patched source. A dirty submodule is expected after preparation; commit only its upstream gitlink in the parent, not a private patched dependency commit.

## Upgrading or dropping a merged patch

1. Preserve local edits and keep the current release reproducible before changing the baseline.
2. Pick a specific upstream commit, inspect overlapping changes and existing PRs, and rebase only the remaining functionality in an isolated worktree.
3. Regenerate the relevant format-patches and `series`; set `base-commit` and the parent gitlink to the same upstream SHA.
4. Once upstream includes a submitted change, remove its patch from `series` and delete the obsolete active patch file. Keep this inventory's PR history.
5. Apply/check the complete series in a fresh checkout. Run its Python tests, host tests/build, iOS compilation checks for modified iOS sources, and `swift build`. Runtime tests with real controllers/games remain distinct from compilation.

## Historical source

`archive/bc5815a-nxlauncher-fork.patch` is the exact former monolithic diff (`bc5815a..7463eba`). It is retained for comparison only and is never applied. `dm_padmap.h` was already tracked at the old baseline, so that original diff did not contain it; the new mapping patch is self-contained.

## Verification on 2026-10-23

The complete nine-patch series passes `Tools/prepare-nxnative.py --check` on upstream `677345b0933f`. Replaying all nine patches with whitespace errors rejected in an isolated index produces tree `844442cca3c4d726965361246e34ec7398e99c6e`. All 57 launcher Python tests pass, including the 12 preparation regressions. Actual Metal sampling through the production sampled-view path passes 156 checks, including unsupported view-format fallback; the mip-range regression still passes 34 checks. Both use Metal API validation. A 110-second Echoes input run confirms the heart-HUD rectangle is gone at frames 3000 and 6000. See `docs/echoes-of-wisdom-mac-repair.md` for scope and diagnostic references.

A release launcher was rebuilt with the complete patched source. Its embedded archive matches the current font source, Metal renderer, both view tests, graphics Makefile and Mac export script byte-for-byte, and its deep strict ad-hoc signature verification passes. Existing compiler warnings remain; these tests do not establish whole-game or iOS-device compatibility.

## Verification on 2026-10-22

Before adding the repairs, `Tools/prepare-nxnative.py --check` verified the existing six patches. The eight-patch series was then replayed with whitespace errors rejected in an isolated index and checked in an isolated worktree on `677345b0933f`; the resulting tree was `c2f0bcd8a38ddb638a3d9f21772eb34a9b8496f4`. The focused shared-font regression passed 137 checks, and the production Metal mip-range regression passed 34 checks with `MTL_DEBUG_LAYER=1`, using `GAME=01007EF00011E000`. The Metal compilation emitted warnings from the existing renderer. All 12 preparation-tool regression tests passed. The parent dependency was prepared and checked with all eight patches, retaining its upstream HEAD and real index. No host or launcher archive was built for this integration, and no build or host execution was performed in the repair worktree.

The six-patch series was prepared and checked against upstream `677345b0933f`; both `Tools/prepare-nxnative.py` and `--check` verified all six patches, and the real submodule index remained unchanged. The upstream JSON progress suite passed all 6 tests. Host component tests for `GAME=01007EF00011E000` passed all 17 programs, including mapping, memory-configuration, language, touch, filesystem, audio and timing tests. Modified Mac and iOS Objective-C sources passed strict syntax checks. The default Echoes host (`GAME=01008CF01BAAC000`) was compiled in the isolated worktree by the coordinating build owner. These are preparation, syntax, component and compilation checks, not a claim of a full game/IPA/controller runtime test.

Earlier release checks on the former eight-patch baseline included a 59 MB self-contained tools archive, byte-for-byte archive payload comparisons, a no-game AppKit touch-coordinate/release harness, 25 JSON progress tests, `swift build`, and `bootstrap.sh --check`. Those results describe that earlier baseline and are not rerun claims for this six-patch update.
