# Changelog / 更新记录

[English](README.md) · [简体中文](README.zh-CN.md)

Only recorded changes and their validation boundaries are described here. A release heading is not evidence that an asset has already been published.

这里只记录改动与验证边界；出现版本标题不表示资产已经发布。

## 0.1.6 — 2026-10-28

**Gamepad icon in three styles with a settings picker, plus a cleaner workspace and home page. / 三种手柄图标与设置页图标选择，并清理工作区与首页排版。**

Release: [v0.1.6](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.6). The release is a **signed and notarized DMG**: Developer ID signature, hardened runtime, secure timestamp, and the notarization ticket stapled to the image, so Gatekeeper accepts it on other Macs without a first-launch round-trip. It is also the first release published as a normal release rather than a prerelease, so its notes appear on the repository's Releases page.

Release：[v0.1.6](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.6)。发布物是**签名并已公证的 DMG**：Developer ID 签名、hardened runtime、安全时间戳，公证票据已盖章到映像，因此其他 Mac 上 Gatekeeper 可直接放行，无需首次联网换取记录。这也是首个以正式发布（非 prerelease）方式发布的版本，说明会显示在仓库的 Releases 页。

### Distribution / 分发方式

- Only a DMG is produced. `stapler` cannot attach a ticket to a ZIP and `notarytool` rejects a bare `.app`, so the DMG is the container that can carry a stapled ticket. A ZIP would still work online but could be blocked offline on first launch.
- `Scripts/make-dmg.sh` builds the image with the usual Applications drop link and signs it with a secure timestamp; `Scripts/verify-release.sh` now accepts `.app`, `.zip` and `.dmg`, mounting an image read-only and reporting the ticket state.
- Nested signing retries Apple's timestamp server a few times on transient failures, which previously aborted a whole build.
- The manifest records `timestamp: secure`, `notarized: true` and `stapled: true` alongside the DMG size and SHA-256; the notary profile name is passed on the command line and never stored in the repository.

对应中文：

- 只产出 DMG。`stapler` 无法给 ZIP 盖章，`notarytool` 又不接受裸 `.app`，所以只有 DMG 能携带盖章票据。ZIP 联网时可用，但首次启动在断网时可能被拦截。
- `Scripts/make-dmg.sh` 生成带“应用程序”快捷方式的映像并用安全时间戳签名；`Scripts/verify-release.sh` 现在支持 `.app`/`.zip`/`.dmg`，会只读挂载映像并报告票据状态。
- 嵌套签名遇到 Apple 时间戳服务偶发失败会自动重试，此前一次抖动会让整轮构建失败。
- 清单记录 `timestamp: secure`、`notarized: true`、`stapled: true` 以及 DMG 大小与 SHA-256；公证 profile 名只通过命令行传入，从不写入仓库。

### Icon / 图标

- The emblem is a gamepad in three styles: **实心 (solid)** filled silhouette with the controls cut through to the red tile, **描边 (outline)** rim only with solid controls, and **复古 (retro)** a flat panel with minimal symbols. Solid is the app icon and the default.
- All three share one silhouette box centred on the tile (512,512), so switching styles does not make the icon jump. The pad is 534×362 instead of the earlier 282-high shape that sat low, and the bottom recess is shallow rather than a deep notch.
- General settings gained an **图标** row with three previews. Choosing one stores the preference and changes the running app's Dock and app-switcher icon. It cannot change the bundle icon that Finder and Launchpad read, because rewriting the signed bundle would break its signature; the sheet says so.

对应中文：

- 图案改为手柄，共三款：**实心**（暖白实心、控件挖空透红）、**描边**（只画轮廓、控件实心）、**复古**（扁平面板 + 极简符号）。实心为应用图标与默认项。
- 三款共用同一轮廓并以格子中心 (512,512) 对齐，切换风格不会跳位。手柄尺寸为 534×362，取代此前仅 282 高、整体偏下的形状，底部凹口也由深槽改浅。
- 通用设置新增 **图标** 一行，含三个预览。选择后写入偏好并立即改变运行中 App 的 Dock 与应用切换器图标。Finder 与启动台读取的包内图标无法在运行时改写（会破坏签名），界面已注明。

### Workspace and home page / 工作区与首页

- The per-game settings no longer nest a panel, a segmented track and a cell inside the card; the controls now sit directly on the card, matching the lighter 0.1.2 layout.
- The build-log header uses a hairline instead of a filled grey band, while the whole row stays clickable.
- Home game cards show the artwork alone with a name and one status line; the duplicate "待编译" badge on the artwork and the "尚未读取版本" line are gone. Placeholder artwork is smaller and quieter. 外观 uses the same segmented control as the game settings.

对应中文：

