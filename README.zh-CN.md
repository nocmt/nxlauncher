<div align="center">

<img src="docs/brand/hero.svg" alt="NxLauncher — 从你的游戏库，走向原生构建" width="920" />

# NxLauncher

**让你的游戏库，拥有清晰的原生构建路径。**

为 [nxnative](https://github.com/seedds/nxnative) 构建流水线打造的 macOS 启动器。
整理自备游戏、检查环境、追踪构建，并导出 Mac App 或 iOS IPA。

[![版本](https://img.shields.io/badge/version-0.1.6-C72835)](CHANGELOG.md)
[![平台](https://img.shields.io/badge/host-Apple%20Silicon-111827)](#环境要求)
[![运行系统](https://img.shields.io/badge/game%20runtime-macOS%2026%2B-087F8C)](#环境要求)
[![流水线](https://img.shields.io/badge/powered%20by-nxnative-555)](https://github.com/seedds/nxnative)

**[English](README.md) · 简体中文**

[**下载最新版本**](https://github.com/nocmt/nxlauncher/releases/latest) · [最快开始](#最快开始) · [实测游戏](docs/tested-games.md) · [排障指南](docs/troubleshooting.md)

</div>

> **0.1.6 已发布**为 [GitHub 正式发布版](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.6)，分发签名并**已公证**的磁盘映像：Developer ID 签名、hardened runtime、安全时间戳、公证票据已盖章到 DMG，其他 Mac 上 Gatekeeper 可直接放行。Release 只含 DMG、校验和与清单，不含游戏、密钥或存档。验证范围与未验证项见[发布流程](docs/releasing.md)。

## 从游戏库到构建产物

| | 你能做什么 |
|---|---|
| **统一游戏库** | 记录游戏文件夹、身份、版本与构建状态。移除条目只移除引用，原文件、产物和存档仍留在磁盘。 |
| **先检查，再构建** | 区分本体、更新和 DLC，检查密钥文件是否可用、是否有移植档案，以及目标平台依赖。 |
| **默认走 Mac** | `build` 默认构建 Mac，成功后自动导出 `.app`，不会自动启动游戏。 |
| **明确的 iOS 路径** | 选择 iOS 生成 IPA；安装仍需要合适的签名、描述文件与受支持真机。 |
| **看得见的过程** | 可复制构建输出，保留分阶段日志，按会话导出诊断 ZIP。 |
| **每款游戏独立设置** | 帧率目标、游戏语言、掌机／主机模式采用横排分段单选控件，并写入各自设置文件。启动器 UI 主要为中文；游戏语言是另一项设置。 |
| **依赖引导安装** | 显示缺失工具；固定 Homebrew 包白名单中的安装操作需确认。Xcode、Homebrew 使用官方安装引导。 |

NxLauncher 自动化的是构建流程。兼容性仍由游戏、更新版本、上游 profile、图形后端及主机环境共同决定。**有 profile，不等于已经实测。**

## 最快开始

1. 从 [v0.1.6 发布页](https://github.com/nocmt/nxlauncher/releases/tag/v0.1.6) 下载 `NxLauncher-0.1.6-macos-arm64.dmg`，打开磁盘映像，把 `NxLauncher.app` 拖入“应用程序”。
2. 在**通用设置／编译环境**中检查 **Mac** 目标，按提示补齐工具。安装前先核对将要执行的包列表。
3. 添加一个游戏文件夹，放入自己合法获取的本体 NSP/XCI 和匹配更新、DLC；在通用设置选择自己的 `prod.keys`，文件保留在原位置。
4. 核对识别出的游戏、更新与档案，然后构建 **Mac**。首次着色器处理可能较久，保留日志。
5. 主动打开导出的 `.app`，检查画面、输入、声音和存档读写，再判断是否适合使用。

流水线不要求输入固件。项目不提供游戏、密钥或获取来源。导出的游戏 App／IPA 可能包含受版权保护的游戏数据，**导出不代表可以公开分享或重新分发**。

## 环境要求

| 用途 | 要求与边界 |
|---|---|
| 启动器界面 | Apple Silicon Mac。Swift 包声明 macOS 14+，不代表游戏运行时也支持 macOS 14。 |
| Mac 游戏构建／运行 | 按 **macOS 26+**、完整 Xcode、macOS SDK 与 Metal 工具链准备，并通过 `doctor --target mac`。**Mac 目标不要求 iOS SDK。** |
| iOS IPA 构建 | 兼容的 Mac 构建主机、iPhoneOS SDK、目标工具，以及适合导出方式和设备的签名／描述文件；先运行 `doctor --target ios`。 |
| 解包、重写与着色器处理 | 兼容的 arm64 .NET 10 SDK **及运行时**、`zstd`、`spirv-cross` 和诊断所列 Python 模块；iOS 还使用 `xcodegen`。 |
| 源码开发 | Swift/Xcode、Git、Python 3.12+；`bootstrap.sh` 使用仓库内独立虚拟环境。 |

打包版启动器携带工具归档、Python 和 Python wheels，但系统构建工具仍需安装。导出的 Mac 游戏携带运行资源，仍受系统、GPU 和游戏兼容性限制。磁盘需同时容纳原始包、解包目录、着色器缓存和每份导出；不承诺固定耗时或空间占用。

官方入口：[Xcode](https://developer.apple.com/xcode/) · [Homebrew](https://brew.sh/) · [.NET 10](https://dotnet.microsoft.com/download/dotnet/10.0)。

## 有本地成功打包记录的游戏

以下均为**历史结果**，**尚未在最终 0.1.6 基线上重新游玩验证**。

| 游戏／版本 | 历史打包证据 | 可以支持的运行结论 |
|---|---|---|
| 塞尔达传说：智慧的再现 · **1.1.0 / `v196608`** | Mac 导出、IPA 构建记录 | 2026-10-23 用户确认 Mac 正常打包游玩；另有有限时长的画面／操作记录。不代表通关或 iOS 真机验证。 |
| 塞尔达传说：旷野之息 · **1.9.0 / `v1114112`** | nxnative IPA 完成日志、历史 Mac 打包记录 | 独立 nxnative Mac 日志到达第 2100 帧，收到 SIGTERM 后正常退出。属于有限运行；**不采用 MacNativeGames 的 117 FPS 结果**。 |
| 集合啦！动物森友会 · **3.0.3 / `v2228224`** | IPA 完成日志、保留的 nxnative Mac App 元数据 | nxnative 日志存在帧提交与 DLC 枚举，也含 `[RED]` 报告；只能支持有限运行，不能视为无错误全流程验证。 |

[查看证据来源、版本与支持边界 →](docs/tested-games.md)。`games` 命令展示的是档案列表，不是实测清单。

## 命令行最短路径

在完成准备的源码仓库中执行。命令逐行输出 JSON 事件。请将示例路径替换为自己的目录。

```bash
python3 Tools/pack_pipeline.py doctor --target mac
python3 Tools/pack_pipeline.py plan --target mac \
  --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
python3 Tools/pack_pipeline.py build --target mac \
  --game-dir "$HOME/Games/MyGame" --keys "$HOME/Keys/prod.keys"
```

`build` 默认 `--target mac`，成功后自动导出 Mac App，不自动启动。iOS 则在 `doctor`、`plan`、`build` 中一致使用 `--target ios`。

| 参数／命令 | 用途 |
|---|---|
| `--graphics-api auto\|nvn\|vulkan\|gl` | build/doctor/export 的图形 API 选择，先用 `auto`；可选择不等于所有游戏均支持。 |
| `build --rebuild` | 显式要求重建，避免直接复用已有构建状态；先保留日志与存档。 |
| `build --rebuild-shaders` | 排查旧／不兼容着色器状态时显式重建着色器，耗时可能显著增加。 |
| `games` | 列出上游游戏档案。 |
| `diagnostics --out ZIP [--session ID]` | 导出诊断包，可指定会话；分享前检查内容。 |

```bash
python3 Tools/pack_pipeline.py diagnostics --out "$HOME/Desktop/NxLauncher-diagnostics.zip"
python3 Tools/pack_pipeline.py diagnostics \
  --out "$HOME/Desktop/NxLauncher-session.zip" --session SESSION_ID
```

已有工作目录的导出使用另一组 target 名称：

```bash
python3 Tools/pack_pipeline.py export --target mac-app \
  --game 01007EF00011E000 --ver v1114112 \
  --work "$HOME/Games/MyGame/01007EF00011E000_build" \
  --out "$HOME/Desktop/MyGame.app"
```

另有 `ios-ipa`、`ios-ipa-unsigned`。未签名 IPA 需要后续签名；签名成功也不等于一定能安装或运行。详见[打包最佳实践](docs/打包最佳实践.md)。

## 数据放在哪里

| 数据 | 位置／行为 |
|---|---|
| 原始游戏、密钥 | 用户选择的位置；不要把密钥放进仓库或问题报告。 |
| 游戏库、全局偏好 | macOS `UserDefaults`，保存目录引用与元数据。 |
| 工作目录、阶段日志 | `<游戏目录>/<TITLE_ID>_build/`，包括 `logs/`、解包结果和缓存。完成清单为 `.nxlauncher/build-mac.json`／`build-ios.json`；只有旧文件不等于当前构建完整。 |
| 流水线会话 | `~/Library/Application Support/NxLauncher/Pipeline/sessions/<SESSION_ID>/`；`NXLAUNCHER_STATE_DIR` 可更改状态根目录。 |
| 打包版解出的工具 | `~/Library/Caches/NxLauncher/home`，与游戏存档分离。 |
| 当前 Mac 导出的存档、设置、日志 | `~/Library/Application Support/nxnative/<TITLE_ID>/` 下的 `save/`、`env.txt`、`log.txt`、`temp/`。 |
| 旧版游戏导出 | 可能仍使用 Application Support 下按 App 名命名的目录。迁移前备份新旧位置；启动器根据选中的 App 判断布局。 |
| 诊断 ZIP | `--out` 指定位置；日志可能包含路径、环境／工具版本和错误细节。 |

升级前先备份存档。移除游戏库条目不是清理磁盘。刷新构建缓存时不要删除 Application Support。

## 从源码构建启动器

```bash
git clone https://github.com/nocmt/nxlauncher.git
cd nxlauncher
./bootstrap.sh
swift run NxLauncher
```

`bootstrap.sh` 默认 Mac，准备 iOS 使用 `./bootstrap.sh --target ios`。它准备子模块与补丁，选择 Python 3.12+，建立 `.venv`，安装清单固定版本依赖并构建启动器，会修改工作目录。兼容的 CPython 3.13 arm64 可离线使用 bundled wheels；源码使用其他解释器 ABI 时可能下载精确固定版本。`./bootstrap.sh --check --target mac` 跳过安装／构建，但检查仍可能写临时文件或诊断会话，**不承诺零写入**。游戏目标依赖使用对应 `doctor` 核对。

```bash
swift build -c release
bash Scripts/make-app.sh
python3 Tools/prepare-nxnative.py --check
python3 -m unittest discover -s Tests -v
```

产物为 `dist/NxLauncher.app`。游戏导出默认采用开放字体 **NotoSansSC**，字体 helper 已做本地验证；不承诺覆盖每款游戏的全部字形与布局。分发清单以核对后的[第三方声明](THIRD_PARTY_NOTICES.md)为准。

协调者已确认上游 HEAD／base 为 **`201dfd1280684e9d3ceac8b644236fdac11b6cc2`**，保留 **5 个功能补丁**，准备后的目标 tree 为 **`a3814a41de5781b208525f25b6facabcf8cd423f`**。准备契约记录在 [`patches/base-commit`](patches/base-commit)、[`patches/series`](patches/series) 和[补丁说明](patches/README.md)。host／graphics 组件及上游 Python 已有检查验证；最终 0.1.6 验证未运行真实游戏，历史测试不能代替当前游戏产物的运行验收。

## 遇到问题

[排障指南](docs/troubleshooting.md)提供依赖、Finder／终端差异、文件／密钥识别、着色器、导出、Gatekeeper、存档位置、画面、iOS 签名和诊断检查的具体路径，无需依赖 AI 才能处理。

反馈请附版本、目标、系统／芯片、title ID／更新版本、图形 API、失败阶段和检查后的诊断 ZIP。不要上传密钥、游戏包、解包资源、存档或签名凭据。可通过 [Issues](https://github.com/nocmt/nxlauncher/issues)反馈。

## 支持边界

- UI 主要中文；这里提供中英文文档，不声称 UI 双语。
- 不保证所有游戏兼容、完整通关、稳定帧率或 iOS 真机成功。
- 不提供游戏／密钥来源，不授权公开分发含游戏数据的导出。
- Developer ID 签名对本地构建是可选项；正式发布为 **Developer ID 签名并已公证**，并以 DMG 分发——只有 DMG（或 pkg）能携带盖章票据。
- NxLauncher 源码使用 [LICENSE](LICENSE)。上游、字体和依赖保留各自条款，分发前需要依据核对后的[第三方声明](THIRD_PARTY_NOTICES.md)。

[更新记录](CHANGELOG.md) · [发布流程](docs/releasing.md) · [隐私与诊断](docs/privacy.md) · [上游 nxnative](https://github.com/seedds/nxnative)
