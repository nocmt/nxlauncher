<div align="center">

<img src="docs/brand/hero.svg" alt="NxLauncher — your library, a clearer path to native builds" width="920" />

# NxLauncher

**Your library. A clearer path to native builds.**

A macOS launcher for the [nxnative](https://github.com/seedds/nxnative) pipeline.
Organize your own game dumps, inspect the toolchain, build, and export a Mac app or iOS IPA.

[![Version](https://img.shields.io/badge/version-0.1.4-C72835)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/host-Apple%20Silicon-111827)](#requirements)
[![Runtime](https://img.shields.io/badge/game%20runtime-macOS%2026%2B-087F8C)](#requirements)
[![Pipeline](https://img.shields.io/badge/powered%20by-nxnative-555)](https://github.com/seedds/nxnative)

**English · [简体中文](README.zh-CN.md)**

[**Download latest release**](https://github.com/nocmt/nxlauncher/releases/latest) · [Quick start](#quick-start) · [Tested games](docs/tested-games.md) · [Troubleshooting](docs/troubleshooting.md)

</div>

> **0.1.4 is published** as a [GitHub prerelease](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.4): **Developer ID signed, hardened runtime, not notarized and not stapled**, so Gatekeeper may still block it on another Mac. The release contains only the launcher ZIP, its checksum and its manifest: no games, keys or saves. See [release notes](docs/releasing.md) for what was verified and what was not.

## A library that builds

| | What you get |
|---|---|
| **One home for your games** | Folder references, game identity, versions and build status. Removing a library entry leaves source files, outputs and saves on disk. |
| **Inspect before building** | Separate base game, updates and DLC; check key-file availability, game profiles and target-specific dependencies. |
| **Mac first** | `build` defaults to Mac, exports a `.app` on success and does not launch it automatically. |
| **An explicit iOS path** | Select iOS for an IPA. Installation needs suitable signing and a supported physical device. |
| **Visible progress** | Copyable build output, stage logs and session-oriented diagnostic ZIP export. |
| **Per-game settings** | Frame-rate target, game language and handheld/console mode are arranged as horizontal segmented single-choice controls and saved in each game's settings file. The launcher UI is primarily Chinese. |
| **Guided dependencies** | Missing-tool guidance and confirmation before fixed-allowlist Homebrew installation. Xcode and Homebrew setup use official guides. |

NxLauncher automates a build workflow. Compatibility depends on the exact game/update, upstream profile, graphics backend and host. **A profile is not a compatibility test.**

## Quick start

1. Get `NxLauncher.app` from [Releases](https://github.com/nocmt/nxlauncher/releases/latest) once `v0.1.4` is published. Extract the archive before opening it.
2. Open **通用设置 / 编译环境** and check the **Mac** target. Follow missing-tool guidance; review the package list before confirming an installation.
3. Add one game folder with your legally obtained base NSP/XCI and matching update/DLC. Select your own `prod.keys` in General Settings; the file stays at its original location.
4. Check the detected title, update and profile, then build for **Mac**. First-time shader work can be lengthy; keep the logs.
5. Open the exported `.app` explicitly. Check rendering, input, sound and save/load before treating the result as usable.

No firmware input is required by this pipeline. No game dumps, keys or download sources are supplied. Exported apps/IPAs can contain copyrighted game data; exporting does not grant permission to redistribute them.

## Requirements

| Task | Requirements and boundaries |
|---|---|
| Launcher UI | Apple Silicon Mac. The Swift package declares macOS 14+; this does **not** make the game runtime compatible with macOS 14. |
| Build/play a Mac game | Plan for **macOS 26+**, full Xcode with macOS SDK and Metal tools, plus `doctor --target mac` dependencies. **Mac does not require the iOS SDK.** |
| Build an iOS IPA | A compatible Mac build host, iPhoneOS SDK, target-specific tools and appropriate signing/provisioning. Check `doctor --target ios`. |
| Extraction/rewrite/shaders | Compatible arm64 .NET 10 SDK **and** runtime, `zstd`, `spirv-cross`, and the Python modules reported by diagnostics. iOS also uses `xcodegen`. |
| Source development | Swift/Xcode, Git and Python 3.12+; `bootstrap.sh` prepares a repository-local virtual environment. |

The packaged launcher includes its tools archive, Python and Python wheels. It still needs the system build toolchain. Exported Mac games carry runtime resources but still need a compatible OS/GPU and game-specific support. Allow disk space for the original dump, extraction, shader caches and every export; there is no universal duration or storage guarantee.

Official setup: [Xcode](https://developer.apple.com/xcode/) · [Homebrew](https://brew.sh/) · [.NET 10](https://dotnet.microsoft.com/download/dotnet/10.0).

## Games with local packaging evidence

These are **historical results**. **None has been revalidated through gameplay on the final 0.1.4 baseline.**

| Game / version | Historical packaging | Supported runtime statement |
|---|---|---|
| The Legend of Zelda: Echoes of Wisdom · **1.1.0 / `v196608`** | Mac export and IPA records | User confirmed normal Mac packaging/gameplay on 2026-10-23; bounded graphics/input runs are documented. No whole-game or iOS-device claim. |
| The Legend of Zelda: Breath of the Wild · **1.9.0 / `v1114112`** | nxnative IPA completion log; historical Mac packaging record | Separate nxnative Mac log reaches frame 2100 and exits gracefully on SIGTERM. Limited execution; **MacNativeGames' 117 FPS result is excluded**. |
| Animal Crossing: New Horizons · **3.0.3 / `v2228224`** | IPA completion log and retained nxnative Mac app metadata | nxnative log records frame submission and DLC enumeration, but also `[RED]` reports. Limited execution, not clean full-game validation. |

[Evidence ledger, versions and limitations →](docs/tested-games.md). `games` lists profiles, not tested games.

## Command-line shortest path

Run from a prepared source checkout. Commands emit JSON events, one per line. Replace the example paths with your own.

```bash
python3 Tools/pack_pipeline.py doctor --target mac
python3 Tools/pack_pipeline.py plan --target mac \
  --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
python3 Tools/pack_pipeline.py build --target mac \
  --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
```

`build` defaults to `--target mac`, exports the Mac app and does not start it. Use `--target ios` consistently in `doctor`, `plan` and `build` for iOS.

| Option / command | Purpose |
|---|---|
| `--graphics-api auto\|nvn\|vulkan\|gl` | Graphics selection for `build`, `doctor` and `export`; start with `auto`. A selectable backend is not universal game support. |
| `build --rebuild` | Explicit rebuild instead of relying on reusable build state. Preserve logs and saves first. |
| `build --rebuild-shaders` | Rebuild shader artifacts when investigating stale/incompatible shader state; expect expensive work. |
| `games` | List upstream game profiles. |
| `diagnostics --out ZIP [--session ID]` | Export diagnostics, optionally for a selected session. Inspect before sharing. |

```bash
python3 Tools/pack_pipeline.py diagnostics --out "$HOME/Desktop/NxLauncher-diagnostics.zip"
python3 Tools/pack_pipeline.py diagnostics \
  --out "$HOME/Desktop/NxLauncher-session.zip" --session SESSION_ID
```

Existing-work export uses different target names:

```bash
python3 Tools/pack_pipeline.py export --target mac-app \
  --game 01007EF00011E000 --ver v1114112 \
  --work "$HOME/Games/MyGame/01007EF00011E000_build" \
  --out "$HOME/Desktop/MyGame.app"
```

Other export targets are `ios-ipa` and `ios-ipa-unsigned`. An unsigned IPA needs signing; signing alone does not guarantee installation or execution. See [packaging practice](docs/打包最佳实践.md).

## Where your data lives

| Data | Location / behavior |
|---|---|
| Original game and keys | Your selected paths. Keep keys out of repositories and reports. |
| Library/global preferences | macOS `UserDefaults`: folder references and metadata. |
| Build workspace/stage logs | `<game-folder>/<TITLE_ID>_build/`, including `logs/`, extraction and caches. Completion manifests are `.nxlauncher/build-mac.json` and `build-ios.json`; old files alone do not mean a complete current build. |
| Pipeline sessions | `~/Library/Application Support/NxLauncher/Pipeline/sessions/<SESSION_ID>/`; `NXLAUNCHER_STATE_DIR` can override the state root. |
| Packaged launcher's extracted tools | `~/Library/Caches/NxLauncher/home`; separate from saves. |
| Current Mac game's saves/settings/log | `~/Library/Application Support/nxnative/<TITLE_ID>/`: `save/`, `env.txt`, `log.txt`, `temp/`. |
| Older exported games | May use an app-name folder under Application Support. Back up both locations before migration; the launcher follows the selected app's layout. |
| Diagnostic ZIP | Your `--out` destination. Logs can expose paths, environment/tool versions and failure details. |

Back up saves before upgrades. Removing a library entry is not disk cleanup. Do not delete Application Support to refresh build caches.

## Build NxLauncher from source

```bash
git clone https://github.com/nocmt/nxlauncher.git
cd nxlauncher
./bootstrap.sh
swift run NxLauncher
```

`bootstrap.sh` defaults to Mac; use `./bootstrap.sh --target ios` when preparing iOS. It prepares the submodule/patches, selects Python 3.12+, creates `.venv`, installs the inventory's pinned Python dependencies and builds the launcher. Compatible CPython 3.13 arm64 uses bundled wheels offline; other source-checkout interpreter ABIs may download exact pinned versions. It modifies the checkout. `./bootstrap.sh --check --target mac` skips setup/build but checks can still write temporary files or diagnostic sessions; it is not a zero-write guarantee. Use target-specific `doctor` for game requirements.

```bash
swift build -c release
bash Scripts/make-app.sh
python3 Tools/prepare-nxnative.py --check
python3 -m unittest discover -s Tests -v
```

The app is written to `dist/NxLauncher.app`. Default exported-game fonts use open **NotoSansSC**; the helper has been checked locally, which does not guarantee every game's font coverage. See [third-party notices](THIRD_PARTY_NOTICES.md) for the reviewed distribution inventory.

The coordinator confirmed upstream HEAD/base **`201dfd1280684e9d3ceac8b644236fdac11b6cc2`**, with **five functional patches** and prepared target tree **`a3814a41de5781b208525f25b6facabcf8cd423f`**. [`patches/base-commit`](patches/base-commit), [`patches/series`](patches/series) and [patch notes](patches/README.md) record the preparation contract. Host/graphics components and upstream Python checks have been exercised; no actual game was run for final 0.1.4 validation. Historical tests do not validate the current packaged game's behavior.

## Get unstuck

[Troubleshooting](docs/troubleshooting.md) provides concrete checks for dependencies, Finder/Terminal differences, inputs/keys, shaders, export failures, Gatekeeper, missing saves, graphics, iOS signing and diagnostic review. No AI assistant is required.

For a report include launcher version, target, OS/chip, title ID/update, graphics API, failing stage and a reviewed diagnostic ZIP. Do not attach keys, dumps, extracted game resources, saves or signing credentials. For issues: [Issues](https://github.com/nocmt/nxlauncher/issues).

## Project boundaries

- Primarily Chinese UI, with English and Chinese documentation.
- No promise of all-game compatibility, whole-game completion, stable FPS or iOS-device success.
- No game/key sourcing or permission to redistribute exported game content.
- Developer ID is an optional signing path; this release plans a **Developer ID–signed, unnotarized preview**. Local/ad-hoc signature verification is a separate check.
- NxLauncher source uses [LICENSE](LICENSE). Upstream, fonts and dependencies retain their own terms; distribution decisions require the reviewed [third-party notices](THIRD_PARTY_NOTICES.md).

[Changelog](CHANGELOG.md) · [Release process](docs/releasing.md) · [Privacy and diagnostics](docs/privacy.md) · [Upstream nxnative](https://github.com/seedds/nxnative)