- 游戏设置不再在卡片内嵌套面板、分段轨道和选中格，控件直接放在卡片上，回到 0.1.2 那种更轻的层次。
- 构建日志标题改为细线分隔而非整条灰底，整行仍可点击。
- 首页游戏卡片只显示封面、名称与一行状态；去掉封面上重复的“待编译”胶囊和“尚未读取版本”一行。占位图形更小更淡。外观改为与游戏设置一致的分段控件。

## 0.1.5 — 2026-10-28

**New icon: the soft red gradient tile now carries a gamepad emblem. / 新图标：柔和红渐变底改为手柄图案。**

Release: [v0.1.5](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.5). Same packaging and signing path: Developer ID signed, hardened runtime, not notarized and not stapled.

Release：[v0.1.5](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.5)。打包与签名方式不变：Developer ID 签名、hardened runtime、未公证、未 staple。

- The emblem changed from the launch triangle to a gamepad: rounded body and grips, plus pad, two round buttons and a short antenna, cut out of a warm-white silhouette so the red tile shows through the controls. The red gradient tile, corner radius and single-emblem composition are unchanged.
- Nothing else changed; no behavior, dependency or document content differs from 0.1.4 apart from the icon and version.

对应中文：

- 图案由启动三角改为手柄：圆润机身与两侧握把、十字键、两个圆形按键和一小段天线，用暖白剪影挖空，红色底从按键处透出。红渐变底、圆角与单一图案的构图保持不变。
- 其余无改动；除图标与版本号外，行为、依赖和文档内容与 0.1.4 一致。

## 0.1.4 — 2026-10-28

**Fixes for the 0.1.3 controls: dependency details stay open, and the segmented choices fit the row. / 修复 0.1.3 控件问题：依赖详情可正常展开，分段控件不再撑满整行。**

Release: [v0.1.4](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.4). Same packaging and signing path: Developer ID signed, hardened runtime, not notarized and not stapled.

Release：[v0.1.4](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.4)。打包与签名方式不变：Developer ID 签名、hardened runtime、未公证、未 staple。

- The dependency details section always collapsed itself as soon as a check finished, because a successful check explicitly set the expanded flag to false. It now only auto-expands when something is missing, so clicking it expands and stays expanded. Clicking the whole header row toggles it, matching the build log.
- The three per-game segmented choices no longer stretch across the card. Each option has a fixed cell (language 84 pt, frame rate 92 pt, operation mode 116 pt, 26 pt tall plus padding), so the groups sit at a natural width and stay easy to hit.
- No change to build, export, dependency or diagnostics behavior.

对应中文：

- 依赖详情以前只要检查完成就会自动收起（检查成功时代码直接把展开状态设为 false），所以看起来“点了只会检查”。现在只在缺少依赖时自动展开，点击整条标题即可展开并保持；点击区域与构建日志一致。
- 三个分段单选不再拉满整张卡片：每个选项固定宽度（语言 84、帧率 92、运行模式 116，外加高度 26 与内边距），整组保持自然宽度，同时仍然好点。
- 构建、导出、依赖与诊断行为未改动。

## 0.1.3 — 2026-10-28

**Usability release: larger settings controls, a full-width log toggle, a quieter settings sheet and a simpler icon. / 易用性版本：设置控件更大、日志可整条点击、设置页更安静、图标更简洁。**

Release: [v0.1.3](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.3). Same packaging and signing path as 0.1.2: Developer ID signed, hardened runtime, not notarized and not stapled.

Release：[v0.1.3](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.3)。打包与签名方式同 0.1.2：Developer ID 签名、hardened runtime、未公证、未 staple。

- Per-game language, frame rate and operation mode are now custom segmented buttons: each option is a 30-point-tall target with its whole cell clickable, 102-155 points wide, replacing the small native segmented control. Selecting one still writes the per-game setting immediately.
- The build log header is one full-width button (about 1057 points wide); clicking the title, the count or the chevron expands it, and the expanded state shows the log and its actions.
- The general settings sheet no longer shows the log text. It keeps "open log", "save diagnostics" and "copy all", plus a one-line count, so the sheet stays readable.
- The app icon is simplified to a soft red gradient tile with a single rounded warm-white launch triangle, replacing the layered portal.
- Nothing changed in the build, export, dependency or diagnostics behavior.

对应中文：

- 每款游戏的游戏语言、目标帧率、运行模式改为自绘分段按钮：每个选项高 30 点、整格可点、宽 102–155 点，替代原来偏小的系统分段控件；选择后仍立即写入该游戏设置。
- 构建日志标题改为整条按钮（约 1057 点宽），点标题、条数或箭头都能展开，展开后显示日志内容与操作按钮。
- 通用设置页不再显示日志正文，只保留“打开日志／保存诊断包／复制全部”和一行条数，页面更清爽。
- 图标简化为柔和红色渐变底加一个圆润的暖白启动三角，替换原来的层叠门结构。
- 构建、导出、依赖与诊断行为未改动。

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
