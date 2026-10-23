# NxLauncher patch inventory

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
