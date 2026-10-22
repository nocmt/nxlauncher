# NxLauncher patch inventory

The dependency is pinned to upstream [`26a72dd5620ff8ea4a0ad23240e401e3802b2c7b`](https://github.com/seedds/nxnative/commit/26a72dd5620ff8ea4a0ad23240e401e3802b2c7b), fetched on 2026-10-22. `base-commit` is authoritative; `series` lists the patches in application order. The submodule points to upstream, while the applied changes remain in its working tree.

## Why these patches remain local

| Patch | Purpose | Upstream treatment |
|---|---|---|
| 0001 Mac mouse routing | Route touches through the content view so AppKit window controls receive their events; allow Command shortcuts | [PR #48](https://github.com/seedds/nxnative/pull/48), independent of launcher preferences |
| 0002 Mac window/mouse options | Mouse look, mouse-as-A, window size, rounded corners, FPS and diagnostics | Local product behavior; preserves upstream fullscreen and display scale |
| 0003 Controller mapping | Preserve existing Nintendo/Xbox glyph mapping and optional `DM_PADMAP` override on Mac/iOS | Local preference; upstream intentionally maps by position. Uses upstream bridge, not a duplicate |
| 0004 Memory overrides | Preserve `DM_MEM_RESERVE`, `DM_MEM_POOL`, `DM_MEM_ALIAS` for existing launcher options, with parser/layout checks | Local pending broader evidence and profile discussion; defaults unchanged |
| 0005 Touch diagnostics | Restore polling/operation-mode logs used to diagnose mouse/touch behavior | Local diagnostics; retains upstream touch points and mode filtering |
| 0006 Mac language fallback | Follow Mac preferred language when `DM_LANG` is absent, retaining legacy Chinese/English fallback | Local because only two fallback outcomes are supported; iOS keeps upstream `DMLanguage` semantics |
| 0007 Touch diagnostic synchronization | Keep polling diagnostics race-free under concurrent guest reads | Local correction to 0005 |
| 0008 JSON progress | Expose structured stage/step/progress/stage_end/say output for GUI and script consumers | [PR #49](https://github.com/seedds/nxnative/pull/49), independent of launcher preferences |

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

## Verification on 2026-10-22

The native series built the BotW host (`GAME=01007EF00011E000`) and passed all 17 host test programs including mapping, memory-configuration and language tests. Modified Mac/iOS translation units passed strict syntax checks. The Mac mouse PR additionally passed a no-game AppKit touch-coordinate/release harness. JSON progress passed 25 standard-library tests with warnings treated as errors. `swift build` passed with an existing actor-isolation warning; `bootstrap.sh --check` passed. All eight patches applied, verified and repeated successfully in a clean upstream worktree. A 59 MB self-contained tools archive was built, and nine representative patched source/test files matched its payload byte-for-byte. These are build and component checks, not a claim of a full game/IPA/controller runtime test.
