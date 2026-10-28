# Changelog / 更新记录

[English](README.md) · [简体中文](README.zh-CN.md)

Only recorded changes and their validation boundaries are described here. A release heading is not evidence that an asset has already been published.

这里只记录改动与验证边界；出现版本标题不表示资产已经发布。

## 0.1.2 — 2026-10-28

**Published as a GitHub prerelease: Developer ID signed, not notarized, not stapled. / 已作为 GitHub 预发布版发布：Developer ID 签名，未公证、未 staple。**

Release: [v0.1.2](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.2). Assets are the launcher ZIP, its `.sha256` and its manifest; no games, keys or saves are attached. Before publication the repository history was rewritten to drop an old screenshot file whose revisions contained third-party game cover artwork (see [release procedure](docs/releasing.md#history-rewrite-2026-10-28)); a local Git bundle keeps the pre-rewrite history.

Release：[v0.1.2](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.2)。资产只有启动器 ZIP、`.sha256` 和清单，不含游戏、密钥或存档。发布前已重写历史，移除一份旧截图文件（其若干版本含第三方游戏封面美术，见[发布流程](docs/releasing.md#history-rewrite-2026-10-28)）；重写前的历史保留在本地 Git bundle 中。

### Workflow / 构建流程

- Target-specific `plan`, `build` and `doctor`: `--target mac|ios`. Mac builds do not require the iOS SDK.
- `build` defaults to Mac and automatically exports the app after success, without launching it.
- Graphics selection: `--graphics-api auto|nvn|vulkan|gl`; backend availability is not a game-compatibility guarantee.
- Explicit `--rebuild` and `--rebuild-shaders` controls for build/shader regeneration.
- `diagnostics --out ZIP [--session ID]` for diagnostic export, with a reminder to review contents before submission.
- Mac-default `bootstrap.sh --target mac|ios`, Python 3.12+ selection and pinned dependency inventory. Compatible CPython 3.13 arm64 uses bundled wheels; other source-checkout ABIs may download pinned versions. `--check` is not a zero-write guarantee.
- Dependency guidance and confirmed installation for a fixed Homebrew package allowlist; official Xcode/Homebrew setup guidance.

对应中文：

- `plan`、`build`、`doctor` 区分 `mac|ios`；Mac 不要求 iOS SDK。
- 默认 Mac 构建成功后自动导出，不自动启动。
- 增加显式图形 API 选择、构建／着色器重建控制，以及可指定会话的诊断导出。
- 依赖安装限定固定 brew 白名单并要求确认；Xcode／Homebrew 使用官方引导。

### Presentation and documentation / 品牌与文档

- Original brand artwork referenced from `docs/brand/hero.svg`; no old screenshot containing personal paths is embedded in these READMEs. The icon is a new red-and-warm-white launch-strata mark; composition came from this project's own library motif and only the palette was informed by a reference image the owner supplied.
- English and Chinese READMEs link to each other, with a download entry, requirements, shortest path, data locations, source build and support boundaries.
- Expanded troubleshooting and packaging guidance; a bilingual game-evidence ledger separates packaging from runtime and current-release validation.
- Default exported-game fonts use open NotoSansSC; the font helper has been checked locally. Font coverage and dependency redistribution remain subject to game testing and reviewed third-party terms.
- Per-game language, frame-rate and handheld/console settings use horizontal segmented single-choice controls; values remain per-game settings.
- Launcher UI remains primarily Chinese; bilingual documentation does not imply bilingual UI.

对应中文：

- 引用原创品牌 SVG，不使用含个人路径的旧截图。图标改为红／暖白“启动层叠”标记；构图来自本项目自己的游戏库意象，参考图只用于配色，未复制其中任何形状。
- 中英文 README 互链，补齐下载、功能、快速开始、目录、构建和支持边界。
- 新增详细排障及游戏证据清单，更新打包实践，移除旧 `miniapps` 命令与个人机器路径。
- 默认开放字体 NotoSansSC，helper 已本地验证；字形覆盖与第三方分发范围仍需分别核实。
- UI 主要中文，不将文档双语描述成界面双语。

### Upstream and release verification / 上游与发布验证

The coordinator confirmed upstream HEAD/base **`201dfd1280684e9d3ceac8b644236fdac11b6cc2`**, **five functional patches**, and prepared target tree **`a3814a41de5781b208525f25b6facabcf8cd423f`**. Authoritative records are [`patches/base-commit`](patches/base-commit), [`patches/series`](patches/series) and [patch notes](patches/README.md). Host/graphics components and upstream Python checks have been exercised; final 0.1.2 validation did not run an actual game.

协调者已确认上述上游基线、5 个功能补丁及目标 tree。host／graphics 组件和上游 Python 已有检查验证；本次最终验证未运行真实游戏，不把组件检查写成游戏可玩性验收。

A Developer ID identity is available, so the 0.1.2 build was produced as a **Developer ID–signed, unnotarized, unstapled** local artifact because notarization credentials are unavailable; it is not notarized and Gatekeeper may still block it. Its manifest records the actual identity, timestamp mode (`none`), ZIP size and SHA-256. The release tooling's Developer ID path remains optional; ad-hoc signature checks are not notarization. See [release procedure](docs/releasing.md), [privacy](docs/privacy.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

已有 Developer ID、无公证凭据，因此 0.1.2 以 **Developer ID 签名、未公证、未 staple** 的本地产物交付；Gatekeeper 仍可能拦截。清单记录实际签名身份、时间戳模式（`none`）、ZIP 大小与 SHA-256。发布工具的可选 Developer ID 路径与 Apple 公证分别处理。

### Game validation boundary / 游戏验证边界

- Echoes of Wisdom **1.1.0 / `v196608`**: historical user-confirmed normal Mac packaging/gameplay and bounded rendering/input checks.
- Breath of the Wild **1.9.0 / `v1114112`**: historical nxnative packaging and limited Mac execution; MacNativeGames' 117 FPS result is explicitly excluded.
- Animal Crossing: New Horizons **3.0.3 / `v2228224`**: historical IPA/Mac artifacts and limited runtime log evidence, including `[RED]` reports.
- **None has been revalidated through gameplay on the final 0.1.2 baseline. No iOS-device or whole-game completion claim is made.**

对应中文：智慧的再现有历史用户正常打包游玩反馈；旷野之息、动森依实际日志标注历史打包及有限运行。**三款均未在最终 0.1.2 基线重新游玩，不作 iOS 真机或完整通关保证。**详见[实测记录](docs/tested-games.md)。

## Earlier local history / 更早的本地历史

The repository contains earlier multi-game library work, bundled-tool packaging, upstream patch maintenance and Echoes font/graphics investigations. This changelog does not assign unverified release dates or compatibility claims to those commits. Refer to Git history and the dated [Echoes repair record](docs/echoes-of-wisdom-mac-repair.md) for provenance.

仓库保留较早的多游戏库、工具内置、上游补丁维护以及智慧的再现字体／画面调查记录。此处不为这些提交补写未经核实的公开发布日期或兼容性承诺，来源以 Git 历史和带日期的修复记录为准。
